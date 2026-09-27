import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/jadwal_harian_screen.dart';
import 'screens/jadwal_ringkasan_screen.dart';
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

  Widget _body() {
    switch (_navIndex) {
      case 1:
        return _jadwalTab == 0
            ? JadwalHarianScreen(
                onSwitchTab: (i) => setState(() => _jadwalTab = i))
            : JadwalRingkasanScreen(
                onSwitchTab: (i) => setState(() => _jadwalTab = i));
      case 2:
        return const _Placeholder(title: 'Analisis');
      case 3:
        return const _Placeholder(title: 'Rencana');
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

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppHeader(title: title),
        const HeaderDivider(),
        const Spacer(),
        Text(
          '$title — segera hadir',
          style: const TextStyle(color: C.navInactive, fontSize: 14),
        ),
        const Spacer(),
      ],
    );
  }
}
