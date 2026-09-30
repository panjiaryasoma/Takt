import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Header dengan logo "Tk" + judul + trailing opsional (mis. tombol Tambah).
class AppHeader extends StatelessWidget {
  const AppHeader({super.key, required this.title, this.trailing, this.onBack});

  final String title;
  final Widget? trailing;

  /// Bila diisi, tampilkan tombol back bulat di kiri header.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          if (onBack != null) ...[
            GestureDetector(
              onTap: onBack,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: C.card,
                  shape: BoxShape.circle,
                  border: Border.all(color: C.accent.withValues(alpha: 0.6)),
                ),
                alignment: Alignment.center,
                child:
                    const Icon(Icons.chevron_left, color: C.accent, size: 22),
              ),
            ),
            const SizedBox(width: 12),
          ],
          SizedBox(
            width: 47,
            height: 43,
            child: Image.asset(
              C.logoAsset,
              width: 47,
              height: 43,
              fit: BoxFit.contain,
              // Fallback ke teks "Tk" kalau file logo belum ada di assets.
              errorBuilder: (context, error, stack) => Container(
                decoration: BoxDecoration(
                  color: C.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Tk',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: C.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            Flexible(child: trailing!),
          ],
        ],
      ),
    );
  }
}

/// Tombol "Tambah" pill kecil (accent) untuk header.
class AddButton extends StatelessWidget {
  const AddButton({super.key, this.onTap, this.label = 'Add'});

  final VoidCallback? onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: C.accent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, color: C.bg, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: C.bg,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Divider putih tebal (rounded) di bawah header.
class HeaderDivider extends StatelessWidget {
  const HeaderDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 4,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(100),
      ),
    );
  }
}

/// Heading section: judul kiri + aksi opsional kanan.
class SectionHeading extends StatelessWidget {
  const SectionHeading({super.key, required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: C.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                action!,
                style: const TextStyle(
                  color: C.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Kotak dengan garis putus-putus (dashed) — untuk dropzone upload.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.child, this.radius = 14});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(radius: radius),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: child,
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.radius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = C.navInactive
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);

    const dash = 6.0;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dash),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => false;
}


class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.semanticLabel,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
        label: semanticLabel ?? label,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.75)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class PresentationCard extends StatelessWidget {
  const PresentationCard({
    super.key,
    required this.child,
    this.highlightColor,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final Color? highlightColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: C.card,
          borderRadius: BorderRadius.circular(14),
          border: highlightColor == null
              ? null
              : Border.all(color: highlightColor!),
        ),
        child: child,
      );
}

class PresentationSectionTitle extends StatelessWidget {
  const PresentationSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: C.white,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      );
}

class HorizontalSwipeSurface extends StatefulWidget {
  const HorizontalSwipeSurface({
    super.key,
    required this.child,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.behavior = HitTestBehavior.translucent,
    this.distanceThreshold = 48,
    this.velocityThreshold = 500,
  });

  final Widget child;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;
  final HitTestBehavior behavior;
  final double distanceThreshold;
  final double velocityThreshold;

  @override
  State<HorizontalSwipeSurface> createState() =>
      _HorizontalSwipeSurfaceState();
}

class _HorizontalSwipeSurfaceState extends State<HorizontalSwipeSurface> {
  double _dragDx = 0;

  void _reset() {
    _dragDx = 0;
  }

  void _finish(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final distance = _dragDx;
    _reset();

    if (distance.abs() < widget.distanceThreshold &&
        velocity.abs() < widget.velocityThreshold) {
      return;
    }

    final direction = distance.abs() >= widget.distanceThreshold
        ? distance
        : velocity;
    if (direction < 0) {
      widget.onSwipeLeft?.call();
    } else if (direction > 0) {
      widget.onSwipeRight?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onHorizontalDragStart: (_) => _reset(),
      onHorizontalDragUpdate: (details) {
        _dragDx += details.primaryDelta ?? 0;
      },
      onHorizontalDragEnd: _finish,
      onHorizontalDragCancel: _reset,
      child: widget.child,
    );
  }
}
