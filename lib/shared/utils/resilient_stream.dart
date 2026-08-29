import 'dart:async';

/// Wraps a Supabase Realtime stream so a transient WebSocket drop (e.g.
/// `RealtimeSubscribeException` after the app/tab sits idle for a while)
/// doesn't leave a `StreamProvider` stuck showing an error screen forever.
///
/// A plain `StreamProvider` just reflects whatever its stream last did -
/// once that stream emits an error, Riverpod treats it as final and won't
/// retry on its own, even though supabase_flutter's own Realtime client
/// keeps trying to reconnect under the hood; that reconnect never
/// resurfaces as a new stream to whoever already subscribed, so the
/// screen is stuck on "Something went wrong" until it's fully unmounted
/// and re-mounted from scratch.
///
/// [create] is called again - a fresh `.stream(...)` call, i.e. a brand
/// new Realtime subscription - after [retryDelay] whenever the current
/// one errors, instead of letting the error propagate. Riverpod keeps
/// showing the last good value in the meantime (no new events arrive
/// during the gap, and this wrapper never itself emits an error), so a
/// dropped connection reads as "quietly reconnecting", not a crash.
Stream<T> resilientRealtimeStream<T>(
  Stream<T> Function() create, {
  Duration retryDelay = const Duration(seconds: 3),
}) async* {
  while (true) {
    try {
      yield* create();
      // A realtime `.stream()` isn't expected to complete on its own -
      // if it somehow does, retrying is still better than going dead.
    } catch (_) {
      // Swallowed deliberately - see the doc comment above. The next
      // loop iteration re-subscribes.
    }
    await Future.delayed(retryDelay);
  }
}
