-- SuperDelivery: a photograph of the rider, so dispatch and the rider
-- themselves can see who the account belongs to.
--
-- LOCKED AT APPROVAL, NOT AT UPLOAD
--
-- A rider can retake their photo as often as they like while they are
-- still signing up and waiting to be approved - the one that came out
-- dark, or of their thumb, is theirs to fix before anyone has looked at
-- it. The moment an admin approves them (is_active), it is fixed. The
-- photo is how someone is identified - by dispatch looking at the roster,
-- and by anyone comparing the person at the door to the account that was
-- assigned the job. A rider who can swap it at will can hand their
-- account to somebody else and have the app agree, which is the whole
-- thing this is meant to prevent. Approval is the point at which a human
-- has looked at the photo and accepted it, so that is the point it stops
-- being theirs to change.
--
-- Staff can always replace one. Otherwise a rider whose first upload came
-- out dark, sideways or accidentally of their thumb is stuck with it for
-- the life of the account, and the only fix would be deleting the person.
--
-- Enforced in three places, because a rule that lives only in the UI is
-- not a rule: the column guard below (a rider's own update silently keeps
-- the old value), the storage policy (no second object in their folder
-- once the column is set), and no update or delete grant on the object
-- itself.

alter table public.profiles
  add column if not exists avatar_path text;

comment on column public.profiles.avatar_path is 'Path inside the private `rider-photos` bucket, not a URL - the bucket is not public, so it is read through a signed URL generated per view. Write-once for the account holder; staff can replace it. See 0090.';

-- ---------------------------------------------------------------------------
-- Storage: rider photographs
--
-- Private, unlike proof-of-delivery. These are pictures of people's faces,
-- and everyone who has any business seeing one - the rider, dispatch - is
-- signed in, so there is nothing to gain from leaving them readable by
-- anyone holding the URL.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('rider-photos', 'rider-photos', false)
on conflict (id) do nothing;

-- A rider reads their own; staff read all. The first path segment is the
-- owner's user id, which is what ties an object to an account.
drop policy if exists "rider photos: own or staff read" on storage.objects;
create policy "rider photos: own or staff read"
  on storage.objects for select
  using (
    bucket_id = 'rider-photos'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.is_dispatcher_or_above()
    )
  );

-- The same rule at the storage layer: a rider may put a file in their own
-- folder while they are still unapproved, or if they have no photo at all
-- (which is how a rider who predates this feature gets one). Staff are
-- never restricted - replacing a bad photo is their job.
drop policy if exists "rider photos: first upload or staff" on storage.objects;
create policy "rider photos: first upload or staff"
  on storage.objects for insert
  with check (
    bucket_id = 'rider-photos'
    and (
      public.is_dispatcher_or_above()
      or (
        (storage.foldername(name))[1] = auth.uid()::text
        and exists (
          select 1 from public.profiles p
          where p.id = auth.uid()
            and (p.avatar_path is null or not p.is_active)
        )
      )
    )
  );

-- Overwriting, so a retake during signup replaces the file rather than
-- littering the rider's folder with abandoned ones. Same window as the
-- insert policy: only while unapproved.
drop policy if exists "rider photos: staff update" on storage.objects;
create policy "rider photos: unapproved own or staff update"
  on storage.objects for update
  using (
    bucket_id = 'rider-photos'
    and (
      public.is_dispatcher_or_above()
      or (
        (storage.foldername(name))[1] = auth.uid()::text
        and exists (
          select 1 from public.profiles p
          where p.id = auth.uid() and not p.is_active
        )
      )
    )
  );

drop policy if exists "rider photos: staff delete" on storage.objects;
create policy "rider photos: staff delete"
  on storage.objects for delete
  using (bucket_id = 'rider-photos' and public.is_dispatcher_or_above());

-- ---------------------------------------------------------------------------
-- enforce_profile_role_change: recreated from 0083, with the photo rule and
-- the identity fields now closed to the account holder.
--
-- A rider can read everything about themselves and change none of it. Who
-- they are - their name, their phone, their Ghana Card, their licence, the
-- bike they ride - is what dispatch matched to a job and what a customer
-- was told to expect at the door. A rider editing it after the fact is
-- exactly the hand-over-your-account problem the photo rule exists to stop,
-- and it would be odd to lock the face while leaving the name open. Changes
-- go through staff.
--
-- What is deliberately still theirs to write, because it is how the app
-- works rather than who they are:
--
--   is_online                              the availability toggle
--   last_lat, last_lng, location_updated_at  live position while riding
--   must_change_password                   cleared when they set a password
--   terms_accepted_at, terms_version       stamped when they accept
--
-- Locking those would take a rider offline permanently and stop dispatch
-- seeing anyone move, so the list below is a denylist of identity, not a
-- blanket freeze.
--
-- BEFORE UPDATE only, so signup - which inserts the row through
-- handle_new_user() - is unaffected and still carries every field.
--
-- Everything above the identity block is unchanged; see 0083 for why each
-- of those is staff-only, and 0072 for permission_overrides, which has a
-- guard trigger of its own.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_profile_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  is_service_role boolean := auth.role() = 'service_role' or auth.uid() is null;
  may_manage boolean := is_service_role or public.can_manage_profile(old.role::text);
  is_super boolean := is_service_role or public.is_super_admin();
begin
  if new.role is distinct from old.role and not is_super then
    new.role := old.role;
  end if;
  if new.is_frozen is distinct from old.is_frozen and not is_super then
    new.is_frozen := old.is_frozen;
  end if;
  if new.daily_fee_tier_override_id is distinct from old.daily_fee_tier_override_id
     and not is_super
  then
    new.daily_fee_tier_override_id := old.daily_fee_tier_override_id;
  end if;

  if new.is_active is distinct from old.is_active and not may_manage then
    new.is_active := old.is_active;
  end if;
  if new.payment_access_override_until is distinct from old.payment_access_override_until
     and not may_manage
  then
    new.payment_access_override_until := old.payment_access_override_until;
  end if;
  if new.zone_id is distinct from old.zone_id and not may_manage then
    new.zone_id := old.zone_id;
  end if;

  -- Theirs to change right up until approval, and never after. is_active
  -- is exactly that line: false through signup and while they wait, true
  -- once a human has looked at the photo and accepted it. Staff can
  -- always replace one.
  if new.avatar_path is distinct from old.avatar_path
     and old.avatar_path is not null
     and old.is_active
     and not may_manage
  then
    new.avatar_path := old.avatar_path;
  end if;

  -- Identity. Read-only to the account holder; changed by request, through
  -- staff, who are then the ones on the audit trail for it.
  if not may_manage then
    new.email := old.email;
    new.full_name := old.full_name;
    new.phone := old.phone;
    new.ghana_card_number := old.ghana_card_number;
    new.date_of_birth := old.date_of_birth;
    new.residential_address := old.residential_address;
    new.vehicle_number := old.vehicle_number;
    new.vehicle_type := old.vehicle_type;
    new.driving_license_number := old.driving_license_number;
    new.driving_license_expiry := old.driving_license_expiry;
    new.vehicle_insurance_number := old.vehicle_insurance_number;
    new.vehicle_insurance_expiry := old.vehicle_insurance_expiry;
  end if;

  return new;
end;
$$;
