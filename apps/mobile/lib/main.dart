import 'package:flutter/material.dart';

import 'screens/analisis_kompetisi_screen.dart';
import 'screens/home_screen.dart';
import 'screens/jadwal_harian_screen.dart';
import 'screens/jadwal_ringkasan_screen.dart';
import 'screens/progres_analisis_screen.dart';
import 'screens/rencana_screen.dart';
import 'screens/review_brief_screen.dart';
import 'screens/tambah_jadwal_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/common.dart';

void main() {
  runApp(const TaktApp());
}

class TaktApp extends StatelessWidget {
  const TaktApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Takt',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const RootShell(),
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
              )
            : JadwalRingkasanScreen(
                onSwitchTab: (i) => setState(() => _jadwalTab = i));
      case 2:
        switch (_analisisStep) {
          case 1:
            return ProgresAnalisisScreen(
                onReadResult: () => setState(() => _analisisStep = 2));
          case 2:
            return ReviewBriefScreen(
                onBack: () => setState(() => _analisisStep = 1),
                onTambahJadwal: () => setState(() {
                      _analisisStep = 0;
                      _navIndex = 1;
                      _jadwalTab = 0;
                      _showTambahJadwal = true;
                    }),
                onSimpan: () => setState(() {
                      _analisisStep = 0;
                      _navIndex = 1;
                      _jadwalTab = 0;
                    }));
          case 0:
          default:
            return AnalisisKompetisiScreen(
                onSubmit: () => setState(() => _analisisStep = 1));
        }
      case 3:
        return RencanaScreen(
          onTinjau: () => setState(() => _navIndex = 1),
          onCekJadwal: () => setState(() => _navIndex = 1),
        );
      case 0:
      default:
        return const HomeScreen();
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
        onTap: (i) => setState(() => _navIndex = i),
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
