import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// RencanaScreen — "Rencana tersimpan".
/// Section: Rencana tersimpan (Tinjau) + History Rencana Disetujui (Cek Jadwal).
class RencanaScreen extends StatelessWidget {
  const RencanaScreen({super.key, this.onTinjau, this.onCekJadwal});

  final VoidCallback? onTinjau;
  final VoidCallback? onCekJadwal;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppHeader(title: 'Rencana tersimpan'),
        const HeaderDivider(),
        const SizedBox(height: 20),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Title('Rencana tersimpan'),
                const SizedBox(height: 12),
                _SavedCard(
                  title: 'Lomba Makan',
                  subtitle: 'Sebelum 17 September 2026',
                  onTap: onTinjau,
                ),
                const SizedBox(height: 12),
                _SavedCard(
                  title: 'Lomba Makan',
                  subtitle: 'Sebelum 15 September 2026',
                  onTap: onTinjau,
                ),
                const SizedBox(height: 24),
                const _Title('History Rencana Disetujui'),
                const SizedBox(height: 12),
                _HistoryCard(onTap: onCekJadwal),
                const SizedBox(height: 12),
                _HistoryCard(onTap: onCekJadwal),
                const SizedBox(height: 12),
                _HistoryCard(onTap: onCekJadwal),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            color: C.white, fontSize: 18, fontWeight: FontWeight.w700),
      );
}

/// Card "Rencana tersimpan": ikon daun + judul + subtitle + tombol Tinjau.
class _SavedCard extends StatelessWidget {
  const _SavedCard({
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: C.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.eco_outlined, color: C.accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: C.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        color: C.detailMuted, fontSize: 12, height: 1.3)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _PillButton(
            label: 'Tinjau',
            icon: Icons.info_outline,
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}

/// Card "History Rencana Disetujui": ikon check + judul + meta + Cek Jadwal.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: C.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.check_circle_outline,
                color: C.accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Lomba Hackaton',
                    style: TextStyle(
                        color: C.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                SizedBox(height: 2),
                Text('21 Sep · oleh Anda',
                    style: TextStyle(color: C.detailMuted, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _PillButton(label: 'Cek Jadwal', onTap: onTap),
        ],
      ),
    );
  }
}

/// Tombol pill accent kecil (opsional dengan ikon).
class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, this.icon, this.onTap});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: C.accent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: C.accentText, size: 15),
              const SizedBox(width: 5),
            ],
            Text(label,
                style: const TextStyle(
                    color: C.accentText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
