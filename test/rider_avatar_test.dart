import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:superd/models/profile.dart';
import 'package:superd/models/rider_rating.dart';
import 'package:superd/models/user_role.dart';
import 'package:superd/shared/widgets/rider_avatar.dart';

void main() {
  group('initials', () {
    test('one letter for one name, two for a full one', () {
      expect(RiderAvatar.initialsOf('Kofi'), 'K');
      expect(RiderAvatar.initialsOf('Kofi Mensah'), 'KM');
    });

    test('first and last, not the middle', () {
      expect(RiderAvatar.initialsOf('Kofi Kwame Mensah'), 'KM');
    });

    test('survives whatever a dispatcher actually typed', () {
      // A profile name is free text and these have all been seen.
      expect(RiderAvatar.initialsOf('  kofi   mensah  '), 'KM');
      expect(RiderAvatar.initialsOf(''), '?');
      expect(RiderAvatar.initialsOf('   '), '?');
    });

    test('handles a name that is not Latin script', () {
      // Characters, not code units: taking [0] of a string would split a
      // multi-byte glyph and render a replacement character.
      expect(RiderAvatar.initialsOf('Åsa Ödegård'), 'ÅÖ');
    });
  });

  testWidgets('falls back to initials when there is no photo', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RiderAvatar(name: 'Kofi Mensah')),
      ),
    );
    expect(find.text('KM'), findsOneWidget);
  });

  group('who may still set a photo', () {
    Profile rider({String? avatarPath, required bool isActive}) => Profile(
      id: 'r1',
      email: 'kofi@example.com',
      fullName: 'Kofi',
      role: UserRole.driver,
      isActive: isActive,
      avatarPath: avatarPath,
    );

    test('a rider still signing up can', () {
      expect(rider(isActive: false).canStillSetPhoto, isTrue);
    });

    test('and can retake it while they wait for approval', () {
      expect(
        rider(avatarPath: 'r1/photo.jpg', isActive: false).canStillSetPhoto,
        isTrue,
      );
    });

    test('once approved, the photo is fixed', () {
      expect(
        rider(avatarPath: 'r1/photo.jpg', isActive: true).canStillSetPhoto,
        isFalse,
      );
    });

    test('but an approved rider who never had one can still add it', () {
      // Every rider who predates this feature is in exactly this state.
      expect(rider(isActive: true).canStillSetPhoto, isTrue);
    });
  });

  group('rating', () {
    test('no ratings is not a score of zero', () {
      final empty = RiderRating.fromMap({'average': null, 'ratings_count': 0});
      expect(empty.hasRatings, isFalse);
      expect(empty.average, isNull);
    });

    test('reads the star breakdown the function returns', () {
      final r = RiderRating.fromMap({
        'average': 4.5,
        'ratings_count': 2,
        'five_star': 1,
        'four_star': 1,
        'three_star': 0,
        'two_star': 0,
        'one_star': 0,
      });
      expect(r.hasRatings, isTrue);
      expect(r.average, 4.5);
      expect(r.byStar[5], 1);
      expect(r.byStar[1], 0);
    });
  });
}
