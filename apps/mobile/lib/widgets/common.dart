import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Status bar mock (390x44) — meniru frame Figma.
class StatusBarMock extends StatelessWidget {
  const StatusBarMock({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '9:41',
              style: TextStyle(color: C.white, fontSize: 14),
            ),
            Row(
              children: const [
                Icon(Icons.signal_cellular_alt, color: C.white, size: 16),
                SizedBox(width: 6),
                Icon(Icons.wifi, color: C.white, size: 16),
                SizedBox(width: 6),
                Icon(Icons.battery_full, color: C.white, size: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Header dengan logo "Tk" + judul + trailing opsional (mis. tombol Tambah).
class AppHeader extends StatelessWidget {
  const AppHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 47,
            height: 43,
            decoration: BoxDecoration(
              color: C.white,
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: Image.asset(
              C.logoAsset,
              width: 47,
              height: 43,
              fit: BoxFit.cover,
              // Fallback ke teks "Tk" kalau file logo belum ada di assets.
              errorBuilder: (context, error, stack) => const Text(
                'Tk',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 24),
          Text(
            title,
            style: const TextStyle(color: C.white, fontSize: 20),
          ),
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Tombol "Tambah" pill kecil (accent) untuk header.
class AddButton extends StatelessWidget {
  const AddButton({super.key, this.onTap, this.label = 'Tambah'});

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
