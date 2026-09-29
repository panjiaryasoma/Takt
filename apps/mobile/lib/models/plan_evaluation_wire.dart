import 'dart:convert';

import 'enums.dart';

/// Public /plans/evaluate v1 response. Construction validates the whole graph.
/// No model in this file exposes a mutable collection or an unchecked constructor.
final class PlanEvaluateResponseV1 {
  PlanEvaluateResponseV1._(_Wire w)
      : evaluationId = w.uuid('evaluation_id'),
        evaluatedAt = w.time('evaluated_at'),
        basis = EvaluationBasisV1._(w.value('basis')),
        readiness = ReadinessTriage._(w.value('readiness')),
        planning = w.value('planning') == null
            ? null
            : PlanningDecisionV1._(w.value('planning')) {
    final ready = readiness.status == ReadinessStatus.readyToEvaluate;
    if (ready != (planning != null) || ready != (basis.planning != null)) {
      _invalid('readiness/planning/basis.planning shape mismatch');
    }
    if (readiness.ruleVersion != basis.readiness.ruleVersion) {
      _invalid('readiness rule does not match evaluation basis');
    }
    final decision = planning;
    if (decision == null) return;
    for (final candidate in decision.candidates) {
      if (candidate.ref.evaluationId != evaluationId) {
        _invalid('candidate belongs to another evaluation');
      }
    }
    final set = decision.recommendation;
    if (set == null) return;
    for (final ref in [set.primaryCandidate, ...set.alternativeCandidates]) {
      if (ref.evaluationId != evaluationId) {
        _invalid('recommendation reference belongs to another evaluation');
      }
    }
    final trace = set.trace;
    if (trace.competitionId != basis.report.competitionId ||
        trace.reportVersion != basis.report.reportVersion ||
        trace.assemblyMaterialFingerprint != basis.report.assemblyMaterialFingerprint ||
        trace.evaluationBasisFingerprint != basis.fingerprint ||
        trace.planningBasisFingerprint != basis.planning!.basisFingerprint ||
        trace.planningPolicyVersion != basis.planning!.policyVersion) {
      _invalid('recommendation trace does not match evaluation basis');
    }
    final payload = set.recommendation;
    _checkProjection(decision.candidate(set.primaryCandidate.candidateId)!,
        payload.suggestedWindows, payload.recommendedNextWork);
    for (final alternative in payload.alternatives) {
      final candidate = decision.candidate(alternative.candidateId)!;
      if (alternative.bufferMinutes != candidate.bufferMinutes) {
        _invalid('alternative buffer differs from the referenced candidate');
      }
      _checkProjection(candidate, alternative.suggestedWindows, alternative.recommendedNextWork);
    }
  }

  factory PlanEvaluateResponseV1.parse(String originalResponseJson) =>
      PlanEvaluateResponseV1._(_Wire(jsonDecode(originalResponseJson), 'response', {
        'evaluation_id', 'evaluated_at', 'basis', 'readiness', 'planning',
      }));

  final String evaluationId;
  final DateTime evaluatedAt;
  final EvaluationBasisV1 basis;
  final ReadinessTriage readiness;
  final PlanningDecisionV1? planning;
}

final class EvaluationBasisV1 {
  factory EvaluationBasisV1._(Object? value) {
    final w = _Wire(value, 'basis', {
      'version', 'domain_schema_version', 'fingerprint', 'report', 'readiness', 'planning',
    });
    w.literal('version', 'evaluation-basis-v1');
    w.literal('domain_schema_version', '3.0.0');
    return EvaluationBasisV1._validated(
      w.sha('fingerprint'), ReportBasisV1._(w.value('report')),
      ReadinessBasisV1._(w.value('readiness')),
      w.value('planning') == null ? null : PlanningBasisV1._(w.value('planning')),
    );
  }
  const EvaluationBasisV1._validated(this.fingerprint, this.report, this.readiness, this.planning);
  final String fingerprint;
  final ReportBasisV1 report;
  final ReadinessBasisV1 readiness;
  final PlanningBasisV1? planning;
}

final class ReportBasisV1 {
  factory ReportBasisV1._(Object? value) {
    final w = _Wire(value, 'basis.report', {
      'competition_id', 'report_version', 'reconciliation_policy_version',
      'assembly_policy_version', 'assembly_material_fingerprint',
    });
    w.literal('reconciliation_policy_version', 'reconciliation-v1');
    w.literal('assembly_policy_version', 'canonical-v1');
    return ReportBasisV1._validated(w.text('competition_id'),
        w.integer('report_version', min: 1), w.sha('assembly_material_fingerprint'));
  }
  const ReportBasisV1._validated(this.competitionId, this.reportVersion, this.assemblyMaterialFingerprint);
  final String competitionId;
  final int reportVersion;
  final String assemblyMaterialFingerprint;
}

