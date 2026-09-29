import 'package:flutter/foundation.dart';

import '../data/repositories/saved_plan_repository.dart';

final class SavedPlanDetailViewModel extends ChangeNotifier {
  SavedPlanDetailViewModel(this._repository);

  final SavedPlanRepository _repository;

  SavedPlanDetail? _detail;
  bool _loading = false;
  bool _saving = false;
  String? _error;

  SavedPlanDetail? get detail => _detail;
  bool get loading => _loading;
  bool get saving => _saving;
  String? get error => _error;

  Future<void> load(String savedPlanId) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _detail = await _repository.loadDetail(savedPlanId);
      if (_detail == null) {
        _error = 'This saved plan is no longer available.';
      }
    } on Object {
      _error = 'Saved plan details could not be loaded.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> updateProgress({
    required String savedPlanTaskId,
    required int progressPercent,
    int? actualMinutes,
    bool clearActualMinutes = false,
  }) async {
    final id = _detail?.summary.plan.id;
    if (_saving || id == null) return false;
    _saving = true;
    _error = null;
    notifyListeners();
    try {
      await _repository.updateTaskProgress(
        savedPlanTaskId: savedPlanTaskId,
        progressPercent: progressPercent,
        actualMinutes: actualMinutes,
        clearActualMinutes: clearActualMinutes,
      );
      _detail = await _repository.loadDetail(id);
      return true;
    } on Object {
      _error = 'Task progress could not be saved.';
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}
