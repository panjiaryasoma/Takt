import 'enums.dart';

/// Model SAVED_PLAN_REVISIONS — satu revisi dari sebuah rencana tersimpan.
/// Rantai revisi dibentuk lewat supersedesRevisionId (null = revisi akar #1).
class SavedPlanRevision {
  SavedPlanRevision({
    required this.id,
    required this.savedPlanId,
    required this.revisionNumber,
    required this.evaluationId,
    required this.selectedCandidateId,
    required this.selectionSource,
    this.supersedesRevisionId,
    required this.acceptedAtEpochMs,
  });

  final String id;
  final String savedPlanId;

  /// >= 1; revisi akar = 1.
  final int revisionNumber;

  /// Evaluasi yang jadi dasar revisi (UNIQUE — satu evaluasi satu revisi).
  final String evaluationId;
  final String selectedCandidateId;
  final SelectionSource selectionSource;

  /// null = revisi akar; selain itu id revisi yang digantikan.
  final String? supersedesRevisionId;

  final int acceptedAtEpochMs;

  DateTime get acceptedAt =>
      DateTime.fromMillisecondsSinceEpoch(acceptedAtEpochMs);

  bool get isRoot => supersedesRevisionId == null;

  factory SavedPlanRevision.fromMap(Map<String, Object?> m) =>
      SavedPlanRevision(
        id: m['id']! as String,
        savedPlanId: m['saved_plan_id']! as String,
        revisionNumber: m['revision_number']! as int,
        evaluationId: m['evaluation_id']! as String,
        selectedCandidateId: m['selected_candidate_id']! as String,
        selectionSource:
            SelectionSource.fromWire(m['selection_source']! as String),
        supersedesRevisionId: m['supersedes_revision_id'] as String?,
        acceptedAtEpochMs: m['accepted_at_epoch_ms']! as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'saved_plan_id': savedPlanId,
        'revision_number': revisionNumber,
        'evaluation_id': evaluationId,
        'selected_candidate_id': selectedCandidateId,
        'selection_source': selectionSource.wire,
        'supersedes_revision_id': supersedesRevisionId,
        'accepted_at_epoch_ms': acceptedAtEpochMs,
      };
}
