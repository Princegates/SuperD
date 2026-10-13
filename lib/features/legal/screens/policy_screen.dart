import 'package:flutter/material.dart';

import '../../../shared/legal/superd_legal_policy.dart';
import '../../../core/app_identity.dart';

/// Renders one of this app's legal documents - [kPolicySections] (the
/// Terms of Service & Privacy Policy both the vendor and driver signup
/// screens link to before their "I agree" checkbox can be ticked) by
/// default, or [kCookiePolicySections] when pushed as the Cookie Policy.
/// Public - reachable with no session, same as the signup screens
/// themselves (see the '/legal/terms' and '/legal/cookies' exemptions in
/// app_router.dart).
class PolicyScreen extends StatelessWidget {
  const PolicyScreen({
    super.key,
    this.appBarTitle = 'Terms & Privacy Policy',
    this.sections = kPolicySections,
    this.version = kTermsVersion,
    this.effectiveDate = kTermsEffectiveDate,
  });

  /// A dedicated constructor rather than every call site repeating the
  /// four constants below - see [kCookiePolicySections]'s doc comment.
  const PolicyScreen.cookies({super.key})
    : appBarTitle = 'Cookie Policy',
      sections = kCookiePolicySections,
      version = kCookiePolicyVersion,
      effectiveDate = kCookiePolicyEffectiveDate;

  final String appBarTitle;
  final List<PolicySection> sections;
  final String version;
  final String effectiveDate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(appBarTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                Text(
                  '$kOperatorLegalName - $kAppName',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Version $version - effective $effectiveDate',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 24),
                for (final section in sections) ...[
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
