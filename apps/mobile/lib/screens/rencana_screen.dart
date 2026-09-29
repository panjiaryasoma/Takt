import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';
import '../viewmodels/rencana_view_model.dart';
import '../widgets/common.dart';

/// RencanaScreen — "Rencana tersimpan".
/// Section: Rencana tersimpan (Tinjau) + History Rencana Disetujui (Cek Jadwal).
/// Data dari [RencanaViewModel].
class RencanaScreen extends StatelessWidget {
  const RencanaScreen({super.key, this.onTinjau, this.onCekJadwal});

  /// Tinjau rencana tersimpan (baca lagi hasil analisis). Membawa entry-nya.
  final void Function(SavedPlanEntry entry)? onTinjau;

  /// Cek jadwal lomba yang sudah disetujui (highlight di kalender).
  final void Function(SavedPlanEntry entry)? onCekJadwal;

  static const _bulan = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];
  static const _bulanSingkat = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];

  String _deadlineLabel(DateTime d) =>
      'Sebelum ${d.day} ${_bulan[d.month - 1]} ${d.year}';

  String _decidedLabel(SavedPlanEntry e) {
    final d = e.decidedAt;
    if (d == null) return 'oleh ${e.decidedBy ?? 'Anda'}';
    return '${d.day} ${_bulanSingkat[d.month - 1]} · oleh ${e.decidedBy ?? 'Anda'}';
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RencanaViewModel>();
    final tersimpan = vm.tersimpan;
    final disetujui = vm.disetujui;

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
                if (tersimpan.isEmpty)
                  const _Empty(
                    icon: Icons.eco_outlined,
                    text:
                        'Belum ada rencana tersimpan. Simpan dari hasil analisis.',
                  )
                else
                  ...tersimpan.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _SavedCard(
                          title: e.title,
                          subtitle: _deadlineLabel(e.deadline),
                          onTap: () => onTinjau?.call(e),
                        ),
                      )),
                const SizedBox(height: 24),
                const _Title('History Rencana Disetujui'),
                const SizedBox(height: 12),
                if (disetujui.isEmpty)
                  const _Empty(
                    icon: Icons.check_circle_outline,
                    text: 'Belum ada rencana yang disetujui.',
                  )
                else
                  ...disetujui.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _HistoryCard(
                          title: e.title,
                          meta: _decidedLabel(e),
                          onTap: () => onCekJadwal?.call(e),
                        ),
                      )),
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

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
            child: Icon(icon, color: C.accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: C.detailMuted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
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
  const _HistoryCard({required this.title, required this.meta, this.onTap});

  final String title;
  final String meta;
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
              children: [
                Text(title,
                    style: const TextStyle(
                        color: C.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(meta,
                    style: const TextStyle(
                        color: C.detailMuted, fontSize: 12)),
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
