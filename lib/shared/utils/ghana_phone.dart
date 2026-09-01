/// Normalizes and validates Ghanaian phone numbers to the `+233XXXXXXXXX`
/// international format every SMS-sending Edge Function expects (see
/// `supabase/functions/_shared/sms.ts` and the README's SMS setup
/// section) - used by every signup and admin form that collects a phone
/// number.
class GhanaPhone {
  GhanaPhone._();

  static final RegExp _national = RegExp(r'^[0-9]{9}$');

  /// Accepts a Ghanaian number in any of the common shapes a person might
  /// type - `024xxxxxxx`, `+233xxxxxxxxx`, `233xxxxxxxxx` - with or without
  /// spaces/dashes, and returns it as `+233xxxxxxxxx`. Returns null if
  /// [raw] isn't a recognizable Ghanaian number.
  static String? normalize(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    final String national;
    if (digits.startsWith('+233')) {
      national = digits.substring(4);
    } else if (digits.startsWith('233')) {
      national = digits.substring(3);
    } else if (digits.startsWith('0')) {
      national = digits.substring(1);
    } else {
      national = digits;
    }
    if (!_national.hasMatch(national)) return null;
    return '+233$national';
  }

  /// A [TextFormField] validator. Set [required] to false for an optional
  /// field - blank stays fine, but anything typed still has to be a valid
  /// Ghanaian number.
  static String? Function(String?) validator({bool required = true}) {
    return (value) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty) return required ? 'Required' : null;
      return normalize(trimmed) == null
          ? 'Enter a valid Ghana phone number, e.g. 024 XXX XXXX'
          : null;
    };
  }
}
