import 'dart:convert';

import 'package:takt_mobile/models/evaluation_session.dart';

const evaluationId = '11111111-1111-4111-8111-111111111111';
const primaryId = 'primary-option';
const alternativeId = 'later-option';

EvaluationSession testSession({int generation = 12, int revision = 3,
    String readiness = 'READY_TO_EVALUATE', String feasibility = 'TIGHT_CAPACITY',
    bool alternatives = true}) => EvaluationSession.fromEvaluationSnapshot(
  sessionId: 'session-$generation', generation: generation, inputRevision: revision,
  analysisSnapshotId: 'snapshot-2', evaluationRequestJson: '{"host": true}',
  evaluationResponseJson: jsonEncode(decisionFixture(readiness: readiness,
      feasibility: feasibility, alternatives: alternatives)),
);

/// Public v1 wire fixture, never imported by the application/runtime host.
Map<String, dynamic> decisionFixture({
  String readiness = 'READY_TO_EVALUATE',
  String feasibility = 'TIGHT_CAPACITY',
  bool alternatives = true,
}) {
  final ready = readiness == 'READY_TO_EVALUATE';
  final infeasible = feasibility == 'NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS';
  final reportHash = List.filled(64, 'a').join();
  final evaluationHash = List.filled(64, 'b').join();
  final planningHash = List.filled(64, 'c').join();
  Map<String, Object> ref(String id) => {
        'evaluation_id': evaluationId,
        'candidate_id': id,
      };
  Map<String, Object> window(int hour) => {
        'task_id': 'task-draft',
        'start': '2026-10-01T${hour.toString().padLeft(2, '0')}:00:00Z',
        'end': '2026-10-01T${hour.toString().padLeft(2, '0')}:30:00Z',
        'allocated_minutes': 30,
        'availability_source': 'user-work-window',
      };
  Map<String, Object> next(int hour) => {
        ...window(hour),
        'task_name': 'Build prototype',
      };
  Map<String, Object> candidate(String id, int hour, int buffer) => {
        'ref': ref(id),
        'work_blocks': [window(hour)],
        'buffer_minutes': buffer,
        'assumptions': ['Work estimates have been confirmed.'],
      };

  // Round-trip gives every test its own nested mutable copy for adversarial edits.
  return jsonDecode(jsonEncode({
    'evaluation_id': evaluationId,
    'evaluated_at': '2026-09-29T10:00:00.123456Z',
    'basis': {
      'version': 'evaluation-basis-v1',
      'domain_schema_version': '3.0.0',
      'fingerprint': evaluationHash,
      'report': {
        'competition_id': 'competition-1',
        'report_version': 2,
        'reconciliation_policy_version': 'reconciliation-v1',
        'assembly_policy_version': 'canonical-v1',
        'assembly_material_fingerprint': reportHash,
      },
      'readiness': {
        'basis_version': 'readiness-basis-v1',
        'basis_fingerprint': reportHash,
        'projection_version': 'readiness-projection-v1',
        'rule_version': '1.0',
      },
      'planning': ready
          ? {
              'basis_version': 'planning-basis-v1',
              'basis_fingerprint': planningHash,
              'policy_version': 'planning-policy-v1',
              'solver_backend': 'ortools-cp-sat',
              'solver_backend_version': '9.15.6755',
            }
          : null,
    },
    'readiness': {
      'status': readiness,
      'blocking_reasons': switch (readiness) {
        'DEADLINE_PASSED' => ['authoritative_submission_deadline_passed'],
        'ELIGIBILITY_BLOCKED' => ['minimum_age_not_met'],
        'INSUFFICIENT_INFORMATION' => ['mandatory_competition_information_missing'],
        _ => <String>[],
      },
      'review_items': readiness == 'NEEDS_REVIEW'
          ? ['user_age_unknown']
          : <String>[],
      'passed_checks': ready ? ['deadline_valid'] : <String>[],
      'rule_version': '1.0',
    },
    'planning': !ready
        ? null
        : {
            'feasibility': feasibility,
            'candidates': infeasible
                ? []
                : [
                    candidate(primaryId, 12, 180),
                    if (alternatives) candidate(alternativeId, 13, 120),
                  ],
            'allowed_actions': [
              if (!infeasible) 'ACCEPT',
              if (!infeasible && alternatives) 'CHOOSE_ALTERNATIVE',
              'EDIT_CONSTRAINTS',
              'IGNORE',
            ],
            'reason_codes': [
              if (infeasible) 'REQUIRED_LIKELY_INFEASIBLE'
              else if (feasibility == 'TIGHT_CAPACITY') 'REQUIRED_MAX_INFEASIBLE'
              else 'ALL_REQUIRED_SCENARIOS_FEASIBLE',
              if (feasibility == 'FEASIBLE') 'FULL_SCOPE_LIKELY_FEASIBLE',
              if (feasibility == 'FEASIBLE_WITH_TRADEOFFS') 'FULL_SCOPE_LIKELY_INFEASIBLE',
            ],
            'tradeoff_codes': [
              if (feasibility == 'FEASIBLE_WITH_TRADEOFFS') 'OPTIONAL_SCOPE_DOES_NOT_FIT',
            ],
            'sensitivity_codes': [
              if (feasibility == 'TIGHT_CAPACITY') 'EFFORT_OVERRUN_BREAKS_PLAN',
              if (feasibility == 'FEASIBLE' || feasibility == 'FEASIBLE_WITH_TRADEOFFS')
                'MAX_EFFORT_SCENARIO_FEASIBLE',
            ],
            'recommendation': infeasible
                ? null
                : {
                    'primary_candidate': ref(primaryId),
                    'alternative_candidates': [
                      if (alternatives) ref(alternativeId),
                    ],
                    'recommendation': {
                      'recommended_candidate_id': primaryId,
                      'recommended_next_work': next(12),
                      'suggested_windows': [window(12)],
                      'alternatives': [
                        if (alternatives)
                          {
                            'candidate_id': alternativeId,
                            'buffer_minutes': 120,
                            'recommended_next_work': next(13),
                            'suggested_windows': [window(13)],
                            'tradeoffs': ['Finishes 60 minutes later.'],
                          },
                      ],
                      'rationale': ['Required work fits at the likely estimate.'],
                      'tradeoffs': <String>[],
                      'assumptions': [
                        {'task_id': 'task-draft', 'description': 'Single-person work.'},
                      ],
                    },
                    'trace': {
                      'competition_id': 'competition-1',
                      'report_version': 2,
                      'assembly_material_fingerprint': reportHash,
                      'evaluation_basis_fingerprint': evaluationHash,
                      'planning_basis_fingerprint': planningHash,
                      'planning_policy_version': 'planning-policy-v1',
                    },
                  },
          },
  })) as Map<String, dynamic>;
}