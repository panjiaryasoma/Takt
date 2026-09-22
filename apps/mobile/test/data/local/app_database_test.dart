import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takt_mobile/data/local/app_database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('MVP schema exposes exactly the 16 persisted domain tables', () {
    final tableNames = database.allTables
        .map((table) => table.actualTableName)
        .toSet();

    expect(
      tableNames,
      {
        'commitments',
        'recurrence_rules',
        'recurrence_exceptions',
        'planning_preferences',
        'competitions',
        'competition_briefs',
        'canonical_fields',
        'evidence',
        'tasks',
        'task_dependencies',
        'candidate_allocations',
        'allocation_blocks',
        'recommendations',
        'recommendation_alternatives',
        'accepted_commitments',
        'task_progress',
      },
    );
    expect(tableNames, isNot(contains('available_blocks')));
  });

  test('actual effort stays nullable instead of silently becoming zero', () async {
    final columns =
        await database.customSelect('PRAGMA table_info(task_progress)').get();
    final actualMinutes = columns.singleWhere(
      (row) => row.read<String>('name') == 'actual_minutes',
    );

    expect(actualMinutes.read<int>('notnull'), 0);
  });

  test('brief history is versioned and cannot overwrite a version slot', () async {
    await database.customStatement(
      '''
      INSERT INTO competitions (
        id, name, source_type, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?)
      ''',
      ['cmp-1', 'Competition', 'OFFICIAL', 0, 0],
    );

    await database.customStatement(
      '''
      INSERT INTO competition_briefs (
        id, competition_id, version, readiness_status, generated_at,
        unresolved_critical_count
      ) VALUES (?, ?, ?, ?, ?, ?)
      ''',
      ['brief-1', 'cmp-1', 1, 'READY_TO_EVALUATE', 0, 0],
    );

    await expectLater(
      database.customStatement(
        '''
        INSERT INTO competition_briefs (
          id, competition_id, version, readiness_status, generated_at,
          unresolved_critical_count
        ) VALUES (?, ?, ?, ?, ?, ?)
        ''',
        ['brief-2', 'cmp-1', 1, 'READY_TO_EVALUATE', 0, 0],
      ),
      throwsA(anything),
    );
  });
}
