import 'package:flutter/material.dart';

import '../models/competition_brief.dart';
import '../theme/app_theme.dart';

/// ReviewBriefScreen — Figma node 11:1627 ("Review brief kompetisi").
/// Hasil analisis: info lomba, rundown tahapan, deadline, analisa jadwal.
/// Data dari [CompetitionBrief] (demo sekarang, AI model nanti).
class ReviewBriefScreen extends StatelessWidget {
  const ReviewBriefScreen({
    super.key,
    this.brief,
    this.onBack,
    this.onTambahJadwal,
    this.onSimpan,
  });

  final CompetitionBrief? brief;
  final VoidCallback? onBack;
  final VoidCallback? onTambahJadwal;
  final VoidCallback? onSimpan;

  @override
  Widget build(BuildContext context) {
    final b = brief ?? CompetitionBrief.demo();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back + eyebrow + judul
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: C.card,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.chevron_left, color: C.accent, size: 22),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'LANGKAH 1 DARI 2',
            style: TextStyle(
              color: C.navInactive,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Review brief kompetisi',
            style: TextStyle(color: C.white, fontSize: 22),
          ),
          const SizedBox(height: 20),

          // Info Lomba
          const _SectionTitle('Info Lomba'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: C.accent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.nama,
                          style: const TextStyle(
                              color: C.accentText,
                              fontSize: 15,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(b.penyelenggara,
                          style: const TextStyle(
                              color: C.accentSub, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: C.accentSub,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(b.online ? 'Online' : 'Offline',
                      style: const TextStyle(color: C.white, fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Detail card: Format, Deskripsi, Output
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: C.card,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FieldLabel('Format'),
                const SizedBox(height: 6),
                _pill(b.format),
                const SizedBox(height: 14),
                const _FieldLabel('Deskripsi'),
                const SizedBox(height: 6),
                _block(b.deskripsi),
                const SizedBox(height: 14),
                const _FieldLabel('Output yang Dikumpulkan'),
                const SizedBox(height: 6),
                _block(b.output.map((e) => '• $e').join('\n')),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Rundown Tahapan Lomba
          const _SectionTitle('Rundown Tahapan Lomba'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: C.card,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...List.generate(b.rundown.length, (i) {
                  final t = b.rundown[i];
                  return _TimelineItem(
                    title: t.title,
                    date: t.date,
                    first: i == 0,
                    last: i == b.rundown.length - 1,
                  );
                }),
                const SizedBox(height: 6),
                const Text(
                  'Kompetisi ini berjalan bertahap dan berakhir pada babak final.',
                  style: TextStyle(color: C.detailMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Deadline & Waktu Tersisa
          const _SectionTitle('Deadline & Waktu Tersisa'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: C.card,
              borderRadius: BorderRadius.circular(12),
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
                  child: const Icon(Icons.calendar_month,
                      color: C.accent, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    b.deadlineLabel,
                    style: const TextStyle(color: C.white, fontSize: 13),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: C.accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('${b.sisaHari} Hari Lagi',
                      style: const TextStyle(
                          color: C.bg,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Analisa Kondisi Jadwal
          const _SectionTitle('Analisa Kondisi Jadwal'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: C.card,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Analisa Kondisi Jadwal',
                    style: TextStyle(
                        color: C.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                ...b.analisaJadwal.map((a) {
                  final c = switch (a.severity) {
                    BriefSeverity.tinggi => C.padat,
                    BriefSeverity.sedang => C.sibuk,
                    BriefSeverity.aman => C.kosong,
                  };
                  return _AnalysisLine(
                    color: c,
                    textColor:
                        a.severity == BriefSeverity.aman ? C.kosong : C.white,
                    text: a.text,
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Aksi: Tambah Jadwal (primary) + Simpan Jadwal (outline)
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onTambahJadwal,
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: C.accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Tambah Jadwal',
                      style: TextStyle(
                        color: C.accentText,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: onSimpan,
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: C.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: C.accent, width: 1.4),
                    ),
                    child: const Text(
                      'Simpan Jadwal',
                      style: TextStyle(
                        color: C.accent,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _pill(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: C.accentSub,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: const TextStyle(color: C.white, fontSize: 13)),
      );

  static Widget _block(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: C.accentSub,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: const TextStyle(color: C.white, fontSize: 13, height: 1.5)),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            color: C.white, fontSize: 16, fontWeight: FontWeight.w700),
      );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            color: C.accent, fontSize: 12, fontWeight: FontWeight.w700),
      );
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.title,
    required this.date,
    this.first = false,
    this.last = false,
  });

  final String title;
  final String date;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: C.accent,
                  shape: BoxShape.circle,
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(width: 2, color: C.accentSub),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(color: C.white, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(date,
                      style: const TextStyle(
                          color: C.detailMuted, fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisLine extends StatelessWidget {
  const _AnalysisLine({
    required this.color,
    required this.text,
    this.textColor = C.white,
  });

  final Color color;
  final String text;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(color: textColor, fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
