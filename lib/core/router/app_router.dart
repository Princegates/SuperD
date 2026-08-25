import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/screens/admin_dashboard_screen.dart';
import '../../features/admin/screens/create_delivery_screen.dart';
import '../../features/admin/screens/delivery_detail_admin_screen.dart';
import '../../features/admin/screens/staff_form_screen.dart';
import '../../features/admin/screens/team_screen.dart';
import '../../models/profile.dart';
import '../../features/auth/screens/change_password_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/reset_password_screen.dart';
import '../../features/auth/screens/signup_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/driver/screens/delivery_detail_driver_screen.dart';
import '../../features/driver/screens/driver_dashboard_screen.dart';
import '../../models/user_role.dart';
import '../providers/core_providers.dart';
import 'fade_slide_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final profileState = ref.watch(currentProfileProvider);

  final hasSession = authState.valueOrNull?.session != null;
  final isLoading =
      authState.isLoading ||
      (hasSession && profileState.isLoading && !profileState.hasValue);
  final role = profileState.valueOrNull?.role;

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final loc = state.matchedLocation;

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
