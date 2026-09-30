import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:takt_mobile/models/recovery_policy.dart';

void main() {
  test('Dart recovery matches every 5A contract joined to the 6A SSOT', () {
    final export = Process.runSync(
      'python3',
      ['-m', 'tests.support.recovery_policy'],
      workingDirectory: '../..',
    );
    expect(export.exitCode, 0, reason: export.stderr.toString());
    final rows = jsonDecode(export.stdout as String) as List;
    expect(rows, isNotEmpty);
    for (final row in rows) {
      final actual = RecoveryPolicy.classify(FailureIdentity(
        code: row['code'] as String,
        stage: row['stage'] as String,
        statusCode: row['status_code'] as int,
        origin: FailureOrigin.backend,
      ));
      final wireName = actual.name.replaceAllMapped(
        RegExp('[A-Z]'),
        (match) => '_${match[0]}',
      ).toUpperCase();
      expect(wireName, row['recovery_class'],
          reason: '${row['endpoint']} / ${row['contract_key']}');
    }
    for (final code in ['UNKNOWN_BACKEND_ERROR', 'FUTURE_CODE']) {
      expect(
        RecoveryPolicy.classify(FailureIdentity(
          code: code, stage: 'unknown', statusCode: 503,
          origin: FailureOrigin.backend,
        )),
        RecoveryClass.noAutomaticRecovery,
      );
    }
  });
}
