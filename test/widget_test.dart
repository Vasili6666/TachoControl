import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tachocontrol/main.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final db = await ShiftDatabase.database;
    await db.delete('shifts');
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

  testWidgets('restores active shift from database on app start', (
    WidgetTester tester,
  ) async {
    final db = await ShiftDatabase.database;
    final start = DateTime(2026, 10, 4, 7, 15);
    await db.insert('shifts', {
      'start_at': start.toIso8601String(),
      'created_at': start.toIso8601String(),
      'mileage': '12345',
    });

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('04.10.2026'), findsWidgets);
    expect(find.textContaining('07:15'), findsWidgets);

    await tester.tap(find.text('END'));
    await tester.pumpAndSettle();

    final rows = await db.query('shifts');
    expect(rows.length, 1);
    expect(rows.first['end_at'], isNotNull);
    expect(rows.first['start_at'], isNotNull);
  });

  testWidgets('history cell taps open editing dialog',
      (WidgetTester tester) async {
    final db = await ShiftDatabase.database;
    final start = DateTime(2026, 10, 4, 7, 15);
    final end = DateTime(2026, 10, 4, 16, 45);
    await db.insert('shifts', {
      'start_at': start.toIso8601String(),
      'end_at': end.toIso8601String(),
      'created_at': start.toIso8601String(),
      'mileage': '12345',
      'comments': 'Test',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: const ShiftHistoryPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('07:15'), findsOneWidget);
    await tester.tap(find.text('07:15'));
    await tester.pumpAndSettle();

    expect(find.text('Изменить start_at'), findsOneWidget);
  });
}
