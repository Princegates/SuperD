import 'package:flutter/material.dart';

import '../../../core/theme/console_design.dart';

/// The Admin Console's one panel primitive - every `_SectionCard`,
/// `_Card`, and bespoke `Container` + `BoxShadow` duplicated per Console
/// screen collapses into this. A flat surface with a single hairline
/// border rather than a drop shadow: the shadow told the eye "this is
/// floating above the page", which reads as a marketing dashboard
/// template; a border instead says "this is one bounded panel on a
/// control surface", closer to the operations-software feel the Console
/// actually needs. See `ConsoleColors`/`ConsoleRadius` for the tokens.
class ConsoleCard extends StatelessWidget {
  const ConsoleCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });

  final String? title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final hasHeader = title != null || icon != null || trailing != null;
    return Container(
      decoration: BoxDecoration(
        color: ConsoleColors.surface,
        borderRadius: BorderRadius.circular(ConsoleRadius.lg),
        border: Border.all(color: ConsoleColors.border),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasHeader) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (icon != null) ...[
                    _IconChip(icon: icon!, color: iconColor),
                    const SizedBox(width: ConsoleSpace.sm),
                  ],
                  if (title != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title!, style: ConsoleText.cardTitle),
                          if (subtitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Text(
                                subtitle!,
                                style: ConsoleText.cardSubtitle,
                              ),
                            ),
                        ],
                      ),
                    )
                  else
                    const Spacer(),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: ConsoleSpace.md),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? ConsoleColors.primary;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(ConsoleRadius.sm),
      ),
      child: Icon(icon, size: 16, color: c),
    );
  }
}

/// A short line for a card with nothing in it yet - same wording weight
/// across every Console tab instead of each screen inventing its own
/// grey `Text`.
class ConsoleEmptyState extends StatelessWidget {
  const ConsoleEmptyState(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ConsoleSpace.sm),
      child: Text(message, style: ConsoleText.bodyMuted),
    );
  }
}
