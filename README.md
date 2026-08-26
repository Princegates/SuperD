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
    0008_role_change_bootstrap.sql  fixes promoting a super admin via direct SQL
    0009_staff_profile_fields.sql   date of birth + residential address fields
  functions/
    admin-create-driver/           Edge Function: creates a driver's or dispatcher's login
    admin-delete-driver/           Edge Function: deletes a driver's or dispatcher's login
    admin-update-email/            Edge Function: fixes a driver's or dispatcher's email
    notify-driver-assigned/        Edge Function: texts the customer when a driver is assigned
    notify-vendor-registered/      Edge Function: emails a vendor their link when they register
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

There's no self-signup in the app — every account (driver, dispatcher, or
super admin) is created deliberately, either from the Team screen by an
existing super admin, or, for the very first account, straight from
Supabase:

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
   handles it client-side once `index.html` loads. Every static host
   calls this something different:
   - **Nginx**: `try_files $uri /index.html;`
   - **Apache**: a `.htaccess` rewrite rule to `index.html`
   - **Netlify**: a `_redirects` file with `/*  /index.html  200`
   - **Vercel**: a `rewrites` entry in `vercel.json`
   - **Firebase Hosting**: `"rewrites": [{"source": "**", "destination": "/index.html"}]`
     in `firebase.json`
   - **GitHub Pages**: doesn't support this natively - avoid it for this
     app, or use a `404.html`-based redirect trick instead

   Without this, `https://your-domain.example/v/AB12CD34EF` 404s instead
   of opening the request form - only `/` (the bare domain) would work.

Once it's live, set `APP_BASE_URL` to that exact domain (see **Getting the
link's domain right** below) so vendor links and their emails point at it.

### Web dashboard is back-office only

This is a dashboard for dispatchers and super admins, not a driver app -
so on **web** specifically, a driver account signing in gets signed
straight back out, with a message explaining why. Drivers still exist as
a role (a dispatcher/super admin still creates and manages them from
Team), they just can't sign in through this particular deployment; a
native mobile build wouldn't have this restriction, once one exists.

There's also no self-signup ("Create account") at all, on any platform -
every account is created deliberately, either by a super admin from Team,
or, for the very first one, straight from Supabase (see **Promote your
first super admin** above).

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

**This only records payments — it doesn't collect money.** There's no
payment gateway wired in, so card/mobile-money payments still have to
happen outside the app (a card reader, a mobile money transfer, etc.); the
app just tracks that it happened. Wiring an actual gateway (Stripe,
Paystack, Flutterwave, ...) to charge customers in-app is a bigger,
separate piece of work — the schema has a `gateway_reference` column ready
for it whenever you're ready to take that on.

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
  on the way.

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

If a vendor didn't give an email, or `RESEND_API_KEY`/`APP_BASE_URL` isn't
set, or the send fails, nothing breaks - registration still succeeds; the
failure is only visible in the function's logs
(`supabase functions logs notify-vendor-registered`).

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

### Zones

**Zones** are a fixed, admin-managed list of named areas (e.g. "East Legon",
"Osu") used to group both drivers and vendors, so a dispatcher assigning a
driver can see who's actually nearby, and so pricing can eventually vary by
area. Assign a driver to one from their edit screen in **Team**, and a
vendor to one when they're registered.

Only a super admin can create a zone or change what it covers - that
happens from **Zones** in the dashboard's nav (a super-admin-only section,
see **Admin dashboard** below), not from Vendors. There, each zone can
also be given a list of specific
named places within it (e.g. the "East Legon" zone might list "American
House", "Trasacco Valley", ...) - tap a zone to expand it, "Add location"
to pin one on the map (its name is pre-filled via reverse geocoding, but
editable), and the × on any location to remove it. Drivers and vendors
never see these individual locations - they still just pick the zone
itself by name from a dropdown; the locations are reference data for
whoever's defining what each zone actually covers.

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

- **Every dispatcher and super admin sees**: **Deliveries** (a row of
  quick-glance KPI cards - today's deliveries, pending, in progress,
  delivered today, active drivers - above the live job board itself:
  filter by status, create one, tap in for details), **Team** (add/edit/
  remove drivers, and dispatchers if you're a super admin), and
  **Vendors** (register/edit vendors, copy their links, activate/deactivate).
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
  - **Zones** - create zones (the fixed list drivers and vendors pick
    from elsewhere) and define what each one covers by pinning named
    locations within it.

A dispatcher literally has no way to reach the Admin Console sections -
they're not just hidden, there's no route for them to type into the
address bar either, since they live as plain in-app navigation state
rather than their own URLs. The underlying data is independently
RLS-protected regardless (e.g. `audit_log`'s select policy is
`is_super_admin()` only), so it's not relying on the UI alone.

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
