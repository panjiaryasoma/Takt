import 'planning_preferences.dart';

final class PlanningTaskDraft {
  PlanningTaskDraft({
    required this.taskId,
    required this.name,
    required this.mandatory,
    required List<String> dependencies,
    required this.effortMinMinutes,
    required this.effortLikelyMinutes,
    required this.effortMaxMinutes,
    required List<String> assumptions,
  })  : dependencies = List.unmodifiable(dependencies),
        assumptions = List.unmodifiable(assumptions) {
    if (taskId.trim().isEmpty || name.trim().isEmpty) {
      throw const FormatException('Task ID and name must not be empty.');
    }
    if (dependencies.contains(taskId) ||
        dependencies.toSet().length != dependencies.length) {
      throw const FormatException('Task dependencies are invalid.');
    }
    if (effortMinMinutes < 0 ||
        effortLikelyMinutes < effortMinMinutes ||
        effortMaxMinutes < effortLikelyMinutes) {
      throw const FormatException('Task effort must satisfy min <= likely <= max.');
    }
  }

  factory PlanningTaskDraft.create({
    required String name,
    bool mandatory = true,
    int effortMinMinutes = 60,
    int effortLikelyMinutes = 120,
    int effortMaxMinutes = 180,
    List<String> dependencies = const [],
    List<String> assumptions = const [],
  }) {
    return PlanningTaskDraft(
      taskId: 'task-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      mandatory: mandatory,
      dependencies: dependencies,
      effortMinMinutes: effortMinMinutes,
      effortLikelyMinutes: effortLikelyMinutes,
      effortMaxMinutes: effortMaxMinutes,
      assumptions: assumptions,
    );
  }

  factory PlanningTaskDraft.fromWire(Map<String, dynamic> map) {
    List<String> strings(Object? value, String field) {
      if (value is! List || value.any((item) => item is! String)) {
        throw FormatException('Invalid task $field.');
      }
      return value.cast<String>();
    }

    final taskId = map['task_id'];
    final name = map['name'];
    final mandatory = map['mandatory'];
    final min = map['effort_min_minutes'];
    final likely = map['effort_likely_minutes'];
    final max = map['effort_max_minutes'];
    if (taskId is! String ||
        name is! String ||
        mandatory is! bool ||
        min is! int ||
        likely is! int ||
        max is! int) {
      throw const FormatException('Invalid persisted task snapshot.');
    }
    return PlanningTaskDraft(
      taskId: taskId,
      name: name,
      mandatory: mandatory,
      dependencies: strings(map['dependencies'], 'dependencies'),
      effortMinMinutes: min,
      effortLikelyMinutes: likely,
      effortMaxMinutes: max,
      assumptions: strings(map['assumptions'], 'assumptions'),
    );
  }

  final String taskId;
  final String name;
  final bool mandatory;
  final List<String> dependencies;
  final int effortMinMinutes;
  final int effortLikelyMinutes;
  final int effortMaxMinutes;
  final List<String> assumptions;

  Map<String, Object?> toWire() => {
        'task_id': taskId,
        'name': name,
        'mandatory': mandatory,
        'dependencies': dependencies,
        'effort_min_minutes': effortMinMinutes,
        'effort_likely_minutes': effortLikelyMinutes,
        'effort_max_minutes': effortMaxMinutes,
        'assumptions': assumptions,
      };

  PlanningTaskDraft copyWith({
    String? name,
    bool? mandatory,
    List<String>? dependencies,
    int? effortMinMinutes,
    int? effortLikelyMinutes,
    int? effortMaxMinutes,
    List<String>? assumptions,
  }) {
    return PlanningTaskDraft(
      taskId: taskId,
      name: name ?? this.name,
      mandatory: mandatory ?? this.mandatory,
      dependencies: dependencies ?? this.dependencies,
      effortMinMinutes: effortMinMinutes ?? this.effortMinMinutes,
      effortLikelyMinutes: effortLikelyMinutes ?? this.effortLikelyMinutes,
      effortMaxMinutes: effortMaxMinutes ?? this.effortMaxMinutes,
      assumptions: assumptions ?? this.assumptions,
    );
  }
}

final class ReadinessContextDraft {
  const ReadinessContextDraft({
    this.age,
    this.studentStatus,
    this.country,
    this.selectedScope,
    this.requireTechnologyInformation = false,
  });

  factory ReadinessContextDraft.fromWire(Map<String, dynamic> map) {
    final user = map['user'];
    if (user is! Map) {
      throw const FormatException('Invalid readiness user context.');
    }
    final age = user['age'];
    final studentStatus = user['student_status'];
    final country = user['country'];
    final selectedScope = map['selected_scope'];
    final requireTechnologyInformation = map['require_technology_information'];
    if (age != null && age is! int ||
        studentStatus != null && studentStatus is! bool ||
        country != null && country is! String ||
        selectedScope != null && selectedScope is! String ||
        requireTechnologyInformation is! bool) {
      throw const FormatException('Invalid readiness context snapshot.');
    }
    return ReadinessContextDraft(
      age: age as int?,
      studentStatus: studentStatus as bool?,
      country: country as String?,
      selectedScope: selectedScope as String?,
      requireTechnologyInformation: requireTechnologyInformation,
    );
  }

  final int? age;
  final bool? studentStatus;
  final String? country;
  final String? selectedScope;
  final bool requireTechnologyInformation;

  Map<String, Object?> toWire() => {
        'user': {
          'age': age,
          'student_status': studentStatus,
          'country': _blankToNull(country),
        },
        'selected_scope': _blankToNull(selectedScope),
        'require_technology_information': requireTechnologyInformation,
      };

