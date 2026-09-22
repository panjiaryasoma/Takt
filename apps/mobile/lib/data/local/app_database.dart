import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class RecurrenceRules extends Table {
  TextColumn get id => text()();
  TextColumn get rrule => text()();
  DateTimeColumn get startsAt => dateTime()();
  DateTimeColumn get endsAt => dateTime().nullable()();
  TextColumn get timezone => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Commitments extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get type => text()();
  DateTimeColumn get startAt => dateTime()();
  DateTimeColumn get endAt => dateTime()();
  TextColumn get timezone => text()();
  TextColumn get recurrenceRuleId =>
      text().nullable().references(RecurrenceRules, #id)();
  TextColumn get source => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class RecurrenceExceptions extends Table {
  TextColumn get id => text()();
  TextColumn get recurrenceRuleId => text().references(RecurrenceRules, #id)();
  DateTimeColumn get originalStartAt => dateTime()();
  TextColumn get action => text()();
  DateTimeColumn get replacementStartAt => dateTime().nullable()();
  DateTimeColumn get replacementEndAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PlanningPreferences extends Table {
  IntColumn get id => integer()();
  TextColumn get timezone => text()();
  IntColumn get maxProjectMinutesPerDay => integer()();
  IntColumn get preferredFocusMinutes => integer()();
  IntColumn get bufferTargetMinutes => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Competitions extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get organizer => text().nullable()();
  TextColumn get sourceUrl => text().nullable()();
  TextColumn get sourceType => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CompetitionBriefs extends Table {
  TextColumn get id => text()();
  TextColumn get competitionId => text().references(Competitions, #id)();
  IntColumn get version => integer()();
  DateTimeColumn get submissionDeadline => dateTime().nullable()();
  TextColumn get deadlineTimezone => text().nullable()();
  TextColumn get readinessStatus => text()();
  DateTimeColumn get generatedAt => dateTime()();
  DateTimeColumn get confirmedAt => dateTime().nullable()();
  IntColumn get unresolvedCriticalCount =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {competitionId, version},
      ];
}

class CanonicalFields extends Table {
  TextColumn get id => text()();
  TextColumn get briefId => text().references(CompetitionBriefs, #id)();
  TextColumn get fieldName => text()();
  TextColumn get rawValue => text().nullable()();
  TextColumn get normalizedValueJson => text().nullable()();
  TextColumn get state => text()();
  BoolColumn get isCritical => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Evidence extends Table {
  TextColumn get id => text()();
  TextColumn get canonicalFieldId => text().references(CanonicalFields, #id)();
  TextColumn get sourceType => text()();
  TextColumn get sourceLocator => text()();
  IntColumn get pageNumber => integer().nullable()();
  TextColumn get rawExcerpt => text().nullable()();
  TextColumn get extractionPath => text()();
  RealColumn get confidence => real().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get competitionId => text().references(Competitions, #id)();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get taskType => text()();
  BoolColumn get mandatory => boolean()();
  IntColumn get effortMinMinutes => integer()();
  IntColumn get effortLikelyMinutes => integer()();
  IntColumn get effortMaxMinutes => integer()();
  TextColumn get status => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class TaskDependencies extends Table {
  TextColumn get taskId => text().references(Tasks, #id)();
  TextColumn get dependsOnTaskId => text().references(Tasks, #id)();

  @override
  Set<Column<Object>> get primaryKey => {taskId, dependsOnTaskId};
}

class CandidateAllocations extends Table {
  TextColumn get id => text()();
  TextColumn get competitionId => text().references(Competitions, #id)();
  TextColumn get briefId => text().references(CompetitionBriefs, #id)();
  TextColumn get feasibilityStatus => text()();
  IntColumn get bufferMinutes => integer()();
  RealColumn get score => real()();
  DateTimeColumn get generatedAt => dateTime()();
  BoolColumn get isStale => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AllocationBlocks extends Table {
  TextColumn get id => text()();
  TextColumn get candidateId => text().references(CandidateAllocations, #id)();
  TextColumn get taskId => text().references(Tasks, #id)();
  DateTimeColumn get startAt => dateTime()();
  DateTimeColumn get endAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Recommendations extends Table {
  TextColumn get id => text()();
  TextColumn get competitionId => text().references(Competitions, #id)();
  TextColumn get candidateId => text().references(CandidateAllocations, #id)();
  TextColumn get recommendedTaskId =>
      text().nullable().references(Tasks, #id)();
  TextColumn get status => text()();
  TextColumn get rationale => text()();
  TextColumn get tradeoffsJson => text()();
  TextColumn get assumptionsJson => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class RecommendationAlternatives extends Table {
  TextColumn get recommendationId =>
      text().references(Recommendations, #id)();
  TextColumn get candidateId =>
      text().references(CandidateAllocations, #id)();
  IntColumn get rank => integer()();

  @override
  Set<Column<Object>> get primaryKey => {recommendationId, candidateId};
}

class AcceptedCommitments extends Table {
  TextColumn get id => text()();
  TextColumn get competitionId => text().references(Competitions, #id)();
  TextColumn get taskId => text().references(Tasks, #id)();
  TextColumn get recommendationId =>
      text().nullable().references(Recommendations, #id)();
  DateTimeColumn get startAt => dateTime()();
  DateTimeColumn get endAt => dateTime()();
  DateTimeColumn get acceptedAt => dateTime()();
  TextColumn get source => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class TaskProgress extends Table {
  TextColumn get id => text()();
  TextColumn get taskId => text().references(Tasks, #id)();
  IntColumn get progressPercent => integer()();
  IntColumn get actualMinutes => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {taskId},
      ];
}

@DriftDatabase(
  tables: [
    Commitments,
    RecurrenceRules,
    RecurrenceExceptions,
    PlanningPreferences,
    Competitions,
    CompetitionBriefs,
    CanonicalFields,
    Evidence,
    Tasks,
    TaskDependencies,
    CandidateAllocations,
    AllocationBlocks,
    Recommendations,
    RecommendationAlternatives,
    AcceptedCommitments,
    TaskProgress,
  ],
)
final class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'takt'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
