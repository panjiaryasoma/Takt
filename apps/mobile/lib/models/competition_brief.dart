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