  ReadinessContextDraft copyWith({
    int? age,
    bool? studentStatus,
    String? country,
    String? selectedScope,
    bool? requireTechnologyInformation,
    bool clearAge = false,
    bool clearStudentStatus = false,
    bool clearCountry = false,
    bool clearSelectedScope = false,
  }) {
    return ReadinessContextDraft(
      age: clearAge ? null : (age ?? this.age),
      studentStatus:
          clearStudentStatus ? null : (studentStatus ?? this.studentStatus),
      country: clearCountry ? null : (country ?? this.country),
      selectedScope:
          clearSelectedScope ? null : (selectedScope ?? this.selectedScope),
      requireTechnologyInformation:
          requireTechnologyInformation ?? this.requireTechnologyInformation,
    );
  }
}

final class PlanningWindowPolicyV1 {
  PlanningWindowPolicyV1({
    required this.timezone,
    required this.startMinutesOfDay,
    required this.endMinutesOfDay,
  }) {
    if (timezone.trim().isEmpty ||
        startMinutesOfDay < 0 ||
        startMinutesOfDay >= 1440 ||
        endMinutesOfDay <= 0 ||
        endMinutesOfDay > 1440 ||
        startMinutesOfDay >= endMinutesOfDay) {
      throw const FormatException('Invalid planning window policy.');
    }
  }

  static const policyVersion = 'planning-window-policy-v1';

  factory PlanningWindowPolicyV1.defaults(String timezone) =>
      PlanningWindowPolicyV1(
        timezone: timezone,
        startMinutesOfDay: 8 * 60,
        endMinutesOfDay: 22 * 60,
      );

  factory PlanningWindowPolicyV1.fromJson(Map<String, dynamic> map) {
    if (map['policy_version'] != policyVersion ||
        map['timezone'] is! String ||
        map['start_local'] is! String ||
        map['end_local'] is! String) {
      throw const FormatException('Unsupported planning window policy.');
    }
    return PlanningWindowPolicyV1(
      timezone: map['timezone'] as String,
      startMinutesOfDay: _parseClock(map['start_local'] as String),
      endMinutesOfDay: _parseClock(map['end_local'] as String),
    );
  }

  final String timezone;
  final int startMinutesOfDay;
  final int endMinutesOfDay;

  String get startLocal => _clock(startMinutesOfDay);
  String get endLocal => _clock(endMinutesOfDay);

  Map<String, Object?> toJson() => {
        'policy_version': policyVersion,
        'timezone': timezone,
        'start_local': startLocal,
        'end_local': endLocal,
      };

  PlanningWindowPolicyV1 copyWith({
    String? timezone,
    int? startMinutesOfDay,
    int? endMinutesOfDay,
  }) {
    return PlanningWindowPolicyV1(
      timezone: timezone ?? this.timezone,
      startMinutesOfDay: startMinutesOfDay ?? this.startMinutesOfDay,
      endMinutesOfDay: endMinutesOfDay ?? this.endMinutesOfDay,
    );
  }
}

final class PlanningDraft {
  PlanningDraft({
    required this.readinessContext,
    required List<PlanningTaskDraft> tasks,
    required this.preferences,
    required this.windowPolicy,
  }) : tasks = List.unmodifiable(tasks) {
    _validateTasks(this.tasks);
    if (preferences.timezone != windowPolicy.timezone) {
      throw const FormatException(
        'Planning preferences and window policy timezone must match.',
      );
    }
  }

  final ReadinessContextDraft readinessContext;
  final List<PlanningTaskDraft> tasks;
  final PlanningPreferences preferences;
  final PlanningWindowPolicyV1 windowPolicy;

  PlanningDraft copyWith({
    ReadinessContextDraft? readinessContext,
    List<PlanningTaskDraft>? tasks,
    PlanningPreferences? preferences,
    PlanningWindowPolicyV1? windowPolicy,
  }) {
    final nextPreferences = preferences ?? this.preferences;
    final nextPolicy = windowPolicy ??
        (preferences != null && preferences.timezone != this.windowPolicy.timezone
            ? this.windowPolicy.copyWith(timezone: preferences.timezone)
            : this.windowPolicy);
    return PlanningDraft(
      readinessContext: readinessContext ?? this.readinessContext,
      tasks: tasks ?? this.tasks,
      preferences: nextPreferences,
      windowPolicy: nextPolicy,
    );
  }
}

void _validateTasks(List<PlanningTaskDraft> tasks) {
  final ids = tasks.map((task) => task.taskId).toSet();
  if (ids.length != tasks.length) {
    throw const FormatException('Task IDs must be unique.');
  }
  for (final task in tasks) {
    if (task.dependencies.any((dependency) => !ids.contains(dependency))) {
      throw FormatException(
        'Task ${task.taskId} references an unknown dependency.',
      );
    }
  }

  final visiting = <String>{};
  final visited = <String>{};
  final byId = {for (final task in tasks) task.taskId: task};
  bool visit(String id) {
    if (visiting.contains(id)) return false;
    if (visited.contains(id)) return true;
    visiting.add(id);
    for (final dependency in byId[id]!.dependencies) {
      if (!visit(dependency)) return false;
    }
    visiting.remove(id);
    visited.add(id);
    return true;
  }

  if (ids.any((id) => !visit(id))) {
    throw const FormatException('Task dependencies must be acyclic.');
  }
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _clock(int minutes) {
  final hour = (minutes ~/ 60).toString().padLeft(2, '0');
  final minute = (minutes % 60).toString().padLeft(2, '0');
  return '$hour:$minute';
}

int _parseClock(String value) {
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
  if (match == null) throw const FormatException('Invalid local clock time.');
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) {
    throw const FormatException('Invalid local clock time.');
  }
  return hour * 60 + minute;
}
