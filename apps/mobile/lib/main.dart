import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/competition_brief.dart';
import 'screens/analisis_kompetisi_screen.dart';
import 'screens/home_screen.dart';
import 'screens/jadwal_harian_screen.dart';
import 'screens/jadwal_ringkasan_screen.dart';
import 'screens/progres_analisis_screen.dart';
import 'screens/rekomendasi_jadwal_screen.dart';
import 'screens/rencana_screen.dart';
import 'screens/review_brief_screen.dart';
import 'screens/tambah_jadwal_screen.dart';
import 'theme/app_theme.dart';
import 'viewmodels/analisis_view_model.dart';
import 'viewmodels/jadwal_view_model.dart';
import 'viewmodels/rencana_view_model.dart';
import 'widgets/common.dart';

void main() {
  runApp(const TaktApp());
}

class TaktApp extends StatelessWidget {
  const TaktApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => JadwalViewModel()),
        ChangeNotifierProvider(create: (_) => AnalisisViewModel()),
        ChangeNotifierProvider(create: (_) => RencanaViewModel()),
      ],
      child: MaterialApp(
        title: 'Takt',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const RootShell(),
      ),
    );
  }
}

/// Shell dengan bottom navigation (Beranda / Jadwal / Analisis / Rencana).
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _navIndex = 0; // 0 beranda, 1 jadwal, 2 analisis, 3 rencana
  int _jadwalTab = 0; // 0 harian, 1 ringkasan
  bool _showTambahJadwal = false; // overlay form Tambah Jadwal
  int _analisisStep = 0; // 0 kompetisi(form), 1 progres, 2 review brief
  bool _showRekomendasi = false; // overlay rekomendasi jadwal dari lomba
  CompetitionBrief? _briefAktif;

  CompetitionBrief get _brief => _briefAktif ??= CompetitionBrief.demo();

  Widget _body() {
    switch (_navIndex) {
      case 1:
        if (_showTambahJadwal) {
          return TambahJadwalScreen(
            onBack: () => setState(() => _showTambahJadwal = false),
            onSave: () => setState(() => _showTambahJadwal = false),
          );
        }
        return _jadwalTab == 0
            ? JadwalHarianScreen(
                onSwitchTab: (i) => setState(() => _jadwalTab = i),
                onAdd: () => setState(() => _showTambahJadwal = true),
                onBack: () => setState(() => _navIndex = 0),
              )
            : JadwalRingkasanScreen(
                onSwitchTab: (i) => setState(() => _jadwalTab = i));
      case 2:
        if (_showRekomendasi) {
          return RekomendasiJadwalScreen(
            brief: _brief,
            onBack: () => setState(() => _showRekomendasi = false),
            onSubmitDone: () => setState(() {
              // Setelah submit rekomendasi: masuk kalender & buka tab Jadwal.
              _showRekomendasi = false;
              _analisisStep = 0;
              _navIndex = 1;
              _jadwalTab = 0;
            }),
          );
        }
        switch (_analisisStep) {
          case 1:
            return ProgresAnalisisScreen(
                onReadResult: () => setState(() => _analisisStep = 2));
          case 2:
            return ReviewBriefScreen(
                brief: _brief,
                onBack: () => setState(() => _analisisStep = 1),
                // Tambah Jadwal: buka layar rekomendasi (judul+deskripsi
                // otomatis, slot dari jadwal kosong).
                onTambahJadwal: () =>
                    setState(() => _showRekomendasi = true),
                // Simpan: masukkan ke daftar Rencana tersimpan, lalu buka tab.
                onSimpan: () {
                  context.read<RencanaViewModel>().simpan(
                        competitionId: _brief.competitionId,
                        title: _brief.nama,
                        deadline: _brief.deadline,
                      );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('"${_brief.nama}" disimpan ke Rencana'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                  setState(() {
                    _analisisStep = 0;
                    _navIndex = 3;
                  });
                });
          case 0:
          default:
            return AnalisisKompetisiScreen(
                onSubmit: () => setState(() => _analisisStep = 1));
        }
      case 3:
        return RencanaScreen(
          onTinjau: (entry) => setState(() {
            // Tinjau: kembali membaca hasil analisis (Review Brief).
            _navIndex = 2;
            _analisisStep = 2;
          }),
          onCekJadwal: (entry) {
            // Cek Jadwal: buka tab Jadwal & fokus ke tanggal lomba.
            context.read<JadwalViewModel>().fokusKompetisi(entry.competitionId);
            setState(() {
              _navIndex = 1;
              _jadwalTab = 0;
              _showTambahJadwal = false;
            });
          },
        );
      case 0:
      default:
        return HomeScreen(
          onLihatJadwal: () => setState(() {
            _navIndex = 1;
            _jadwalTab = 0;
            _showTambahJadwal = false;
          }),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const StatusBarMock(),
            Expanded(child: _body()),
          ],
        ),
      ),
      bottomNavigationBar: _BottomNav(
        activeIndex: _navIndex,
        onTap: (i) => setState(() {
          _navIndex = i;
          // Setiap masuk tab Jadwal, selalu mulai dari daftar jadwal —
          // jangan langsung ke form Tambah Jadwal.
          if (i == 1) _showTambahJadwal = false;
        }),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.activeIndex, required this.onTap});

  final int activeIndex;
  final ValueChanged<int> onTap;

  static const _items = <(IconData, String)>[
    (Icons.home_rounded, 'Beranda'),
    (Icons.calendar_today_rounded, 'Jadwal'),
    (Icons.auto_awesome_rounded, 'Analisis'),
    (Icons.bookmark_rounded, 'Rencana'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: C.card,
      padding: EdgeInsets.only(
        top: 10,
        bottom: 8 + MediaQuery.of(context).padding.bottom,
        left: 10,
        right: 10,
      ),
      child: Row(
        children: List.generate(_items.length, (i) {
          final active = i == activeIndex;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _items[i].$1,
                    size: 20,
                    color: active ? C.accent : C.navInactive,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _items[i].$2,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: active ? C.accent : C.navInactive,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
