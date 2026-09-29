// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:tachocontrol/main.dart';

void main() {
  testWidgets('shows shift status and toggles it', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('TachoControl'), findsOneWidget);
    expect(find.text('Смена не начата'), findsOneWidget);

    await tester.tap(find.text('Начать смену'));
    await tester.pump();

    expect(find.text('Смена начата'), findsOneWidget);
    expect(find.text('Завершить смену'), findsOneWidget);
  });
}
