import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takt_mobile/data/database/app_database.dart';
import 'package:takt_mobile/data/repositories/drift_schedule_repository.dart';
import 'package:takt_mobile/main.dart';

void main() {
  testWidgets('renders the preserved primary navigation', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = DriftScheduleRepository(database);
    addTearDown(repository.close);

    await tester.pumpWidget(TaktApp(scheduleRepository: repository));
    await tester.pumpAndSettle();

    expect(find.text('Beranda'), findsOneWidget);
    expect(find.text('Jadwal'), findsOneWidget);
    expect(find.text('Analisis'), findsOneWidget);
    expect(find.text('Rencana'), findsOneWidget);
    expect(find.text('Ringkasan pekan ini'), findsOneWidget);
  });
}
