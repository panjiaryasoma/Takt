import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Thin Drift wrapper for Takt's local-first SQLite store.
///
/// v1 contains the Hari 1B schedule slice. v2 adds Hari 2B competition
/// analysis snapshots. v3 adds 4B evaluation, accepted-plan and progress
/// persistence while preserving all earlier tables.
class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor);

  factory AppDatabase.open() => AppDatabase(_openConnection());

  factory AppDatabase.forTesting(QueryExecutor executor) =>
      AppDatabase(executor);

  @override
  int get schemaVersion => 3;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  Iterable<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (_) async {
          for (final statement in [
            ..._schemaV1Statements,
            ..._schemaV2Statements,
            ..._schemaV3Statements,
          ]) {
            await customStatement(statement);
          }
        },
        onUpgrade: (_, from, to) async {
          if (to != 3 || from < 1 || from > 2) {
            throw StateError(
              'Unsupported Takt database migration $from -> $to.',
            );
          }
          if (from < 2) {
            for (final statement in _schemaV2Statements) {
              await customStatement(statement);
            }
          }
          if (from < 3) {
            for (final statement in _schemaV3Statements) {
              await customStatement(statement);
            }
          }
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


const _schemaV2Statements = <String>[
  '''
CREATE TABLE competitions (
    id TEXT PRIMARY KEY CHECK (length(trim(id)) > 0),
    created_at_epoch_ms INTEGER NOT NULL,
    updated_at_epoch_ms INTEGER NOT NULL
)
''',
  '''
CREATE TABLE analysis_snapshots (
    id TEXT PRIMARY KEY CHECK (length(trim(id)) > 0),
    competition_id TEXT NOT NULL,
    report_version INTEGER NOT NULL CHECK (report_version >= 1),
    assembly_material_fingerprint TEXT NOT NULL CHECK (
      length(assembly_material_fingerprint) = 64
    ),
    source_set_fingerprint TEXT CHECK (
      source_set_fingerprint IS NULL OR length(source_set_fingerprint) = 64
    ),
    wire_fingerprint TEXT NOT NULL CHECK (length(wire_fingerprint) = 64),
    report_changed INTEGER NOT NULL CHECK (report_changed IN (0, 1)),
    response_json TEXT NOT NULL CHECK (length(response_json) > 0),
    cached_at_epoch_ms INTEGER NOT NULL,
    FOREIGN KEY (competition_id) REFERENCES competitions(id)
      ON UPDATE CASCADE ON DELETE CASCADE
)
''',
  '''
CREATE INDEX idx_analysis_snapshot_competition_cached
ON analysis_snapshots(competition_id, cached_at_epoch_ms DESC, id DESC)
''',
];


const _schemaV3Statements = <String>[
  '''
CREATE TABLE evaluations (
    id TEXT PRIMARY KEY CHECK (length(trim(id)) > 0),
    competition_id TEXT NOT NULL,
    analysis_snapshot_id TEXT NOT NULL,
    evaluated_at_epoch_ms INTEGER NOT NULL,
    request_json TEXT NOT NULL CHECK (length(request_json) > 0),
    response_json TEXT NOT NULL CHECK (length(response_json) > 0),
    planning_window_policy_json TEXT NOT NULL CHECK (
      length(planning_window_policy_json) > 0
    ),
    evaluation_basis_fingerprint TEXT NOT NULL CHECK (
      length(evaluation_basis_fingerprint) = 64
    ),
    readiness_status TEXT NOT NULL CHECK (
      readiness_status IN (
        'READY_TO_EVALUATE',
        'NEEDS_REVIEW',
        'ELIGIBILITY_BLOCKED',
        'DEADLINE_PASSED',
        'INSUFFICIENT_INFORMATION'
      )
    ),
    feasibility_status TEXT CHECK (
      feasibility_status IS NULL OR feasibility_status IN (
        'FEASIBLE',
        'FEASIBLE_WITH_TRADEOFFS',
        'TIGHT_CAPACITY',
        'NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS'
      )
    ),
    created_at_epoch_ms INTEGER NOT NULL,
    FOREIGN KEY (competition_id) REFERENCES competitions(id)
      ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (analysis_snapshot_id) REFERENCES analysis_snapshots(id)
      ON UPDATE CASCADE ON DELETE RESTRICT
)
''',
  '''
CREATE INDEX idx_evaluations_competition_created
ON evaluations(competition_id, created_at_epoch_ms DESC, id DESC)
''',
  '''
CREATE TABLE reevaluation_transitions (
    id TEXT PRIMARY KEY CHECK (length(trim(id)) > 0),
    prior_evaluation_id TEXT NOT NULL,
    current_evaluation_id TEXT,
    kind TEXT NOT NULL CHECK (kind IN ('UNCHANGED','SUPERSEDED')),
    transport_request_json TEXT NOT NULL CHECK (
      length(transport_request_json) > 0
    ),
    transport_response_json TEXT NOT NULL CHECK (
      length(transport_response_json) > 0
    ),
    transition_json TEXT NOT NULL CHECK (length(transition_json) > 0),
    error_json TEXT,
    created_at_epoch_ms INTEGER NOT NULL,
    FOREIGN KEY (prior_evaluation_id) REFERENCES evaluations(id)
      ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (current_evaluation_id) REFERENCES evaluations(id)
      ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (
      (
        kind = 'UNCHANGED'
        AND current_evaluation_id IS NULL
        AND error_json IS NULL
      )
      OR
      (
        kind = 'SUPERSEDED'
        AND (
          (
            current_evaluation_id IS NOT NULL
            AND error_json IS NULL
          )
          OR
          (
            current_evaluation_id IS NULL
            AND error_json IS NOT NULL
          )
        )
      )
    )
)
''',
  '''
CREATE UNIQUE INDEX idx_reevaluation_current_evaluation
ON reevaluation_transitions(current_evaluation_id)
WHERE current_evaluation_id IS NOT NULL
''',
  '''
CREATE INDEX idx_reevaluation_prior_created
ON reevaluation_transitions(prior_evaluation_id, created_at_epoch_ms DESC, id DESC)
''',
  '''
CREATE TABLE saved_plans (
    id TEXT PRIMARY KEY CHECK (length(trim(id)) > 0),
    competition_id TEXT NOT NULL UNIQUE,
    created_at_epoch_ms INTEGER NOT NULL,
    updated_at_epoch_ms INTEGER NOT NULL,
    FOREIGN KEY (competition_id) REFERENCES competitions(id)
      ON UPDATE CASCADE ON DELETE RESTRICT
)
''',
  '''
CREATE TABLE saved_plan_revisions (
    id TEXT PRIMARY KEY CHECK (length(trim(id)) > 0),
    saved_plan_id TEXT NOT NULL,
    revision_number INTEGER NOT NULL CHECK (revision_number >= 1),
    evaluation_id TEXT NOT NULL UNIQUE,
    selected_candidate_id TEXT NOT NULL CHECK (
      length(trim(selected_candidate_id)) > 0
    ),
    selection_source TEXT NOT NULL CHECK (
      selection_source IN ('PRIMARY','ALTERNATIVE')
    ),
    supersedes_revision_id TEXT,
    accepted_at_epoch_ms INTEGER NOT NULL,
    FOREIGN KEY (saved_plan_id) REFERENCES saved_plans(id)
      ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (evaluation_id) REFERENCES evaluations(id)
      ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (supersedes_revision_id) REFERENCES saved_plan_revisions(id)
      ON UPDATE CASCADE ON DELETE RESTRICT,
    UNIQUE (saved_plan_id, revision_number)
)
''',
  '''
CREATE UNIQUE INDEX idx_saved_plan_revision_single_successor
ON saved_plan_revisions(supersedes_revision_id)
WHERE supersedes_revision_id IS NOT NULL
''',
  '''
CREATE UNIQUE INDEX idx_saved_plan_revision_single_root
ON saved_plan_revisions(saved_plan_id)
WHERE supersedes_revision_id IS NULL
''',
  '''
CREATE TRIGGER trg_saved_plan_revision_guard
BEFORE INSERT ON saved_plan_revisions
BEGIN
  SELECT CASE
    WHEN NEW.supersedes_revision_id IS NULL AND NEW.revision_number <> 1
    THEN RAISE(ABORT, 'root revision must be revision 1')
  END;
  SELECT CASE
    WHEN NEW.supersedes_revision_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM saved_plan_revisions parent
        WHERE parent.id = NEW.supersedes_revision_id
          AND parent.saved_plan_id = NEW.saved_plan_id
          AND NEW.revision_number = parent.revision_number + 1
      )
    THEN RAISE(ABORT, 'revision parent must be same-plan and sequential')
  END;
  SELECT CASE
    WHEN NEW.supersedes_revision_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM saved_plan_revisions child
        WHERE child.supersedes_revision_id = NEW.supersedes_revision_id
      )
    THEN RAISE(ABORT, 'revision parent is no longer the current leaf')
  END;
  SELECT CASE
    WHEN (
      SELECT e.competition_id
      FROM evaluations e
      WHERE e.id = NEW.evaluation_id
    ) <> (
      SELECT p.competition_id
      FROM saved_plans p
      WHERE p.id = NEW.saved_plan_id
    )
    THEN RAISE(ABORT, 'evaluation competition does not match saved plan')
  END;
END
''',
  '''
CREATE TABLE saved_plan_tasks (
    id TEXT PRIMARY KEY CHECK (length(trim(id)) > 0),
    saved_plan_revision_id TEXT NOT NULL,
    domain_task_id TEXT NOT NULL CHECK (length(trim(domain_task_id)) > 0),
    ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
    name TEXT NOT NULL CHECK (length(trim(name)) > 0),
    mandatory INTEGER NOT NULL CHECK (mandatory IN (0, 1)),
    effort_min_minutes INTEGER NOT NULL CHECK (effort_min_minutes >= 0),
    effort_likely_minutes INTEGER NOT NULL CHECK (
      effort_likely_minutes >= effort_min_minutes
    ),
    effort_max_minutes INTEGER NOT NULL CHECK (
      effort_max_minutes >= effort_likely_minutes
    ),
    dependencies_json TEXT NOT NULL CHECK (length(dependencies_json) > 0),
    assumptions_json TEXT NOT NULL CHECK (length(assumptions_json) > 0),
    task_payload_json TEXT NOT NULL CHECK (length(task_payload_json) > 0),
    FOREIGN KEY (saved_plan_revision_id) REFERENCES saved_plan_revisions(id)
      ON UPDATE CASCADE ON DELETE CASCADE,
    UNIQUE (saved_plan_revision_id, domain_task_id),
    UNIQUE (saved_plan_revision_id, ordinal)
)
''',
  '''
CREATE TABLE accepted_commitments (
    id TEXT PRIMARY KEY CHECK (length(trim(id)) > 0),
    saved_plan_revision_id TEXT NOT NULL,
    saved_plan_task_id TEXT NOT NULL,
    source_block_ordinal INTEGER NOT NULL CHECK (source_block_ordinal >= 0),
    start_at_epoch_ms INTEGER NOT NULL CHECK (start_at_epoch_ms % 60000 = 0),
    end_at_epoch_ms INTEGER NOT NULL CHECK (
      end_at_epoch_ms % 60000 = 0 AND end_at_epoch_ms > start_at_epoch_ms
    ),
    allocated_minutes INTEGER NOT NULL CHECK (allocated_minutes > 0),
    original_availability_source TEXT NOT NULL CHECK (
      length(trim(original_availability_source)) > 0
    ),
    source_block_json TEXT NOT NULL CHECK (length(source_block_json) > 0),
    accepted_at_epoch_ms INTEGER NOT NULL,
    FOREIGN KEY (saved_plan_revision_id) REFERENCES saved_plan_revisions(id)
      ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (saved_plan_task_id) REFERENCES saved_plan_tasks(id)
      ON UPDATE CASCADE ON DELETE CASCADE,
    UNIQUE (saved_plan_revision_id, source_block_ordinal),
    CHECK (
      end_at_epoch_ms - start_at_epoch_ms = allocated_minutes * 60000
    )
)
''',
  '''
CREATE TRIGGER trg_accepted_commitment_task_revision
BEFORE INSERT ON accepted_commitments
BEGIN
  SELECT CASE
    WHEN NOT EXISTS (
      SELECT 1 FROM saved_plan_tasks task
      WHERE task.id = NEW.saved_plan_task_id
        AND task.saved_plan_revision_id = NEW.saved_plan_revision_id
    )
    THEN RAISE(ABORT, 'accepted block task must belong to the same revision')
  END;
END
''',
  '''
CREATE TABLE task_progress (
    saved_plan_task_id TEXT PRIMARY KEY,
    progress_percent INTEGER NOT NULL CHECK (
      progress_percent BETWEEN 0 AND 100
    ),
    actual_minutes INTEGER CHECK (
      actual_minutes IS NULL OR actual_minutes >= 0
    ),
    updated_at_epoch_ms INTEGER NOT NULL,
    FOREIGN KEY (saved_plan_task_id) REFERENCES saved_plan_tasks(id)
      ON UPDATE CASCADE ON DELETE CASCADE
)
''',
  '''
CREATE INDEX idx_saved_plan_tasks_revision
ON saved_plan_tasks(saved_plan_revision_id, ordinal)
''',
  '''
CREATE INDEX idx_accepted_commitments_revision_start
ON accepted_commitments(saved_plan_revision_id, start_at_epoch_ms)
''',
];
