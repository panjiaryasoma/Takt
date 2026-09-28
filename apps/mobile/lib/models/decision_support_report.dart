import 'enums.dart';

/// Model WIRE hasil AI model — match persis kontrak backend
/// `packages/contracts/models.py` (DecisionSupportReport dan turunannya).
///
/// INI YANG DIPARSE DARI OUTPUT AI MODEL TEMANMU:
/// ```dart
/// final report = DecisionSupportReport.fromJson(jsonDecode(responseJson));
/// ```
/// Bentuk JSON = `response_json` pada tabel EVALUATIONS (ERD). Field yang di
/// kontrak backend masih longgar (`Any`) dibiarkan `dynamic` di sini juga,
/// supaya tidak menebak bentuk yang belum ditetapkan SSOT.

/// Brief kompetisi canonical (kontrak: CompetitionBrief).
class CompetitionBriefWire {
  const CompetitionBriefWire({
    required this.competitionId,
    required this.name,
    required this.organizer,
    required this.submissionDeadline,
    required this.eligibility,
    required this.deliverables,
    required this.sourceIds,
    required this.unresolvedCriticalFields,
  });

  final String competitionId;
  final String name;
  final String organizer;

  /// AwareDatetime ISO-8601 dari backend.
  final DateTime submissionDeadline;

  /// Bentuk belum dipersempit kontrak → dibiarkan dinamis.
  final Object? eligibility;
  final Object? deliverables;

  final List<String> sourceIds;
  final List<String> unresolvedCriticalFields;

  factory CompetitionBriefWire.fromJson(Map<String, dynamic> j) =>
      CompetitionBriefWire(
        competitionId: j['competition_id'] as String,
        name: j['name'] as String,
        organizer: j['organizer'] as String,
        submissionDeadline:
            DateTime.parse(j['submission_deadline'] as String),
        eligibility: j['eligibility'],
        deliverables: j['deliverables'],
        sourceIds:
            (j['source_ids'] as List? ?? const []).cast<String>(),
        unresolvedCriticalFields:
            (j['unresolved_critical_fields'] as List? ?? const [])
                .cast<String>(),
      );

  Map<String, dynamic> toJson() => {
        'competition_id': competitionId,
        'name': name,
        'organizer': organizer,
        'submission_deadline': submissionDeadline.toIso8601String(),
        'eligibility': eligibility,
        'deliverables': deliverables,
        'source_ids': sourceIds,
        'unresolved_critical_fields': unresolvedCriticalFields,
      };
}

/// Output triage kesiapan (kontrak: ReadinessTriage).
class ReadinessTriage {
  const ReadinessTriage({
    required this.status,
    required this.blockingReasons,
    required this.reviewItems,
    required this.passedChecks,
    required this.ruleVersion,
  });

  final ReadinessStatus status;
  final List<String> blockingReasons;
  final List<String> reviewItems;
  final List<String> passedChecks;
  final String ruleVersion;

  factory ReadinessTriage.fromJson(Map<String, dynamic> j) => ReadinessTriage(
        status: ReadinessStatus.fromWire(j['status'] as String),
        blockingReasons:
            (j['blocking_reasons'] as List? ?? const []).cast<String>(),
        reviewItems:
            (j['review_items'] as List? ?? const []).cast<String>(),
        passedChecks:
            (j['passed_checks'] as List? ?? const []).cast<String>(),
        ruleVersion: (j['rule_version'] as String?) ?? '',
      );
}

/// Satu blok alokasi kerja (kontrak: AllocationBlock).
class AllocationBlock {
  const AllocationBlock({
    required this.taskId,
    required this.start,
    required this.end,
    required this.allocatedMinutes,
    required this.availabilitySource,
  });

  final String taskId;
  final DateTime start;
  final DateTime end;
  final int allocatedMinutes;
  final String availabilitySource;

  factory AllocationBlock.fromJson(Map<String, dynamic> j) => AllocationBlock(
        taskId: j['task_id'] as String,
        start: DateTime.parse(j['start'] as String),
        end: DateTime.parse(j['end'] as String),
        allocatedMinutes: (j['allocated_minutes'] as num).toInt(),
        availabilitySource: j['availability_source'] as String,
      );
}

