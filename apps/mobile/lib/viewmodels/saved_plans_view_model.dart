import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/saved_plan_repository.dart';

final class SavedPlansViewModel extends ChangeNotifier {
  SavedPlansViewModel(
    this._repository, {
    this.closeRepositoryOnDispose = true,
  });

  final SavedPlanRepository _repository;
  final bool closeRepositoryOnDispose;
  StreamSubscription<List<SavedPlanSummary>>? _subscription;

  List<SavedPlanSummary> _items = const [];
  bool _loading = true;
  String? _error;

  List<SavedPlanSummary> get items => List.unmodifiable(_items);
  bool get loading => _loading;
  String? get error => _error;

  Future<void> initialize() async {
    if (_subscription != null) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await _repository.initialize();
      _subscription = _repository.watchSummaries().listen(
        (items) {
          _items = List.unmodifiable(items);
          _loading = false;
          _error = null;
          notifyListeners();
        },
        onError: (Object error, StackTrace stack) {
          _loading = false;
          _error = 'Saved plans could not be loaded.';
          notifyListeners();
        },
      );
    } on Object {
      _loading = false;
      _error = 'Saved plans could not be opened.';
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    try {
      _items = await _repository.listSummaries();
      _loading = false;
      _error = null;
    } on Object {
      _error = 'Saved plans could not be refreshed.';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    if (closeRepositoryOnDispose) {
      unawaited(_repository.close());
    }
    super.dispose();
  }
}
