import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takt_mobile/models/evaluation_session.dart';

import 'support/decision_fixture.dart';

void main() {
  test('derives its immutable response only from the unchanged original JSON', () {
    final raw = '  ${jsonEncode(decisionFixture())}\n';
    const request = ' { "opaque": [1, 2.0], "text": "host-owned" }\n';
    final session = EvaluationSession.fromRaw(sessionId: 'session-1', generation: 12,
        inputRevision: 3, analysisSnapshotId: 'snapshot-2',
        originalRequestJson: request, originalResponseJson: raw);
    expect(session.originalRequestJson, request);
    expect(session.originalResponseJson, raw);
    expect(session.parsedResponse.evaluationId, evaluationId);
    expect(session.parsedResponse.basis.report.reportVersion, 2);
    expect(() => session.parsedResponse.planning!.candidates.clear(), throwsUnsupportedError);
  });

  test('invalid raw response cannot become a session', () {
    expect(() => EvaluationSession.fromRaw(sessionId: 'session-1', generation: 0,
        inputRevision: 0, analysisSnapshotId: 'snapshot-1',
        originalRequestJson: '{}', originalResponseJson: '{}'), throwsFormatException);
  });

  test('rejects invalid host identity/revision metadata', () {
    for (final invalid in [
      ('', 0, 0, 'snapshot'), ('session', -1, 0, 'snapshot'),
      ('session', 0, -1, 'snapshot'), ('session', 0, 0, ' '),
    ]) {
      expect(() => EvaluationSession.fromRaw(sessionId: invalid.$1, generation: invalid.$2,
          inputRevision: invalid.$3, analysisSnapshotId: invalid.$4,
          originalRequestJson: '{}', originalResponseJson: jsonEncode(decisionFixture())),
          throwsFormatException);
    }
  });
}
