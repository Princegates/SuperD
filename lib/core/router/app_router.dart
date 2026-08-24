import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/screens/admin_dashboard_screen.dart';
import '../../features/admin/screens/create_delivery_screen.dart';
import '../../features/admin/screens/delivery_detail_admin_screen.dart';
import '../../features/admin/screens/drivers_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/signup_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/driver/screens/delivery_detail_driver_screen.dart';
import '../../features/driver/screens/driver_dashboard_screen.dart';
import '../../models/user_role.dart';
import '../providers/core_providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final profileState = ref.watch(currentProfileProvider);

  final hasSession = authState.valueOrNull?.session != null;
  final isLoading = authState.isLoading ||
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
        if (loc == '/login' || loc == '/signup') return null;
        return '/login';
      }

      // Logged in from here on.
      final home = role == UserRole.admin ? '/admin' : '/driver';

      if (loc == '/splash' || loc == '/login' || loc == '/signup') {
        return home;
      }
      if (role == UserRole.admin && !loc.startsWith('/admin')) return home;
      if (role == UserRole.driver && !loc.startsWith('/driver')) return home;
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),

      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminDashboardScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => const CreateDeliveryScreen(),
          ),
          GoRoute(
            path: 'drivers',
            builder: (context, state) => const DriversScreen(),
          ),
          GoRoute(
            path: 'delivery/:id',
            builder: (context, state) => DeliveryDetailAdminScreen(
              deliveryId: state.pathParameters['id']!,
            ),
          ),
        ],
      ),

      GoRoute(
        path: '/driver',
        builder: (context, state) => const DriverDashboardScreen(),
        routes: [
          GoRoute(
            path: 'delivery/:id',
            builder: (context, state) => DeliveryDetailDriverScreen(
              deliveryId: state.pathParameters['id']!,
            ),
          ),
        ],
      ),
    ],
  );
});
