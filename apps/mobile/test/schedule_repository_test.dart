import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takt_mobile/data/database/app_database.dart';
import 'package:takt_mobile/data/repositories/drift_schedule_repository.dart';
import 'package:takt_mobile/data/repositories/schedule_repository.dart';
import 'package:takt_mobile/models/commitment.dart';
import 'package:takt_mobile/models/enums.dart';
import 'package:takt_mobile/models/planning_preferences.dart';
import 'package:takt_mobile/models/recurrence_exception.dart';
import 'package:takt_mobile/models/recurrence_rule.dart';
import 'package:takt_mobile/viewmodels/jadwal_view_model.dart';

void main() {
  test('fresh database initializes schedule plus analysis schema v2', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.initialize();

    expect(await db.userVersion(), 2);
    final tables = await db.customSelect(
      '''
SELECT name FROM sqlite_master
WHERE type = 'table' AND name IN (
  'commitments',
  'recurrence_rules',
  'recurrence_exceptions',
  'planning_preferences',
  'competitions',
  'analysis_snapshots'
)
ORDER BY name
''',
    ).get();
    expect(
      tables.map((row) => row.data['name']).toSet(),
      {
        'commitments',
        'recurrence_rules',
        'recurrence_exceptions',
        'planning_preferences',
        'competitions',
        'analysis_snapshots',
      },
    );
    await expectLater(
      db.customStatement(
        '''
INSERT INTO commitments (
  id, title, category, type, start_at_epoch_ms, end_at_epoch_ms,
  timezone, source, created_at_epoch_ms, updated_at_epoch_ms
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
        ['bad', 'Invalid type', null, 'UNKNOWN', 60000, 120000,
         'Asia/Jakarta', 'test', 1, 1],
      ),
      throwsA(anything),
    );
  });


  test('v1 to v2 migration preserves existing commitments', () async {
    final dir = await Directory.systemTemp.createTemp('takt_v1_migration_');
    final file = File('${dir.path}/takt.sqlite3');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    final seed = AppDatabase.forTesting(NativeDatabase(file));
    await seed.initialize();
    await seed.customStatement('DROP TABLE analysis_snapshots');
    await seed.customStatement('DROP TABLE competitions');
    await seed.customStatement('PRAGMA user_version = 1');
    await seed.customStatement(
      '''
INSERT INTO commitments (
  id, title, category, type, start_at_epoch_ms, end_at_epoch_ms,
  timezone, source, created_at_epoch_ms, updated_at_epoch_ms
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
      [
        'cmt-v1',
        'Existing v1 commitment',
        null,
        'FIXED',
        60000,
        120000,
        'Asia/Jakarta',
        'migration-test',
        1,
        1,
      ],
    );
    await seed.close();

    final migrated = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(migrated.close);
    await migrated.initialize();

    expect(await migrated.userVersion(), 2);
    final commitments = await migrated.customSelect(
      'SELECT id FROM commitments WHERE id = ?',
      variables: [Variable<String>('cmt-v1')],
    ).get();
    expect(commitments, hasLength(1));

    final analysisTables = await migrated.customSelect(
      '''
SELECT name FROM sqlite_master
WHERE type = 'table' AND name IN ('competitions', 'analysis_snapshots')
ORDER BY name
''',
    ).get();
    expect(
      analysisTables.map((row) => row.data['name']),
      ['analysis_snapshots', 'competitions'],
    );
  });

  test('commitment survives closing and reopening the sqlite file', () async {
    final dir = await Directory.systemTemp.createTemp('takt_schedule_test_');
    final file = File('${dir.path}/takt.sqlite3');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    final firstDb = AppDatabase.forTesting(NativeDatabase(file));
    final firstRepository = DriftScheduleRepository(firstDb);
    await firstRepository.initialize();

    final start = DateTime(2026, 9, 29, 9);
    final end = DateTime(2026, 9, 29, 10);
    final now = DateTime(2026, 9, 29, 8).millisecondsSinceEpoch;
    await firstRepository.createCommitment(
      Commitment(
        id: 'cmt-persist',
        title: 'Kelas',
        category: 'Kuliah',
        type: CommitmentType.fixed,
        startAtEpochMs: start.millisecondsSinceEpoch,
        endAtEpochMs: end.millisecondsSinceEpoch,
        timezone: 'Asia/Jakarta',
        source: 'test',
        createdAtEpochMs: now,
        updatedAtEpochMs: now,
      ),
    );
    await firstRepository.close();

    final secondDb = AppDatabase.forTesting(NativeDatabase(file));
    final secondRepository = DriftScheduleRepository(secondDb);
    addTearDown(secondRepository.close);
    await secondRepository.initialize();

    final state = await secondRepository.loadState();
    expect(state.commitments, hasLength(1));
    expect(state.commitments.single.id, 'cmt-persist');
    expect(state.commitments.single.title, 'Kelas');
  });

  test('weekly recurrence is derived and one occurrence can be cancelled', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = DriftScheduleRepository(db);
    final vm = JadwalViewModel(repository);
    addTearDown(repository.close);

    await vm.initialize();
    await Future<void>.delayed(Duration.zero);

    final created = await vm.tambahRutin(
      title: 'Kelas rutin',
      category: 'Kuliah',
      weekdays: {DateTime.monday, DateTime.wednesday},
      jamMulai: 9,
      menitMulai: 0,
      jamSelesai: 10,
      menitSelesai: 30,
      mulaiDari: DateTime(2026, 9, 28),
    );
    expect(created, isTrue);
    await Future<void>.delayed(Duration.zero);

    final monday = vm.itemsOn(DateTime(2026, 9, 28));
    final wednesday = vm.itemsOn(DateTime(2026, 9, 30));
    expect(monday, hasLength(1));
    expect(wednesday, hasLength(1));
    expect(wednesday.single.durationMinutes, 90);
    expect(vm.all, hasLength(1), reason: 'recurrence must not clone commitments');

    final cancelled = await vm.cancelOccurrence(wednesday.single);
    expect(cancelled, isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(vm.itemsOn(DateTime(2026, 9, 30)), isEmpty);
    expect(vm.itemsOn(DateTime(2026, 10, 5)), hasLength(1));
  });

  test('commitment can be updated and deleted through the repository', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = DriftScheduleRepository(db);
    addTearDown(repository.close);
    await repository.initialize();

    final createdAt = DateTime(2026, 9, 29, 8).millisecondsSinceEpoch;
    final original = Commitment(
      id: 'cmt-crud',
      title: 'Kelas',
      category: 'Kuliah',
      type: CommitmentType.fixed,
      startAtEpochMs: DateTime(2026, 9, 29, 9).millisecondsSinceEpoch,
      endAtEpochMs: DateTime(2026, 9, 29, 10).millisecondsSinceEpoch,
      timezone: 'Asia/Jakarta',
      source: 'test',
      createdAtEpochMs: createdAt,
      updatedAtEpochMs: createdAt,
    );
    await repository.createCommitment(original);

    final updated = Commitment(
      id: original.id,
      title: 'Kelas pindah',
      category: 'Kuliah',
      type: CommitmentType.flexible,
      startAtEpochMs: DateTime(2026, 9, 29, 11).millisecondsSinceEpoch,
      endAtEpochMs: DateTime(2026, 9, 29, 12).millisecondsSinceEpoch,
      timezone: 'Asia/Jakarta',
      source: original.source,
      createdAtEpochMs: original.createdAtEpochMs,
      updatedAtEpochMs: createdAt + 60000,
    );
    await repository.updateCommitment(updated);

    var state = await repository.loadState();
    expect(state.commitments, hasLength(1));
    expect(state.commitments.single.title, 'Kelas pindah');
    expect(state.commitments.single.type, CommitmentType.flexible);

    await repository.deleteCommitment(original.id);
    state = await repository.loadState();
    expect(state.commitments, isEmpty);
  });

  test('moved recurrence replaces only the targeted occurrence', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = DriftScheduleRepository(db);
    final vm = JadwalViewModel(repository);
    addTearDown(repository.close);

    await vm.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(
      await vm.tambahRutin(
        title: 'Rapat rutin',
        weekdays: {DateTime.monday},
        jamMulai: 9,
        menitMulai: 0,
        jamSelesai: 10,
        menitSelesai: 0,
        mulaiDari: DateTime(2026, 9, 28),
      ),
      isTrue,
    );
    await Future<void>.delayed(Duration.zero);

    final original = vm.itemsOn(DateTime(2026, 9, 28)).single;
    expect(
      await vm.moveOccurrence(
        original,
        DateTime(2026, 9, 29, 14),
        DateTime(2026, 9, 29, 15),
      ),
      isTrue,
    );
    await Future<void>.delayed(Duration.zero);

    expect(vm.itemsOn(DateTime(2026, 9, 28)), isEmpty);
    final replacement = vm.itemsOn(DateTime(2026, 9, 29));
    expect(replacement, hasLength(1));
    expect(replacement.single.startAt.hour, 14);
    expect(vm.itemsOn(DateTime(2026, 10, 5)), hasLength(1));
  });

  test('retry after initial DB failure reloads state and attaches updates', () async {
    final repository = _FailOnceScheduleRepository();
    final vm = JadwalViewModel(repository);

    await vm.initialize();
    expect(vm.errorMessage, 'Gagal membuka database jadwal.');
    expect(vm.all, isEmpty);

    await vm.retry();
    await Future<void>.delayed(Duration.zero);

    expect(vm.errorMessage, isNull);
    expect(vm.all.map((item) => item.id), contains('cmt-recovered'));

    repository.emitSecondState();
    await Future<void>.delayed(Duration.zero);

    expect(vm.all, hasLength(2));
    expect(vm.all.map((item) => item.id), contains('cmt-after-retry'));

    vm.dispose();
  });

}


