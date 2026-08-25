# SuperD

A free, open-source courier delivery management app for Android and iOS,
built with Flutter and a self-hostable Supabase backend.

Three roles, one app:

- **Super Admin** — everything a dispatcher can do, plus managing everyone
  else's role (promote/demote drivers, dispatchers, and other super admins)
  right from the app.
- **Dispatcher** — creates deliveries, assigns them to drivers, tracks every
  job on a live board.
- **Driver** — sees their assigned deliveries, gets one tap to navigate,
  updates status as the job moves (picked up → in transit → delivered), and
  captures a proof-of-delivery photo.

Dispatchers and super admins share the same operations dashboard; only role
management is exclusive to super admins. Everything updates in real time
across all devices.

## Why this stack

- **Flutter** — one codebase for Android and iOS.
- **Supabase** — open-source Postgres + Auth + Realtime + Storage. Run it
  for free forever by self-hosting with Docker, or use Supabase Cloud's free
  tier if you'd rather not manage a server.
- **OpenStreetMap** (via `flutter_map`) — free maps, no API key, no billing
  account required.

No paid service is required to run SuperD.

## Project layout

```
lib/
  core/            app-wide config, theme, router, riverpod providers
  models/          plain Dart models (Delivery, Profile, DeliveryStatus, ...)
  data/repositories/  all Supabase queries live here, nowhere else
  features/
    auth/          login / signup / splash
    admin/         dispatcher/super-admin dashboard, create delivery, team
    driver/        driver dashboard, delivery detail + status updates
  shared/          widgets and utilities used by more than one feature
supabase/
  migrations/
    0001_init.sql                  full schema, RLS policies, storage bucket
    0002_roles_step1_enum.sql      splits "admin" into dispatcher + super_admin
    0002_roles_step2_policies.sql  (run right after step1, see below)
    0003_payments.sql              payments table (records fees, doesn't charge)
    0004_driver_details.sql        Ghana card/vehicle number fields, driver delete policy
    0005_driver_password_reset.sql force a password change on a driver's first sign-in
    0006_profiles_realtime.sql     live-updates profiles (role changes, password flag)
    0007_dispatcher_management.sql lets a super admin add/edit/remove dispatchers too
  functions/
    admin-create-driver/           Edge Function: creates a driver's or dispatcher's login
    admin-delete-driver/           Edge Function: deletes a driver's or dispatcher's login
```

## 1. Stand up Supabase

### Option A — self-hosted (free forever)

1. Clone Supabase's official Docker setup and start it:
   ```bash
   git clone --depth 1 https://github.com/supabase/supabase
   cd supabase/docker
   cp .env.example .env      # edit passwords/JWT secret before going to production
   docker compose up -d
   ```
   Studio will be at `http://localhost:8000`, the API at
   `http://localhost:8000` as well (via Kong).
2. Apply the schema: open the SQL Editor in Studio and run each of these
   **as separate "Run" clicks, in this exact order** — paste one file's
   contents, click Run, wait for it to finish, then move to the next:
   1. `supabase/migrations/0001_init.sql`
   2. `supabase/migrations/0002_roles_step1_enum.sql`
   3. `supabase/migrations/0002_roles_step2_policies.sql`
   4. `supabase/migrations/0003_payments.sql`
   5. `supabase/migrations/0004_driver_details.sql`
   6. `supabase/migrations/0005_driver_password_reset.sql`
   7. `supabase/migrations/0006_profiles_realtime.sql`
   8. `supabase/migrations/0007_dispatcher_management.sql`

   Step 1 and step 2 of the roles migration **must** be separate runs —
   Postgres won't let a brand-new enum value be used in the same
   transaction that created it, so pasting both together errors with
   `unsafe use of new value ... must be committed before they can be used`.
3. Grab your **API URL** and **anon key** from Studio → Project Settings →
   API.
