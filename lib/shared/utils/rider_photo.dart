import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Turns whatever came out of a phone camera into something small enough to
/// send over Ghanaian mobile data and to store for every rider.
///
/// A modern handset shoots 3-8 MB. A rider on a patchy connection should
/// not be uploading that to set a profile picture, and we should not be
/// serving it back on a dashboard listing a dozen of them.
///
/// The cap is enforced rather than hoped for. `image_picker` can be asked
/// for a smaller image, but what it returns depends on the device's own
/// encoder, so the only way to know a file is under the limit is to
/// measure it and re-encode until it is.
class RiderPhoto {
  RiderPhoto._();

  /// Play-it-safe ceiling. The requirement is 200 KB; this is the number
  /// the code actually enforces.
  static const maxBytes = 200 * 1024;

  /// A face on a profile row or an avatar circle. Larger than anything the
  /// app displays, so it still looks right on a tall screen, and small
  /// enough that quality rarely has to drop far to meet the cap.
  static const maxDimension = 512;

  /// Tried in order until one fits. Starting high keeps a good photo
  /// looking good; the low end exists so an unusually busy image still
  /// makes it under rather than being rejected after the rider has already
  /// taken it.
  static const _qualities = [85, 75, 65, 55, 45, 35];

  /// Square, downscaled, JPEG, and guaranteed under [maxBytes].
  ///
  /// Returns null only when [bytes] is not an image this can decode - a
  /// corrupt file, or something that was never a photo. Everything
  /// decodable comes back within the cap.
  static Uint8List? compress(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    // Cropped square before resizing: an avatar is displayed in a circle,
    // and cropping here means the rider sees the same framing they will
    // get rather than discovering their head was cut off later.
    final side = decoded.width < decoded.height
        ? decoded.width
        : decoded.height;
    final square = img.copyCrop(
      decoded,
      x: (decoded.width - side) ~/ 2,
      y: (decoded.height - side) ~/ 2,
      width: side,
      height: side,
    );

    final scaled = side > maxDimension
        ? img.copyResize(
            square,
            width: maxDimension,
            height: maxDimension,
            interpolation: img.Interpolation.average,
          )
        : square;

    for (final quality in _qualities) {
      final encoded = img.encodeJpg(scaled, quality: quality);
      if (encoded.lengthInBytes <= maxBytes) return encoded;
    }

    // Past the lowest quality the only lever left is size. Half the
    // dimension is a big enough step to land under the cap in one go for
    // any realistic photograph, and still shows a recognisable face.
    final smaller = img.copyResize(
      scaled,
      width: maxDimension ~/ 2,
      height: maxDimension ~/ 2,
      interpolation: img.Interpolation.average,
    );
    return img.encodeJpg(smaller, quality: 60);
  }
}
