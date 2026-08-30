import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

import '../../core/config/env.dart';

const _viewType = 'superd-turnstile-widget';
bool _viewFactoryRegistered = false;

/// The currently-mounted `TurnstileWidget`'s token callback. Only one is
/// ever visible at a time (each public form is its own route), and this
/// is reassigned on every mount - see the class doc below for why a
/// single mutable Dart variable is used here instead of a JS-side named
/// global lookup.
ValueChanged<String>? _currentOnToken;

void _registerViewFactoryOnce() {
  if (_viewFactoryRegistered) return;
  _viewFactoryRegistered = true;
  ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
    final div = html.DivElement();
    _renderTurnstileWhenReady(div);
    return div;
  });
}

/// Calls Cloudflare's `turnstile.render(element, options)` directly on
/// [div] once the API script has finished loading, polling briefly if it
/// hasn't yet (it's loaded `async defer` in `web/index.html`, so it may
/// still be in flight when a view factory first runs). Explicit rendering
/// against the actual element reference is required here rather than
/// Turnstile's own automatic `<div class="cf-turnstile">` DOM scan: that
/// scan queries `document.querySelectorAll`, which never finds this div -
/// Flutter Web mounts `HtmlElementView` content inside a shadow root, and
/// a plain DOM query can't cross that boundary. A direct object reference
/// has no such problem.
void _renderTurnstileWhenReady(html.DivElement div) {
  final turnstile = js.context['turnstile'] as js.JsObject?;
  if (turnstile == null) {
    Timer(
      const Duration(milliseconds: 150),
      () => _renderTurnstileWhenReady(div),
    );
    return;
  }
  final options = js.JsObject.jsify({'sitekey': Env.turnstileSiteKey});
  // Assigned directly rather than as part of the jsify'd map above -
  // jsify's Map/Iterable tree-walk isn't guaranteed to hand an already-
  // interop'd Dart closure (from allowInterop) through to the resulting
  // JS object untouched, so the callback is attached to the plain JS
  // object jsify already produced instead, the same way any other JS
  // property assignment on a JsObject works.
  // The optional second parameter isn't Turnstile's documented callback
  // signature (just `function(token)`), but Cloudflare's widget was
  // observed calling it with a second argument in production - dart2js
  // compiles an allowInterop'd closure with an exact-arity dispatch
  // table (a "$1" entry for one argument), so a real 2-argument call
  // against a strictly-1-argument closure has no matching entry and
  // throws a NoSuchMethodError before the token ever reaches Dart code.
  // Accepting an optional second positional parameter makes dart2js
  // compile both a $1 and $2 entry, so either call arity works.
  options['callback'] = js.allowInterop((String token, [dynamic _]) {
    _currentOnToken?.call(token);
  });
  turnstile.callMethod('render', [div, options]);
}

/// Renders Cloudflare Turnstile's widget inline in a Flutter Web page,
/// calling [onToken] once a visitor passes the challenge - see the
/// README's "Public form protection" section. Web implementation of the
/// conditional export in `turnstile_widget.dart`; see
/// `turnstile_widget_stub.dart` for every other platform.
///
/// The view factory is only ever registered once (`_registerViewFactoryOnce`
/// no-ops on later calls), so the `render()` callback it sets up can't
/// close over a specific widget instance's `onToken` - instead, it always
/// forwards through the single mutable `_currentOnToken`, which
/// `initState` points at the *current* mount every time this widget is
/// built.
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
    _currentOnToken = widget.onToken;
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
