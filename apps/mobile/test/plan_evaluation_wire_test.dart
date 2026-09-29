import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takt_mobile/models/enums.dart';
import 'package:takt_mobile/models/plan_evaluation_wire.dart';

import 'support/decision_fixture.dart';

void main() {
  PlanEvaluateResponseV1 parse(Map<String, dynamic> raw) =>
      PlanEvaluateResponseV1.parse(jsonEncode(raw));

  test('parses primary, alternatives, trace and all feasibility statuses', () {
    for (final status in FeasibilityStatus.values) {
      final response = parse(decisionFixture(feasibility: status.wire));
      expect(response.planning!.feasibility, status);
      expect(response.evaluatedAt.isUtc, isTrue);
      if (status != FeasibilityStatus.notFeasible) {
        expect(response.planning!.recommendation!.primaryCandidate.candidateId,
            primaryId);
        expect(response.planning!.candidates.last.ref.candidateId, alternativeId);
      }
    }
  });

  test('every blocked readiness has no planning or planning basis', () {
    for (final status in ReadinessStatus.values
        .where((item) => item != ReadinessStatus.readyToEvaluate)) {
      final response = parse(decisionFixture(readiness: status.wire));
      expect(response.planning, isNull);
      expect(response.basis.planning, isNull);
    }
  });

  final invalid = <String, void Function(Map<String, dynamic>)>{
    'unknown root key': (r) => r['extra'] = true,
    'missing nullable key': (r) => r.remove('planning'),
    'unknown readiness': (r) => r['readiness']['status'] = 'READY',
    'unknown feasibility': (r) => r['planning']['feasibility'] = 'MAYBE',
    'unknown action': (r) => r['planning']['allowed_actions'][0] = 'AUTO_BOOK',
    'unknown basis version': (r) => r['basis']['version'] = 'evaluation-basis-v2',
    'unknown schema': (r) => r['basis']['domain_schema_version'] = '99',
    'unknown readiness rule': (r) => r['readiness']['rule_version'] = '2.0',
    'unknown solver': (r) => r['basis']['planning']['solver_backend'] = 'other',
    'unknown nested key': (r) => r['planning']['candidates'][0]['extra'] = 0,
    'ready without planning': (r) => r['planning'] = null,
    'ready without planning basis': (r) => r['basis']['planning'] = null,
    'blocked with planning': (r) => r['readiness']['status'] = 'NEEDS_REVIEW',
    'blocked with planning basis': (r) {
      r['readiness']['status'] = 'NEEDS_REVIEW';
      r['planning'] = null;
    },
    'duplicate candidate': (r) => r['planning']['candidates'][1] =
        r['planning']['candidates'][0],
    'cross evaluation candidate': (r) => r['planning']['candidates'][0]['ref']
        ['evaluation_id'] = '22222222-2222-4222-8222-222222222222',
    'unknown primary': (r) => r['planning']['recommendation']['primary_candidate']
        ['candidate_id'] = 'absent',
    'payload primary mismatch': (r) => r['planning']['recommendation']
        ['recommendation']['recommended_candidate_id'] = alternativeId,
    'alternative order mismatch': (r) => r['planning']['recommendation']
        ['alternative_candidates'][0]['candidate_id'] = primaryId,
    'alternative payload mismatch': (r) => r['planning']['recommendation']
        ['recommendation']['alternatives'][0]['candidate_id'] = primaryId,
    'missing candidates': (r) => r['planning']['candidates'] = [],
    'missing recommendation': (r) => r['planning']['recommendation'] = null,
    'infeasible with candidates': (r) => r['planning']['feasibility'] =
        'NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS',
    'duplicate action': (r) => r['planning']['allowed_actions'].add('ACCEPT'),
    'missing alternative action': (r) =>
        r['planning']['allowed_actions'].remove('CHOOSE_ALTERNATIVE'),
    'action order mismatch': (r) => r['planning']['allowed_actions'] =
        ['IGNORE', 'EDIT_CONSTRAINTS', 'CHOOSE_ALTERNATIVE', 'ACCEPT'],
    'trace competition': (r) => r['planning']['recommendation']['trace']
        ['competition_id'] = 'another-report',
    'trace report version': (r) =>
        r['planning']['recommendation']['trace']['report_version'] = 3,
    'trace material': (r) => r['planning']['recommendation']['trace']
        ['assembly_material_fingerprint'] = List.filled(64, 'd').join(),
    'trace evaluation basis': (r) => r['planning']['recommendation']['trace']
        ['evaluation_basis_fingerprint'] = List.filled(64, 'd').join(),
    'trace planning basis': (r) => r['planning']['recommendation']['trace']
        ['planning_basis_fingerprint'] = List.filled(64, 'd').join(),
    'float report version': (r) => r['basis']['report']['report_version'] = 2.0,
    'negative buffer': (r) => r['planning']['candidates'][0]['buffer_minutes'] = -1,
    'naive datetime': (r) => r['evaluated_at'] = '2026-09-29T10:00:00',
    'normalized invalid date': (r) => r['evaluated_at'] = '2026-02-30T10:00:00Z',
    'normalized invalid hour': (r) => r['evaluated_at'] = '2026-09-29T25:00:00Z',
    'invalid offset': (r) => r['evaluated_at'] = '2026-09-29T10:00:00+25:00',
    'bad UUID': (r) => r['evaluation_id'] = 'not-an-evaluation',
    'bad SHA': (r) => r['basis']['fingerprint'] = 'not-a-hash',
    'allocation duration': (r) => r['planning']['candidates'][0]['work_blocks'][0]
        ['allocated_minutes'] = 40,
    'allocation second alignment': (r) => r['planning']['candidates'][0]
        ['work_blocks'][0]['start'] = '2026-10-01T12:00:01Z',
    'reversed allocation': (r) => r['planning']['candidates'][0]['work_blocks'][0]
        ['end'] = '2026-10-01T11:30:00Z',
    'alternative buffer mismatch': (r) => r['planning']['recommendation']
        ['recommendation']['alternatives'][0]['buffer_minutes'] = 999,
    'window mismatch': (r) => r['planning']['recommendation']['recommendation']
        ['suggested_windows'][0]['allocated_minutes'] = 99,
    'next work mismatch': (r) => r['planning']['recommendation']['recommendation']
        ['recommended_next_work']['task_id'] = 'other-task',
  };
  for (final entry in invalid.entries) {
    test('rejects ${entry.key}', () {
      final raw = decisionFixture();
      entry.value(raw);
      expect(() => parse(raw), throwsFormatException);
    });
  }

  test('infeasible has exactly edit and ignore, single candidate has no chooser', () {
    final infeasible = decisionFixture(
      feasibility: 'NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS',
    );
    expect(parse(infeasible).planning!.candidates, isEmpty);
    infeasible['planning']['allowed_actions'].insert(0, 'ACCEPT');
    expect(() => parse(infeasible), throwsFormatException);
    expect(parse(decisionFixture(alternatives: false)).planning!.allowedActions,
        [RecommendationAction.accept, RecommendationAction.editConstraints,
          RecommendationAction.ignore]);
  });

  test('nested response collections cannot mutate after parsing', () {
    final response = parse(decisionFixture());
    final planning = response.planning!;
    final recommendation = planning.recommendation!;
    final mutations = <void Function()>[
      () => response.readiness.passedChecks.clear(),
      () => response.readiness.reviewItems.clear(),
      () => response.readiness.blockingReasons.clear(),
      () => planning.candidates.clear(),
      () => planning.allowedActions.clear(),
      () => planning.reasonCodes.clear(),
      () => planning.tradeoffCodes.clear(),
      () => planning.sensitivityCodes.clear(),
      () => planning.candidates.first.workBlocks.clear(),
      () => planning.candidates.first.assumptions.clear(),
      () => recommendation.alternativeCandidates.clear(),
      () => recommendation.recommendation.suggestedWindows.clear(),
      () => recommendation.recommendation.alternatives.clear(),
      () => recommendation.recommendation.rationale.clear(),
      () => recommendation.recommendation.tradeoffs.clear(),
      () => recommendation.recommendation.assumptions.clear(),
      () => recommendation.recommendation.alternatives.first.suggestedWindows.clear(),
      () => recommendation.recommendation.alternatives.first.tradeoffs.clear(),
    ];
    for (final mutate in mutations) {
      expect(mutate, throwsUnsupportedError);
    }
  });

  test('explicit zero-work candidate and null next-work preserve backend semantics', () {
    final raw = decisionFixture(alternatives: false);
    raw['planning']['candidates'][0]['work_blocks'] = [];
    raw['planning']['recommendation']['recommendation']['suggested_windows'] = [];
    raw['planning']['recommendation']['recommendation']['recommended_next_work'] = null;
    expect(parse(raw).planning!.candidates.single.workBlocks, isEmpty);
  });
}
