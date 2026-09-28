import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Thin Drift wrapper for Takt's local-first SQLite store.
///
/// Issue 1B deliberately creates only the schedule slice of the final physical
/// schema. Later issues can migrate this same database from v1 -> v2 -> v3.
class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor);

  factory AppDatabase.open() => AppDatabase(_openConnection());

  factory AppDatabase.forTesting(QueryExecutor executor) =>
      AppDatabase(executor);

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  Iterable<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (_) async {
          for (final statement in _schemaV1Statements) {
            await customStatement(statement);
          }
        },
        onUpgrade: (_, from, to) {
          throw StateError(
            'Unsupported Takt database migration $from -> $to. ',
          );
        },
        beforeOpen: (_) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('PRAGMA journal_mode = WAL');
        },
      );

  Future<void> initialize() async {
    // Trigger Drift's open lifecycle and migration before repositories query.
    await customSelect('SELECT 1').getSingle();
  }

  Future<int> userVersion() async {
    final row = await customSelect('PRAGMA user_version').getSingle();
    return row.data['user_version'] as int? ?? 0;
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'takt.sqlite3'));
    return NativeDatabase.createInBackground(file);
  });
}

const _schemaV1Statements = <String>[
  '''
CREATE TABLE commitments (
    id TEXT PRIMARY KEY CHECK (length(trim(id)) > 0),
    title TEXT NOT NULL CHECK (length(trim(title)) > 0),
    category TEXT,
    type TEXT NOT NULL CHECK (type IN ('FIXED','FLEXIBLE')),
    start_at_epoch_ms INTEGER NOT NULL CHECK (start_at_epoch_ms % 60000 = 0),
    end_at_epoch_ms INTEGER NOT NULL CHECK (
      end_at_epoch_ms % 60000 = 0 AND end_at_epoch_ms > start_at_epoch_ms
    ),
    timezone TEXT NOT NULL CHECK (length(trim(timezone)) > 0),
    source TEXT NOT NULL CHECK (length(trim(source)) > 0),
    created_at_epoch_ms INTEGER NOT NULL,
    updated_at_epoch_ms INTEGER NOT NULL
)
''',
  '''
CREATE TABLE recurrence_rules (
    id TEXT PRIMARY KEY CHECK (length(trim(id)) > 0),
    commitment_id TEXT NOT NULL UNIQUE,
    rrule TEXT NOT NULL CHECK (length(trim(rrule)) > 0),
    timezone TEXT NOT NULL CHECK (length(trim(timezone)) > 0),
    active_from_epoch_ms INTEGER NOT NULL CHECK (active_from_epoch_ms % 60000 = 0),
    active_until_epoch_ms INTEGER CHECK (
      active_until_epoch_ms IS NULL OR (
        active_until_epoch_ms % 60000 = 0
        AND active_until_epoch_ms > active_from_epoch_ms
      )
    ),
    FOREIGN KEY (commitment_id) REFERENCES commitments(id)
      ON UPDATE CASCADE ON DELETE CASCADE
)
''',
  '''
CREATE TABLE recurrence_exceptions (
    id TEXT PRIMARY KEY CHECK (length(trim(id)) > 0),
    recurrence_rule_id TEXT NOT NULL,
    original_start_at_epoch_ms INTEGER NOT NULL CHECK (
      original_start_at_epoch_ms % 60000 = 0
    ),
    action TEXT NOT NULL CHECK (action IN ('CANCELLED','MOVED')),
    replacement_start_at_epoch_ms INTEGER,
    replacement_end_at_epoch_ms INTEGER,
    FOREIGN KEY (recurrence_rule_id) REFERENCES recurrence_rules(id)
      ON UPDATE CASCADE ON DELETE CASCADE,
    UNIQUE (recurrence_rule_id, original_start_at_epoch_ms),
    CHECK (
      (
        action = 'CANCELLED'
        AND replacement_start_at_epoch_ms IS NULL
        AND replacement_end_at_epoch_ms IS NULL
      )
      OR
      (
        action = 'MOVED'
        AND replacement_start_at_epoch_ms IS NOT NULL
        AND replacement_end_at_epoch_ms IS NOT NULL
        AND replacement_start_at_epoch_ms % 60000 = 0
        AND replacement_end_at_epoch_ms % 60000 = 0
        AND replacement_end_at_epoch_ms > replacement_start_at_epoch_ms
      )
    )
)
''',
  '''
CREATE TABLE planning_preferences (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    timezone TEXT NOT NULL CHECK (length(trim(timezone)) > 0),
    max_project_minutes_per_day INTEGER NOT NULL CHECK (
      max_project_minutes_per_day BETWEEN 0 AND 1440
    ),
    preferred_focus_minutes INTEGER NOT NULL CHECK (preferred_focus_minutes > 0),
    buffer_target_minutes INTEGER NOT NULL CHECK (buffer_target_minutes >= 0),
    updated_at_epoch_ms INTEGER NOT NULL
)
''',
  'CREATE INDEX idx_commitments_start ON commitments(start_at_epoch_ms)',
  'CREATE INDEX idx_recurrence_rule_commitment ON recurrence_rules(commitment_id)',
  '''
CREATE INDEX idx_recurrence_exception_rule_start
ON recurrence_exceptions(recurrence_rule_id, original_start_at_epoch_ms)
''',
];
