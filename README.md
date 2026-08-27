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
  updates status as the job moves (accept & begin trip → in transit → picked
  up → delivered), and captures a proof-of-delivery photo.

Dispatchers and super admins share the same operations dashboard; only role
management is exclusive to super admins. Everything updates in real time
across all devices.

## Why this stack

- **Flutter** — one codebase for Android and iOS.
- **Supabase** — open-source Postgres + Auth + Realtime + Storage. Run it
  for free forever by self-hosting with Docker, or use Supabase Cloud's free
  tier if you'd rather not manage a server.
- **Google Maps** (via `google_maps_flutter`) — the location picker and
  map previews for pickup/drop-off run on Google Maps, on Android, iOS,
  and web alike. This is the one piece of SuperD that isn't free: it
  needs a Google Cloud project with billing enabled and an API key you
  manage yourself (Google's free monthly credit covers normal usage for
  most deployments). See **Google Maps setup** below.

Everything except Google Maps runs with no paid service required.

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
    0008_role_change_bootstrap.sql  fixes promoting a super admin via direct SQL
    0009_staff_profile_fields.sql   date of birth + residential address fields
    0014_driver_self_signup.sql     self-signed-up drivers start pending approval, not active
    0015_driver_live_location.sql   last_lat/last_lng/location_updated_at for the Live Map
    0016_currency_ghs.sql           switches the recorded-payment currency default to GHS (Ghana cedi)
    0017_app_settings.sql           single-row app_settings table (currency), editable from Console > Settings
    0018_app_settings_theme.sql     adds the selected UI theme to app_settings
    0019_driver_web_login_toggle.sql adds allow_driver_web_login to app_settings
    0020_vendors_realtime.sql       live-updates vendors, for the new-vendor in-app notification
    0021_sms_log.sql                logs SMS send attempts per vendor, for usage-based billing (schema only - not yet wired to a UI)
    0022_delivery_pricing.sql       base_fare/price_per_km on app_settings + automatic pricing in submit_delivery_request
    0023_driver_reject_and_undo.sql lets a driver reject an unaccepted assignment or undo their last status tap
    0024_seed_accra_zones.sql       optional seed data: 10 Accra-area zones with starter named locations
    0025_driver_categories_and_status.sql  vehicle_type, is_online, is_frozen on profiles + the guards around them
    0026_zone_pricing_and_auto_assign.sql   per-zone pricing, a low-high price estimate, and same-zone auto-assignment
  functions/
    admin-create-driver/           Edge Function: creates a driver's or dispatcher's login
    admin-delete-driver/           Edge Function: deletes a driver's or dispatcher's login
    admin-update-email/            Edge Function: fixes a driver's or dispatcher's email
    notify-driver-assigned/        Edge Function: texts the customer when a driver is assigned
    notify-vendor-registered/      Edge Function: emails a vendor their link when they register
    notify-driver-application/     Edge Function: emails staff when a driver signs themselves up
    notify-driver-approved/        Edge Function: emails a driver once their signup is approved
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
   9. `supabase/migrations/0008_role_change_bootstrap.sql`
   10. `supabase/migrations/0009_staff_profile_fields.sql`
   11. `supabase/migrations/0010_vendors_zones.sql`
   12. `supabase/migrations/0011_audit_log.sql`
   13. `supabase/migrations/0012_zone_locations.sql`
   14. `supabase/migrations/0013_vendor_email.sql`

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
2. Open the SQL Editor and run the same fourteen files from Option A above,
   **one at a time, in order** — the roles migration's two steps can't be
   combined into a single run (see the note above).
3. Copy the **Project URL** and **anon public key** from Project Settings →
   API.
4. Deploy the two driver-management Edge Functions (see **Driver
   management** below).

### Promote your first super admin

Dispatcher and super admin accounts are always created deliberately, from
the Team screen by an existing super admin — there's no self-signup for
either role. (A driver can create their own account from the native app,
pending approval - see **Driver self-signup** below - but that's the one
exception.) For the very first account, create it straight from Supabase:

