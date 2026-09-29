import 'dart:convert';

import '../utils/deterministic_json.dart';
import 'enums.dart';
import 'plan_evaluation_wire.dart';

final class ReevaluationTransitionWire {
  const ReevaluationTransitionWire({
    required this.kind,
    required this.priorEvaluationId,
    required this.priorBasisFingerprint,
    required this.currentBasisFingerprint,
    required this.priorEvaluationFreshness,
    required this.changeReasons,
  });

  factory ReevaluationTransitionWire.fromValue(Object? value) {
    final map = _strictObject(value, const {
      'kind',
      'prior_evaluation_id',
      'prior_basis_fingerprint',
      'current_basis_fingerprint',
      'prior_evaluation_freshness',
      'change_reasons',
    }, 'transition');

    final kindText = _text(map['kind'], 'transition.kind');
    final kind = ReevaluationKind.fromWire(kindText);
    final priorId = _uuid(map['prior_evaluation_id'], 'transition.prior_evaluation_id');
    final priorFingerprint =
        _sha(map['prior_basis_fingerprint'], 'transition.prior_basis_fingerprint');
    final currentRaw = map['current_basis_fingerprint'];
    final currentFingerprint = currentRaw == null
        ? null
        : _sha(currentRaw, 'transition.current_basis_fingerprint');
    final freshness =
        _text(map['prior_evaluation_freshness'], 'transition.prior_evaluation_freshness');
    if (freshness != (kind == ReevaluationKind.unchanged ? 'CURRENT' : 'STALE')) {
      throw const FormatException(
        'REEVALUATION_CONTRACT_INVALID: transition freshness is inconsistent.',
      );
    }
    final reasonsRaw = map['change_reasons'];
    if (reasonsRaw is! List || reasonsRaw.any((item) => item is! String)) {
      throw const FormatException(
        'REEVALUATION_CONTRACT_INVALID: change_reasons must be strings.',
      );
    }
    final reasons = List<String>.unmodifiable(reasonsRaw.cast<String>());
    const allowedReasons = {
      'REPORT_BASIS_CHANGED',
      'READINESS_BASIS_CHANGED',
      'PLANNING_BASIS_CHANGED',
    };
    if (reasons.any((reason) => !allowedReasons.contains(reason)) ||
        reasons.toSet().length != reasons.length) {
      throw const FormatException(
        'REEVALUATION_CONTRACT_INVALID: invalid change reasons.',
      );
    }

    if (kind == ReevaluationKind.unchanged) {
      if (reasons.isNotEmpty || currentFingerprint != priorFingerprint) {
        throw const FormatException(
          'REEVALUATION_CONTRACT_INVALID: invalid UNCHANGED transition.',
        );
      }
    } else if (reasons.isEmpty ||
        currentFingerprint == priorFingerprint && currentFingerprint != null) {
      throw const FormatException(
        'REEVALUATION_CONTRACT_INVALID: invalid SUPERSEDED transition.',
      );
    }

    return ReevaluationTransitionWire(
      kind: kind,
      priorEvaluationId: priorId,
      priorBasisFingerprint: priorFingerprint,
      currentBasisFingerprint: currentFingerprint,
      priorEvaluationFreshness: freshness,
      changeReasons: reasons,
    );
  }

  final ReevaluationKind kind;
  final String priorEvaluationId;
  final String priorBasisFingerprint;
  final String? currentBasisFingerprint;
  final String priorEvaluationFreshness;
  final List<String> changeReasons;

  Map<String, Object?> toJson() => {
        'kind': kind.wire,
        'prior_evaluation_id': priorEvaluationId,
        'prior_basis_fingerprint': priorBasisFingerprint,
        'current_basis_fingerprint': currentBasisFingerprint,
        'prior_evaluation_freshness': priorEvaluationFreshness,
        'change_reasons': changeReasons,
      };
}

final class PlanReevaluateSuccessWire {
  const PlanReevaluateSuccessWire({
    required this.transition,
    required this.evaluation,
    required this.evaluationResponseJson,
  });

