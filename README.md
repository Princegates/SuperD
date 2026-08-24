# SuperD

A free, open-source courier delivery management app for Android and iOS,
built with Flutter and a self-hostable Supabase backend.

Two roles, one app:

- **Dispatcher** — creates deliveries, assigns them to drivers, tracks every
  job on a live board.
- **Driver** — sees their assigned deliveries, gets one tap to navigate,
  updates status as the job moves (picked up → in transit → delivered), and
  captures a proof-of-delivery photo.

Everything updates in real time between dispatcher and driver devices.

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
    admin/         dispatcher dashboard, create delivery, driver list
    driver/        driver dashboard, delivery detail + status updates
  shared/          widgets and utilities used by more than one feature
supabase/
  migrations/0001_init.sql   full schema, RLS policies, storage bucket
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
2. Apply the schema in `supabase/migrations/0001_init.sql`: open the SQL
   Editor in Studio, paste the file's contents, and run it. (Or use the
   Supabase CLI: `supabase db push` against your self-hosted instance.)
3. Grab your **API URL** and **anon key** from Studio → Project Settings →
   API.

### Option B — Supabase Cloud free tier

1. Create a free project at [supabase.com](https://supabase.com).
2. Open the SQL Editor, paste in `supabase/migrations/0001_init.sql`, run it.
3. Copy the **Project URL** and **anon public key** from Project Settings →
   API.

### Promote your first dispatcher

Every new sign-up becomes a `driver` by default (see the schema — this is a
deliberate safety default). To make yourself an admin/dispatcher, sign up
once through the app, then run this in the SQL Editor:

```sql
update public.profiles set role = 'admin' where email = 'you@example.com';
```

Admins can't yet be created from within the app on purpose — role escalation
always goes through the database, so a driver can never grant themselves
dispatcher access.

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

- `profiles` — one row per user, holds `role` (`admin` or `driver`).
- `deliveries` — one row per parcel job: pickup/drop-off address +
  coordinates, customer info, status, assigned driver, timestamps.
- `delivery_status_history` — an automatic audit trail of every status
  change.
- Storage bucket `proof-of-delivery` — photos drivers capture on delivery.

Row Level Security enforces the roles at the database level, not just in
the app:

- Dispatchers (`admin` role) can see and edit everything.
- Drivers can only see deliveries assigned to them, and can only change
  `status`, `notes`, and the proof-of-delivery photo — a database trigger
  silently reverts any other field a driver's update tries to touch, so a
  compromised or modified client can't reassign jobs or edit customer data.

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