class _FailOnceScheduleRepository implements ScheduleRepository {
  _FailOnceScheduleRepository() {
    _state = _buildState(['cmt-recovered']);
  }

  final StreamController<ScheduleState> _changes =
      StreamController<ScheduleState>.broadcast();
  late ScheduleState _state;
  bool _failFirstInitialize = true;

  @override
  Future<void> initialize() async {
    if (_failFirstInitialize) {
      _failFirstInitialize = false;
      throw StateError('simulated open failure');
    }
  }

  @override
  Stream<ScheduleState> watchState() async* {
    yield _state;
    yield* _changes.stream;
  }

  @override
  Future<ScheduleState> loadState() async => _state;

  @override
  Future<void> refresh() async {
    _changes.add(_state);
  }

  void emitSecondState() {
    _state = _buildState(['cmt-recovered', 'cmt-after-retry']);
    _changes.add(_state);
  }

  @override
  Future<void> createCommitment(
    Commitment commitment, {
    RecurrenceRule? recurrenceRule,
  }) async {}

  @override
  Future<void> updateCommitment(
    Commitment commitment, {
    RecurrenceRule? recurrenceRule,
  }) async {}

  @override
  Future<void> deleteCommitment(String commitmentId) async {}

  @override
  Future<void> upsertRecurrenceException(
    RecurrenceException exception,
  ) async {}

  @override
  Future<void> savePlanningPreferences(
    PlanningPreferences preferences,
  ) async {}

  @override
  Future<void> close() => _changes.close();

  static ScheduleState _buildState(List<String> ids) {
    final now = DateTime(2026, 9, 29, 9).millisecondsSinceEpoch;
    return ScheduleState(
      commitments: [
        for (var index = 0; index < ids.length; index++)
          Commitment(
            id: ids[index],
            title: 'Recovered schedule $index',
            type: CommitmentType.fixed,
            startAtEpochMs: now + index * 3600000,
            endAtEpochMs: now + (index + 1) * 3600000,
            timezone: 'Asia/Jakarta',
            source: 'test',
            createdAtEpochMs: now,
            updatedAtEpochMs: now,
          ),
      ],
      recurrenceRules: const [],
      recurrenceExceptions: const [],
      preferences: PlanningPreferences.defaults(),
    );
  }
}
