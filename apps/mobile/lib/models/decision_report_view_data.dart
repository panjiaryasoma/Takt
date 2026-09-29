import 'enums.dart';
import 'plan_evaluation_wire.dart';

/// Presentation only: no feasibility calculation, ranking, or input generation.
final class DecisionReportViewData {
  const DecisionReportViewData(this.response);
  final PlanEvaluateResponseV1 response;

  String get readinessLabel => switch (response.readiness.status) {
    ReadinessStatus.readyToEvaluate => 'Ready to evaluate',
    ReadinessStatus.needsReview => 'Needs review',
    ReadinessStatus.eligibilityBlocked => 'Participant requirements not met',
    ReadinessStatus.deadlinePassed => 'Submission deadline has passed',
    ReadinessStatus.insufficientInformation => 'Insufficient information',
  };

  String get feasibilityLabel => switch (response.planning?.feasibility) {
    null => 'Not evaluated',
    FeasibilityStatus.feasible => 'Feasible',
    FeasibilityStatus.feasibleWithTradeoffs => 'Feasible with tradeoffs',
    FeasibilityStatus.tightCapacity => 'Tight capacity',
    FeasibilityStatus.notFeasible => 'Not feasible under current constraints',
  };

  String get feasibilityExplanation => switch (response.planning?.feasibility) {
    null => switch (response.readiness.status) {
      ReadinessStatus.needsReview => 'Schedule feasibility was not evaluated because some information still needs review.',
      ReadinessStatus.insufficientInformation => 'Schedule feasibility was not evaluated because required information is still insufficient.',
      ReadinessStatus.eligibilityBlocked => 'Schedule feasibility was not evaluated because participant requirements are not met.',
      ReadinessStatus.deadlinePassed => 'Schedule feasibility was not evaluated because the submission deadline has passed.',
      ReadinessStatus.readyToEvaluate => throw StateError('Ready response requires planning'),
    },
    FeasibilityStatus.feasible => 'Required work and its prerequisites fit at the maximum estimate. The full scope fits at the likely estimate.',
    FeasibilityStatus.feasibleWithTradeoffs => 'Required work and its prerequisites fit at the maximum estimate, but the full scope does not fit at the likely estimate.',
    FeasibilityStatus.tightCapacity => 'Required work and its prerequisites fit at the likely estimate, but not at the maximum estimate.',
    FeasibilityStatus.notFeasible => 'Required work and its prerequisites do not fit at the likely estimate under the current constraints.',
  };

  DecisionCandidateViewData candidate(PublicCandidateV1 candidate) {
    final set = response.planning!.recommendation!;
    final payload = set.recommendation;
    if (candidate.ref.candidateId == set.primaryCandidate.candidateId) {
      return DecisionCandidateViewData(candidate, candidate.bufferMinutes,
          payload.recommendedNextWork, payload.suggestedWindows, payload.tradeoffs);
    }
    final alternative = payload.alternatives.firstWhere((item) => item.candidateId == candidate.ref.candidateId);
    return DecisionCandidateViewData(candidate, alternative.bufferMinutes,
        alternative.recommendedNextWork, alternative.suggestedWindows, alternative.tradeoffs);
  }

  /// Translate backend evidence without adding a new domain decision. Raw codes
  /// remain available in details; an unknown code gets a neutral explanation.
  static String explain(String code) {
    if (code.startsWith('unresolved_critical_field:')) {
      return 'Important competition information still needs review.';
    }
    return _explanations[code] ?? 'There is an additional evaluation note. See the evaluation details.';
  }
}

final class DecisionCandidateViewData {
  const DecisionCandidateViewData(this.candidate, this.bufferMinutes,
      this.nextWork, this.windows, this.tradeoffs);
  final PublicCandidateV1 candidate;
  final int bufferMinutes;
  final RecommendedNextWorkV1? nextWork;
  final List<SuggestedWorkWindowV1> windows;
  final List<String> tradeoffs;
}

const _explanations = {
  'submission_deadline_missing': 'The submission deadline is not known yet.',
  'authoritative_submission_deadline_passed': 'The authoritative submission deadline has passed.',
  'deadline_valid': 'The submission deadline was still valid at evaluation time.',
  'mandatory_competition_information_missing': 'Required competition information is incomplete.',
  'user_age_unknown': 'Participant age is required to check eligibility.',
  'minimum_age_not_met': 'The minimum age requirement is not met.',
  'minimum_age_met': 'The minimum age requirement is met.',
  'student_status_unknown': 'Student status needs to be confirmed.',
  'student_status_requirement_not_met': 'The student-status requirement is not met.',
  'student_status_met': 'The student-status requirement is met.',
  'user_country_unknown': 'Participant country is required.',
  'region_requirement_not_met': 'The participant region requirement is not met.',
  'region_eligible': 'The participant region requirement is met.',
  'mandatory_information_complete': 'Required competition information is complete.',
  'REQUIRED_LIKELY_INFEASIBLE': 'Required work does not fit at the likely estimate.',
  'REQUIRED_MAX_INFEASIBLE': 'Required work does not fit at the maximum estimate.',
  'FULL_SCOPE_LIKELY_INFEASIBLE': 'The full scope does not fit at the likely estimate.',
  'FULL_SCOPE_LIKELY_SCENARIO_UNKNOWN': 'Full-scope feasibility cannot be determined yet.',
  'ALL_REQUIRED_SCENARIOS_FEASIBLE': 'Required work fits in the minimum, likely, and maximum scenarios.',
  'FULL_SCOPE_LIKELY_FEASIBLE': 'The full scope fits at the likely estimate.',
  'MINIMUM_EFFORT_SCENARIO_FEASIBLE': 'Required work fits at the minimum estimate.',
  'MIN_SCENARIO_UNKNOWN': 'Feasibility at the minimum estimate cannot be determined yet.',
  'LIKELY_EFFORT_SCENARIO_INFEASIBLE': 'Required work does not fit at the likely estimate.',
  'EFFORT_OVERRUN_BREAKS_PLAN': 'The plan is sensitive to work taking longer than expected.',
  'MAX_EFFORT_SCENARIO_FEASIBLE': 'Required work still fits at the maximum estimate.',
  'MAX_SCENARIO_UNKNOWN': 'Feasibility at the maximum estimate cannot be determined yet.',
  'OPTIONAL_SCOPE_DOES_NOT_FIT': 'Some optional work must be removed under the current constraints.',
};