final class ReadinessBasisV1 {
  factory ReadinessBasisV1._(Object? value) {
    final w = _Wire(value, 'basis.readiness', {
      'basis_version', 'basis_fingerprint', 'projection_version', 'rule_version',
    });
    w.literal('basis_version', 'readiness-basis-v1');
    w.literal('projection_version', 'readiness-projection-v1');
    w.literal('rule_version', '1.0');
    return ReadinessBasisV1._validated(w.sha('basis_fingerprint'), w.text('rule_version'));
  }
  const ReadinessBasisV1._validated(this.basisFingerprint, this.ruleVersion);
  final String basisFingerprint;
  final String ruleVersion;
}

final class PlanningBasisV1 {
  factory PlanningBasisV1._(Object? value) {
    final w = _Wire(value, 'basis.planning', {
      'basis_version', 'basis_fingerprint', 'policy_version',
      'solver_backend', 'solver_backend_version',
    });
    w.literal('basis_version', 'planning-basis-v1');
    w.literal('policy_version', 'planning-policy-v1');
    w.literal('solver_backend', 'ortools-cp-sat');
    return PlanningBasisV1._validated(w.sha('basis_fingerprint'),
        w.text('policy_version'), w.text('solver_backend_version'));
  }
  const PlanningBasisV1._validated(this.basisFingerprint, this.policyVersion, this.solverBackendVersion);
  final String basisFingerprint;
  final String policyVersion;
  // Package versions are opaque metadata, not a second semantic-policy allowlist.
  final String solverBackendVersion;
}

final class ReadinessTriage {
  factory ReadinessTriage._(Object? value) {
    final w = _Wire(value, 'readiness', {
      'status', 'blocking_reasons', 'review_items', 'passed_checks', 'rule_version',
    });
    w.literal('rule_version', '1.0');
    return ReadinessTriage._validated(
      w.enumeration('status', ReadinessStatus.values, (item) => item.wire),
      w.strings('blocking_reasons'), w.strings('review_items'),
      w.strings('passed_checks'), w.text('rule_version'),
    );
  }
  const ReadinessTriage._validated(this.status, this.blockingReasons,
      this.reviewItems, this.passedChecks, this.ruleVersion);
  final ReadinessStatus status;
  final List<String> blockingReasons;
  final List<String> reviewItems;
  final List<String> passedChecks;
  final String ruleVersion;
}

final class PlanningDecisionV1 {
  factory PlanningDecisionV1._(Object? value) {
    final w = _Wire(value, 'planning', {
      'feasibility', 'candidates', 'allowed_actions', 'reason_codes',
      'tradeoff_codes', 'sensitivity_codes', 'recommendation',
    });
    final feasibility = w.enumeration('feasibility', FeasibilityStatus.values, (item) => item.wire);
    final candidates = w.items('candidates', PublicCandidateV1._);
    final actions = List<RecommendationAction>.unmodifiable(w.strings('allowed_actions').map(
      (text) => _enumValue(text, RecommendationAction.values, (item) => item.wire),
    ));
    final recommendation = w.value('recommendation') == null
        ? null : RecommendationSetV1._(w.value('recommendation'));
    final candidateIds = candidates.map((item) => item.ref.candidateId).toList();
    if (candidateIds.toSet().length != candidateIds.length ||
        actions.toSet().length != actions.length) {
      _invalid('duplicate public candidate or action');
    }
    if (feasibility == FeasibilityStatus.notFeasible) {
      if (candidates.isNotEmpty || recommendation != null ||
          !_same(actions, [RecommendationAction.editConstraints, RecommendationAction.ignore])) {
        _invalid('infeasible decision must contain only edit and ignore');
      }
    } else {
      if (candidates.isEmpty || recommendation == null) {
        _invalid('recommendable decision requires candidates and recommendation');
      }
      final refs = [recommendation.primaryCandidate, ...recommendation.alternativeCandidates];
      if (!_same(candidateIds, refs.map((item) => item.candidateId).toList())) {
        _invalid('recommendation references must match candidate pool in canonical order');
      }
      final expected = [
        RecommendationAction.accept,
        if (recommendation.alternativeCandidates.isNotEmpty) RecommendationAction.chooseAlternative,
        RecommendationAction.editConstraints, RecommendationAction.ignore,
      ];
      if (!_same(actions, expected)) _invalid('allowed_actions do not match candidate availability');
    }
    return PlanningDecisionV1._validated(feasibility, candidates, actions,
        w.strings('reason_codes'), w.strings('tradeoff_codes'),
        w.strings('sensitivity_codes'), recommendation);
  }
  const PlanningDecisionV1._validated(this.feasibility, this.candidates, this.allowedActions,
      this.reasonCodes, this.tradeoffCodes, this.sensitivityCodes, this.recommendation);
  final FeasibilityStatus feasibility;
  final List<PublicCandidateV1> candidates;
  final List<RecommendationAction> allowedActions;
  final List<String> reasonCodes;
  final List<String> tradeoffCodes;
  final List<String> sensitivityCodes;
  final RecommendationSetV1? recommendation;

