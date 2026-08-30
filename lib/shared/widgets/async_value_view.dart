import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Small helper to render the three states of an [AsyncValue] consistently
/// across every screen (loading spinner, readable error, data).
class AsyncValueView<T> extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return value.when(
      data: data,
      loading: () =>
          loading?.call(context) ??
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          ),
      error: (err, stack) =>
          error?.call(err) ??
          Center(
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
                  if (onRetry != null) ...[
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: onRetry,
                      child: const Text('Try again'),
                    ),
                  ],
                ],
              ),
            ),
          ),
    );
  }
}
