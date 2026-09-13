import 'package:flutter_test/flutter_test.dart';
import 'package:superd/core/app_identity.dart';
import 'package:superd/shared/legal/superd_legal_policy.dart';

/// The rename from SuperD to SuperDelivery was found by a rider looking at
/// a login screen, months after everything else had changed. These make the
/// next one impossible to miss the same way.
void main() {
  test('nothing user-facing still says the old name', () {
    expect(kAppName, 'SuperDelivery');

    final stale = <String>[
      for (final section in kPolicySections)
        if (RegExp(r'SuperD(?!elivery)').hasMatch(section.body)) section.title,
    ];
    expect(stale, isEmpty, reason: 'policy sections still on the old name');
  });

  test('the policy defines the platform by the name it now uses', () {
    final intro = kPolicySections.first.body;
    expect(intro, contains('SuperDelivery (the "Platform")'));
    // The defined term and the name used throughout have to be the same
    // string, or the document defines one party and then talks about
    // another.
    expect(intro, contains('("SuperDelivery", "we", "us", or "our")'));
    expect(intro, contains('Anknovate IT Services'));
  });

  test('the terms version moved with the text', () {
    expect(kTermsVersion, '1.3');
    expect(kTermsEffectiveDate, '13 September 2026');
  });
}