1. Supabase dashboard → **Authentication → Users → Add user** (email +
   password, and toggle **Auto Confirm User** on so it doesn't wait on a
   confirmation email you haven't set up yet).
2. This fires the same trigger a normal signup would, creating a matching
   `profiles` row — defaulted to `driver` (see the schema, a deliberate
   safety default). Promote it in the SQL Editor:
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

### Google Maps setup

The location picker (pickup/drop-off pin-dropping) and the small map
previews on delivery detail screens run on Google Maps. Unlike the rest
of this README, this one piece needs a paid Google Cloud account (a free
monthly credit covers normal usage) and a key you manage - there's no way
around that; it's a Google requirement, not something baked into the app.

**1. Get an API key.** [Google Cloud Console](https://console.cloud.google.com/)
→ create a project (or reuse one) → enable **billing** on it → **APIs &
Services → Library** → enable:
- **Maps SDK for Android**
- **Maps SDK for iOS**
- **Maps JavaScript API** (only if you're building the web dashboard)

Then **APIs & Services → Credentials → Create Credentials → API key**.
Restrict it (strongly recommended, since an unrestricted key can be used
by anyone who finds it):
- Android: restrict to your app's package name (`com.superd.superd`) and
  SHA-1 signing fingerprint (`keytool -list -v -keystore <path-to-your-keystore>`).
- iOS: restrict to your app's bundle ID.
- Web: restrict to your actual hosting domain (HTTP referrers) - this key
  is visible in page source no matter what, so referrer restriction is the
  real protection, not secrecy.

You can create one key per platform with its own restriction, or one
unrestricted key for local testing and tighter ones for production - your
call.

**2. Android** - add the key to `android/local.properties` (gitignored,
created automatically when you first open/build the project):
```
mapsApiKey=YOUR_ANDROID_KEY_HERE
```
`android/app/build.gradle.kts` reads it from there and injects it into
the manifest at build time - nothing to touch in the manifest itself.

**3. iOS** - copy the template and fill in your key:
```bash
cp ios/Flutter/ApiKeys.xcconfig.example ios/Flutter/ApiKeys.xcconfig
```
```
GOOGLE_MAPS_API_KEY = YOUR_IOS_KEY_HERE
```
(`ApiKeys.xcconfig` is gitignored.) This needs a Mac with Xcode to take
effect - run `pod install` in `ios/` afterward so CocoaPods pulls in the
Google Maps SDK that `google_maps_flutter_ios` depends on.

**4. Web** - edit `web/index.html` directly and replace
`YOUR_GOOGLE_MAPS_API_KEY_HERE` in the `<script src="https://maps.googleapis.com/maps/api/js?key=...">`
tag with your web key. This one isn't gitignored - a Maps JavaScript API
key is meant to be visible in page source; restrict it by HTTP referrer
in Cloud Console instead of trying to hide it.

Without a key configured for a given platform, the map screens still
build and open, they just won't render any tiles - a good way to confirm
everything else in the app still works before chasing down a key.

### Picking a location: search, current location, or tap the map

The location picker (used for a driver/dispatcher's pickup/drop-off pin,
and by a customer on the public delivery-request form) offers three ways
to set a point, all on the one Google Map:

- **Type an address** into the search box at the top and press enter (or
  the search icon) - up to 5 matches show in a dropdown; tapping one jumps
  the map there and drops the pin.
- **Use my location** - the location icon next to search grabs the
  device's current GPS position (prompting for permission if needed) and
  pins that directly. This also runs **automatically** the first time the
  picker opens with nothing already set (not when re-opening it to edit
  an existing pin, so that never gets silently overwritten) - so on most
  devices the pin is already sitting on the customer's actual location
  before they touch anything.
- **Tap the map** directly, same as before.

The address search runs on OpenStreetMap's free Nominatim service, same
as the reverse-geocoding that already fills in an address from a dropped
pin - deliberately not Google's Places Autocomplete, since that's a
separate paid API on top of the Maps SDK/JavaScript API key above, and
this app tries to avoid stacking additional billed services where a free
one does the job. The map tiles themselves still render via Google Maps
regardless of which of the three methods set the pin.

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

### Hosting the web build

Vendor and customer links (`/vendor-signup`, `/v/<code>`) only make sense
as a **web** page - that's what you hand a customer, not an app they
install. Build it with:

```bash
flutter build web --dart-define-from-file=env.json --no-web-resources-cdn
```

`--no-web-resources-cdn` matters: without it, Flutter loads its
CanvasKit renderer from Google's CDN (`gstatic.com`) at runtime instead
of the copy already bundled in your build - a bad fit for a
self-hostable app, since it silently breaks the whole page on any
network that blocks that domain (a corporate firewall, a restrictive
country, ...). With the flag, everything the page needs ships in
`build/web/` itself.

This produces a static site in `build/web/` - upload that folder's
contents to whatever serves your subdomain (a plain web server, Nginx,
Netlify, Vercel, Firebase Hosting, GitHub Pages, ...).

Two things every host needs to be configured with, or vendor/customer
links will 404:

1. **HTTPS on that subdomain** - `Vendor.email`'s link and the app's own
   `Uri.base` check both require `https://` (or `http://` for local
   testing), not a bare domain.
2. **SPA fallback**: every path must serve `index.html`, not a real file
   on disk - `/v/AB12CD34EF` doesn't exist as a file, the app's router
   handles it client-side once `index.html` loads. `web/_redirects`
   ships in this repo already, so **Netlify** picks this up automatically
   with no extra config - `flutter build web` copies it straight into
   `build/web/`. Other hosts call this something different, and need
   their own equivalent added by hand:
   - **Nginx**: `try_files $uri /index.html;`
   - **Apache**: a `.htaccess` rewrite rule to `index.html`
   - **Vercel**: a `rewrites` entry in `vercel.json`
   - **Firebase Hosting**: `"rewrites": [{"source": "**", "destination": "/index.html"}]`
     in `firebase.json`
   - **GitHub Pages**: doesn't support this natively - avoid it for this
     app, or use a `404.html`-based redirect trick instead

   Without this, `https://your-domain.example/v/AB12CD34EF` 404s instead
   of opening the request form - only `/` (the bare domain) would work.

**Deploying to Netlify specifically**: `netlify.toml` in this repo already
has the right build command and publish directory (`build/web`) - connect
the repo (Site configuration → deploy from Git) and it builds itself,
including cloning the Flutter SDK fresh each build (Netlify's own image
doesn't have Flutter installed). It reads `SUPABASE_URL` and
`SUPABASE_ANON_KEY` from Netlify's own environment variables rather than
`env.json` (which is gitignored and never reaches the build), so add both
under Site configuration → Environment variables with the same values as
your local `env.json`. Note that Netlify's UI-configured build settings
take priority over `netlify.toml` if both are set - if you've previously
set a custom Build command by hand in the dashboard, clear it (or update
it to match) so the version-controlled one in `netlify.toml` actually
takes effect.

Once it's live, set `APP_BASE_URL` to that exact domain (see **Getting the
link's domain right** below) so vendor links and their emails point at it.

### Web dashboard is back-office only

This is a dashboard for dispatchers and super admins, not a driver app -
so on **web** specifically, a driver account signing in gets signed
straight back out, with a message explaining why. Drivers still exist as
a role (a dispatcher/super admin still creates and manages them from
Team), they just can't sign in through this particular deployment; a
native mobile build wouldn't have this restriction, once one exists.

A super admin can temporarily lift this from **Console > Settings**
("Allow driver sign-in on the web") - useful for testing the driver
experience (accepting a delivery, live location sharing, ...) in a
browser before the native Android/iOS apps are built and distributed.
The Settings screen itself displays and edits it live (same `app_settings`
row as currency and theme), but the router's actual gate check
(`driverWebLoginAllowedProvider`) deliberately does a plain one-time
fetch instead of subscribing to that realtime stream - re-run on every
sign-in/out, not continuously. A driver's redirect decision shouldn't
hang, or silently fall back to "denied", just because a WebSocket
channel is slow to connect or times out, which does happen in practice
on some projects/networks; a plain REST fetch either succeeds or
fails outright; nothing to get stuck waiting on. The trade-off:
switching the toggle off no longer force-signs-out a driver already
using the web app mid-session - it only takes effect on their next
sign-in - which is a reasonable price for the gate itself being reliable.

There's still no self-signup for a **dispatcher** or **super admin**
account, on any platform - those are always created deliberately, either
by a super admin from Team, or, for the very first one, straight from
Supabase (see **Promote your first super admin** above). A **driver**
account is the one exception - see below.

### Driver self-signup

A driver can create their own account from the login screen's Driver tab
on the native app only (this route doesn't exist on the web build at all -
the router keeps it out of reach there, consistent with drivers never
being able to sign in to the web dashboard either). They pick their own
password immediately, no temporary one to change later.

That account starts **inactive**, though - pending approval - and can't
be assigned any deliveries until a dispatcher or super admin approves it
from the Team screen (the same toggle used to deactivate any existing
driver later). Until then, signing in shows a "pending approval" screen
instead of the driver dashboard. Recently self-signed-up drivers also show
a "Pending approval" badge on the Console's Onboarding tab, alongside the
existing "Awaiting password setup" one, so a super admin has one place to
spot new signups needing a look.

This is safe against a spoofed client: what decides whether a new account
starts active or pending is `raw_app_meta_data`, which can only be set
server-side with the service-role key (by the `admin-create-driver` Edge
Function, for accounts a dispatcher creates from Team) - never by
`user_metadata` a signing-up client controls. See
`supabase/migrations/0014_driver_self_signup.sql`.

### Driver application emails

Three more notifications, on top of the account-created one in **Staff
management** below - all wired up the same way as the vendor/customer
ones above: a **Supabase Database Webhook** on the `profiles` table, not
called from the app itself, so they fire no matter which screen changed
the row.

- **Application submitted** - the moment a driver self-signs-up, two
  emails go out from the same trigger: every active dispatcher and super
  admin is emailed the applicant's name, email, and phone with a nudge to
  review them from Team, and the applicant themselves gets a short
  receipt ("we've received your application, a dispatcher will review it
  soon"). An admin-created driver never triggers either (they land
  already active).
- **Application approved** - the moment a dispatcher/super admin flips a
  pending driver's toggle to active, that driver is emailed to let them
  know they can now sign in and start receiving deliveries. Deactivating
  someone, or any other profile edit, doesn't trigger this - only the
  pending → active transition does.

**Setup** (reusing the same Resend account and secret as everywhere else
in this README):

```bash
supabase functions deploy notify-driver-application
supabase functions deploy notify-driver-approved
```

Then, Supabase dashboard → **Database → Webhooks → Create a new webhook**,
twice:

| | Table | Events | Edge Function |
|---|---|---|---|
| Application submitted | `profiles` | `Insert` | `notify-driver-application` |
| Application approved | `profiles` | `Update` | `notify-driver-approved` |

Both use **Type**: `Supabase Edge Functions` and **HTTP Method**: `POST`,
same as the other webhooks in this README.

**If the Webhooks page isn't there** (some projects never provision the
`supabase_functions` schema it depends on until it's used for the first
time - you'll get `schema "supabase_functions" does not exist` if you try
the SQL-trigger route below without it), skip the dashboard entirely and
wire the same thing up with `pg_net` directly - the extension Webhooks
uses under the hood.

This route needs one extra step first: these two functions must be
deployed with JWT verification off, since they're only ever called by
this project's own database triggers (never an end-user client), and
they don't trust the caller's identity anyway - each one re-fetches
everything it emails fresh from the database by id. `supabase/config.toml`
in this repo already has that configured:

```toml
[functions.notify-driver-application]
verify_jwt = false

[functions.notify-driver-approved]
verify_jwt = false
```

(The `supabase functions deploy --no-verify-jwt` flag some older docs
mention has been dropped from current CLI versions in favor of this
config file - deploying without it present, or with an out-of-date CLI
that ignores it, is what produces `UNAUTHORIZED_INVALID_JWT_FORMAT` or
`UNAUTHORIZED_NO_AUTH_HEADER` from `net._http_response` below.)

Redeploy both once `config.toml` is in place:

```bash
supabase functions deploy notify-driver-application
supabase functions deploy notify-driver-approved
```

Then, from the **SQL Editor**:

```sql
create extension if not exists pg_net;

create or replace function public.trigger_notify_driver_application()
returns trigger
language plpgsql
as $$
begin
  perform net.http_post(
    url := 'https://your-project-ref.supabase.co/functions/v1/notify-driver-application',
    headers := '{"Content-type": "application/json"}'::jsonb,
    body := jsonb_build_object('record', row_to_json(new))
  );
  return new;
end;
$$;

drop trigger if exists notify_driver_application on public.profiles;
create trigger notify_driver_application
after insert on public.profiles
for each row
execute function public.trigger_notify_driver_application();

create or replace function public.trigger_notify_driver_approved()
returns trigger
language plpgsql
as $$
begin
  perform net.http_post(
    url := 'https://your-project-ref.supabase.co/functions/v1/notify-driver-approved',
    headers := '{"Content-type": "application/json"}'::jsonb,
    body := jsonb_build_object('record', row_to_json(new), 'old_record', row_to_json(old))
  );
  return new;
end;
$$;

drop trigger if exists notify_driver_approved on public.profiles;
create trigger notify_driver_approved
after update on public.profiles
for each row
execute function public.trigger_notify_driver_approved();
```

No `Authorization` header needed at all with `verify_jwt = false` - one
less place for a long token to get mangled by a copy-paste.

**Debugging a webhook that isn't firing**: `pg_net` sends its HTTP
requests asynchronously, so the trigger itself won't show an error even
if the call fails. Check what actually happened with:

```sql
select id, status_code, content, error_msg, created
from net._http_response
order by created desc
limit 5;
```

A `404` means the function name in the URL doesn't match anything
deployed (`supabase functions list` shows the real slugs); a `401` means
an auth problem (should no longer happen with `verify_jwt = false` set
correctly - redeploy if you still see one).

The `Authorization` header just needs to carry *some* validly-signed
project JWT to get past the Edge Function platform's own auth check - the
anon key works fine and is already public inside your app bundle anyway,
so there's nothing more sensitive being exposed by pasting it into a
trigger definition. This produces the exact same `{record, old_record}`
payload shape the dashboard's Webhooks feature would have sent, so the
Edge Functions themselves don't need to know or care which route created
the trigger.

Each function only trusts the profile's *id* (and, for the approval one,
whether `is_active` changed) from the webhook payload - the actual name/
email/phone/role sent in the email is always re-fetched fresh from the
database, so a forged request can't be used to email made-up content
anywhere. If `RESEND_API_KEY` isn't set or a send fails, nothing breaks -
the signup or approval itself still goes through; the failure is only
visible in the function's logs (`supabase functions logs
notify-driver-application` / `notify-driver-approved`).

## Staff management

Dispatchers and super admins can add, edit, and remove drivers straight from
the Team screen — Full name, email, telephone number, residential address,
Ghana card number, and vehicle number. Super admins can also add, edit, and
remove **dispatchers** the same way — Full name, date of birth, email,
telephone number, and residential address are all required for a
dispatcher (checked both in the form and server-side). Dispatcher
management is exclusive to the super admin role, since dispatchers managing
other dispatchers would be a peer managing peers. A super admin's own
account can't be removed from this screen either way; that's not a roster
edit.

The same screen has a toggle to approve a driver who signed themselves up
(see **Driver self-signup** above) or deactivate any existing driver or
dispatcher - an inactive driver shows a "Pending approval" badge and can't
be assigned deliveries until switched on.

Creating or deleting a login needs Supabase's admin API, which requires the
project's service-role key. That key must never be embedded in the app
(anyone could pull it out of the APK and get full database access), so
those actions go through a trio of Edge Functions instead — the
service-role key lives only on Supabase's servers, never on a device. The
same functions handle both drivers and dispatchers.

### Supabase Cloud

Deploy them once, with the [Supabase CLI](https://supabase.com/docs/guides/cli):

```bash
supabase login
supabase link --project-ref your-project-ref
supabase functions deploy admin-create-driver
supabase functions deploy admin-delete-driver
supabase functions deploy admin-update-email
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

**Edit** is a plain profile update, with one exception: the email field is
locked unless the signed-in user is a super admin. A super admin editing
any driver or dispatcher can fix a wrong email right there — it goes
through the `admin-update-email` Edge Function (changing someone else's
login identity needs the admin API, same reason as create/delete) and
takes effect immediately, no confirmation email required. A dispatcher
editing a driver still can't touch email.

**Remove** deletes the account's login entirely (their profile row goes
with it automatically). A dispatcher can only remove drivers; removing a
dispatcher requires a super admin, checked server-side inside the Edge
Function, not just hidden in the UI. Removing a super admin isn't wired up
here at all, since that's a bigger decision than a roster edit. Editing a
super admin's own email isn't wired up here either, for the same reason.

If you skip deploying the functions, everything else in the app still
works — "Add", "Remove", and a super admin's email fix will just show an
error until they're deployed. Editing other fields and self-signup are
unaffected.

## How the data model works

- `profiles` — one row per user: `role` (`driver`, `dispatcher`, or
  `super_admin`), plus `full_name`, `phone`, `residential_address`,
  `date_of_birth` (dispatchers only), `ghana_card_number`, and
  `vehicle_number` (the last two are drivers only), and
  `must_change_password` (forces the mandatory password screen described
  above for accounts added by a dispatcher/super admin).
- `deliveries` — one row per parcel job: pickup/drop-off address +
  coordinates, customer info, status, assigned driver, timestamps.
- `delivery_status_history` — an automatic audit trail of every status
  change.
- `payments` — a recorded payment against a delivery: amount, currency,
  method (cash/card/mobile money/bank transfer), and status
  (pending/paid/failed/refunded).
- `zones` — the fixed, admin-managed list of named areas drivers and
  vendors are grouped into.
- `zone_locations` — named places within a zone (e.g. specific landmarks),
  added by a super admin from the Admin Console to document what a zone
  actually covers.
- `vendors` — a business with a unique `code` (its public link), registered
  location, and optional zone; `created_by` is null for a self-registered
  vendor, or the staff account that added them otherwise.
- `audit_log` — an append-only record of staff/vendor/delivery/payment
  actions for the Admin Console, writable only through `log_audit_event`
  and readable only by a super admin.
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

Payments default to **GHS (Ghana cedi)** — `0016_currency_ghs.sql` sets
that as the column default and backfills any existing rows. It's still a
plain `text` column, not hardcoded into the UI (the Finance tab groups and
totals by whatever currency is actually on each row).

A super admin can change the app-wide currency from **Console > Settings**
(`0017_app_settings.sql` — a single-row `app_settings` table; only a super
admin can update it, everyone signed in can read it). Changing it only
affects new deliveries/payments going forward — amounts already recorded
keep whatever currency they were entered in, so historical payments and
the Finance tab's per-currency breakdown stay accurate even across a
currency change.

**This only records payments — it doesn't collect money.** There's no
payment gateway wired in, so card/mobile-money payments still have to
happen outside the app (a card reader, a mobile money transfer, etc.); the
app just tracks that it happened. Wiring an actual gateway (Stripe,
Paystack, Flutterwave, ...) to charge customers in-app is a bigger,
separate piece of work — the schema has a `gateway_reference` column ready
for it whenever you're ready to take that on.

### Delivery pricing (public request form)

A delivery a *customer* submits through a vendor's link (`/v/:code`, no
login) is quoted automatically:

```
Customer Delivery Price = Base Delivery Fare + Distance Charge
```

- **Base fare** and **price per km** are super-admin-configurable from
  **Console > Settings** (same `app_settings` row as currency/theme —
  `0022_delivery_pricing.sql`), defaulting to 5 and 1.5 in the app's
  currency. A **zone** can override both for vendors registered in it —
  set from that zone's card in **Console > Zones** — falling back to the
  app-wide default when left blank (`0026_zone_pricing_and_auto_assign.sql`).
- **Distance** is a straight-line (haversine great-circle) calculation
  between the vendor's registered location and the customer's dropped pin
  — not real road distance, and not a paid Distance Matrix API, consistent
  with how this app already avoids Google Places for address search. If a
  customer only types an address without dropping a pin, they're charged
  just the base fare.
- **Capped at 50** (in the app's currency) — however far the drop-off,
  this is the most a single delivery is ever quoted or charged. The
  request form shows this as a low-high **range** (roughly 15% below the
  capped amount up to it, since a straight-line distance to a freshly
  dropped pin is necessarily an estimate) via the anonymous-safe
  `get_delivery_price_estimate()` RPC — refreshed the moment a drop-off
  location is set, before the customer submits anything.
- The real charge is computed **server-side**, inside
  `submit_delivery_request` — never trusted from the client, and always
  matching the estimate's high end — and a `payments` row is created for
  the delivery automatically when the quoted amount is greater than zero.
  The confirmation screen shows this actual server-quoted fee once
  submitted.
- **Optional extras** (e.g. a fragile-item surcharge) aren't a configurable
  line-item catalog yet — a dispatcher can still adjust a delivery's
  payment amount by hand from the delivery detail screen if a particular
  order needs one.

Deliveries created directly by a dispatcher/super admin (the "New
delivery" form in the admin console) are unaffected — those already let
the dispatcher set the delivery fee by hand.

### Automatic same-zone driver assignment

A customer-submitted request doesn't need a dispatcher at all when
someone's available: `submit_delivery_request` looks for a driver in the
vendor's zone who is **online**, **active**, and **not frozen**, and
assigns them immediately (status goes straight to `assigned`, same as a
dispatcher assigning one by hand) instead of sitting at `pending`.

Among the drivers who qualify, it specifically prefers whoever **already
has the most active deliveries in that same zone** — so several requests
from the same area consolidate onto one driver's route instead of
spreading across everyone at once — tie-broken by whoever currently has
the lightest total workload (for a fair start when nobody in the zone has
any yet). If nobody in the zone is online, the delivery lands at
`pending` exactly as before, for a dispatcher to assign by hand.

This is just what happens automatically when nobody has to step in — a
dispatcher can always reassign an auto-assigned delivery afterward, the
same as any other one.

## Driver actions: reject and undo

- **Reject** - a full-size button right next to "Accept & begin trip" while
  the delivery is still `assigned` (i.e. before the driver has accepted it) -
  equal billing with accept, since it's a real fork for the driver to make,
  not a buried correction. Sends the delivery back to the unassigned pool
  (`pending`, no driver) for a dispatcher to give to someone else, and
  prompts for confirmation first since it's not reversible from the
  driver's side. The dispatcher/super admin console gets a "Delivery #... is
  unassigned and needs a new driver" notification the moment this happens,
  the same way a brand-new customer request does.
- **Undo** - tucked in the "⋮" menu (top right) once the driver has moved
  past `assigned` (`in_transit`, `picked_up`, or `delivered`), for walking
  back one step if they tapped the wrong button: `in_transit` → `assigned`,
  `picked_up` → `in_transit`, `delivered` → `picked_up`. Kept out of the way
  since it's a correction, not part of the main flow.

Rejecting needs a small, deliberately narrow exception in
`enforce_delivery_update()` (`0023_driver_reject_and_undo.sql`): normally a
driver can never change `assigned_driver_id` (that's what stops them
reassigning jobs to themselves or anyone else), but this carves out the one
case of a driver clearing *their own* assignment while it's still
`assigned` - re-checked server-side in `driver_reject_delivery()`, not just
trusted from the client. Undo needs no schema change at all - a driver can
already freely set `status` on their own assigned deliveries, so it's just
the same status-update call with the previous status.

## Driver categories and availability

Three more per-driver fields, all added in
`0025_driver_categories_and_status.sql`:

- **Vehicle type** — Motorbike, Car, Van/Truck, or Tricycle. Set from the
  Add/Edit driver form (**Team**) or a driver's own self-signup form; both
  are optional, so a driver can stay unset until edited. The **Team**
  screen groups drivers by this (with an "Unspecified vehicle" group for
  anyone without one), separately from dispatchers and super admins.
- **Online/offline** — a driver's own "available for new deliveries"
  toggle, shown as a bar at the top of their dashboard. Purely
  informational for dispatch, except that it's also what the zone
  auto-assignment algorithm (above) checks before handing them a new
  customer request - a driver who's offline is skipped, same as one who's
  inactive or frozen.
- **Frozen** — a super-admin-only control (e.g. for unpaid commission),
  toggled from **Team** with a confirmation prompt and a "Frozen" badge on
  the driver's row. A frozen driver keeps full access to whatever's
  already assigned to them - they can still work it to completion - but
  can't accept a delivery still sitting at `assigned`, and can't be newly
  assigned another one either (both blocked server-side, not just in the
  UI - see `enforce_delivery_update()`/`enforce_delivery_insert()`). Their
  own dashboard shows a persistent banner explaining why, and unfreezing
  is the same toggle in reverse. Protected the same way `role` is - a
  driver or dispatcher can't unfreeze themselves or anyone else by hand,
  only a super admin's change is let through
  (`enforce_profile_role_change()`).

## App theme

A super admin can switch the whole app's brand color from **Console >
Settings**: six built-in presets (Navy & Gold - the original brand look
and the default - Ocean Blue, Forest Green, Sunset Orange, Royal Purple,
and Charcoal), defined in `lib/core/theme/app_theme.dart` as
`kThemePresets`. Only the identity colors (`primary`/`accent` and their
light tints) change per theme; the semantic status colors (success/
warning/danger/neutral used for delivery and payment status) stay fixed
across every theme, since red-means-trouble/green-means-done is a UX
convention, not a branding choice.

It applies for every user of the app, live, not just the super admin who
changed it - the same realtime `app_settings` row that carries the
currency carries the theme. Under the hood, `AppTheme`'s colors are plain
static fields (matching how the rest of the app already reads them,
`AppTheme.primary` etc., rather than `Theme.of(context)`), so a change
alone wouldn't repaint anything already on screen; `SuperDApp` keys its
root widget on the current theme, which forces Flutter to rebuild the
entire app when it changes. Navigation isn't lost across that rebuild -
`GoRouter`'s state (the current route) lives in the router instance
itself, outside the remounted widget tree.

Adding a 7th theme is a matter of adding one more `ThemePreset` entry to
`kThemePresets` - nothing else needs to change.

## Customer SMS notifications

The moment a delivery gets a driver assigned - whether that's set right at
creation or changed later from the delivery detail screen - the customer is
texted the rider's name and phone number, via
[Twilio](https://www.twilio.com).

This isn't triggered from the app itself; it's wired up as a **Supabase
Database Webhook** on the `deliveries` table, so it fires no matter which
screen or code path changed `assigned_driver_id` - there's nothing to wire
up per-screen, and nothing extra to remember if this logic changes later.

### 1. Get a Twilio number

Sign up at [twilio.com](https://www.twilio.com) (a trial account works for
testing), buy/activate a phone number capable of sending SMS, and note down
from the console:

- **Account SID**
- **Auth Token**
- Your **Twilio phone number** (in `+1XXXXXXXXXX` format)

A trial account can only text phone numbers you've manually verified in the
Twilio console first - fine for testing, but you'll need a paid account
before real customers can receive these.

### 2. Set the secrets and deploy the function

```bash
supabase secrets set TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
supabase secrets set TWILIO_AUTH_TOKEN=your_auth_token
supabase secrets set TWILIO_FROM_NUMBER=+1XXXXXXXXXX
supabase functions deploy notify-driver-assigned
```

(Self-hosted: add those three as environment variables on the `functions`
container instead of `supabase secrets set`, same as `RESEND_API_KEY`
earlier.)

### 3. Create the Database Webhook

In the Supabase dashboard: **Database → Webhooks → Create a new webhook**.

- **Table**: `deliveries`
- **Events**: `Insert` and `Update` (a driver can be assigned at creation
  or later)
- **Type**: `Supabase Edge Functions` (not "HTTP Request" - this option
  has Supabase attach the right authorization automatically, so there's
  nothing else to configure)
- **Edge Function**: `notify-driver-assigned`
- **HTTP Method**: `POST`

That's it - no need to enable `pg_net` yourself on Supabase Cloud, it's
already on for this exact feature. Self-hosted: run
`create extension if not exists pg_net;` once first if the webhook won't
save.

### Notes

- **Customer phone numbers should be in international format**
  (`+233XXXXXXXXX`, not `0XXXXXXXXX`) - Twilio rejects anything else, and
  the dispatcher's create-delivery form doesn't currently enforce that
  format for them.
- The function only trusts the delivery's *id* from the webhook payload -
  everything else (the driver's real name/phone, the customer's real
  phone) is re-fetched fresh from the database, so a forged request can't
  be used to text an arbitrary number with made-up content.
- If the Twilio secrets aren't set, or the send fails, nothing breaks -
  the assignment itself still goes through; the failure is only visible in
  the function's logs (`supabase functions logs notify-driver-assigned`).

## Vendors, zones, and public delivery requests

A **vendor** is a business (a restaurant, a shop, ...) that wants its own
customers to be able to request a delivery without ever installing the app
or having a SuperD account. Registering a vendor - either through the
public signup page or the dispatcher/super-admin "Add vendor" screen -
generates a unique link like `https://your-app.example/v/AB12CD34EF`. That
link:

- Opens a public delivery-request form ("Ordering from *Vendor name*") for
  the vendor's own customers to fill in their name, phone, and drop-off
  location. Pickup is always the vendor's registered location, so the
  customer only ever supplies the drop-off - it lands as a `pending`
  delivery for a dispatcher to assign a driver to, same as one entered
  manually.
- Doubles as the vendor's own order-tracking page at
  `.../v/AB12CD34EF/orders` - a live list of every delivery placed through
  that link, its status, and the assigned driver's name/phone once one's
  on the way. "Live" here means polled every 5 seconds, not true Postgres
  realtime - this page is anonymous/no-login, and `deliveries` has no anon
  read policy at all (only the scoped RPC below), so there's no table to
  subscribe to without opening up direct access that would let anyone
  enumerate other vendors' orders. A status change animates in (color,
  icon, and label cross-fade) rather than snapping, and each order card
  eases into place the first time it appears.

None of this needs a login. It's built on four Postgres functions
(`register_vendor`, `get_vendor_by_code`, `submit_delivery_request`,
`get_vendor_deliveries`) that Supabase's `anon` key is allowed to call -
each one is scoped strictly to the single vendor matched by the code it's
given, and there's no direct table access for `anon` at all, so there's no
way to enumerate or read another vendor's data through it.

### Getting the link's domain right

The vendor's link needs a real `http(s)://` address in front of it. When
you're running/managing SuperD as a **web build**, this is automatic - it
uses the page's own address. When staff manage vendors from a **non-web
build** (the Android/iOS/desktop app), there's no page address to read, so
set `APP_BASE_URL` in your `env.json` to wherever the web build is actually
hosted:

```json
{
  "SUPABASE_URL": "...",
  "SUPABASE_ANON_KEY": "...",
  "APP_BASE_URL": "https://your-app-domain.example"
}
```

Leave it out entirely for a web-only deployment. Without it, on a non-web
build, vendor links fall back to a bare `/v/<code>` path - accurate, but
not something you can actually hand a customer.

### Emailing a vendor their link

A vendor can give an email address when registering (self-signup or the
"Add vendor" screen). If they do, they're emailed their `/v/<code>` link
the moment their record is created - one less thing for whoever registered
them to remember to share. SMS delivery of the same link is planned as a
follow-up; email comes first.

Like the customer SMS notification above, this is wired up as a
**Supabase Database Webhook** (not called from the app itself), so it
fires no matter which screen registered the vendor:

1. **Reuse your existing Resend account** (the same one from **Emailing
   the new account its password**) - no new signup needed, just deploy the
   function with that same secret already set:
   ```bash
   supabase functions deploy notify-vendor-registered
   ```
2. **Set `APP_BASE_URL`** as a secret too, so the function knows what
   domain to put in front of the vendor's code (Edge Functions can't read
   this from `env.json` - that's a Flutter build-time value, this is a
   separate runtime secret for the function itself):
   ```bash
   supabase secrets set APP_BASE_URL=https://your-app-domain.example
   ```
   (Self-hosted: add it as an environment variable on the `functions`
   container instead, same as `RESEND_API_KEY`.)
3. **Create the Database Webhook**: Supabase dashboard →
   **Database → Webhooks → Create a new webhook**.
   - **Table**: `vendors`
   - **Events**: `Insert` only (a vendor's link doesn't change after
     registration, so there's nothing to re-send on update)
   - **Type**: `Supabase Edge Functions`
   - **Edge Function**: `notify-vendor-registered`
   - **HTTP Method**: `POST`

**If the Webhooks page isn't there** (same situation as the driver
application emails above - some projects only get a raw
trigger-to-Postgres-function form under **Database → Triggers**, not the
polished Edge-Function webhook picker): use the same `pg_net` fallback.
`supabase/config.toml` already has `notify-vendor-registered` set to
`verify_jwt = false` for this reason - redeploy it once that's in place,
then from the **SQL Editor**:

```sql
create extension if not exists pg_net;

create or replace function public.trigger_notify_vendor_registered()
returns trigger
language plpgsql
as $$
begin
  perform net.http_post(
    url := 'https://your-project-ref.supabase.co/functions/v1/notify-vendor-registered',
    headers := '{"Content-type": "application/json"}'::jsonb,
    body := jsonb_build_object('record', row_to_json(new))
  );
  return new;
end;
$$;

drop trigger if exists notify_vendor_registered on public.vendors;
create trigger notify_vendor_registered
after insert on public.vendors
for each row
execute function public.trigger_notify_vendor_registered();
```

Same debugging approach too - `pg_net` sends this asynchronously, so
check what actually happened with
`select * from net._http_response order by created desc limit 5;`
in the SQL Editor.

If a vendor didn't give an email, or `RESEND_API_KEY`/`APP_BASE_URL` isn't
set, or the send fails, nothing breaks - registration still succeeds; the
failure is only visible in the function's logs
(`supabase functions logs notify-vendor-registered`).

The same webhook also emails every active dispatcher/super admin a "New
vendor registered on SuperD" notice, independently of whether the vendor
themselves has an email on file or their own send succeeded - staff still
hear about it either way. On top of that, whoever's got the admin
dashboard open sees an in-app notification the moment a new vendor
registers, the same `SnackBar` + "View" pattern as new deliveries and new
driver assignments - backed by realtime on the `vendors` table
(`0020_vendors_realtime.sql`), not the webhook, so it fires even if
`RESEND_API_KEY`/`APP_BASE_URL` were never configured at all.

To register as a vendor yourself, visit `/vendor-signup` - no dispatcher
needed. To register one on a vendor's behalf instead, open **Vendors**
from the dashboard's nav → **Add vendor**.

From that same **Vendors** screen, a dispatcher/super admin can edit a
vendor's name, phone, zone, or location at any time (the pencil icon opens
a full edit form), and can deactivate a vendor's link with the toggle icon
on its card - an inactive link stops accepting new delivery requests, but
the vendor's existing orders and tracking page keep working. Deactivating
never changes the vendor's `code`, so reactivating restores the exact same
link.

