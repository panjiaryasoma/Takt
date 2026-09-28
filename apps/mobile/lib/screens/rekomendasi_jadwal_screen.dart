import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/competition_brief.dart';
import '../theme/app_theme.dart';
import '../viewmodels/jadwal_view_model.dart';

/// RekomendasiJadwalScreen — dibuka dari Review Brief saat pilih "Tambah
/// Jadwal". Judul & deskripsi terisi otomatis dari nama lomba; AI (sekarang
/// heuristik) merekomendasikan slot pengerjaan dari jadwal kosong pengguna
/// sebelum deadline. Pengguna bisa hapus slot lalu submit final.
class RekomendasiJadwalScreen extends StatefulWidget {
  const RekomendasiJadwalScreen({
    super.key,
    required this.brief,
    this.onBack,
    this.onSubmitDone,
  });

  final CompetitionBrief brief;
  final VoidCallback? onBack;
  final VoidCallback? onSubmitDone;

  @override
  State<RekomendasiJadwalScreen> createState() =>
      _RekomendasiJadwalScreenState();
}

class _RekomendasiJadwalScreenState extends State<RekomendasiJadwalScreen> {
  late List<DateTimeRange> _slot;

  static const _hari = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
  static const _bulan = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];

  @override
  void initState() {
    super.initState();
    _hitungRekomendasi();
  }

  void _hitungRekomendasi() {
    final vm = context.read<JadwalViewModel>();
    _slot = vm.rekomendasiSlot(
      sebelum: widget.brief.deadline,
      butuhSesi: 4,
      durasiMenit: 120,
    );
  }

  String _labelSlot(DateTimeRange r) {
    final s = r.start;
    final e = r.end;
    final hh = (int v) => v.toString().padLeft(2, '0');
    return '${_hari[s.weekday - 1]}, ${s.day} ${_bulan[s.month - 1]} · '
        '${hh(s.hour)}.${hh(s.minute)}–${hh(e.hour)}.${hh(e.minute)}';
  }

  void _submit() {
    final vm = context.read<JadwalViewModel>();
    if (_slot.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada slot untuk ditambahkan')),
      );
      return;
    }
    vm.terapkanRekomendasi(
      competitionId: widget.brief.competitionId,
      judulLomba: widget.brief.nama,
      deskripsi: widget.brief.deskripsi,
      slot: _slot,
    );
    widget.onSubmitDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.brief;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back kiri atas
          GestureDetector(
            onTap: widget.onBack,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: C.card,
                shape: BoxShape.circle,
                border: Border.all(color: C.accent.withValues(alpha: 0.6)),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.chevron_left, color: C.accent, size: 22),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Rencana Pengerjaan',
              style: TextStyle(color: C.white, fontSize: 24)),
          const SizedBox(height: 4),
          const Text(
            'Judul & deskripsi terisi otomatis dari lomba. AI merekomendasikan '
            'slot dari jadwal kosong Anda sebelum deadline.',
            style: TextStyle(color: C.detailMuted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 20),

          // Judul otomatis
          _FieldCard(
            label: 'Judul Jadwal (otomatis)',
            child: Text(b.nama,
                style: const TextStyle(color: C.white, fontSize: 16)),
          ),
          const SizedBox(height: 16),

          // Deskripsi otomatis
          _FieldCard(
            label: 'Deskripsi (otomatis)',
            child: Text(b.deskripsi,
                style: const TextStyle(
                    color: C.white, fontSize: 14, height: 1.4)),
          ),
          const SizedBox(height: 16),

          // Rekomendasi slot AI
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Rekomendasi Slot Pengerjaan',
                  style: TextStyle(
                      color: C.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              GestureDetector(
                onTap: () => setState(_hitungRekomendasi),
                child: const Row(
                  children: [
                    Icon(Icons.auto_awesome, color: C.accent, size: 16),
                    SizedBox(width: 4),
                    Text('Ulangi',
                        style: TextStyle(color: C.accent, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Sebelum ${b.deadlineLabel}',
              style: const TextStyle(color: C.detailMuted, fontSize: 12)),
          const SizedBox(height: 12),

          if (_slot.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: C.card,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Tidak ada slot kosong yang cukup sebelum deadline. Coba '
                'kurangi kegiatan lain atau ubah durasi.',
                style: TextStyle(color: C.detailMuted, fontSize: 13),
              ),
            )
          else
            ...List.generate(_slot.length, (i) {
              final r = _slot[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: C.card,
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: C.accent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: C.bg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text('${i + 1}',
                            style: const TextStyle(
                                color: C.accent,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(_labelSlot(r),
                            style: const TextStyle(
                                color: C.white, fontSize: 13)),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _slot.removeAt(i)),
                        child: const Icon(Icons.close,
                            color: C.detailMuted, size: 18),
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 20),

          // Submit
          GestureDetector(
            onTap: _submit,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: C.accent,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: const Text('Submit ke Jadwal',
                  style: TextStyle(
                      color: C.bg,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: widget.onBack,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: C.card,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: const Text('Batal',
                  style: TextStyle(color: C.white, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldCard extends StatelessWidget {
  const _FieldCard({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.accentSub.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: C.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
