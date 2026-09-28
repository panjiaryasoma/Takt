/// Model SAVED_PLAN_TASKS — satu task dalam sebuah revisi rencana.
/// Estimasi effort punya batas min <= likely <= max (menit).
class SavedPlanTask {
  SavedPlanTask({
    required this.id,
    required this.savedPlanRevisionId,
    required this.domainTaskId,
    required this.ordinal,
    required this.name,
    required this.mandatory,
    required this.effortMinMinutes,
    required this.effortLikelyMinutes,
    required this.effortMaxMinutes,
    required this.dependenciesJson,
    required this.assumptionsJson,
    required this.taskPayloadJson,
  });

  final String id;
  final String savedPlanRevisionId;
  final String domainTaskId;

  /// Urutan tampil (>= 0).
  final int ordinal;
  final String name;
  final bool mandatory;

  final int effortMinMinutes;
  final int effortLikelyMinutes;
  final int effortMaxMinutes;

  /// Disimpan sebagai JSON string (array/objek dari backend).
  final String dependenciesJson;
  final String assumptionsJson;
  final String taskPayloadJson;

  factory SavedPlanTask.fromMap(Map<String, Object?> m) => SavedPlanTask(
        id: m['id']! as String,
        savedPlanRevisionId: m['saved_plan_revision_id']! as String,
        domainTaskId: m['domain_task_id']! as String,
        ordinal: m['ordinal']! as int,
        name: m['name']! as String,
        mandatory: (m['mandatory']! as int) == 1,
        effortMinMinutes: m['effort_min_minutes']! as int,
        effortLikelyMinutes: m['effort_likely_minutes']! as int,
        effortMaxMinutes: m['effort_max_minutes']! as int,
        dependenciesJson: m['dependencies_json']! as String,
        assumptionsJson: m['assumptions_json']! as String,
        taskPayloadJson: m['task_payload_json']! as String,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'saved_plan_revision_id': savedPlanRevisionId,
        'domain_task_id': domainTaskId,
        'ordinal': ordinal,
        'name': name,
        'mandatory': mandatory ? 1 : 0,
        'effort_min_minutes': effortMinMinutes,
        'effort_likely_minutes': effortLikelyMinutes,
        'effort_max_minutes': effortMaxMinutes,
        'dependencies_json': dependenciesJson,
        'assumptions_json': assumptionsJson,
        'task_payload_json': taskPayloadJson,
      };
}
