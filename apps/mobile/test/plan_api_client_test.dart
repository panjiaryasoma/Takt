import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:takt_mobile/data/remote/plan_api_client.dart';
import 'package:takt_mobile/models/enums.dart';
import 'package:takt_mobile/models/reevaluation_wire.dart';

import 'support/decision_fixture.dart';

void main() {
  test('evaluate sends the exact serialized body and preserves raw response',
      () async {
    const requestJson = ' { "planning": true, "value": 1.0 }\n';
    final responseJson = '  ${jsonEncode(decisionFixture())}\n';
    late String observedBody;

    final client = HttpPlanApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((request) async {
        observedBody = request.body;
        expect(request.url.path, '/api/v1/plans/evaluate');
        return http.Response(
          responseJson,
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final result = await client.evaluate(
      evaluationRequestJson: requestJson,
    );

    expect(observedBody, requestJson);
    expect(result.evaluationRequestJson, requestJson);
    expect(result.evaluationResponseJson, responseJson);
    expect(result.response.evaluationId, evaluationId);
    client.close();
  });

  test('re-evaluate wraps prior basis and current request exactly once', () async {
    final priorResponseJson = jsonEncode(decisionFixture());
    const currentRequestJson = '{"current":true,"number":2}';
    late Map<String, dynamic> observed;

    final transition = {
      'kind': 'UNCHANGED',
      'prior_evaluation_id': evaluationId,
      'prior_basis_fingerprint': List.filled(64, 'b').join(),
      'current_basis_fingerprint': List.filled(64, 'b').join(),
      'prior_evaluation_freshness': 'CURRENT',
      'change_reasons': <String>[],
    };
    final rawResponse = jsonEncode({
      'transition': transition,
      'evaluation': null,
    });

    final client = HttpPlanApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((request) async {
        observed = jsonDecode(request.body) as Map<String, dynamic>;
        expect(request.url.path, '/api/v1/plans/re-evaluate');
        return http.Response(rawResponse, 200);
      }),
    );

    final result = await client.reevaluate(
      priorEvaluationId: evaluationId,
      priorEvaluationResponseJson: priorResponseJson,
      currentEvaluationRequestJson: currentRequestJson,
    );

    expect(
      (observed['prior'] as Map<String, dynamic>)['evaluation_id'],
      evaluationId,
    );
    expect(observed['current'], jsonDecode(currentRequestJson));
    expect(result.transportResponseJson, rawResponse);
    expect(result.evaluationRequestJson, currentRequestJson);
    expect(result.success.transition.kind, ReevaluationKind.unchanged);
    expect(result.success.evaluation, isNull);
    client.close();
  });

  test('re-evaluation transition rejects non-canonical change reason order', () {
    expect(
      () => ReevaluationTransitionWire.fromValue({
        'kind': 'SUPERSEDED',
        'prior_evaluation_id': evaluationId,
        'prior_basis_fingerprint': List.filled(64, 'b').join(),
        'current_basis_fingerprint': List.filled(64, 'c').join(),
        'prior_evaluation_freshness': 'STALE',
        'change_reasons': [
          'PLANNING_BASIS_CHANGED',
          'REPORT_BASIS_CHANGED',
        ],
      }),
      throwsFormatException,
    );
  });

  test('re-evaluation error rejects malformed public detail objects', () {
    final raw = jsonEncode({
      'error': {
        'code': 'VALIDATION_ERROR',
        'message': 'Invalid input.',
        'stage': 'validation',
        'details': [
          {
            'path': 'planning.workload',
            'message': 'Invalid.',
          },
        ],
      },
      'transition': null,
    });

    expect(
      () => PlanReevaluateErrorWire.parse(raw),
      throwsFormatException,
    );
  });

  test('trusted re-evaluation failure carries exact transport request', () async {
    final priorResponseJson = jsonEncode(decisionFixture());
    const currentRequestJson = '{"current":true}';
    final transition = {
      'kind': 'SUPERSEDED',
      'prior_evaluation_id': evaluationId,
      'prior_basis_fingerprint': List.filled(64, 'b').join(),
      'current_basis_fingerprint': List.filled(64, 'c').join(),
      'prior_evaluation_freshness': 'STALE',
      'change_reasons': ['PLANNING_BASIS_CHANGED'],
    };
    final rawResponse = jsonEncode({
      'error': {
        'code': 'PLANNING_EXECUTION_FAILED',
        'message': 'Planning failed.',
        'stage': 'planning',
        'details': <Object?>[],
      },
      'transition': transition,
    });

    final client = HttpPlanApiClient(
      baseUrl: 'https://example.test',
      client: MockClient(
        (request) async => http.Response(rawResponse, 500),
      ),
    );

    try {
      await client.reevaluate(
        priorEvaluationId: evaluationId,
        priorEvaluationResponseJson: priorResponseJson,
        currentEvaluationRequestJson: currentRequestJson,
      );
      fail('Expected PlanApiFailure');
    } on PlanApiFailure catch (error) {
      expect(error.code, 'PLANNING_EXECUTION_FAILED');
      expect(error.transition?.kind, ReevaluationKind.superseded);
      expect(error.transportResponseJson, rawResponse);
      expect(error.transportRequestJson, isNotNull);
      final wrapper =
          jsonDecode(error.transportRequestJson!) as Map<String, dynamic>;
      expect(wrapper['current'], jsonDecode(currentRequestJson));
    } finally {
      client.close();
    }
  });
}
