import 'package:flutter/material.dart';

import '../../../shared/legal/superd_legal_policy.dart';

/// Renders [kPolicySections] - the one Terms of Service & Privacy Policy
/// document both the vendor and driver signup screens link to before
/// their "I agree" checkbox can be ticked. Public - reachable with no
/// session, same as the signup screens themselves (see the '/legal/terms'
/// exemption in app_router.dart).
class PolicyScreen extends StatelessWidget {
  const PolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms & Privacy Policy')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                Text(
                  '$kOperatorLegalName - SuperD',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Version $kTermsVersion - effective $kTermsEffectiveDate',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 24),
                for (final section in kPolicySections) ...[
                  Text(
                    section.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final paragraph in section.body.split('\n\n'))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: paragraph.contains('\n- ')
                          ? _BulletedParagraph(paragraph)
                          : Text(
                              paragraph,
                              style: const TextStyle(height: 1.45),
                            ),
                    ),
                  const SizedBox(height: 18),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Splits a paragraph on lines starting with "- " into an intro line (if
/// any) plus real bullet points, rather than showing the literal dashes.
class _BulletedParagraph extends StatelessWidget {
  const _BulletedParagraph(this.paragraph);

  final String paragraph;

  @override
  Widget build(BuildContext context) {
    final lines = paragraph.split('\n');
    final intro = <String>[];
    final bullets = <String>[];
    for (final line in lines) {
      if (line.startsWith('- ')) {
        bullets.add(line.substring(2));
      } else if (line.trim().isNotEmpty) {
        intro.add(line);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (intro.isNotEmpty) ...[
          Text(intro.join(' '), style: const TextStyle(height: 1.45)),
          const SizedBox(height: 6),
        ],
        for (final bullet in bullets)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 7, right: 8),
                  child: Icon(Icons.circle, size: 4, color: Colors.black54),
                ),
                Expanded(
                  child: Text(bullet, style: const TextStyle(height: 1.45)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
