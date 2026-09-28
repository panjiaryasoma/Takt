import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';
import '../viewmodels/jadwal_view_model.dart';

/// Kategori jadwal yang dipilih user.
enum _JenisJadwal { wajib, khusus }

/// TambahJadwalScreen — form "Tambah Jadwal" bercabang:
/// - Wajib (rutin) : pilih hari (Sen–Min, boleh banyak) + jam mulai/selesai
/// - Khusus (sekali): pilih tanggal + jam mulai/selesai
class TambahJadwalScreen extends StatefulWidget {
  const TambahJadwalScreen({super.key, this.onBack, this.onSave});

  final VoidCallback? onBack;
  final VoidCallback? onSave;

  @override
  State<TambahJadwalScreen> createState() => _TambahJadwalScreenState();
}

class _TambahJadwalScreenState extends State<TambahJadwalScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  _JenisJadwal _jenis = _JenisJadwal.wajib;

  /// Hari terpilih untuk jadwal wajib (1=Sen .. 7=Min).
  final Set<int> _hari = {};

  DateTime _tanggal = DateTime.now();
  TimeOfDay _mulai = const TimeOfDay(hour: 13, minute: 0);
  TimeOfDay _selesai = const TimeOfDay(hour: 15, minute: 0);

  static const _monthShort = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];
  static const _namaHari = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String get _tanggalLabel =>
      '${_tanggal.day} ${_monthShort[_tanggal.month - 1]} ${_tanggal.year}';

  String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}.${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pilihTanggal() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _tanggal,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _tanggal = picked);
  }

  Future<void> _pilihWaktu({required bool mulai}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: mulai ? _mulai : _selesai,
    );
    if (picked != null) {
      setState(() {
        if (mulai) {
          _mulai = picked;
        } else {
          _selesai = picked;
        }
      });
    }
  }

  bool _waktuValid() {
    final m = _mulai.hour * 60 + _mulai.minute;
    final s = _selesai.hour * 60 + _selesai.minute;
    return s > m;
  }

  void _simpan() {
    final title = _titleCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final vm = context.read<JadwalViewModel>();
    final messenger = ScaffoldMessenger.of(context);

    if (title.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Judul jadwal wajib diisi')),
      );
      return;
    }
    if (!_waktuValid()) {
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Waktu selesai harus setelah waktu mulai')),
      );
      return;
    }

    if (_jenis == _JenisJadwal.wajib) {
      if (_hari.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Pilih minimal satu hari')),
        );
        return;
      }
      vm.tambahRutin(
        title: title,
        category: desc.isEmpty ? null : desc,
        weekdays: _hari,
        jamMulai: _mulai.hour,
        menitMulai: _mulai.minute,
        jamSelesai: _selesai.hour,
        menitSelesai: _selesai.minute,
      );
    } else {
      final start = DateTime(_tanggal.year, _tanggal.month, _tanggal.day,
          _mulai.hour, _mulai.minute);
      final end = DateTime(_tanggal.year, _tanggal.month, _tanggal.day,
          _selesai.hour, _selesai.minute);
      vm.tambah(
        title: title,
        category: desc.isEmpty ? null : desc,
        start: start,
        end: end,
      );
    }
    widget.onSave?.call();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Back — kiri atas
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
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
                child:
                    const Icon(Icons.chevron_left, color: C.accent, size: 22),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Tambah Jadwal',
            style: TextStyle(color: C.white, fontSize: 24),
          ),
          const SizedBox(height: 24),

          // Judul
          _FieldCard(
            label: 'Judul Jadwal',
            child: _input(_titleCtrl, 'Kelas Metode Riset'),
          ),
          const SizedBox(height: 16),

          // Deskripsi
          _FieldCard(
            label: 'Deskripsi Kegiatan',
            child: _input(_descCtrl, 'Materi bab 3, bawa laptop', maxLines: 2),
          ),
          const SizedBox(height: 16),

          // Jenis: Wajib / Khusus
          _FieldCard(
            label: 'Jenis Jadwal',
            child: Row(
              children: [
                _Chip(
                  label: 'Wajib (rutin)',
                  active: _jenis == _JenisJadwal.wajib,
                  onTap: () => setState(() => _jenis = _JenisJadwal.wajib),
                ),
                const SizedBox(width: 10),
                _Chip(
                  label: 'Khusus (sekali)',
                  active: _jenis == _JenisJadwal.khusus,
                  onTap: () => setState(() => _jenis = _JenisJadwal.khusus),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Cabang: pilih hari (wajib) atau tanggal (khusus)
          if (_jenis == _JenisJadwal.wajib)
            _FieldCard(
              label: 'Setiap hari',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(7, (i) {
                  final weekday = i + 1;
                  final active = _hari.contains(weekday);
                  return _Chip(
                    label: _namaHari[i],
                    active: active,
                    onTap: () => setState(() {
                      if (active) {
                        _hari.remove(weekday);
                      } else {
                        _hari.add(weekday);
                      }
                    }),
                  );
                }),
              ),
            )
          else
            _FieldCard(
              label: 'Tanggal',
              child: _TapValue(value: _tanggalLabel, onTap: _pilihTanggal),
            ),
          const SizedBox(height: 16),

          // Waktu dari - sampai (keduanya)
          Row(
            children: [
              Expanded(
                child: _FieldCard(
                  label: 'Dari jam',
                  child: _TapValue(
                    value: _hhmm(_mulai),
                    onTap: () => _pilihWaktu(mulai: true),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _FieldCard(
                  label: 'Sampai jam',
                  child: _TapValue(
                    value: _hhmm(_selesai),
                    onTap: () => _pilihWaktu(mulai: false),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Tambah
          GestureDetector(
            onTap: _simpan,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: C.accent,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Tambah Jadwal',
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
            onTap: widget.onBack,
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

  Widget _input(TextEditingController ctrl, String hint, {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: C.white, fontSize: 16),
      cursorColor: C.accent,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        hintText: hint,
        hintStyle: const TextStyle(color: C.detailMuted, fontSize: 16),
      ),
    );
  }
}

class _TapValue extends StatelessWidget {
  const _TapValue({required this.value, required this.onTap});

  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Text(
        value,
        style: const TextStyle(color: C.white, fontSize: 16),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active ? C.accent : C.bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? C.bg : C.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
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
