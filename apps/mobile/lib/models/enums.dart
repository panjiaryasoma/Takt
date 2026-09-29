/// Enum domain jadwal — cocok dengan CHECK constraint di takt_schema_v3.sql.
library;

/// Jenis komitmen. SQL: type TEXT CHECK (type IN ('FIXED','FLEXIBLE')).
enum CommitmentType {
  fixed('FIXED'),
  flexible('FLEXIBLE');

  const CommitmentType(this.wire);
  final String wire;

  static CommitmentType fromWire(String value) {
    return CommitmentType.values.firstWhere(
      (item) => item.wire == value,
      orElse: () => throw StateError('Unknown commitment type: $value'),
    );
  }
}

/// Aksi pengecualian recurrence.
enum ExceptionAction {
  cancelled('CANCELLED'),
  moved('MOVED');

  const ExceptionAction(this.wire);
  final String wire;

  static ExceptionAction fromWire(String value) {
    return ExceptionAction.values.firstWhere(
      (item) => item.wire == value,
      orElse: () => throw StateError('Unknown recurrence action: $value'),
    );
  }
}

/// Status kesiapan evaluasi.
enum ReadinessStatus {
  readyToEvaluate('READY_TO_EVALUATE'),
  needsReview('NEEDS_REVIEW'),
  eligibilityBlocked('ELIGIBILITY_BLOCKED'),
  deadlinePassed('DEADLINE_PASSED'),
  insufficientInformation('INSUFFICIENT_INFORMATION');

  const ReadinessStatus(this.wire);
  final String wire;

  static ReadinessStatus fromWire(String value) =>
      ReadinessStatus.values.firstWhere((e) => e.wire == value,
          orElse: () => throw StateError('Unknown readiness status: $value'));
}

/// Status kelayakan (feasibility). Boleh null.
enum FeasibilityStatus {
  feasible('FEASIBLE'),
  feasibleWithTradeoffs('FEASIBLE_WITH_TRADEOFFS'),
  tightCapacity('TIGHT_CAPACITY'),
  notFeasible('NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS');

  const FeasibilityStatus(this.wire);
  final String wire;

  static FeasibilityStatus? fromWire(String? value) {
    if (value == null) return null;
    return FeasibilityStatus.values.firstWhere((e) => e.wire == value,
        orElse: () => throw StateError('Unknown feasibility status: $value'));
  }
}

/// Jenis transisi re-evaluasi.
enum ReevaluationKind {
  unchanged('UNCHANGED'),
  superseded('SUPERSEDED');

  const ReevaluationKind(this.wire);
  final String wire;

  static ReevaluationKind fromWire(String value) =>
      ReevaluationKind.values.firstWhere((e) => e.wire == value,
          orElse: () => throw StateError('Unknown reevaluation kind: $value'));
}

/// Sumber pemilihan kandidat pada revisi rencana.
enum SelectionSource {
  primary('PRIMARY'),
  alternative('ALTERNATIVE');

  const SelectionSource(this.wire);
  final String wire;

  static SelectionSource fromWire(String value) =>
      SelectionSource.values.firstWhere((e) => e.wire == value,
          orElse: () => throw StateError('Unknown selection source: $value'));
}