/// Kandidat rencana hasil solver (kontrak: CandidateAllocation).
class CandidateAllocation {
  const CandidateAllocation({
    required this.candidateId,
    required this.workBlocks,
    required this.bufferMinutes,
    required this.hardConstraintViolations,
    required this.assumptions,
  });

  final String candidateId;
  final List<AllocationBlock> workBlocks;
  final int bufferMinutes;
  final List<String> hardConstraintViolations;
  final List<String> assumptions;

  /// Hanya boleh direkomendasikan bila tak ada pelanggaran hard constraint.
  bool get isRecommendable => hardConstraintViolations.isEmpty;

  factory CandidateAllocation.fromJson(Map<String, dynamic> j) =>
      CandidateAllocation(
        candidateId: j['candidate_id'] as String,
        workBlocks: (j['work_blocks'] as List? ?? const [])
            .map((e) => AllocationBlock.fromJson(e as Map<String, dynamic>))
            .toList(),
        bufferMinutes: (j['buffer_minutes'] as num?)?.toInt() ?? 0,
        hardConstraintViolations:
            (j['hard_constraint_violations'] as List? ?? const [])
                .cast<String>(),
        assumptions:
            (j['assumptions'] as List? ?? const []).cast<String>(),
      );
}

/// Rekomendasi advisory (kontrak: Recommendation). Field longgar dibiarkan
/// dinamis sesuai kontrak.
class Recommendation {
  const Recommendation({
    required this.recommendedCandidateId,
    this.recommendedNextWork,
    this.suggestedWindows = const [],
    this.alternatives = const [],
    this.rationale = const [],
    this.tradeoffs = const [],
    this.assumptions = const [],
  });

  final String recommendedCandidateId;
  final Object? recommendedNextWork;
  final List<Object?> suggestedWindows;
  final List<Object?> alternatives;
  final List<Object?> rationale;
  final List<Object?> tradeoffs;
  final List<Object?> assumptions;

  factory Recommendation.fromJson(Map<String, dynamic> j) => Recommendation(
        recommendedCandidateId:
            (j['recommended_candidate_id'] as String?) ?? '',
        recommendedNextWork: j['recommended_next_work'],
        suggestedWindows:
            (j['suggested_windows'] as List? ?? const []).toList(),
        alternatives: (j['alternatives'] as List? ?? const []).toList(),
        rationale: (j['rationale'] as List? ?? const []).toList(),
        tradeoffs: (j['tradeoffs'] as List? ?? const []).toList(),
        assumptions: (j['assumptions'] as List? ?? const []).toList(),
      );
}

/// Laporan decision-support agregat — ROOT output AI model
/// (kontrak: DecisionSupportReport). Ini yang disimpan di
/// evaluations.response_json (ERD).
class DecisionSupportReport {
  const DecisionSupportReport({
    required this.competitionBrief,
    required this.readiness,
    this.workload,
    this.capacity,
    required this.feasibility,
    this.recommendation,
    this.risks,
    this.assumptions,
  });

  final CompetitionBriefWire competitionBrief;
  final ReadinessTriage readiness;

  /// Belum dipersempit kontrak → dinamis.
  final Object? workload;
  final Object? capacity;

  final FeasibilityStatus feasibility;
  final Recommendation? recommendation;
  final Object? risks;
  final Object? assumptions;

  factory DecisionSupportReport.fromJson(Map<String, dynamic> j) =>
      DecisionSupportReport(
        competitionBrief: CompetitionBriefWire.fromJson(
            j['competition_brief'] as Map<String, dynamic>),
        readiness:
            ReadinessTriage.fromJson(j['readiness'] as Map<String, dynamic>),
        workload: j['workload'],
        capacity: j['capacity'],
        feasibility:
            FeasibilityStatus.fromWire(j['feasibility'] as String?) ??
                FeasibilityStatus.feasible,
        recommendation: j['recommendation'] == null
            ? null
            : Recommendation.fromJson(
                j['recommendation'] as Map<String, dynamic>),
        risks: j['risks'],
        assumptions: j['assumptions'],
      );
}
