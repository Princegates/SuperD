import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/screens/admin_shell_screen.dart';
import '../../features/admin/screens/create_delivery_screen.dart';
import '../../features/admin/screens/delivery_detail_admin_screen.dart';
import '../../features/admin/screens/staff_form_screen.dart';
import '../../features/admin/screens/vendor_form_screen.dart';
import '../../features/auth/screens/change_password_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/reset_password_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/driver/screens/delivery_detail_driver_screen.dart';
import '../../features/driver/screens/driver_dashboard_screen.dart';
import '../../features/driver/screens/driver_signup_screen.dart';
import '../../features/driver/screens/pending_approval_screen.dart';
import '../../features/public/screens/customer_request_screen.dart';
import '../../features/public/screens/track_order_screen.dart';
import '../../features/public/screens/vendor_orders_screen.dart';
import '../../features/public/screens/vendor_signup_screen.dart';
import '../../models/profile.dart';
import '../../models/user_role.dart';
import '../../models/vendor.dart';
import '../providers/core_providers.dart';
import 'fade_slide_page.dart';

/// Bridges Riverpod state changes into go_router's `refreshListenable`, so
/// the SAME [GoRouter] instance re-runs its `redirect` callback whenever
/// auth or profile state changes, instead of the app rebuilding a whole new
/// router object on every change.
///
/// That "rebuild a new GoRouter every time" approach (what this file used
/// to do) has a real bug: Riverpod updating a provider doesn't synchronously
/// swap the new router into the widget tree - Flutter schedules that for
/// the next frame. Anything that calls `context.go(...)` right after
/// triggering a provider update (e.g. clearing "must change password" then
/// navigating) can still hit the *old* router object, whose `redirect`
/// closure captured the *old* state - so it makes the old, wrong decision
/// and bounces the user right back. A single long-lived router whose
/// `redirect` reads current state fresh via `ref.read` every time it runs
/// doesn't have this gap.
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(authStateProvider, (_, _) => notifyListeners());
    ref.listen(currentProfileProvider, (_, _) => notifyListeners());
    ref.listen(driverWebLoginAllowedProvider, (_, _) => notifyListeners());
  }
}