The trash icon **permanently deletes** a vendor instead - unlike
deactivating, this can't be undone, and Postgres rejects it outright if
the vendor has any delivery history at all (same foreign-key protection
as deleting a zone - reassign or leave those deliveries be; deactivate
the vendor if that's really what you want instead). There's no soft
"undelete" - only ever delete a vendor that was registered by mistake and
has no real orders against it yet.

### Zones

**Zones** are a fixed, admin-managed list of named areas (e.g. "East Legon",
"Osu") used to group both drivers and vendors, so a dispatcher assigning a
driver can see who's actually nearby, price customer requests by area, and
auto-assign a driver without a dispatcher at all when one's available (see
**Automatic same-zone driver assignment** above). Assign a driver to one
from their edit screen in **Team**, and a vendor to one when they're
registered.

Only a super admin can create a zone or change what it covers - that
happens from **Zones** in the dashboard's nav (a super-admin-only section,
see **Admin dashboard** below), not from Vendors. There, each zone card
has:

- **A pricing override** - its own base fare / price per km, overriding
  the app-wide default from **Console > Settings** for any vendor
  registered in it. Leave either field blank to keep using the default.
- **A list of specific named places within it** (e.g. the "East Legon"
  zone might list "American House", "Trasacco Valley", ...) - tap a zone
  to expand it, "Add location" to pin one on the map (its name is
  pre-filled via reverse geocoding, but editable), and the × on any
  location to remove it. Drivers and vendors never see these individual
  locations - they still just pick the zone itself by name from a
  dropdown; the locations are reference data for whoever's defining what
  each zone actually covers.

