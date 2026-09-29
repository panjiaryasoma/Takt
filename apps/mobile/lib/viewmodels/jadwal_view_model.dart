import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repositories/saved_plan_repository.dart';
import '../data/repositories/schedule_repository.dart';
import '../models/active_accepted_block.dart';
import '../models/commitment.dart';
import '../models/enums.dart';
import '../models/planning_preferences.dart';
import '../models/recurrence_exception.dart';
import '../models/recurrence_rule.dart';
import '../models/schedule_occurrence.dart';

/// Presentation state for My Schedule.
///
/// SQLite/Drift is authoritative. The in-memory state here is only a read model
/// fed by [ScheduleRepository], so restarting the app does not erase schedules.
class JadwalViewModel extends ChangeNotifier {
  JadwalViewModel(
    this._repository, {
    SavedPlanRepository? savedPlanRepository,
  }) : _savedPlanRepository = savedPlanRepository;

  final ScheduleRepository _repository;
  final SavedPlanRepository? _savedPlanRepository;

  ScheduleState _state = ScheduleState.empty();
  StreamSubscription<ScheduleState>? _subscription;
  StreamSubscription<List<SavedPlanSummary>>? _savedPlanSubscription;
  List<ActiveAcceptedBlock> _acceptedBlocks = const [];
  DateTime _selectedDate = _dateOnly(DateTime.now());

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;

  List<Commitment> get all => List.unmodifiable(_state.commitments);
  List<ActiveAcceptedBlock> get acceptedBlocks =>
      List.unmodifiable(_acceptedBlocks);
  PlanningPreferences get preferences => _state.preferences;
  DateTime get selectedDate => _selectedDate;

