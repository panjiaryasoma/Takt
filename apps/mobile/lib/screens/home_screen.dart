import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';
import '../viewmodels/jadwal_view_model.dart';
import '../widgets/common.dart';

/// HomeScreen — Figma node 11:1262 ("Home").
/// Ringkasan jadwal lokal. Availability authoritative dihitung backend saat evaluasi.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.onLihatJadwal});

  final VoidCallback? onLihatJadwal;

  static int _scheduledThisWeek(JadwalViewModel vm) {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    var total = 0;
    for (var index = 0; index < 7; index++) {
      total += vm.scheduledMinutesOn(monday.add(Duration(days: index)));
    }
    return total;
  }

  static String _jam(int menit) {
    final jam = menit / 60.0;
    final text = jam.toStringAsFixed(1);
    return '$text hr';
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<JadwalViewModel>();
    final terjadwalMenit = _scheduledThisWeek(vm);
    final batasProyekHarianMenit = vm.preferences.maxProjectMinutesPerDay;
    final adaJadwal = vm.all.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                SizedBox(
                  width: 47,
                  height: 43,
                  child: Image.asset(
                    C.logoAsset,
                    width: 47,
                    height: 43,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stack) => Container(
                      decoration: BoxDecoration(
                        color: C.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Tk',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                const Text(
                  'Welcome',
                  style: TextStyle(color: C.white, fontSize: 20),
                ),
              ],
            ),
          ),
          const HeaderDivider(),
          if (vm.isLoading) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 16),
          SectionHeading(
            title: 'This week at a glance',
            action: 'View schedule',
            onAction: onLihatJadwal,
          ),
          const SizedBox(height: 16),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: C.card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _Metric(
                      label: 'Commitments this week',
                      value: _jam(terjadwalMenit),
                      color: C.accent,
                    ),
                    const SizedBox(width: 16),
                    _Metric(
                      label: 'Project limit / day',
                      value: _jam(batasProyekHarianMenit),
                      color: C.white,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Free time is calculated when a plan is evaluated.',
                    style: TextStyle(color: C.detailMuted, fontSize: 11),
                  ),