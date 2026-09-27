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

/// Header dengan logo "Tk" + judul.
class AppHeader extends StatelessWidget {
  const AppHeader({super.key, required this.title});

  final String title;

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
          const SizedBox(width: 24),
          Text(
            title,
            style: const TextStyle(color: C.white, fontSize: 20),
          ),
        ],
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
