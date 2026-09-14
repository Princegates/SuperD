import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:superd/shared/utils/rider_photo.dart';

/// The 200 KB cap is a promise about what riders upload over mobile data,
/// so these use real encoded images rather than checking the arithmetic.

/// Noise, not flat colour: a photograph of a face compresses far worse
/// than a gradient, and a test built on an easy image proves nothing about
/// the case that matters.
Uint8List _noisyPhoto(int width, int height) {
  final image = img.Image(width: width, height: height);
  var seed = 12345;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      // Cheap deterministic pseudo-random, so a failure is reproducible.
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      image.setPixelRgb(
        x,
        y,
        seed % 256,
        (seed >> 8) % 256,
        (seed >> 16) % 256,
      );
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 100));
}

void main() {
  test('a big phone photo comes back under the cap', () {
    // 3000x4000 is an ordinary mid-range phone camera.
    final original = _noisyPhoto(3000, 4000);
    expect(original.lengthInBytes, greaterThan(RiderPhoto.maxBytes));

    final out = RiderPhoto.compress(original)!;
    expect(out.lengthInBytes, lessThanOrEqualTo(RiderPhoto.maxBytes));
  });

  test('worst-case noise still lands under the cap', () {
    // Pure noise at the output size is about as incompressible as a JPEG
    // gets - if the fallback resize did not exist, this is the case that
    // would sail past the limit.
    final out = RiderPhoto.compress(_noisyPhoto(512, 512))!;
    expect(out.lengthInBytes, lessThanOrEqualTo(RiderPhoto.maxBytes));
  });

  test('the result is square, and no larger than it needs to be', () {
    final out = RiderPhoto.compress(_noisyPhoto(1600, 1200))!;
    final decoded = img.decodeImage(out)!;

    expect(decoded.width, decoded.height, reason: 'avatars render in a circle');
    expect(decoded.width, lessThanOrEqualTo(RiderPhoto.maxDimension));
  });

  test('a small photo is not blown up', () {
    final out = RiderPhoto.compress(_noisyPhoto(200, 200))!;
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, 200);
  });

  test('a portrait crops to the middle rather than the top', () {
    // A tall photo of a rider has the face near the centre. Cropping from
    // the top-left would behead them.
    final tall = img.Image(width: 400, height: 1000);
    img.fill(tall, color: img.ColorRgb8(20, 20, 20));
    img.fillRect(
      tall,
      x1: 0,
      y1: 300,
      x2: 399,
      y2: 699,
      color: img.ColorRgb8(240, 240, 240),
    );

    final out = RiderPhoto.compress(
      Uint8List.fromList(img.encodeJpg(tall, quality: 95)),
    )!;
    final decoded = img.decodeImage(out)!;
    final middle = decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2);
    expect(middle.r, greaterThan(200), reason: 'kept the light middle band');
  });

  test('something that is not an image is refused, not mangled', () {
    final notAnImage = Uint8List.fromList('this is a text file'.codeUnits);
    expect(RiderPhoto.compress(notAnImage), isNull);
  });
}
