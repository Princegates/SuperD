import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

import '../../core/config/env.dart';

const _viewType = 'superd-turnstile-widget';
bool _viewFactoryRegistered = false;

void _registerViewFactoryOnce() {
  if (_viewFactoryRegistered) return;
  _viewFactoryRegistered = true;
  ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
    return html.DivElement()
      ..className = 'cf-turnstile'
      ..setAttribute('data-sitekey', Env.turnstileSiteKey)
      ..setAttribute('data-callback', 'onSuperDTurnstileVerified');
  });
}

/// Renders Cloudflare Turnstile's widget inline in a Flutter Web page,
/// calling [onToken] once a visitor passes the challenge - see the
/// README's "Public form protection" section. Web implementation of the
/// conditional export in `turnstile_widget.dart`; see
/// `turnstile_widget_stub.dart` for every other platform.
///
/// Uses Turnstile's own "implicit render" mode: a plain
/// `<div class="cf-turnstile">` that Cloudflare's own script (loaded once
/// in `web/index.html`) finds and renders on its own, including elements
/// added to the DOM after that script has already run - exactly what
/// happens here, since Flutter mounts this widget well after page load.
/// There's no explicit `turnstile.render(...)` call to get wrong, just
/// the div and its data attributes; the token comes back through
/// `data-callback`, wired to a single global JS function that forwards
/// it into whichever `TurnstileWidget` is currently mounted (only one is
/// ever visible at a time - each public form is its own route).
class TurnstileWidget extends StatefulWidget {
  const TurnstileWidget({super.key, required this.onToken});

  final ValueChanged<String> onToken;

  @override
  State<TurnstileWidget> createState() => _TurnstileWidgetState();
}

class _TurnstileWidgetState extends State<TurnstileWidget> {
  @override
  void initState() {
    super.initState();
    _registerViewFactoryOnce();
    js.context['onSuperDTurnstileVerified'] = js.allowInterop(
      (String token) => widget.onToken(token),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (Env.turnstileSiteKey.isEmpty) return const SizedBox.shrink();
    return const SizedBox(
      height: 70,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
