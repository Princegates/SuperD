-- SuperD: email a vendor their link when they register.
--
-- Vendors previously only gave a phone number. Adding email lets a new
-- vendor be sent their unique /v/<code> link automatically (via a
-- Database Webhook + Edge Function - see README) instead of relying on
-- whoever registered them to copy/share it by hand.

alter table public.vendors
  add column if not exists email text;

-- register_vendor's signature is changing (a new `email` parameter), so
-- the old overload needs dropping first - `create or replace` only
-- replaces a function with the exact same argument list, otherwise it
-- creates a second, ambiguous overload alongside the old one.
drop function if exists public.register_vendor(
  text, uuid, double precision, double precision, text, uuid
);

create or replace function public.register_vendor(
  vendor_name text,
  zone_id uuid,
  location_lat double precision,
  location_lng double precision,
  phone text,
  email text default null,
  created_by uuid default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  new_code text;
begin
  loop
    new_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    begin
      insert into public.vendors (
        code, vendor_name, zone_id, location_lat, location_lng, phone, email, created_by
      )
      values (
        new_code, vendor_name, zone_id, location_lat, location_lng, phone, email, created_by
      );
      exit;
    exception when unique_violation then
      -- Vanishingly unlikely with a 10-character code - just try again.
    end;
  end loop;
  return new_code;
end;
$$;

grant execute on function public.register_vendor(
  text, uuid, double precision, double precision, text, text, uuid
) to anon, authenticated;