  PublicCandidateV1? candidate(String? id) {
    for (final candidate in candidates) {
      if (candidate.ref.candidateId == id) return candidate;
    }
    return null;
  }
}

final class CandidateRefV1 {
  factory CandidateRefV1._(Object? value) {
    final w = _Wire(value, 'candidate.ref', {'evaluation_id', 'candidate_id'});
    return CandidateRefV1._validated(w.uuid('evaluation_id'), w.text('candidate_id'));
  }
  const CandidateRefV1._validated(this.evaluationId, this.candidateId);
  final String evaluationId;
  final String candidateId;
}

final class PublicCandidateV1 {
  factory PublicCandidateV1._(Object? value) {
    final w = _Wire(value, 'candidate', {'ref', 'work_blocks', 'buffer_minutes', 'assumptions'});
    return PublicCandidateV1._validated(CandidateRefV1._(w.value('ref')),
        w.items('work_blocks', AllocationBlock._), w.integer('buffer_minutes'), w.strings('assumptions'));
  }
  const PublicCandidateV1._validated(this.ref, this.workBlocks, this.bufferMinutes, this.assumptions);
  final CandidateRefV1 ref;
  final List<AllocationBlock> workBlocks;
  final int bufferMinutes;
  final List<String> assumptions;
}

final class AllocationBlock {
  factory AllocationBlock._(Object? value) {
    final w = _Wire(value, 'work_block', _windowKeys);
    final start = w.time('start');
    final end = w.time('end');
    final minutes = w.integer('allocated_minutes', min: 1);
    if (start.second != 0 || start.millisecond != 0 || start.microsecond != 0 ||
        end.second != 0 || end.millisecond != 0 || end.microsecond != 0 ||
        end.difference(start).inMicroseconds != minutes * Duration.microsecondsPerMinute) {
      _invalid('allocation must have exact positive, minute-aligned duration');
    }
    return AllocationBlock._validated(w.text('task_id'), start, end, minutes, w.text('availability_source'));
  }
  const AllocationBlock._validated(this.taskId, this.start, this.end, this.allocatedMinutes, this.availabilitySource);
  final String taskId;
  final DateTime start;
  final DateTime end;
  final int allocatedMinutes;
  final String availabilitySource;
}

const _windowKeys = {'task_id', 'start', 'end', 'allocated_minutes', 'availability_source'};

/// Public windows/next-work must describe the allocation that Accept hands off.
/// This compares payloads only; it never generates or moves a work window.
void _checkProjection(PublicCandidateV1 candidate, List<SuggestedWorkWindowV1> windows,
    RecommendedNextWorkV1? next) {
  final blocks = [...candidate.workBlocks]..sort((a, b) {
    final start = a.start.compareTo(b.start);
    if (start != 0) return start;
    final task = a.taskId.compareTo(b.taskId);
    return task != 0 ? task : a.end.compareTo(b.end);
  });
  final expected = blocks.map((b) => (b.taskId, b.start, b.end, b.allocatedMinutes, b.availabilitySource)).toList();
  final actual = windows.map((w) => (w.taskId, w.start, w.end, w.allocatedMinutes, w.availabilitySource)).toList();
  if (!_same(expected, actual)) _invalid('suggested windows do not match the referenced allocation');
  if (windows.isEmpty) {
    if (next != null) _invalid('empty allocation cannot recommend next work');
  } else if (next == null ||
      (next.taskId, next.start, next.end, next.allocatedMinutes, next.availabilitySource) != actual.first) {
    _invalid('next work does not match the first suggested window');
  }
}

