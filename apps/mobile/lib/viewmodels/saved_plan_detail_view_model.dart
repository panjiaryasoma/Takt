import 'package:flutter/foundation.dart';

import '../data/repositories/saved_plan_repository.dart';

final class SavedPlanDetailViewModel extends ChangeNotifier {
  SavedPlanDetailViewModel(this._repository);

  final SavedPlanRepository _repository;

  SavedPlanDetail? _detail;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  String? _errorCode;
  bool _preparing = false;
  bool _preparationFailed = false;

  SavedPlanDetail? get detail => _detail;
  bool get loading => _loading;
  bool get saving => _saving;
  String? get error => _error;
  String? get errorCode => _errorCode;
  bool get preparing => _preparing;
  bool get preparationFailed => _preparationFailed;

  Future<void> load(String savedPlanId) async {
    _loading = true;
    _error = null;
    _errorCode = null;
    _preparationFailed = false;
    notifyListeners();
    try {
      _detail = await _repository.loadDetail(savedPlanId);
      if (_detail == null) {
        _error = 'This saved plan is no longer available.';
        _errorCode = 'LOCAL_CONTEXT_MISSING';
      }
    } on Object {
      _error = 'Saved plan details could not be loaded.';
      _errorCode = 'LOCAL_CONTEXT_READ_FAILED';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Preparing a re-evaluation only loads local context; it never evaluates.
  Future<void> prepareReevaluation(Future<void> Function() prepare) async {
    if (_preparing || _saving || _loading) return;
    _preparing = true;
    _preparationFailed = false;
    _error = null;
    _errorCode = null;
    notifyListeners();
    try {
      await prepare();
    } on Object {
      _preparationFailed = true;
      _errorCode = 'LOCAL_CONTEXT_READ_FAILED';
      _error = 'The saved analysis and planning context could not be loaded on this device. Retry loading the context to continue.';
    } finally {
      _preparing = false;
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
    if (_saving || _preparing || _loading || id == null) return false;
    _saving = true;
    _error = null;
    _errorCode = null;
    _preparationFailed = false;
    notifyListeners();
    try {
      await _repository.updateTaskProgress(
        savedPlanTaskId: savedPlanTaskId,
        progressPercent: progressPercent,
        actualMinutes: actualMinutes,
        clearActualMinutes: clearActualMinutes,
      );
    } on Object {
      _error = 'Task progress could not be saved.';
      _errorCode = 'LOCAL_PERSISTENCE_FAILED';
      _saving = false;
      notifyListeners();
      return false;
    }
    // The write committed. A failed projection read cannot undo that truth.
    try {
      await _repository.refresh();
      final refreshed = await _repository.loadDetail(id);
      if (refreshed == null) throw StateError('Saved plan projection missing.');
      _detail = refreshed;
    } on Object {
      _errorCode = 'LOCAL_REFRESH_FAILED';
      _error = 'Task progress is saved, but the displayed plan could not be refreshed. Retry refresh to show the saved progress.';
    } finally {
      _saving = false;
      notifyListeners();
    }
    return true;
  }
}
