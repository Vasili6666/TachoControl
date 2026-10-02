import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tachocontrol/main.dart';

void main() {
  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('app launches with main controls', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('START'), findsOneWidget);
    expect(find.text('SAVE KM'), findsOneWidget);
    expect(find.text('END'), findsOneWidget);
    expect(find.text('DAYS'), findsOneWidget);
    expect(find.text('BACKUP'), findsOneWidget);
    expect(find.text('KM'), findsOneWidget);
  });
}