final class SuggestedWorkWindowV1 {
  factory SuggestedWorkWindowV1._(Object? value) {
    final w = _Wire(value, 'suggested_window', _windowKeys);
    return SuggestedWorkWindowV1._validated(w.text('task_id'), w.time('start'),
        w.time('end'), w.integer('allocated_minutes', min: 1), w.text('availability_source'));
  }
  const SuggestedWorkWindowV1._validated(this.taskId, this.start, this.end, this.allocatedMinutes, this.availabilitySource);
  final String taskId;
  final DateTime start;
  final DateTime end;
  final int allocatedMinutes;
  final String availabilitySource;
}

final class RecommendedNextWorkV1 {
  factory RecommendedNextWorkV1._(Object? value) {
    final w = _Wire(value, 'recommended_next_work', {..._windowKeys, 'task_name'});
    return RecommendedNextWorkV1._validated(w.text('task_id'), w.text('task_name'),
        w.time('start'), w.time('end'), w.integer('allocated_minutes', min: 1), w.text('availability_source'));
  }
  const RecommendedNextWorkV1._validated(this.taskId, this.taskName, this.start, this.end, this.allocatedMinutes, this.availabilitySource);
  final String taskId;
  final String taskName;
  final DateTime start;
  final DateTime end;
  final int allocatedMinutes;
  final String availabilitySource;
}

final class RecommendationAlternativeV1 {
  factory RecommendationAlternativeV1._(Object? value) {
    final w = _Wire(value, 'alternative', {
      'candidate_id', 'buffer_minutes', 'recommended_next_work', 'suggested_windows', 'tradeoffs',
    });
    return RecommendationAlternativeV1._validated(w.text('candidate_id'),
        w.integer('buffer_minutes'), _next(w.value('recommended_next_work')),
        w.items('suggested_windows', SuggestedWorkWindowV1._), w.strings('tradeoffs'));
  }
  const RecommendationAlternativeV1._validated(this.candidateId, this.bufferMinutes,
      this.recommendedNextWork, this.suggestedWindows, this.tradeoffs);
  final String candidateId;
  final int bufferMinutes;
  final RecommendedNextWorkV1? recommendedNextWork;
  final List<SuggestedWorkWindowV1> suggestedWindows;
  final List<String> tradeoffs;
}

RecommendedNextWorkV1? _next(Object? value) => value == null ? null : RecommendedNextWorkV1._(value);

final class RecommendationAssumptionV1 {
  factory RecommendationAssumptionV1._(Object? value) {
    final w = _Wire(value, 'assumption', {'task_id', 'description'});
    return RecommendationAssumptionV1._validated(
        w.value('task_id') == null ? null : w.text('task_id'), w.text('description'));
  }
  const RecommendationAssumptionV1._validated(this.taskId, this.description);
  final String? taskId;
  final String description;
}

final class RecommendationV1 {
  factory RecommendationV1._(Object? value) {
    final w = _Wire(value, 'recommendation.payload', {
      'recommended_candidate_id', 'recommended_next_work', 'suggested_windows',
      'alternatives', 'rationale', 'tradeoffs', 'assumptions',
    });
    return RecommendationV1._validated(w.text('recommended_candidate_id'),
        _next(w.value('recommended_next_work')), w.items('suggested_windows', SuggestedWorkWindowV1._),
        w.items('alternatives', RecommendationAlternativeV1._), w.strings('rationale'),
        w.strings('tradeoffs'), w.items('assumptions', RecommendationAssumptionV1._));
  }
  const RecommendationV1._validated(this.recommendedCandidateId, this.recommendedNextWork,
      this.suggestedWindows, this.alternatives, this.rationale, this.tradeoffs, this.assumptions);
  final String recommendedCandidateId;
  final RecommendedNextWorkV1? recommendedNextWork;
  final List<SuggestedWorkWindowV1> suggestedWindows;
  final List<RecommendationAlternativeV1> alternatives;
  final List<String> rationale;
  final List<String> tradeoffs;
  final List<RecommendationAssumptionV1> assumptions;
}

final class RecommendationTraceV1 {
  factory RecommendationTraceV1._(Object? value) {
    final w = _Wire(value, 'recommendation.trace', {
      'competition_id', 'report_version', 'assembly_material_fingerprint',
      'evaluation_basis_fingerprint', 'planning_basis_fingerprint', 'planning_policy_version',
    });
    w.literal('planning_policy_version', 'planning-policy-v1');
    return RecommendationTraceV1._validated(w.text('competition_id'), w.integer('report_version', min: 1),
        w.sha('assembly_material_fingerprint'), w.sha('evaluation_basis_fingerprint'),
        w.sha('planning_basis_fingerprint'), w.text('planning_policy_version'));
  }
  const RecommendationTraceV1._validated(this.competitionId, this.reportVersion,
      this.assemblyMaterialFingerprint, this.evaluationBasisFingerprint,
      this.planningBasisFingerprint, this.planningPolicyVersion);
  final String competitionId;
  final int reportVersion;
  final String assemblyMaterialFingerprint;
  final String evaluationBasisFingerprint;
  final String planningBasisFingerprint;
  final String planningPolicyVersion;
}