`0024_seed_accra_zones.sql` optionally seeds 10 ready-made zones covering
the greater Accra area (Central Accra, Airport-East Legon,
Osu-Cantonments-Labone, Legon-Madina-North Accra, Adenta-Aburi Corridor,
Teshie-Nungua-Spintex, Tema-Kpone, West Accra, North-West Accra,
Kasoa-Outer West), each with a starter list of named locations - a
head start for a deployer operating there, not something the app assumes.
Skip that migration (or just delete/rename what it adds afterwards from
Console > Zones) if you're deploying somewhere else. The seeded locations
have no coordinates - add one from the map for any that are worth pinning
exactly.

### Rider suggestions

When assigning a driver - whether creating a delivery or from an existing
one's detail screen - drivers already in the same zone as the delivery are
listed first, then everyone else ordered by who currently has the fewest
active jobs. Same-zone matches are labelled "(Suggested)". This is a plain,
free, instant calculation done entirely on-device - not a call to any
external AI service - since "suggest the best rider" reduces to exactly
that: proximity (by zone) and current workload.

## Admin dashboard

Everything a dispatcher or super admin can do lives behind one persistent
navigation surface - a sidebar on a wide screen, a hamburger-menu drawer on
a narrow one - instead of separate full-screen pages you push into and
back out of. What shows up in the nav is role-based:

- **Every dispatcher and super admin sees**: **Home** (the landing page,
  shown before you pick a specific function - a SuperD-branded header, a
  row of quick-glance KPI cards, all deliveries broken down by status, and
  one-tap links into every other section this role can reach), **Deliveries**
  (the live job board: filter by status, create one, tap in for details),
  **Team** (add/edit/remove drivers, and dispatchers if you're a super
  admin), **Vendors** (register/edit vendors, copy their links,
  activate/deactivate), and **Live Map** (every driver currently sharing
  their location, live on Google Maps - see **Live driver tracking**
  below).
- **Super admins additionally see**, grouped under an "Admin Console"
  header in the nav:
  - **Overview** - reporting/analytics computed live from existing data:
    total deliveries by status, completion/cancellation rate, a
    top-drivers leaderboard by completed deliveries, zone activity, and
    top vendors by volume.
  - **Finance** - revenue reconciliation across every payment ever
    recorded: collected vs outstanding (and failed/refunded, when
    present) per currency, a breakdown by payment method, and a
    recent-payments feed.
  - **Audit log** - a chronological record of who did what: role changes,
    staff added/removed, vendors registered/edited/(de)activated, drivers
    assigned, deliveries created, and payments marked paid. Entries are
    written by a `log_audit_event` database function the instant each
    action succeeds elsewhere in the app, and only a super admin can ever
    read them back (RLS on `audit_log` has no policy for anyone else, and
    there's no insert/update/delete policy at all - the log can only
    grow, through that one function, never be edited after the fact).
  - **Onboarding** - a single triage view of recently added staff and
    vendors, flagging what's incomplete (a driver who hasn't set their
    own password yet, a vendor with no zone or a deactivated link) with a
    direct link into the Team/Vendors edit forms to fix it. It doesn't
    duplicate those forms - just surfaces who needs attention.
  - **Zones** - create, rename, or delete zones (the fixed list drivers
    and vendors pick from elsewhere), and define what each one covers by
    pinning named locations within it. Deleting a zone still in use by a
    vendor, driver, or delivery is rejected (reassign those first).
  - **Settings** - app-wide settings: currency (see **Payments** above),
    the UI theme, delivery pricing (see **Delivery pricing** above), and
    whether drivers may sign in on web (see **Web dashboard is
    back-office only**). Six built-in color themes (Navy & Gold, Ocean
    Blue, Forest Green, Sunset Orange, Royal Purple, Charcoal) - picking
    one applies for every user of the app, not just the super admin who
    changed it. All of these are backed by the single-row `app_settings`
    table.

