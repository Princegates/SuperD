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

   Step 1 and step 2 of the roles migration **must** be separate runs —
   Postgres won't let a brand-new enum value be used in the same
   transaction that created it, so pasting both together errors with
   `unsafe use of new value ... must be committed before they can be used`.
3. Grab your **API URL** and **anon key** from Studio → Project Settings →
   API.

### Option B — Supabase Cloud free tier

1. Create a free project at [supabase.com](https://supabase.com).
2. Open the SQL Editor and run the same three files from Option A above,
   **one at a time, in order** — the roles migration's two steps can't be
   combined into a single run (see the note above).
3. Copy the **Project URL** and **anon public key** from Project Settings →
   API.

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

## How the data model works

- `profiles` — one row per user, holds `role` (`driver`, `dispatcher`, or
  `super_admin`).
- `deliveries` — one row per parcel job: pickup/drop-off address +
  coordinates, customer info, status, assigned driver, timestamps.
- `delivery_status_history` — an automatic audit trail of every status
  change.
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
