import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/screens/admin_dashboard_screen.dart';
import '../../features/admin/screens/create_delivery_screen.dart';
import '../../features/admin/screens/delivery_detail_admin_screen.dart';
import '../../features/admin/screens/staff_form_screen.dart';
import '../../features/admin/screens/team_screen.dart';
import '../../features/admin/screens/vendor_form_screen.dart';
import '../../features/admin/screens/vendors_screen.dart';
import '../../features/auth/screens/change_password_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/reset_password_screen.dart';
import '../../features/auth/screens/signup_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/driver/screens/delivery_detail_driver_screen.dart';
import '../../features/driver/screens/driver_dashboard_screen.dart';
import '../../features/public/screens/customer_request_screen.dart';
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

      // Public, no-login pages: a vendor's self-signup form, and the
      // customer request/tracking pages behind a vendor's unique code.
      // These must work for a completely anonymous visitor, so they're
      // exempt from every session/role check below.
      if (loc == '/vendor-signup' || loc.startsWith('/v/')) return null;

      if (isLoading) {
        return loc == '/splash' ? null : '/splash';
      }

      if (!hasSession) {
        const publicRoutes = {'/login', '/signup', '/forgot-password'};
        if (publicRoutes.contains(loc)) return null;
        if (loc == '/reset-password') {
          return state.extra is String ? null : '/forgot-password';
        }
        return '/login';
      }

      // Logged in from here on. Dispatchers and super admins share the
      // '/admin' operations area; only drivers get '/driver'.
      final home = role == UserRole.driver ? '/driver' : '/admin';
      final changePasswordPath = '$home/change-password';

      if (loc == '/splash' ||
          loc == '/login' ||
          loc == '/signup' ||
          loc == '/forgot-password' ||
          loc == '/reset-password') {
        return home;
      }
      if (role != UserRole.driver && !loc.startsWith('/admin')) return home;
      if (role == UserRole.driver && !loc.startsWith('/driver')) return home;

      // A driver created by a dispatcher must set their own password before
      // touching anything else in the app.
      if ((profileState.valueOrNull?.mustChangePassword ?? false) &&
          loc != changePasswordPath) {
        return changePasswordPath;
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
        path: '/signup',
        pageBuilder: (context, state) =>
            fadeSlidePage(key: state.pageKey, child: const SignupScreen()),
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
        path: '/v/:code',
        pageBuilder: (context, state) => fadeSlidePage(
          key: state.pageKey,
          child: CustomerRequestScreen(code: state.pathParameters['code']!),
        ),
        routes: [
          GoRoute(
            path: 'orders',
            pageBuilder: (context, state) => fadeSlidePage(
              key: state.pageKey,
              child: VendorOrdersScreen(code: state.pathParameters['code']!),
            ),
          ),
        ],
      ),

      GoRoute(
        path: '/admin',
        pageBuilder: (context, state) => fadeSlidePage(
          key: state.pageKey,
          child: const AdminDashboardScreen(),
        ),
        routes: [
          GoRoute(
            path: 'new',
            pageBuilder: (context, state) => fadeSlidePage(
              key: state.pageKey,
              child: const CreateDeliveryScreen(),
            ),
          ),
          GoRoute(
            path: 'team',
            pageBuilder: (context, state) =>
                fadeSlidePage(key: state.pageKey, child: const TeamScreen()),
            routes: [
              GoRoute(
                path: 'new',
                pageBuilder: (context, state) => fadeSlidePage(
                  key: state.pageKey,
                  child: StaffFormScreen(
                    roleToCreate: (state.extra as UserRole?) ?? UserRole.driver,
                  ),
                ),
              ),
              GoRoute(
                path: 'edit',
                pageBuilder: (context, state) => fadeSlidePage(
                  key: state.pageKey,
                  child: StaffFormScreen(existing: state.extra as Profile),
                ),
              ),
            ],
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
            path: 'vendors',
            pageBuilder: (context, state) =>
                fadeSlidePage(key: state.pageKey, child: const VendorsScreen()),
            routes: [
              GoRoute(
                path: 'new',
                pageBuilder: (context, state) => fadeSlidePage(
                  key: state.pageKey,
                  child: const VendorFormScreen(),
                ),
              ),
              GoRoute(
                path: 'edit',
                pageBuilder: (context, state) => fadeSlidePage(
                  key: state.pageKey,
                  child: VendorFormScreen(existing: state.extra as Vendor),
                ),
              ),
            ],
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
        ],
      ),
    ],
  );
});
