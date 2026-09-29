import 'package:flutter_test/flutter_test.dart';
import 'package:tachocontrol/main.dart';

void main() {
  testWidgets('app launches with main controls', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('TachoControl'), findsOneWidget);
    expect(find.text('START'), findsOneWidget);
    expect(find.text('END'), findsOneWidget);
    expect(find.text('SEND'), findsOneWidget);
    expect(find.text('DAYS'), findsOneWidget);
    expect(find.text('KM'), findsOneWidget);
  });
}
