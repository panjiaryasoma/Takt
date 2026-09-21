import 'package:flutter_test/flutter_test.dart';
import 'package:takt_mobile/main.dart';

void main() {
  testWidgets('renders primary navigation cards', (tester) async {
    await tester.pumpWidget(const TaktApp());

    expect(find.text('My Schedule'), findsOneWidget);
    expect(find.text('Analyze Competition'), findsOneWidget);
    expect(find.text('Saved Plans'), findsOneWidget);
  });
}