4. Deploy the two driver-management Edge Functions (needed for the "Add
   driver" / "Remove driver" buttons — see **Driver management** below).

### Option B — Supabase Cloud free tier

1. Create a free project at [supabase.com](https://supabase.com).
2. Open the SQL Editor and run the same eight files from Option A above,
   **one at a time, in order** — the roles migration's two steps can't be
   combined into a single run (see the note above).
3. Copy the **Project URL** and **anon public key** from Project Settings →
   API.
4. Deploy the two driver-management Edge Functions (see **Driver
   management** below).

### Promote your first super admin

Every new sign-up becomes a `driver` by default (see the schema — this is a
deliberate safety default). To bootstrap your first super admin, sign up
once through the app, then run this in the SQL Editor:

```sql
update public.profiles set role = 'super_admin' where email = 'you@example.com';
```

From then on, that account can promote/demote anyone else (to `driver`,
`dispatcher`, or `super_admin`) right from the app's Team screen — no more
SQL needed except for this one bootstrap step. Roles can't be changed from
within the app by anyone but a super admin; a database trigger enforces
this even if a client is compromised or modified.

### Enable "Forgot password?"

The app's password reset uses a one-time code emailed to the user, not a
deep link — simpler and more reliable on mobile. For the code to actually
appear in the email, update the template once:

Supabase dashboard → **Authentication → Email Templates → Reset Password**,
and make sure the body includes `{{ .Token }}` (the default template only
has a link). A minimal working body is just:

```
Your SuperD password reset code is: {{ .Token }}
```

## 2. Configure the app

Copy the example config and fill in the values from step 1:

```bash
cp env.json.example env.json
```

```json
{
  "SUPABASE_URL": "https://your-project.supabase.co",
  "SUPABASE_ANON_KEY": "your-anon-key"
}
```

`env.json` is gitignored — your keys never get committed. The app reads it
at build/run time via `--dart-define-from-file`, so there's no secret baked
into the app bundle as a plain asset file.

## 3. Run it

```bash
flutter pub get
flutter run --dart-define-from-file=env.json
```

Build a release APK/IPA the same way:

```bash
flutter build apk --dart-define-from-file=env.json
flutter build ios --dart-define-from-file=env.json
```

If you forget `env.json`, the app shows a friendly "not configured yet"
screen instead of crashing.

## Staff management

Dispatchers and super admins can add, edit, and remove drivers straight from
the Team screen — Full name, email, phone number, Ghana card number, and
vehicle number. Super admins can also add, edit, and remove **dispatchers**
the same way (Full name, email, phone number) — that part is exclusive to
the super admin role, since dispatchers managing other dispatchers would be
a peer managing peers. A super admin's own account can't be removed from
this screen either way; that's not a roster edit.

Creating or deleting a login needs Supabase's admin API, which requires the
project's service-role key. That key must never be embedded in the app
(anyone could pull it out of the APK and get full database access), so
those two actions go through a pair of Edge Functions instead — the
service-role key lives only on Supabase's servers, never on a device. The
same two functions handle both drivers and dispatchers.

### Supabase Cloud

Deploy them once, with the [Supabase CLI](https://supabase.com/docs/guides/cli):

```bash
supabase login
supabase link --project-ref your-project-ref
supabase functions deploy admin-create-driver
supabase functions deploy admin-delete-driver
```

### Self-hosted

The Docker Compose setup already runs a `functions` container (Deno's
edge runtime) that serves whatever is in its `volumes/functions` folder —
copy this repo's `supabase/functions` folder in there (so you end up with
`volumes/functions/admin-create-driver`, `volumes/functions/_shared`, etc.)
and restart that one container:

```bash
cp -r supabase/functions/* /path/to/supabase/docker/volumes/functions/
docker compose restart functions
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided automatically
inside every Edge Function — no need to set those yourself.

### Emailing the new account its password

**Add driver**/**Add dispatcher** generate a random temporary password and
email it straight to the new hire, using the same
[Resend](https://resend.com) account you set up for password-reset emails
(see **Enable "Forgot password?"** below — skip ahead if you haven't set
that up yet). Give the Edge Function that same Resend API key as a secret:

```bash
supabase secrets set RESEND_API_KEY=re_your_resend_api_key
```

(Self-hosted: add `RESEND_API_KEY=re_your_resend_api_key` to the `functions`
container's environment in your `docker-compose.yml`/`.env` and restart it.)

If you'd rather send from a different address than
`noreply@superd.anknovate.com`, also set `RESEND_FROM_EMAIL` (e.g.
`"SuperD <noreply@yourdomain.com>"`) — it must be on a domain you've
verified with Resend.

If `RESEND_API_KEY` isn't set, or the send fails for any reason, account
creation still succeeds — the app shows the temporary password in a dialog
as a fallback so the person adding them can share it another way.

Either way, **the new hire must set their own password on first sign-in**:
signing in with the temporary password immediately opens a mandatory
"Change password" screen (enforced by the router — there's no way to reach
the rest of the app until it's done, even by force-quitting or navigating
back).

**Edit** is a plain profile update — no Edge Function needed. Email can't
be changed from this form, since it's tied to the login itself.

**Remove** deletes the account's login entirely (their profile row goes
with it automatically). A dispatcher can only remove drivers; removing a
dispatcher requires a super admin, checked server-side inside the Edge
Function, not just hidden in the UI. Removing a super admin isn't wired up
here at all, since that's a bigger decision than a roster edit.

If you skip deploying the functions, everything else in the app still
works — "Add" and "Remove" will just show an error until they're deployed.
Editing existing accounts and self-signup are unaffected.

## How the data model works

- `profiles` — one row per user: `role` (`driver`, `dispatcher`, or
  `super_admin`), plus `full_name`, `phone`, `ghana_card_number`, and
  `vehicle_number` (the last two are mainly filled in for drivers), and
  `must_change_password` (forces the mandatory password screen described
  above for drivers added by a dispatcher).
- `deliveries` — one row per parcel job: pickup/drop-off address +
  coordinates, customer info, status, assigned driver, timestamps.
- `delivery_status_history` — an automatic audit trail of every status
  change.
- `payments` — a recorded payment against a delivery: amount, currency,
  method (cash/card/mobile money/bank transfer), and status
  (pending/paid/failed/refunded).
- Storage bucket `proof-of-delivery` — photos drivers capture on delivery.

Row Level Security enforces the roles at the database level, not just in
the app:

- Dispatchers and super admins can see and edit all deliveries.
- Drivers can only see deliveries assigned to them, and can only change
  `status`, `notes`, and the proof-of-delivery photo — a database trigger
  silently reverts any other field a driver's update tries to touch, so a
  compromised or modified client can't reassign jobs or edit customer data.
- Only super admins can change a `profiles.role` value — a separate trigger
  reverts any role change attempted by a dispatcher, driver, or a
  compromised client.

## Payments

A dispatcher can set an expected delivery fee and payment method when
creating a delivery, which records a `pending` payment. Either the
dispatcher/super admin or the driver assigned to that delivery can mark it
`paid` (e.g. once cash-on-delivery is collected) from the delivery detail
screen.

**This only records payments — it doesn't collect money.** There's no
payment gateway wired in, so card/mobile-money payments still have to
happen outside the app (a card reader, a mobile money transfer, etc.); the
app just tracks that it happened. Wiring an actual gateway (Stripe,
Paystack, Flutterwave, ...) to charge customers in-app is a bigger,
separate piece of work — the schema has a `gateway_reference` column ready
for it whenever you're ready to take that on.

## Testing

```bash
flutter analyze
flutter test
```

Both run without any Supabase project configured — they don't need
`env.json`.

## Roadmap ideas (not implemented yet)

- Customer-facing tracking page (public, keyed by `tracking_code`).
- Push notifications on status change.
- Live driver location while en route.
- Multi-stop routes / route optimization.
- Online payment gateway (charge customers in-app, not just record it).
- **Multi-tenant SaaS**: today SuperD is single-business — one Supabase
  project runs one courier company. Selling it to other companies as a
  hosted product means adding an `organizations` table, scoping every
  table and RLS policy by organization, and reworking sign-up to
  create-or-join an org, plus subscription billing for the orgs
  themselves. This is a significant redesign of the security model, not
  an incremental feature — worth its own dedicated planning pass before
  starting, especially against a database already running real traffic.