final class RecommendationSetV1 {
  factory RecommendationSetV1._(Object? value) {
    final w = _Wire(value, 'recommendation', {
      'primary_candidate', 'alternative_candidates', 'recommendation', 'trace',
    });
    final primary = CandidateRefV1._(w.value('primary_candidate'));
    final alternatives = w.items('alternative_candidates', CandidateRefV1._);
    final payload = RecommendationV1._(w.value('recommendation'));
    final ids = alternatives.map((item) => item.candidateId).toList();
    if (ids.toSet().length != ids.length || ids.contains(primary.candidateId) ||
        alternatives.any((item) => item.evaluationId != primary.evaluationId) ||
        payload.recommendedCandidateId != primary.candidateId ||
        !_same(ids, payload.alternatives.map((item) => item.candidateId).toList())) {
      _invalid('recommendation primary/alternative references do not match payload');
    }
    return RecommendationSetV1._validated(primary, alternatives, payload, RecommendationTraceV1._(w.value('trace')));
  }
  const RecommendationSetV1._validated(this.primaryCandidate, this.alternativeCandidates, this.recommendation, this.trace);
  final CandidateRefV1 primaryCandidate;
  final List<CandidateRefV1> alternativeCandidates;
  final RecommendationV1 recommendation;
  final RecommendationTraceV1 trace;
}

// These readers deliberately stay separate from 2B's readers: 2B's string-array
// reader rejects duplicates, while public decision explanations may repeat.
final class _Wire {
  _Wire(Object? value, this.path, Set<String> keys) {
    if (value is! Map<String, dynamic> ||
        value.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(value.keys.toSet()).isNotEmpty) {
      _invalid('$path must contain exactly ${keys.join(', ')}');
    }
    _map = value;
  }
  late final Map<String, dynamic> _map;
  final String path;
  Object? value(String key) => _map[key];
  String text(String key) => _text(value(key), '$path.$key');
  void literal(String key, String expected) {
    if (text(key) != expected) _invalid('$path.$key unsupported version/value');
  }
  int integer(String key, {int min = 0}) {
    final n = value(key);
    if (n is! int || n < min) _invalid('$path.$key must be an integer >= $min');
    return n;
  }
  List<T> items<T>(String key, T Function(Object?) parse) {
    final values = value(key);
    if (values is! List) _invalid('$path.$key must be an array');
    return List<T>.unmodifiable(values.map(parse));
  }
  List<String> strings(String key) => items(key, (value) => _text(value, '$path.$key[]'));
  T enumeration<T>(String key, List<T> values, String Function(T) wire) => _enumValue(text(key), values, wire);
  String sha(String key) {
    final s = text(key);
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(s)) _invalid('$path.$key must be SHA-256 hex');
    return s;
  }
  String uuid(String key) {
    final s = text(key);
    if (!RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(s)) {
      _invalid('$path.$key must be a UUID');
    }
    return s;
  }
  DateTime time(String key) {
    final s = text(key);
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?(Z|[+-](\d{2}):(\d{2}))$').firstMatch(s);
    if (m == null) _invalid('$path.$key must be a timezone-aware ISO timestamp');
    int part(int index) => int.parse(m.group(index)!);
    final year = part(1), month = part(2), day = part(3);
    if (year < 1 || month < 1 || month > 12 || day < 1 ||
        day > DateTime.utc(year, month + 1, 0).day ||
        part(4) > 23 || part(5) > 59 || part(6) > 59 ||
        (m.group(8) != 'Z' && (part(9) > 23 || part(10) > 59))) {
      _invalid('$path.$key contains an invalid date/time');
    }
    return DateTime.parse(s).toUtc();
  }
}

String _text(Object? value, String path) {
  if (value is! String || value.trim().isEmpty) _invalid('$path must be a nonblank string');
  return value;
}

T _enumValue<T>(String text, List<T> values, String Function(T) wire) {
  for (final value in values) {
    if (wire(value) == text) return value;
  }
  _invalid('unknown enum/action: $text');
}

bool _same<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Never _invalid(String message) => throw FormatException('RESPONSE_CONTRACT_INVALID: $message');
