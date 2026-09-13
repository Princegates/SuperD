import 'package:flutter/material.dart';

/// Lays tiles out in equal columns that fit the screen they are on.
///
/// Summary tiles across this app each used to set their own width - 160
/// for most, 130 or 140 for the smaller ones - which is how every one of
/// these screens ended up a single column on a phone. A 360dp handset
/// leaves 320dp inside the usual side padding, and two 160dp tiles plus
/// the 12dp gap between them need 332. Twelve pixels short, so `Wrap` did
/// the only thing it could and gave each tile a line of its own, running
/// the summary off the bottom of the screen with half the width blank
/// beside it.
///
/// So width is decided here, from the space actually available, and the
/// tiles just fill what they are given. Two up on a phone, more as the
/// window grows, and never a lone tile stranded on the last row.
///
/// This is for grids of like-sized summary tiles. It is not for a row of
/// buttons, or for the fixed column widths that keep a table's figures in
/// line - those want their own measurements and are left alone.
class TileGrid extends StatelessWidget {
  const TileGrid({
    super.key,
    required this.children,
    this.minTileWidth = 150,
    this.maxColumns = 4,
  });

  final List<Widget> children;

  /// Narrower than this and a column is dropped. Set by what the content
  /// needs to stay readable, not by what looks tidy empty.
  final double minTileWidth;

  /// Stops a wide desktop window spreading six tiles into one thin line.
  final int maxColumns;

  static const _spacing = 12.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fits =
            ((constraints.maxWidth + _spacing) / (minTileWidth + _spacing))
                .floor();
        // Two is the floor even on a very narrow screen: one tile per row
        // is the layout this exists to prevent, and a slightly cramped
        // pair still reads better than a column of six.
        final columns = fits.clamp(2, maxColumns);
        final width =
            (constraints.maxWidth - _spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: _spacing,
          runSpacing: _spacing,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}
