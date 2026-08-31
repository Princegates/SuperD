import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Push notification groundwork: registers this device's FCM token against
/// the signed-in profile (see `device_push_tokens` in
/// `0057_device_push_tokens.sql`) and routes a notification tap to the
/// right screen. Mobile-only for now (Android/iOS) - web push needs its
/// own VAPID setup this app doesn't have, and the one thing this exists
/// for right now (telling a driver a delivery just landed on them faster
/// than SMS/email) is entirely a mobile concern anyway.
///
/// Everything here degrades quietly until an actual Firebase project is
/// wired up (`google-services.json`/`GoogleService-Info.plist` added to
/// the platform folders - see the README's "Push notifications" section):
/// [initialize] catches `Firebase.initializeApp()` throwing when there's
/// no config to find, and every other method is a no-op until that
/// succeeds - same as how this codebase already treats Twilio/Google
/// Maps/Google Directions being unconfigured.
class PushNotificationService {
  PushNotificationService(this._client);

  final SupabaseClient _client;

  static const _table = 'device_push_tokens';

  bool _initialized = false;

  bool get _supportsPush => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Sets up notification-tap routing. Call once, near app startup -
  /// idempotent, so it's safe to call again (e.g. from a rebuild).
  /// [onDeliveryNotificationTapped] fires with `data['delivery_id']` off
  /// whichever push carried one - right now that's only the "new delivery
  /// assigned" push (see notify-delivery-events).
  Future<void> initialize({
    required void Function(String deliveryId) onDeliveryNotificationTapped,
  }) async {
    if (_initialized || !_supportsPush) return;

    try {
      await Firebase.initializeApp();
    } catch (_) {
      // No Firebase project configured for this build yet - see the
      // README's "Push notifications" section. Nothing below this can do
      // anything useful without it, so stop here rather than throwing.
      return;
    }

    _initialized = true;

    void handleTap(RemoteMessage message) {
      final deliveryId = message.data['delivery_id'];
      if (deliveryId is String && deliveryId.isNotEmpty) {
        onDeliveryNotificationTapped(deliveryId);
      }
    }

    // The app was already running (foreground or background) and the
    // user tapped the system notification.
    FirebaseMessaging.onMessageOpenedApp.listen(handleTap);
    // The app was launched BY tapping the notification (it wasn't
    // running at all) - onMessageOpenedApp never fires for this case,
    // this is the only way to see it.
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) handleTap(initialMessage);
  }

  /// Asks for notification permission (required up front on iOS, and on
  /// Android 13+) and upserts this device's current token against
  /// [profileId], then keeps it current if Firebase ever rotates it.
  /// Call once a profile is known to be signed in - safe to call again
  /// for the same profile, it's an upsert on the token itself.
  Future<void> registerDevice(String profileId) async {
    if (!_initialized) return;

    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _upsertToken(profileId, token);

      FirebaseMessaging.instance.onTokenRefresh.listen(
        (newToken) => _upsertToken(profileId, newToken),
      );
    } catch (_) {
      // Firebase not configured for this build - see initialize() above.
    }
  }

  Future<void> _upsertToken(String profileId, String token) {
    return _client.from(_table).upsert({
      'profile_id': profileId,
      'token': token,
      'platform': Platform.isIOS ? 'ios' : 'android',
    }, onConflict: 'token');
  }

  /// Removes this device's token on sign-out, so a device someone else
  /// signs into next (a shared dispatch tablet, a driver's phone handed
  /// off) doesn't keep receiving push meant for whoever just signed out.
  /// Best-effort: by the time this runs the client's session is usually
  /// already cleared, so RLS may quietly turn this into a no-op rather
  /// than an actual delete. That's fine either way - the token is unique
  /// per row (see `0057_device_push_tokens.sql`), so the next person who
  /// signs into this device reclaims the same row via [registerDevice]'s
  /// upsert regardless of whether this delete succeeded.
  Future<void> unregisterDevice() async {
    if (!_initialized) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _client.from(_table).delete().eq('token', token);
      }
    } catch (_) {
      // Firebase not configured, or the token was already gone - either
      // way, nothing left to clean up.
    }
  }
}