final _routerRefreshProvider = Provider<_RouterRefreshNotifier>((ref) {
  final notifier = _RouterRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(_routerRefreshProvider);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      // Read fresh every time this runs (triggered by refreshListenable),
      // rather than closing over a value captured when the router itself
      // was built - this router is built once, so a captured value would
      // go stale immediately.
      final authState = ref.read(authStateProvider);
      final profileState = ref.read(currentProfileProvider);

      final hasSession = authState.valueOrNull?.session != null;
      final isLoading =
          authState.isLoading ||
          (hasSession && profileState.isLoading && !profileState.hasValue);
      final role = profileState.valueOrNull?.role;

      final loc = state.matchedLocation;

      // Public, no-login pages: a vendor's self-signup form, the customer
      // request page behind a vendor's public code, a vendor's own orders
      // page behind their PRIVATE ordersCode, and a customer's single-
      // order tracking page behind their tracking code. These must work
      // for a completely anonymous visitor, so they're exempt from every
      // session/role check below.
      if (loc == '/vendor-signup' ||
          loc.startsWith('/v/') ||
          loc.startsWith('/vendor-orders/') ||
          loc.startsWith('/t/')) {
        return null;
      }

      if (isLoading) {
        return loc == '/splash' ? null : '/splash';
      }

      if (!hasSession) {
        final publicRoutes = {
          '/login',
          '/forgot-password',
          // Driver self-signup is native-app only - the web dashboard is
          // back-office only, so this stays unreachable there (falls
          // through to the '/login' redirect below instead).
          if (!kIsWeb) '/driver-signup',
        };
        if (publicRoutes.contains(loc)) return null;
        if (loc == '/reset-password') {
          return state.extra is String ? null : '/forgot-password';
        }
        return '/login';
      }

      // This is normally a back-office dashboard, not the driver app - a
      // driver account signing in on web gets signed straight back out.
      // (Kept to the web build only: driver login always works fine from
      // a native mobile build.) A super admin can flip
      // `allow_driver_web_login` on from Console > Settings to test the
      // driver experience in a browser before the native apps exist.
      //
      // This reads driverWebLoginAllowedProvider - a plain one-time fetch,
      // deliberately not a realtime stream (see its doc comment): a
      // WebSocket channel that's slow to connect or times out must not be
      // able to make this decision hang or silently default to "denied".
      // Still wait for that one fetch to actually finish before deciding,
      // same reasoning as the isLoading gate above - answering "denied"
      // before the real answer arrives would be its own bug.
      final allowState = ref.read(driverWebLoginAllowedProvider);
      if (kIsWeb && role == UserRole.driver && !allowState.hasValue) {
        return loc == '/splash' ? null : '/splash';
      }
      final allowDriverWebLogin = allowState.valueOrNull ?? false;
      if (kIsWeb && role == UserRole.driver && !allowDriverWebLogin) {
        Future(() {
          ref.read(driverWebBlockedProvider.notifier).state = true;
          ref.read(authRepositoryProvider).signOut();
        });
        return loc == '/login' ? null : '/login';
      }

      // Logged in from here on. Dispatchers and super admins share the
      // '/admin' operations area; only drivers get '/driver'.
      final home = role == UserRole.driver ? '/driver' : '/admin';
      final changePasswordPath = '$home/change-password';

      if (loc == '/splash' ||
          loc == '/login' ||
          loc == '/forgot-password' ||
          loc == '/reset-password') {
        return home;
      }
      // Segment-aware, not a raw prefix check - '/driver-signup' starts
      // with the literal characters '/driver' but isn't part of that route
      // tree, so a plain `loc.startsWith('/driver')` would wrongly treat it
      // as already "home" for a driver and skip the redirect below.
      final isAdminRoute = loc == '/admin' || loc.startsWith('/admin/');
      final isDriverRoute = loc == '/driver' || loc.startsWith('/driver/');
      if (role != UserRole.driver && !isAdminRoute) return home;
      if (role == UserRole.driver && !isDriverRoute) return home;

      // A driver created by a dispatcher must set their own password before
      // touching anything else in the app.
      if ((profileState.valueOrNull?.mustChangePassword ?? false) &&
          loc != changePasswordPath) {
        return changePasswordPath;
      }

      // A driver who signed themselves up is inactive until a dispatcher
      // or super admin approves them - see `rankedDriversProvider`, which
      // also keeps a pending driver out of the assignment picker.
      const pendingApprovalPath = '/driver/pending-approval';
      if (role == UserRole.driver &&
          !(profileState.valueOrNull?.isActive ?? true) &&
          loc != pendingApprovalPath) {
        return pendingApprovalPath;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        pageBuilder: (context, state) =>
            fadeSlidePage(key: state.pageKey, child: const SplashScreen()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) =>
            fadeSlidePage(key: state.pageKey, child: const LoginScreen()),
      ),
      GoRoute(
        path: '/forgot-password',
        pageBuilder: (context, state) => fadeSlidePage(
          key: state.pageKey,
          child: const ForgotPasswordScreen(),
        ),
      ),
      GoRoute(
        path: '/reset-password',
        pageBuilder: (context, state) => fadeSlidePage(
          key: state.pageKey,
          child: ResetPasswordScreen(email: state.extra as String),
        ),
      ),

      GoRoute(
        path: '/vendor-signup',
        pageBuilder: (context, state) => fadeSlidePage(
          key: state.pageKey,
          child: const VendorSignupScreen(),
        ),
      ),
      GoRoute(
        path: '/driver-signup',
        pageBuilder: (context, state) => fadeSlidePage(
          key: state.pageKey,
          child: const DriverSignupScreen(),
        ),
      ),
      GoRoute(
        path: '/v/:code',
        pageBuilder: (context, state) => fadeSlidePage(
          key: state.pageKey,
          child: CustomerRequestScreen(code: state.pathParameters['code']!),
        ),
      ),
      // A customer's own single-order tracking page - scoped to the
      // tracking code they were given at submission, never the vendor's
      // full order list. See TrackOrderScreen's doc comment.
      GoRoute(
        path: '/t/:trackingCode',
        pageBuilder: (context, state) => fadeSlidePage(
          key: state.pageKey,
          child: TrackOrderScreen(
            trackingCode: state.pathParameters['trackingCode']!,
          ),
        ),
      ),
      // A vendor's own orders page - deliberately NOT nested under /v/:code
      // any more, since that's the public code every customer already has.
      // This is keyed by the vendor's separate, private ordersCode instead
      // - see 0027_separate_vendor_orders_code.sql.
      GoRoute(
        path: '/vendor-orders/:ordersCode',
        pageBuilder: (context, state) => fadeSlidePage(
          key: state.pageKey,
          child: VendorOrdersScreen(
            ordersCode: state.pathParameters['ordersCode']!,
          ),
        ),
      ),

      GoRoute(
        path: '/admin',
        pageBuilder: (context, state) =>
            fadeSlidePage(key: state.pageKey, child: const AdminShellScreen()),
        routes: [
          GoRoute(
            path: 'new',
            pageBuilder: (context, state) => fadeSlidePage(
              key: state.pageKey,
              child: const CreateDeliveryScreen(),
            ),
          ),
          GoRoute(
            path: 'team/new',
            pageBuilder: (context, state) => fadeSlidePage(
              key: state.pageKey,
              child: StaffFormScreen(
                roleToCreate: (state.extra as UserRole?) ?? UserRole.driver,
              ),
            ),
          ),
          GoRoute(
            path: 'team/edit',
            pageBuilder: (context, state) => fadeSlidePage(
              key: state.pageKey,
              child: StaffFormScreen(existing: state.extra as Profile),
            ),
          ),
          GoRoute(
            path: 'delivery/:id',
            pageBuilder: (context, state) => fadeSlidePage(
              key: state.pageKey,
              child: DeliveryDetailAdminScreen(
                deliveryId: state.pathParameters['id']!,
              ),
            ),
          ),
          GoRoute(
            path: 'vendors/new',
            pageBuilder: (context, state) => fadeSlidePage(
              key: state.pageKey,
              child: const VendorFormScreen(),
            ),
          ),
          GoRoute(
            path: 'vendors/edit',
            pageBuilder: (context, state) => fadeSlidePage(
              key: state.pageKey,
              child: VendorFormScreen(existing: state.extra as Vendor),
            ),
          ),
          GoRoute(
            path: 'change-password',
            pageBuilder: (context, state) => fadeSlidePage(
              key: state.pageKey,
              child: const ChangePasswordScreen(),
            ),
          ),
        ],
      ),

      GoRoute(
        path: '/driver',
        pageBuilder: (context, state) => fadeSlidePage(
          key: state.pageKey,
          child: const DriverDashboardScreen(),
        ),
        routes: [
          GoRoute(
            path: 'delivery/:id',
            pageBuilder: (context, state) => fadeSlidePage(
              key: state.pageKey,
              child: DeliveryDetailDriverScreen(
                deliveryId: state.pathParameters['id']!,
              ),
            ),
          ),
          GoRoute(
            path: 'change-password',
            pageBuilder: (context, state) => fadeSlidePage(
              key: state.pageKey,
              child: const ChangePasswordScreen(),
            ),
          ),
          GoRoute(
            path: 'pending-approval',
            pageBuilder: (context, state) => fadeSlidePage(
              key: state.pageKey,
              child: const PendingApprovalScreen(),
            ),
          ),
        ],
      ),
    ],
  );
});
