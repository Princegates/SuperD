import 'package:flutter/widgets.dart';

/// Non-web fallback - see `turnstile_widget.dart`'s conditional export.
/// Renders nothing and never calls [onToken]. The two public forms this
/// is used on (a shared delivery-request link, a vendor self-signup
/// link) are only ever opened in a browser in practice - not something
/// reached from inside a native build - so there's nothing useful this
/// could do on Android/iOS/desktop even if `dart:html`/`dart:js_interop`
/// were available there, which they aren't.
class TurnstileWidget extends StatelessWidget {
  const TurnstileWidget({super.key, required this.onToken});

  final ValueChanged<String> onToken;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
