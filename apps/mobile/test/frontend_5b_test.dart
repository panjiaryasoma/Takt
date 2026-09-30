import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('5B distinguishes session-outdated from persisted superseded presentation',
      () {
    final decision = File(
      'lib/screens/rekomendasi_jadwal_screen.dart',
    ).readAsStringSync();
    final list = File('lib/screens/rencana_screen.dart').readAsStringSync();
    final detail =
        File('lib/screens/saved_plan_detail_screen.dart').readAsStringSync();

    expect(decision, contains('SESSION OUTDATED'));
    expect(decision, contains('session-outdated-notice'));
    expect(list, contains('SUPERSEDED'));
    expect(list, contains('persisted-stale-summary'));
    expect(detail, contains('Persisted evaluation stale'));
    expect(detail, contains('persisted-evaluation-stale'));
  });

  test('Decision Report presentation does not parse raw request JSON', () {
    final source =
        File('lib/screens/rekomendasi_jadwal_screen.dart').readAsStringSync();
    expect(source, isNot(contains('jsonDecode(')));
    expect(source, isNot(contains('evaluationRequestJson')));
    expect(source, contains('Traceability & evaluation details'));
  });

  test('5B leaves domain and backend contract directories outside its diff scope',
      () {
    final viewModel = File(
      'lib/viewmodels/decision_report_view_model.dart',
    ).readAsStringSync();
    final schedule =
        File('lib/screens/tambah_jadwal_screen.dart').readAsStringSync();

    expect(viewModel, contains('planning?.allowedActions.contains(action)'));
    expect(viewModel, contains('only domain action authority'));
    expect(schedule, contains('Takt does not move it automatically'));
  });
}