A dispatcher literally has no way to reach the Admin Console sections -
they're not just hidden, there's no route for them to type into the
address bar either, since they live as plain in-app navigation state
rather than their own URLs. The underlying data is independently
RLS-protected regardless (e.g. `audit_log`'s select policy is
`is_super_admin()` only), so it's not relying on the UI alone.

### Live driver tracking

The **Live Map** section shows every driver currently sharing their
position as a marker on Google Maps, updating in real time. There's no
background tracking and nothing persists once a driver's app is closed:

- A driver's own app pushes their GPS position (`profiles.last_lat`/
  `last_lng`/`location_updated_at`) every 15 seconds, for as long as their
  dashboard screen stays open and location permission is granted - closing
  the app or losing permission just stops the updates, nothing to turn off
  server-side.
- A driver whose last update is more than 15 minutes old drops off the map
  entirely (`Profile.hasRecentLocation`), so a stale position from a
  driver who went offline a while ago never lingers looking live.
- No new RLS policy was needed for this: a driver can already update any
  column on their own `profiles` row (`0002_roles_step2_policies.sql`),
  and `profiles` was already in the realtime publication
  (`0006_profiles_realtime.sql`), so a dispatcher/super admin's Live Map
  picks up every update automatically.

**Nothing showing up on the Live Map / no location prompt on Android?**
Android only shows the runtime permission dialog for a permission the app
actually declares - `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` in
`android/app/src/main/AndroidManifest.xml`. Without them,
`Geolocator.requestPermission()` resolves immediately without ever
prompting the driver, so location never gets shared and nothing looks
wrong in the UI. If you're on an emulator, also open **Extended controls →
Location**, set a point (or play a route), and make sure "Location" is
toggled on for the AVD - a fresh emulator has no location fix at all until
you set one.

### In-app notifications

Three real-time alerts, all plain in-app `SnackBar`s (not push
notifications, not email) - they only show up while the relevant
dashboard is actually open, computed by diffing the same realtime
streams every screen already watches, so there's no separate
notification pipeline to maintain:

- **Dispatcher/super admin** get one the moment a new delivery request
  comes in (from a vendor's customer link, or created directly) - "New
  delivery request from *customer name*", with a **View** action that
  jumps straight to it.
- **Driver** get one the moment a delivery is newly assigned to them -
  "New delivery assigned: #*tracking code*", same **View** action.
- **Dispatcher/super admin** also get one the moment a new vendor
  registers - "New vendor registered: *vendor name*", with a **View**
  action that jumps to the Vendors section.

None of these fire on the very first load of a dashboard (only once
there's a prior snapshot to diff against), so opening the app to an
already-full list doesn't trigger a flood of notifications for things
that were already there.

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