  factory PlanReevaluateSuccessWire.parse(String raw) {
    final decoded = jsonDecode(raw);
    final map = _strictObject(
      decoded,
      const {'transition', 'evaluation'},
      're-evaluate response',
    );
    final transition = ReevaluationTransitionWire.fromValue(map['transition']);
    final evaluationValue = map['evaluation'];

    if (transition.kind == ReevaluationKind.unchanged) {
      if (evaluationValue != null) {
        throw const FormatException(
          'REEVALUATION_CONTRACT_INVALID: UNCHANGED must not contain an evaluation.',
        );
      }
      return PlanReevaluateSuccessWire(
        transition: transition,
        evaluation: null,
        evaluationResponseJson: null,
      );
    }

    if (evaluationValue is! Map) {
      throw const FormatException(
        'REEVALUATION_CONTRACT_INVALID: SUPERSEDED success requires evaluation.',
      );
    }
    final evaluationJson = deterministicJsonEncode(evaluationValue);
    final evaluation = PlanEvaluateResponseV1.parse(evaluationJson);
    if (transition.currentBasisFingerprint != evaluation.basis.fingerprint ||
        transition.priorEvaluationId == evaluation.evaluationId) {
      throw const FormatException(
        'REEVALUATION_CONTRACT_INVALID: transition and evaluation do not match.',
      );
    }
    return PlanReevaluateSuccessWire(
      transition: transition,
      evaluation: evaluation,
      evaluationResponseJson: evaluationJson,
    );
  }

  final ReevaluationTransitionWire transition;
  final PlanEvaluateResponseV1? evaluation;
  final String? evaluationResponseJson;
}

final class PlanReevaluateErrorWire {
  const PlanReevaluateErrorWire({
    required this.code,
    required this.stage,
    required this.message,
    required this.transition,
    required this.errorJson,
  });

  factory PlanReevaluateErrorWire.parse(String raw) {
    final decoded = jsonDecode(raw);
    final map = _strictObject(
      decoded,
      const {'error', 'transition'},
      're-evaluate error',
    );
    final error = _strictObject(
      map['error'],
      const {'code', 'message', 'stage', 'details'},
      'error',
    );
    final details = error['details'];
    if (details is! List) {
      throw const FormatException(
        'REEVALUATION_CONTRACT_INVALID: error.details must be an array.',
      );
    }
    final transitionValue = map['transition'];
    return PlanReevaluateErrorWire(
      code: _text(error['code'], 'error.code'),
      stage: _text(error['stage'], 'error.stage'),
      message: _text(error['message'], 'error.message'),
      transition: transitionValue == null
          ? null
          : ReevaluationTransitionWire.fromValue(transitionValue),
      errorJson: deterministicJsonEncode(error),
    );
  }

  final String code;
  final String stage;
  final String message;
  final ReevaluationTransitionWire? transition;
  final String errorJson;
}

Map<String, dynamic> _strictObject(
  Object? value,
  Set<String> keys,
  String field,
) {
  if (value is! Map) {
    throw FormatException(
      'REEVALUATION_CONTRACT_INVALID: $field must be an object.',
    );
  }
  final map = Map<String, dynamic>.from(value);
  if (map.keys.toSet().difference(keys).isNotEmpty ||
      keys.difference(map.keys.toSet()).isNotEmpty) {
    throw FormatException(
      'REEVALUATION_CONTRACT_INVALID: $field has unexpected fields.',
    );
  }
  return map;
}

String _text(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException(
      'REEVALUATION_CONTRACT_INVALID: $field must be nonblank.',
    );
  }
  return value;
}

String _uuid(Object? value, String field) {
  final text = _text(value, field);
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(text)) {
    throw FormatException(
      'REEVALUATION_CONTRACT_INVALID: $field must be UUIDv4.',
    );
  }
  return text;
}

String _sha(Object? value, String field) {
  final text = _text(value, field);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(text)) {
    throw FormatException(
      'REEVALUATION_CONTRACT_INVALID: $field must be SHA-256 hex.',
    );
  }
  return text;
}
