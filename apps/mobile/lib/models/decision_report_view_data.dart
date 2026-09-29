import 'enums.dart';
import 'plan_evaluation_wire.dart';

/// Presentation only: no feasibility calculation, ranking, or input generation.
final class DecisionReportViewData {
  const DecisionReportViewData(this.response);
  final PlanEvaluateResponseV1 response;

  String get readinessLabel => switch (response.readiness.status) {
    ReadinessStatus.readyToEvaluate => 'Siap dievaluasi',
    ReadinessStatus.needsReview => 'Perlu review',
    ReadinessStatus.eligibilityBlocked => 'Syarat peserta belum terpenuhi',
    ReadinessStatus.deadlinePassed => 'Batas pengumpulan sudah lewat',
    ReadinessStatus.insufficientInformation => 'Informasi belum cukup',
  };

  String get feasibilityLabel => switch (response.planning?.feasibility) {
    null => 'Belum dievaluasi',
    FeasibilityStatus.feasible => 'Feasible',
    FeasibilityStatus.feasibleWithTradeoffs => 'Feasible dengan tradeoff',
    FeasibilityStatus.tightCapacity => 'Kapasitas ketat',
    FeasibilityStatus.notFeasible => 'Tidak feasible dengan batasan saat ini',
  };

  String get feasibilityExplanation => switch (response.planning?.feasibility) {
    null => 'Evaluasi jadwal menunggu kesiapan informasi dan persyaratan.',
    FeasibilityStatus.feasible => 'Pekerjaan wajib beserta prasyaratnya muat pada estimasi maksimum. Seluruh scope muat pada estimasi likely.',
    FeasibilityStatus.feasibleWithTradeoffs => 'Pekerjaan wajib beserta prasyaratnya muat pada estimasi maksimum, tetapi seluruh scope tidak muat pada estimasi likely.',
    FeasibilityStatus.tightCapacity => 'Pekerjaan wajib beserta prasyaratnya muat pada estimasi likely, tetapi tidak muat pada estimasi maksimum.',
    FeasibilityStatus.notFeasible => 'Pekerjaan wajib beserta prasyaratnya tidak muat pada estimasi likely dengan batasan saat ini.',
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
      return 'Ada informasi penting kompetisi yang perlu ditinjau.';
    }
    return _explanations[code] ?? 'Ada catatan tambahan dari evaluasi. Lihat detail evaluasi.';
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
  'submission_deadline_missing': 'Batas pengumpulan belum diketahui.',
  'authoritative_submission_deadline_passed': 'Batas pengumpulan resmi sudah lewat.',
  'deadline_valid': 'Batas pengumpulan masih berlaku saat evaluasi.',
  'mandatory_competition_information_missing': 'Informasi wajib kompetisi belum lengkap.',
  'user_age_unknown': 'Usia peserta perlu dilengkapi untuk memeriksa persyaratan.',
  'minimum_age_not_met': 'Persyaratan usia minimum belum terpenuhi.',
  'minimum_age_met': 'Persyaratan usia minimum terpenuhi.',
  'student_status_unknown': 'Status pelajar/mahasiswa perlu dikonfirmasi.',
  'student_status_requirement_not_met': 'Persyaratan pelajar/mahasiswa belum terpenuhi.',
  'student_status_met': 'Persyaratan pelajar/mahasiswa terpenuhi.',
  'user_country_unknown': 'Negara peserta perlu dilengkapi.',
  'region_requirement_not_met': 'Persyaratan wilayah peserta belum terpenuhi.',
  'region_eligible': 'Persyaratan wilayah peserta terpenuhi.',
  'mandatory_information_complete': 'Informasi wajib kompetisi sudah lengkap.',
  'REQUIRED_LIKELY_INFEASIBLE': 'Pekerjaan wajib tidak muat pada estimasi likely.',
  'REQUIRED_MAX_INFEASIBLE': 'Pekerjaan wajib tidak muat pada estimasi maksimum.',
  'FULL_SCOPE_LIKELY_INFEASIBLE': 'Seluruh scope tidak muat pada estimasi likely.',
  'FULL_SCOPE_LIKELY_SCENARIO_UNKNOWN': 'Kelayakan seluruh scope belum dapat ditentukan.',
  'ALL_REQUIRED_SCENARIOS_FEASIBLE': 'Pekerjaan wajib muat pada skenario minimum, likely, dan maksimum.',
  'FULL_SCOPE_LIKELY_FEASIBLE': 'Seluruh scope muat pada estimasi likely.',
  'MINIMUM_EFFORT_SCENARIO_FEASIBLE': 'Pekerjaan wajib muat pada estimasi minimum.',
  'MIN_SCENARIO_UNKNOWN': 'Kelayakan pada estimasi minimum belum dapat ditentukan.',
  'LIKELY_EFFORT_SCENARIO_INFEASIBLE': 'Pekerjaan wajib tidak muat pada estimasi likely.',
  'EFFORT_OVERRUN_BREAKS_PLAN': 'Rencana sensitif terhadap pekerjaan yang memakan waktu lebih lama.',
  'MAX_EFFORT_SCENARIO_FEASIBLE': 'Pekerjaan wajib masih muat pada estimasi maksimum.',
  'MAX_SCENARIO_UNKNOWN': 'Kelayakan pada estimasi maksimum belum dapat ditentukan.',
  'OPTIONAL_SCOPE_DOES_NOT_FIT': 'Sebagian pekerjaan opsional perlu dikeluarkan dengan batasan saat ini.',
};
