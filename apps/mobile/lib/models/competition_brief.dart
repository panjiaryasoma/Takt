import 'decision_support_report.dart';
import 'enums.dart';

/// Ringkasan brief lomba hasil analisis AI (sumber data ReviewBriefScreen).
///
/// TITIK INTEGRASI AI: sekarang pakai [CompetitionBrief.demo]. Saat AI model
/// temanmu siap, panggil [CompetitionBrief.fromReport] dengan hasil
/// [DecisionSupportReport.fromJson] — UI tidak berubah.
class CompetitionBrief {
  const CompetitionBrief({
    required this.competitionId,
    required this.nama,
    required this.penyelenggara,
    required this.format,
    required this.deskripsi,
    required this.output,
    required this.rundown,
    required this.deadline,
    required this.deadlineLabel,
    required this.sisaHari,
    required this.analisaJadwal,
    this.online = true,
  });

  final String competitionId;
  final String nama;
  final String penyelenggara;
  final String format;
  final String deskripsi;

  /// Daftar output yang dikumpulkan (per baris).
  final List<String> output;

  /// Tahapan lomba (judul + tanggal).
  final List<BriefTahap> rundown;

  /// Deadline utama (untuk perancangan jadwal "sebelum tanggal ini").
  final DateTime deadline;
  final String deadlineLabel;
  final int sisaHari;

  /// Baris analisa kondisi jadwal (warna severity + teks).
  final List<BriefAnalisa> analisaJadwal;

  final bool online;

  /// Data contoh sebelum AI model tersedia.
  factory CompetitionBrief.demo() => CompetitionBrief(
        competitionId: 'demo-hackathon-ai-2026',
        nama: 'Hackathon Nasional AI 2026',
        penyelenggara: 'Kementerian Kominfo x Telkom Indonesia',
        format: 'Tim (3-5 orang)',
        deskripsi:
            'Kompetisi pengembangan solusi AI untuk permasalahan publik di '
            'Indonesia. Peserta membangun prototipe aplikasi berbasis AI dalam '
            'waktu 48 jam.',
        output: const [
          'Proposal solusi (PDF)',
          'Prototipe aplikasi',
          'Video demo (3 menit)',
          'Slide presentasi',
        ],
        rundown: const [
          BriefTahap('Pendaftaran & Pengumpulan Proposal', '1-15 Okt 2026'),
          BriefTahap('Penyisihan (Review Proposal)', '20-25 Okt 2026'),
          BriefTahap('Babak Semifinal (48 Jam Hackathon)', '5-7 Nov 2026'),
          BriefTahap('Grand Final & Presentasi', '20 Nov 2026'),
        ],
        deadline: DateTime(2026, 10, 15),
        deadlineLabel: 'Deadline Penyisihan: 15 Oktober 2026',
        sisaHari: 18,
        analisaJadwal: const [
          BriefAnalisa(severity: BriefSeverity.tinggi,
              text: 'Status jadwal saat ini: Padat'),
          BriefAnalisa(severity: BriefSeverity.sedang,
              text: 'Jadwal bentrok: 2 kegiatan bentrok di minggu yang sama'),
          BriefAnalisa(severity: BriefSeverity.sedang,
              text:
                  'Estimasi beban kerja: Tinggi – perlu alokasi 15-20 jam/minggu'),
          BriefAnalisa(severity: BriefSeverity.aman,
              text: 'Rekomendasi: Bisa diambil jika mengurangi 1 kegiatan lain'),
        ],
      );

  /// Bangun brief UI dari output AI model (DecisionSupportReport).
  /// Field yang belum ada padanannya di kontrak (rundown, analisa naratif)
  /// diturunkan seadanya; sisanya diambil langsung dari brief wire.
  factory CompetitionBrief.fromReport(DecisionSupportReport r) {
    final b = r.competitionBrief;
    final deadline = b.submissionDeadline;
    final sisa = deadline.difference(DateTime.now()).inDays;

    // deliverables bisa berupa list string atau struktur lain (Any di kontrak).
    final deliverables = <String>[];
    final d = b.deliverables;
    if (d is List) {
      deliverables.addAll(d.map((e) => e.toString()));
    } else if (d is String && d.isNotEmpty) {
      deliverables.add(d);
    }

    // Analisa jadwal diturunkan dari feasibility + readiness.
    final analisa = <BriefAnalisa>[
      BriefAnalisa(
        severity: switch (r.feasibility) {
          FeasibilityStatus.feasible => BriefSeverity.aman,
          FeasibilityStatus.feasibleWithTradeoffs => BriefSeverity.sedang,
          FeasibilityStatus.tightCapacity => BriefSeverity.sedang,
          FeasibilityStatus.notFeasible => BriefSeverity.tinggi,
        },
        text: 'Kelayakan: ${r.feasibility.wire}',
      ),
      for (final reason in r.readiness.blockingReasons)
        BriefAnalisa(severity: BriefSeverity.tinggi, text: reason),
      for (final item in r.readiness.reviewItems)
        BriefAnalisa(severity: BriefSeverity.sedang, text: item),
    ];

    return CompetitionBrief(
      competitionId: b.competitionId,
      nama: b.name,
      penyelenggara: b.organizer,
      format: '—',
      deskripsi: b.eligibility?.toString() ?? '',
      output: deliverables,
      rundown: const [],
      deadline: deadline,
      deadlineLabel:
          'Deadline: ${deadline.day}/${deadline.month}/${deadline.year}',
      sisaHari: sisa < 0 ? 0 : sisa,
      analisaJadwal: analisa,
    );
  }
}

class BriefTahap {
  const BriefTahap(this.title, this.date);
  final String title;
  final String date;
}

enum BriefSeverity { aman, sedang, tinggi }

class BriefAnalisa {
  const BriefAnalisa({required this.severity, required this.text});
  final BriefSeverity severity;
  final String text;
}
