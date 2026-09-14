import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A rider's photograph, or their initials when there isn't one.
///
/// Always renders something. A roster where one row is blank because a
/// signed URL expired reads as a bug; initials read as "no photo yet",
/// which is the truth and is what most rows will be at first.
class RiderAvatar extends StatelessWidget {
  const RiderAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.size = 44,
  });

  /// Used for the initials fallback, so it wants the rider's display name.
  final String name;

  /// A signed URL from `ProfileRepository.riderPhotoUrl(s)`. These expire,
  /// so hold them no longer than the screen that fetched them.
  final String? photoUrl;

  final double size;

  /// One letter for a single name, two for a longer one. Trimmed and
  /// split defensively: a profile can hold anything a dispatcher typed.
  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+'))
      ..removeWhere((p) => p.isEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: url == null
          ? _Initials(name: name, size: size)
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              // A photo that fails to load falls back rather than leaving
              // a broken-image glyph on a dispatcher's roster.
              errorBuilder: (context, _, _) =>
                  _Initials(name: name, size: size),
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : _Initials(name: name, size: size),
            ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        RiderAvatar.initialsOf(name),
        style: TextStyle(
          // Scales with the circle so the same widget works at 32 on a
          // list row and at 120 on a profile screen.
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          color: AppTheme.primary,
        ),
      ),
    );
  }
}