  Future<void> initialize() async {
    if (_subscription != null) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.initialize();
      final saved = _savedPlanRepository;
      if (saved != null) {
        await saved.initialize();
        _acceptedBlocks = await saved.activeAcceptedBlocks();
        _savedPlanSubscription = saved.watchSummaries().listen((_) async {
          try {
            _acceptedBlocks = await saved.activeAcceptedBlocks();
            notifyListeners();
          } on Object {
            _errorMessage = 'Accepted plan schedule could not be refreshed.';
            notifyListeners();
          }
        });
      }
      _subscription = _repository.watchState().listen(
        (state) {
          _state = state;
          _isLoading = false;
          _errorMessage = null;
          notifyListeners();
        },
        onError: (Object error, StackTrace stackTrace) {
          _isLoading = false;
          _errorMessage = 'Failed to read the local schedule.';
          notifyListeners();
        },
      );
    } catch (_) {
      _isLoading = false;
      _errorMessage = 'Failed to open the schedule database.';
      notifyListeners();
    }
  }

  Future<void> retry() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.initialize();
      _state = await _repository.loadState();
      _subscription ??= _repository.watchState().listen(
        (state) {
          _state = state;
          _isLoading = false;
          _errorMessage = null;
          notifyListeners();
        },
        onError: (Object error, StackTrace stackTrace) {
          _isLoading = false;
          _errorMessage = 'Failed to read the local schedule.';
          notifyListeners();
        },
      );
      _isLoading = false;
    } catch (_) {
      _isLoading = false;
      _errorMessage = 'The schedule still could not be loaded.';
    }
    notifyListeners();
  }

  List<ScheduleOccurrence> get itemsForSelectedDate => itemsOn(_selectedDate);

  List<ActiveAcceptedBlock> get acceptedItemsForSelectedDate =>
      acceptedItemsOn(_selectedDate);

  List<ActiveAcceptedBlock> acceptedItemsOn(DateTime day) {
    final start = _dateOnly(day);
    final end = start.add(const Duration(days: 1));
    return _acceptedBlocks
        .where((block) =>
            !block.startAt.isBefore(start) && block.startAt.isBefore(end))
        .toList(growable: false)
      ..sort((a, b) => a.startAtEpochMs.compareTo(b.startAtEpochMs));
  }

  List<ScheduleOccurrence> itemsOn(DateTime day) {
    final start = _dateOnly(day);
    final end = start.add(const Duration(days: 1));
    return occurrencesBetween(start, end);
  }

  List<ScheduleOccurrence> occurrencesBetween(
    DateTime startInclusive,
    DateTime endExclusive,
  ) {
    final output = <ScheduleOccurrence>[];
    final rulesByCommitment = <String, RecurrenceRule>{
      for (final rule in _state.recurrenceRules) rule.commitmentId: rule,
    };
    final exceptionsByRule = <String, List<RecurrenceException>>{};
    for (final exception in _state.recurrenceExceptions) {
      exceptionsByRule.putIfAbsent(exception.recurrenceRuleId, () => []).add(exception);
    }

    for (final commitment in _state.commitments) {
      final rule = rulesByCommitment[commitment.id];
      if (rule == null) {
        final start = commitment.startAt;
        if (!start.isBefore(startInclusive) && start.isBefore(endExclusive)) {
          output.add(ScheduleOccurrence(
            commitment: commitment,
            startAtEpochMs: commitment.startAtEpochMs,
            endAtEpochMs: commitment.endAtEpochMs,
            originalStartAtEpochMs: commitment.startAtEpochMs,
          ));
        }
        continue;
      }

      final ruleExceptions = exceptionsByRule[rule.id] ?? const [];
      final exceptionByOriginal = <int, RecurrenceException>{
        for (final exception in ruleExceptions) exception.originalStartAtEpochMs: exception,
      };
      final weekdays = weekdaysFor(rule);
      final durationMs = commitment.endAtEpochMs - commitment.startAtEpochMs;
      final baseStart = commitment.startAt;
      final activeFrom = DateTime.fromMillisecondsSinceEpoch(rule.activeFromEpochMs);
      final activeUntil = rule.activeUntilEpochMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(rule.activeUntilEpochMs!);

      var day = _dateOnly(startInclusive);
      while (day.isBefore(endExclusive)) {
        if (weekdays.contains(day.weekday)) {
          final occurrenceStart = DateTime(
            day.year,
            day.month,
            day.day,
            baseStart.hour,
            baseStart.minute,
          );
          final originalStartMs = _floorToMinute(occurrenceStart.millisecondsSinceEpoch);
          final inActiveRange = !occurrenceStart.isBefore(activeFrom) &&
              (activeUntil == null || occurrenceStart.isBefore(activeUntil));

          if (inActiveRange && !exceptionByOriginal.containsKey(originalStartMs)) {
            output.add(ScheduleOccurrence(
              commitment: commitment,
              startAtEpochMs: originalStartMs,
              endAtEpochMs: originalStartMs + durationMs,
              originalStartAtEpochMs: originalStartMs,
              recurrenceRuleId: rule.id,
            ));
          }
        }
        day = day.add(const Duration(days: 1));
      }

      for (final exception in ruleExceptions) {
        if (exception.action != ExceptionAction.moved) continue;
        final replacementStartMs = exception.replacementStartAtEpochMs;
        final replacementEndMs = exception.replacementEndAtEpochMs;
        if (replacementStartMs == null || replacementEndMs == null) continue;
        final replacementStart = DateTime.fromMillisecondsSinceEpoch(replacementStartMs);
        if (!replacementStart.isBefore(startInclusive) &&
            replacementStart.isBefore(endExclusive)) {
          output.add(ScheduleOccurrence(
            commitment: commitment,
            startAtEpochMs: replacementStartMs,
            endAtEpochMs: replacementEndMs,
            originalStartAtEpochMs: exception.originalStartAtEpochMs,
            recurrenceRuleId: rule.id,
          ));
        }
      }
    }

    output.sort((a, b) {
      final byStart = a.startAtEpochMs.compareTo(b.startAtEpochMs);
      if (byStart != 0) return byStart;
      return a.commitment.id.compareTo(b.commitment.id);
    });
    return output;
  }

  Set<int> eventDaysOfMonth(DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final days =
        occurrencesBetween(start, end).map((item) => item.startAt.day).toSet();
    days.addAll(
      _acceptedBlocks
          .where((block) =>
              !block.startAt.isBefore(start) && block.startAt.isBefore(end))
          .map((block) => block.startAt.day),
    );
    return days;
  }

  int scheduledMinutesOn(DateTime day) {
    final manual =
        itemsOn(day).fold(0, (sum, item) => sum + item.durationMinutes);
    final accepted = acceptedItemsOn(day)
        .fold(0, (sum, item) => sum + item.durationMinutes);
    return manual + accepted;
  }

  Future<void> refreshAcceptedPlans() async {
    final saved = _savedPlanRepository;
    if (saved == null) return;
    await saved.refresh();
    _acceptedBlocks = await saved.activeAcceptedBlocks();
    notifyListeners();
  }

  void selectDate(DateTime day) {
    _selectedDate = _dateOnly(day);
    notifyListeners();
  }

  void selectDay(int day, {DateTime? inMonth}) {
    final month = inMonth ?? _selectedDate;
    selectDate(DateTime(month.year, month.month, day));
  }

  RecurrenceRule? recurrenceFor(String commitmentId) {
    for (final rule in _state.recurrenceRules) {
      if (rule.commitmentId == commitmentId) return rule;
    }
    return null;
  }

  Set<int> weekdaysFor(RecurrenceRule rule) {
    final parts = <String, String>{};
    for (final part in rule.rrule.split(';')) {
      final split = part.split('=');
      if (split.length == 2) parts[split[0]] = split[1];
    }
    if (parts['FREQ'] != 'WEEKLY') {
      throw StateError('Unsupported recurrence frequency: ${rule.rrule}');
    }
    final byDay = parts['BYDAY'];
    if (byDay == null || byDay.isEmpty) {
      throw StateError('Weekly recurrence requires BYDAY.');
    }
    return byDay.split(',').map(_weekdayFromToken).toSet();
  }

  Future<bool> tambah({
    required String title,
    String? category,
    required DateTime start,
    required DateTime end,
    CommitmentType type = CommitmentType.fixed,
    String timezone = 'Asia/Jakarta',
    String source = 'manual',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final commitment = Commitment(
      id: _newId('cmt'),
      title: title,
      category: category,
      type: type,
      startAtEpochMs: _floorToMinute(start.millisecondsSinceEpoch),
      endAtEpochMs: _floorToMinute(end.millisecondsSinceEpoch),
      timezone: timezone,
      source: source,
      createdAtEpochMs: now,
      updatedAtEpochMs: now,
    );
    final ok = await _save(() => _repository.createCommitment(commitment));
    if (ok) {
      _selectedDate = _dateOnly(start);
      notifyListeners();
    }
    return ok;
  }

  Future<bool> tambahRutin({
    required String title,
    String? category,
    required Set<int> weekdays,
    required int jamMulai,
    required int menitMulai,
    required int jamSelesai,
    required int menitSelesai,
    CommitmentType type = CommitmentType.fixed,
    DateTime? mulaiDari,
    String timezone = 'Asia/Jakarta',
  }) async {
    if (weekdays.isEmpty) return false;
    final first = _firstMatchingDay(_dateOnly(mulaiDari ?? DateTime.now()), weekdays);
    final start = DateTime(first.year, first.month, first.day, jamMulai, menitMulai);
    final end = DateTime(first.year, first.month, first.day, jamSelesai, menitSelesai);
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _newId('cmt');
    final commitment = Commitment(
      id: id,
      title: title,
      category: category,
      type: type,
      startAtEpochMs: _floorToMinute(start.millisecondsSinceEpoch),
      endAtEpochMs: _floorToMinute(end.millisecondsSinceEpoch),
      timezone: timezone,
      source: 'manual-rutin',
      createdAtEpochMs: now,
      updatedAtEpochMs: now,
    );
    final rule = RecurrenceRule(
      id: 'rr_$id',
      commitmentId: id,
      rrule: _weeklyRrule(weekdays),
      timezone: timezone,
      activeFromEpochMs: commitment.startAtEpochMs,
    );
    final ok = await _save(
      () => _repository.createCommitment(commitment, recurrenceRule: rule),
    );
    if (ok) {
      _selectedDate = _dateOnly(first);
      notifyListeners();
    }
    return ok;
  }

  Future<bool> ubah({
    required Commitment existing,
    required String title,
    String? category,
    required CommitmentType type,
    required bool recurring,
    required Set<int> weekdays,
    required DateTime start,
    required DateTime end,
    String timezone = 'Asia/Jakarta',
  }) async {
    final updated = Commitment(
      id: existing.id,
      title: title,
      category: category,
      type: type,
      startAtEpochMs: _floorToMinute(start.millisecondsSinceEpoch),
      endAtEpochMs: _floorToMinute(end.millisecondsSinceEpoch),
      timezone: timezone,
      source: existing.source,
      createdAtEpochMs: existing.createdAtEpochMs,
      updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
    RecurrenceRule? rule;
    if (recurring) {
      if (weekdays.isEmpty) return false;
      final previous = recurrenceFor(existing.id);
      rule = RecurrenceRule(
        id: previous?.id ?? 'rr_${existing.id}',
        commitmentId: existing.id,
        rrule: _weeklyRrule(weekdays),
        timezone: timezone,
        activeFromEpochMs: updated.startAtEpochMs,
        activeUntilEpochMs: previous?.activeUntilEpochMs,
      );
    }
    final ok = await _save(
      () => _repository.updateCommitment(updated, recurrenceRule: rule),
    );
    if (ok) {
      _selectedDate = _dateOnly(start);
      notifyListeners();
    }
    return ok;
  }

  Future<bool> hapus(String id) {
    return _save(() => _repository.deleteCommitment(id));
  }

  Future<bool> cancelOccurrence(ScheduleOccurrence occurrence) async {
    final ruleId = occurrence.recurrenceRuleId;
    if (ruleId == null) return false;
    final exception = RecurrenceException(
      id: _newId('rex'),
      recurrenceRuleId: ruleId,
      originalStartAtEpochMs: occurrence.originalStartAtEpochMs,
      action: ExceptionAction.cancelled,
    );
    return _save(() => _repository.upsertRecurrenceException(exception));
  }

  Future<bool> moveOccurrence(
    ScheduleOccurrence occurrence,
    DateTime replacementStart,
    DateTime replacementEnd,
  ) async {
    final ruleId = occurrence.recurrenceRuleId;
    if (ruleId == null) return false;
    final exception = RecurrenceException(
      id: _newId('rex'),
      recurrenceRuleId: ruleId,
      originalStartAtEpochMs: occurrence.originalStartAtEpochMs,
      action: ExceptionAction.moved,
      replacementStartAtEpochMs: _floorToMinute(replacementStart.millisecondsSinceEpoch),
      replacementEndAtEpochMs: _floorToMinute(replacementEnd.millisecondsSinceEpoch),
    );
    final ok = await _save(
      () => _repository.upsertRecurrenceException(exception),
    );
    if (ok) {
      _selectedDate = _dateOnly(replacementStart);
      notifyListeners();
    }
    return ok;
  }

  Future<bool> updatePlanningPreferences({
    required int maxProjectMinutesPerDay,
    required int preferredFocusMinutes,
    required int bufferTargetMinutes,
    String timezone = 'Asia/Jakarta',
  }) {
    final next = PlanningPreferences(
      timezone: timezone,
      maxProjectMinutesPerDay: maxProjectMinutesPerDay,
      preferredFocusMinutes: preferredFocusMinutes,
      bufferTargetMinutes: bufferTargetMinutes,
      updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
    return _save(() => _repository.savePlanningPreferences(next));
  }

  List<Commitment> itemsForCompetition(String competitionId) => _state.commitments
      .where((item) => item.source == 'lomba:$competitionId')
      .toList()
    ..sort((a, b) => a.startAtEpochMs.compareTo(b.startAtEpochMs));

  bool dayHasCompetition(DateTime day, String competitionId) {
    return itemsOn(day).any(
      (item) => item.commitment.source == 'lomba:$competitionId',
    );
  }

  /// Issue 1B intentionally does not generate solver/recommendation output in
  /// Flutter. 3B will provide backend candidate windows to this presentation
  /// layer instead of re-implementing the scheduling engine here.
  List<DateTimeRange> rekomendasiSlot({
    required DateTime sebelum,
    int butuhSesi = 3,
    int durasiMenit = 120,
    int jamKerjaMulai = 8,
    int jamKerjaSelesai = 21,
  }) {
    return const [];
  }

  Future<bool> terapkanRekomendasi({
    required String competitionId,
    required String judulLomba,
    String? deskripsi,
    required List<DateTimeRange> slot,
  }) async {
    for (final range in slot) {
      final ok = await tambah(
        title: judulLomba,
        category: deskripsi,
        start: range.start,
        end: range.end,
        type: CommitmentType.flexible,
        source: 'lomba:$competitionId',
      );
      if (!ok) return false;
    }
    return true;
  }

  void fokusKompetisi(String competitionId) {
    final accepted = _acceptedBlocks
        .where((item) => item.competitionId == competitionId)
        .toList()
      ..sort((a, b) => a.startAtEpochMs.compareTo(b.startAtEpochMs));
    if (accepted.isNotEmpty) {
      _selectedDate = _dateOnly(accepted.first.startAt);
      notifyListeners();
      return;
    }
    final items = itemsForCompetition(competitionId);
    if (items.isNotEmpty) {
      _selectedDate = _dateOnly(items.first.startAt);
      notifyListeners();
    }
  }

  Future<bool> _save(Future<void> Function() action) async {
    if (_isSaving) return false;
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (_) {
      _errorMessage = 'Failed to save schedule changes. Try again.';
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  static DateTime _firstMatchingDay(DateTime from, Set<int> weekdays) {
    var day = _dateOnly(from);
    for (var i = 0; i < 7; i++) {
      if (weekdays.contains(day.weekday)) return day;
      day = day.add(const Duration(days: 1));
    }
    throw StateError('No matching weekday found.');
  }

  static String _weeklyRrule(Set<int> weekdays) {
    final sorted = weekdays.toList()..sort();
    final tokens = sorted.map(_weekdayToken).join(',');
    return 'FREQ=WEEKLY;BYDAY=$tokens';
  }

  static String _weekdayToken(int weekday) => switch (weekday) {
        DateTime.monday => 'MO',
        DateTime.tuesday => 'TU',
        DateTime.wednesday => 'WE',
        DateTime.thursday => 'TH',
        DateTime.friday => 'FR',
        DateTime.saturday => 'SA',
        DateTime.sunday => 'SU',
        _ => throw ArgumentError.value(weekday, 'weekday'),
      };

  static int _weekdayFromToken(String token) => switch (token) {
        'MO' => DateTime.monday,
        'TU' => DateTime.tuesday,
        'WE' => DateTime.wednesday,
        'TH' => DateTime.thursday,
        'FR' => DateTime.friday,
        'SA' => DateTime.saturday,
        'SU' => DateTime.sunday,
        _ => throw StateError('Unsupported BYDAY token: $token'),
      };

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static int _floorToMinute(int epochMs) => (epochMs ~/ 60000) * 60000;

  static String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}';

  @override
  void dispose() {
    _subscription?.cancel();
    _savedPlanSubscription?.cancel();
    unawaited(_repository.close());
    final saved = _savedPlanRepository;
    if (saved != null) unawaited(saved.close());
    super.dispose();
  }
}