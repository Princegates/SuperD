import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Small helper to render the three states of an [AsyncValue] consistently
/// across every screen (loading spinner, readable error, data).
class AsyncValueView<T> extends StatefulWidget {
  const AsyncValueView({
    super.key,
    required this.value,
    required this.data,
    this.loading,
    this.error,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final WidgetBuilder? loading;
  final Widget Function(Object error)? error;

  /// Shown as a "Try again" button under the default error message (never
  /// shown at all if [error] overrides the default view instead). Most
  /// Realtime-backed screens already retry on their own in the background
  /// - see `resilientRealtimeStream()` - so reaching this screen at all
  /// means that either hasn't happened yet or something upstream (a
  /// one-off fetch, a stream this screen doesn't control) failed outright.
  /// Either way, a driver/dispatcher looking at a dead screen shouldn't
  /// have no way forward except leaving and coming back.
  final VoidCallback? onRetry;

  @override
  State<AsyncValueView<T>> createState() => _AsyncValueViewState<T>();
}

class _AsyncValueViewState<T> extends State<AsyncValueView<T>> {
  Timer? _revealTimer;
  bool _timerRunning = false;
  bool _revealError = false;

  @override
  void didUpdateWidget(covariant AsyncValueView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  /// A Realtime-backed [value] briefly reporting an error the instant its
  /// underlying WebSocket hiccups - then recovering on its own within
  /// `resilientRealtimeStream()`'s reconnect window - shouldn't flash the
  /// error view for that split second only to immediately replace it with
  /// real data. Delays actually showing the error view until it's stuck in
  /// an error state for a moment; a fast self-recovery never gets to
  /// render anything but the (identical-looking) loading state.
  void _syncTimer() {
    if (!widget.value.hasError) {
      _revealTimer?.cancel();
      _revealTimer = null;
      _timerRunning = false;
      if (_revealError) setState(() => _revealError = false);
      return;
    }
    if (_timerRunning) return;
    _timerRunning = true;
    _revealTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _revealError = true);
    });
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncTimer();
    return widget.value.when(
      data: widget.data,
      loading: () => _loadingView(context),
      error: (err, stack) =>
          _revealError ? _errorView(err) : _loadingView(context),
    );
  }

  Widget _loadingView(BuildContext context) =>
      widget.loading?.call(context) ??
      const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );

  Widget _errorView(Object err) {
    if (widget.error != null) return widget.error!(err);
    if (_isConnectivityError(err)) return _offlineView();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Something went wrong:\n$err',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            if (widget.onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: widget.onRetry,
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _offlineView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off, size: 36, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            "You're offline",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "We'll reconnect automatically once you have a signal.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5),
          ),
        ],
      ),
    ),
  );
}

/// Whether [err] is (transitively) a no-network failure rather than a real
/// application error - e.g. Supabase's `RealtimeSubscribeException`
/// wrapping a `SocketException: Failed host lookup` on mobile, or just
/// `WebSocketChannelException: WebSocket connection failed.` on web (the
/// browser's WebSocket API never surfaces the dart:io-style socket detail
/// mobile gets, so it needs its own, vaguer pattern here too). Matched on
/// the stringified error rather than the concrete exception types
/// (`SocketException`, `WebSocketChannelException`, Supabase's
/// `RealtimeSubscribeException`) so this doesn't need to import
/// `dart:io`/`web_socket_channel`/`realtime_client` here just to check a
/// wrapped cause.
bool _isConnectivityError(Object err) {
  final text = err.toString();
  return text.contains('SocketException') ||
      text.contains('Failed host lookup') ||
      text.contains('Connection refused') ||
      text.contains('Connection reset') ||
      text.contains('Connection timed out') ||
      text.contains('Network is unreachable') ||
      text.contains('Software caused connection abort') ||
      text.contains('WebSocketChannelException') ||
      text.contains('WebSocket connection failed');
}
