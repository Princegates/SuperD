/// A Cloudflare Turnstile CAPTCHA widget - see the README's "Public form
/// protection" section. `dart:html`/`dart:js`/`dart:ui_web` (needed for
/// the real implementation) don't exist outside a web build, so this
/// conditionally exports the real widget only when compiling for web,
/// and a do-nothing stub everywhere else - see `turnstile_widget_web.dart`/
/// `turnstile_widget_stub.dart`. Both export the same `TurnstileWidget`
/// API; import this file, never the platform-specific ones directly.
export 'turnstile_widget_stub.dart'
    if (dart.library.html) 'turnstile_widget_web.dart';
