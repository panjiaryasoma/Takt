/// Ringkasan presentation model untuk ReviewBriefScreen.
///
/// Data demo tetap dipakai sampai Hari 2B memasang adapter dari public API DTO
/// current. Jangan parse payload backend langsung ke model presentation ini.
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
        nama: 'National AI Hackathon 2026',
        penyelenggara: 'Ministry of Communication and Informatics x Telkom Indonesia',
        format: 'Team (3-5 people)',
        deskripsi:
            'A competition to build AI solutions for public-sector problems in '
            'Indonesia. Participants build an AI-based application prototype within '
            '48 hours.',
        output: const [
          'Solution proposal (PDF)',
          'Application prototype',
          'Demo video (3 minutes)',
          'Presentation slides',
        ],
        rundown: const [
          BriefTahap('Registration & Proposal Submission', '1-15 Oct 2026'),
          BriefTahap('Qualification Round (Proposal Review)', '20-25 Oct 2026'),
          BriefTahap('Semifinal Round (48-Hour Hackathon)', '5-7 Nov 2026'),
          BriefTahap('Grand Final & Presentation', '20 Nov 2026'),
        ],
        deadline: DateTime(2026, 10, 15),
        deadlineLabel: 'Qualification deadline: 15 October 2026',
        sisaHari: 18,
        analisaJadwal: const [
          BriefAnalisa(severity: BriefSeverity.tinggi,
              text: 'Current schedule status: Busy'),
          BriefAnalisa(severity: BriefSeverity.sedang,
              text: 'Schedule conflict: 2 activities overlap in the same week'),
          BriefAnalisa(severity: BriefSeverity.sedang,
              text:
                  'Estimated workload: High – requires 15-20 hours/week'),
          BriefAnalisa(severity: BriefSeverity.aman,
              text: 'Recommendation: Feasible if one other activity is reduced'),
        ],
      );


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