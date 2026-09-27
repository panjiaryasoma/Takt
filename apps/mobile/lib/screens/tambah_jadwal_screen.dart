import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// TambahJadwalScreen — form "Tambah Jadwal" (Tambah Komitmen).
/// Dibuka dari tombol Tambah di header Jadwal Harian.
class TambahJadwalScreen extends StatelessWidget {
  const TambahJadwalScreen({super.key, this.onBack, this.onSave});

  final VoidCallback? onBack;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Back + judul
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
              child: const Icon(Icons.chevron_left, color: C.accent, size: 22),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Tambah Jadwal',
            style: TextStyle(color: C.white, fontSize: 24),
          ),
          const SizedBox(height: 24),

          // Judul Jadwal
          _FieldCard(
            label: 'Judul Jadwal',
            child: _input(hint: 'Kelas Metode Riset'),
          ),
          const SizedBox(height: 16),

          // Tanggal + Waktu
          Row(
            children: [
              Expanded(
                child: _FieldCard(
                  label: 'Tanggal',
                  child: _input(hint: '23 Sep 2026'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _FieldCard(
                  label: 'Waktu',
                  child: _input(hint: '13.00-17.00'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Berulang
          _FieldCard(
            label: 'Berulang',
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
                  child: const Icon(Icons.repeat, color: C.accent, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Setiap Rabu',
                        style: TextStyle(color: C.white, fontSize: 15)),
                    SizedBox(height: 2),
                    Text('Sampai 18 November 2026',
                        style: TextStyle(color: C.accentSub, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Simpan
          GestureDetector(
            onTap: onSave,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: C.accent,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Simpan Jadwal',
                style: TextStyle(
                  color: C.bg,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Batal
          GestureDetector(
            onTap: onBack,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: C.card,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Batal',
                style: TextStyle(color: C.white, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _input({required String hint}) {
    return TextField(
      style: const TextStyle(color: C.white, fontSize: 16),
      cursorColor: C.accent,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        hintText: hint,
        hintStyle: const TextStyle(color: C.white, fontSize: 16),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.accentSub.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: C.accent,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
