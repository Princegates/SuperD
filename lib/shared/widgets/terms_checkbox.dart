import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

/// The "I agree to the Terms & Privacy Policy" checkbox shared by the
/// vendor and driver signup screens - required before either form's
/// submit button enables (see each screen's `_canSubmit`). Tapping the
/// policy name pushes `/legal/terms` on top of the form rather than
/// navigating away from it, so the system/app-bar back button returns to
/// a still-filled-in form.
class TermsCheckbox extends StatelessWidget {
  const TermsCheckbox({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(color: Colors.black87, fontSize: 13.5);
    const linkStyle = TextStyle(
      color: AppTheme.primary,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: value,
          onChanged: (checked) => onChanged(checked ?? false),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('I agree to the ', style: textStyle),
                GestureDetector(
                  onTap: () => context.push('/legal/terms'),
                  child: const Text('Terms & Privacy Policy', style: linkStyle),
                ),
                const Text('.', style: textStyle),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
