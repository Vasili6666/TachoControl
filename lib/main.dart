import 'dart:io';
import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TachoControl',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class ShiftHistoryPage extends StatefulWidget {
  const ShiftHistoryPage({super.key});

  @override
  State<ShiftHistoryPage> createState() => _ShiftHistoryPageState();
}

class _ShiftHistoryPageState extends State<ShiftHistoryPage> {
  late Future<List<Map<String, Object?>>> _rowsFuture;

  @override
  void initState() {
    super.initState();
    _rowsFuture = ShiftDatabase.getLast56Days();
  }

  Future<void> _restoreCsv() async {
    final bytes = await ShiftDatabase.pickCsvFile();
    if (!mounted || bytes == null) return;

    try {
      final count = await ShiftDatabase.restoreCsv(bytes);
      if (!mounted) return;
      setState(() {
        _rowsFuture = ShiftDatabase.getLast56Days();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Восстановлено записей: $count')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка восстановления: $error')),
      );
    }
  }

  Future<void> _deleteRow(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить запись?'),
        content: const Text('Эта строка будет удалена из базы данных.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ShiftDatabase.deleteRow(id);
    if (!mounted) return;
    setState(() {
      _rowsFuture = ShiftDatabase.getLast56Days();
    });
  }

  Future<void> _editComment(int id, String currentComment) async {
    final comment = await showDialog<String>(
      context: context,
      builder: (_) => _CommentEditorDialog(initialComment: currentComment),
    );
    if (comment == null) return;

    try {
      await ShiftDatabase.updateComment(id, comment);
      if (!mounted) return;
      setState(() {
        _rowsFuture = ShiftDatabase.getLast56Days();
      });
      try {
        await ShiftDatabase.createCsvBackup();
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Комментарий сохранён, но резервная копия не создана'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка сохранения комментария: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('History 56 days'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Restore CSV',
            icon: const Icon(Icons.restore),
            onPressed: _restoreCsv,
          ),
          IconButton(
            tooltip: 'Export CSV',
            icon: const Icon(Icons.file_download),
            onPressed: () async {
              final message = await ShiftDatabase.exportCsv();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(message)),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<Map<String, Object?>>>(
          future: _rowsFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Ошибка загрузки таблицы: ${snapshot.error}',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final rows = snapshot.data!;
            return _HistoryTable(
              rows: rows,
              onDelete: _deleteRow,
              onEditComment: _editComment,
            );
          },
        ),
      ),
    );
  }
}

class _HistoryTable extends StatelessWidget {
  const _HistoryTable({
    required this.rows,
    required this.onDelete,
    required this.onEditComment,
  });

  final List<Map<String, Object?>> rows;
  final Future<void> Function(int id) onDelete;
  final Future<void> Function(int id, String comment) onEditComment;

  String _formatDate(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return '';
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  String _formatTime(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return '';
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatDay(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return '';
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[date.weekday - 1];
  }

  String _formatWork(String startValue, String endValue) {
    final start = DateTime.tryParse(startValue);
    final end = DateTime.tryParse(endValue);
    if (start == null || end == null || end.isBefore(start)) return '';
    final duration = end.difference(start);
    return '${duration.inHours.toString().padLeft(2, '0')}:${(duration.inMinutes % 60).toString().padLeft(2, '0')}';
  }

  String _formatRest(String startValue, String previousEndValue) {
    final start = DateTime.tryParse(startValue);
    final previousEnd = DateTime.tryParse(previousEndValue);
    if (start == null || previousEnd == null || start.isBefore(previousEnd)) {
      return '';
    }
    final duration = start.difference(previousEnd);
    return '${duration.inHours.toString().padLeft(2, '0')}:${(duration.inMinutes % 60).toString().padLeft(2, '0')}';
  }

  String _formatBalance(String restValue) {
    final parts = restValue.split(':');
    if (parts.length != 2) return '';
    final restMinutes =
        (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
    if (restMinutes <= 24 * 60) return '';

    final balanceMinutes = restMinutes - 45 * 60;
    final sign = balanceMinutes < 0 ? '-' : '+';
    final absoluteMinutes = balanceMinutes.abs();
    return '$sign${(absoluteMinutes ~/ 60).toString().padLeft(2, '0')}:${(absoluteMinutes % 60).toString().padLeft(2, '0')}';
  }

  String _formatKilometers(String currentValue, String previousValue) {
    final current = double.tryParse(currentValue.replaceAll(',', '.'));
    final previous = double.tryParse(previousValue.replaceAll(',', '.'));
    if (current == null || previous == null || current < previous) return '';

    final distance = current - previous;
    if (distance == distance.roundToDouble()) {
      return distance.toInt().toString();
    }
    return distance.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              width: constraints.maxWidth < 1100 ? 1100 : constraints.maxWidth,
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFEFEF),
                border: Border.all(color: Colors.black, width: 2),
              ),
              child: Table(
                border: TableBorder.all(color: Colors.black, width: 1),
                columnWidths: const {
                  0: FlexColumnWidth(1.5),
                  1: FlexColumnWidth(0.85),
                  2: FlexColumnWidth(0.9),
                  3: FlexColumnWidth(0.9),
                  4: FlexColumnWidth(0.8),
                  5: FlexColumnWidth(0.8),
                  6: FlexColumnWidth(0.8),
                  7: FlexColumnWidth(1.2),
                  8: FlexColumnWidth(0.9),
                  9: FlexColumnWidth(2.2),
                  10: FlexColumnWidth(0.6),
                },
                children: [
                  const TableRow(
                    decoration: BoxDecoration(color: Color(0xFF73C88B)),
                    children: [
                      _TableHeaderCell('Date'),
                      _TableHeaderCell('DayWeek'),
                      _TableHeaderCell('StartTime'),
                      _TableHeaderCell('EndTime'),
                      _TableHeaderCell('WorkingTime'),
                      _TableHeaderCell('RestTime'),
                      _TableHeaderCell('Balance'),
                      _TableHeaderCell('Odometer'),
                      _TableHeaderCell('Kilometer'),
                      _TableHeaderCell('Comments'),
                      _TableHeaderCell(''),
                    ],
                  ),
                  ...rows.asMap().entries.map((entry) {
                    final index = entry.key;
                    final row = entry.value;
                    final start = row['start_at']?.toString() ?? '';
                    final end = row['end_at']?.toString() ?? '';
                    final comment = row['comments']?.toString() ?? '';
                    final mileage = row['mileage']?.toString() ?? '';
                    final previousMileage = index == 0
                        ? ''
                        : rows[index - 1]['mileage']?.toString() ?? '';
                    final previousEnd = index == 0
                        ? ''
                        : rows[index - 1]['end_at']?.toString() ?? '';
                    final rest = _formatRest(start, previousEnd);
                    final balance = _formatBalance(rest);
                    final id = int.tryParse(row['id']?.toString() ?? '');
                    return TableRow(
                      decoration: BoxDecoration(
                        color: index.isEven
                            ? Colors.white
                            : const Color(0xFFF0F0F0),
                      ),
                      children: [
                        _TableCell(_formatDate(start)),
                        _TableCell(_formatDay(start)),
                        _TableCell(_formatTime(start)),
                        _TableCell(_formatTime(end)),
                        _TableCell(_formatWork(start, end)),
                        _TableCell(rest),
                        _TableCell(
                          balance,
                          textColor: balance.startsWith('+')
                              ? Colors.green.shade700
                              : balance.startsWith('-')
                                  ? Colors.red.shade700
                                  : Colors.black,
                        ),
                        _TableCell(mileage),
                        _TableCell(
                          _formatKilometers(mileage, previousMileage),
                        ),
                        _CommentCell(
                          comment: comment,
                          onTap: id == null
                              ? null
                              : () => onEditComment(id, comment),
                        ),
                        _DeleteCell(
                          onPressed: id == null ? null : () => onDelete(id),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TableHeaderCell extends StatelessWidget {
  const _TableHeaderCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          maxLines: 1,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  const _TableCell(this.text, {this.textColor = Colors.black});

  final String text;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(
            fontSize: 11,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

class _DeleteCell extends StatelessWidget {
  const _DeleteCell({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        iconSize: 16,
        tooltip: 'Удалить строку',
        icon: const Icon(Icons.delete_outline, color: Colors.red),
      ),
    );
  }
}

class _CommentCell extends StatelessWidget {
  const _CommentCell({required this.comment, required this.onTap});

  final String comment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Редактировать комментарий',
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 56,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: comment.isEmpty
              ? const Icon(Icons.add_comment_outlined, size: 18)
              : Text(
                  comment,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.black),
                ),
        ),
      ),
    );
  }
}

class _CommentEditorDialog extends StatefulWidget {
  const _CommentEditorDialog({required this.initialComment});

  final String initialComment;

  @override
  State<_CommentEditorDialog> createState() => _CommentEditorDialogState();
}

class _CommentEditorDialogState extends State<_CommentEditorDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialComment);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Comments'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Заметка об этом дне или нарушении',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class ShiftDatabase {
  static final ShiftDatabase instance = ShiftDatabase._();
  static const _storageChannel = MethodChannel('tachocontrol/storage');

  ShiftDatabase._();

  static Database? _database;

  static Future<Uint8List?> pickCsvFile() async {
    if (!Platform.isAndroid) return null;
    final bytes =
        await _storageChannel.invokeMethod<List<dynamic>>('pickCsvFile');
    if (bytes == null) return null;
    return Uint8List.fromList(bytes.cast<int>());
  }

  static Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'tachocontrol.db');

    _database = await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE shifts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_at TEXT,
            end_at TEXT,
            mileage TEXT,
            comments TEXT,
            created_at TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_shifts_created_at '
            'ON shifts(created_at)',
          );
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE shifts ADD COLUMN comments TEXT');
        }
      },
    );

    await _removeOlderThan112Days(_database!);
    return _database!;
  }

  static Future<void> _removeOlderThan112Days(Database db) async {
    final cutoff =
        DateTime.now().subtract(const Duration(days: 112)).toIso8601String();
    await db.delete(
      'shifts',
      where: 'created_at < ?',
      whereArgs: [cutoff],
    );
  }

  static Future<List<Map<String, Object?>>> getLast56Days() async {
    final db = await database;
    final cutoff =
        DateTime.now().subtract(const Duration(days: 56)).toIso8601String();
    return db.query(
      'shifts',
      where: 'created_at >= ?',
      whereArgs: [cutoff],
      orderBy: 'created_at ASC',
    );
  }

  static Future<void> deleteRow(int id) async {
    final db = await database;
    await db.delete(
      'shifts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> updateComment(int id, String comment) async {
    final db = await database;
    await db.update(
      'shifts',
      {'comments': comment},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<int> restoreCsv(Uint8List bytes) async {
    final text =
        utf8.decode(bytes, allowMalformed: true).replaceFirst('\uFEFF', '');
    final rows = const CsvToListConverter(fieldDelimiter: ';').convert(text);
    if (rows.length < 2) return 0;

    final db = await database;
    final existing = await db.query('shifts');
    final existingKeys = existing
        .map(
          (row) => '${row['start_at']}|${row['end_at']}|${row['mileage']}',
        )
        .toSet();
    var imported = 0;

    for (final row in rows.skip(1)) {
      if (row.length < 4) continue;
      final date = row[0].toString().trim();
      final startTime = row[2].toString().trim();
      if (date.isEmpty || startTime.isEmpty) continue;

      final start = _parseCsvDateTime(date, startTime);
      if (start == null) continue;
      final end = row[3].toString().trim().isEmpty
          ? null
          : _parseCsvDateTime(date, row[3].toString().trim());
      final mileage = row.length > 7 ? row[7].toString().trim() : '';
      final comment = row.length > 9 ? row[9].toString().trim() : '';
      final startAt = start.toIso8601String();
      final endAt = end?.toIso8601String();
      final key = '$startAt|$endAt|$mileage';
      if (!existingKeys.add(key)) continue;

      await db.insert('shifts', {
        'start_at': startAt,
        'end_at': endAt,
        'mileage': mileage,
        'comments': comment,
        'created_at': startAt,
      });
      imported++;
    }

    await _removeOlderThan112Days(db);
    if (imported > 0) await createCsvBackup();
    return imported;
  }

  static DateTime? _parseCsvDateTime(String dateValue, String timeValue) {
    final iso = DateTime.tryParse('$dateValue $timeValue:00');
    if (iso != null) return iso;

    final parts = dateValue.split('-');
    if (parts.length != 3) return null;
    const months = {
      'Jan': 1,
      'Feb': 2,
      'Mar': 3,
      'Apr': 4,
      'May': 5,
      'Jun': 6,
      'Jul': 7,
      'Aug': 8,
      'Sep': 9,
      'Oct': 10,
      'Nov': 11,
      'Dec': 12,
    };
    final day = int.tryParse(parts[0]);
    final month = months[parts[1]];
    final year = int.tryParse(parts[2]);
    final timeParts = timeValue.split(':');
    final hour = int.tryParse(timeParts.first);
    final minute = timeParts.length > 1 ? int.tryParse(timeParts[1]) : null;
    if (day == null ||
        month == null ||
        year == null ||
        hour == null ||
        minute == null) {
      return null;
    }
    return DateTime(year, month, day, hour, minute);
  }

  static Future<File> _createCsvFile(String prefix) async {
    final db = await database;
    final rows = await db.query('shifts', orderBy: 'created_at ASC');
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final backupDirectory = Directory(
      p.join(documentsDirectory.path, 'tachocontrol_backups'),
    );
    await backupDirectory.create(recursive: true);

    final date = DateTime.now();
    final dateName = '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}_'
        '${date.hour.toString().padLeft(2, '0')}-'
        '${date.minute.toString().padLeft(2, '0')}-'
        '${date.second.toString().padLeft(2, '0')}';
    final file = File(
      p.join(backupDirectory.path, '${prefix}_$dateName.csv'),
    );

    final lines = _buildCsvLines(rows);
    final csvContent = '\uFEFF${lines.join('\n')}';
    await file.writeAsString(csvContent);
    await _saveToPublicDownloads(
      fileName: p.basename(file.path),
      content: Uint8List.fromList(utf8.encode(csvContent)),
    );

    final backups = backupDirectory
        .listSync()
        .whereType<File>()
        .where((file) =>
            p.basename(file.path).startsWith('tachocontrol_backup_') &&
            p.extension(file.path).toLowerCase() == '.csv')
        .toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

    for (final oldBackup in backups.skip(3)) {
      await oldBackup.delete();
    }

    return file;
  }

  static Future<void> _saveToPublicDownloads({
    required String fileName,
    required Uint8List content,
  }) async {
    if (!Platform.isAndroid) return;

    await _storageChannel.invokeMethod<void>('saveBackupToDownloads', {
      'fileName': fileName,
      'bytes': content,
    });
  }

  static Future<void> createCsvBackup() async {
    await _createCsvFile('tachocontrol_backup');
  }

  static Future<String> exportCsv() async {
    final file = await _createCsvFile('tachocontrol_export');
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'TachoControl export',
    );
    return 'CSV-файл подготовлен для Excel';
  }

  static List<String> _buildCsvLines(List<Map<String, Object?>> rows) {
    final lines = <String>[
      'Date;DayWeek;StartTime;EndTime;WorkingTime;RestTime;Balance;Odometer;Kilometrage;Comments',
    ];

    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final start = row['start_at']?.toString() ?? '';
      final end = row['end_at']?.toString() ?? '';
      final previousEnd =
          index == 0 ? '' : rows[index - 1]['end_at']?.toString() ?? '';
      final mileage = row['mileage']?.toString() ?? '';
      final comment = row['comments']?.toString() ?? '';
      final previousMileage =
          index == 0 ? '' : rows[index - 1]['mileage']?.toString() ?? '';
      final workingTime = _duration(start, end);
      final restTime = _duration(previousEnd, start);
      final balance = _balance(restTime);
      final kilometers = _kilometers(mileage, previousMileage);

      lines.add([
        start.isEmpty ? '' : start.substring(0, 10),
        start.isEmpty ? '' : _weekday(start),
        _time(start),
        _time(end),
        workingTime,
        restTime,
        balance,
        mileage,
        kilometers,
        comment,
      ].map(_csvValue).join(';'));
    }

    return lines;
  }

  static String _duration(String fromValue, String toValue) {
    final from = DateTime.tryParse(fromValue);
    final to = DateTime.tryParse(toValue);
    if (from == null || to == null || to.isBefore(from)) return '';
    final minutes = to.difference(from).inMinutes;
    return '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
  }

  static String _balance(String restValue) {
    final parts = restValue.split(':');
    if (parts.length != 2) return '';
    final restMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
    if (restMinutes <= 24 * 60) return '';
    final balanceMinutes = restMinutes - 45 * 60;
    final sign = balanceMinutes < 0 ? '-' : '+';
    final absoluteMinutes = balanceMinutes.abs();
    return '$sign${(absoluteMinutes ~/ 60).toString().padLeft(2, '0')}:${(absoluteMinutes % 60).toString().padLeft(2, '0')}';
  }

  static String _kilometers(String currentValue, String previousValue) {
    final current = double.tryParse(currentValue.replaceAll(',', '.'));
    final previous = double.tryParse(previousValue.replaceAll(',', '.'));
    if (current == null || previous == null || current < previous) return '';
    final distance = current - previous;
    return distance == distance.roundToDouble()
        ? distance.toInt().toString()
        : distance.toStringAsFixed(1);
  }

  static String _csvValue(String value) {
    return '"${value.replaceAll('"', '""')}"';
  }

  static String _time(String value) {
    if (value.length < 16) return '';
    return value.substring(11, 16);
  }

  static String _weekday(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return '';
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[date.weekday - 1];
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  DateTime? _startAt;
  DateTime? _endAt;
  final TextEditingController _mileageController = TextEditingController();
  bool _isMileageEditing = false;

  @override
  void initState() {
    super.initState();
    ShiftDatabase.database;
  }

  static DateTime? _tryParseManualDateTime(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) return null;

    final dashMatch = RegExp(
      r'^(\d{1,2})\.(\d{1,2})\.(\d{4})\s+(\d{1,2}):(\d{2})$',
    ).firstMatch(normalized);
    if (dashMatch != null) {
      final day = int.tryParse(dashMatch.group(1)!);
      final month = int.tryParse(dashMatch.group(2)!);
      final year = int.tryParse(dashMatch.group(3)!);
      final hour = int.tryParse(dashMatch.group(4)!);
      final minute = int.tryParse(dashMatch.group(5)!);
      if (day == null ||
          month == null ||
          year == null ||
          hour == null ||
          minute == null) {
        return null;
      }
      return DateTime(year, month, day, hour, minute);
    }

    final isoCandidate = normalized.replaceAll('.', '-');
    final parsed = DateTime.tryParse(isoCandidate);
    if (parsed != null) return parsed;

    final slashMatch = RegExp(
      r'^(\d{1,2})/(\d{1,2})/(\d{4})\s+(\d{1,2}):(\d{2})$',
    ).firstMatch(normalized);
    if (slashMatch != null) {
      final day = int.tryParse(slashMatch.group(1)!);
      final month = int.tryParse(slashMatch.group(2)!);
      final year = int.tryParse(slashMatch.group(3)!);
      final hour = int.tryParse(slashMatch.group(4)!);
      final minute = int.tryParse(slashMatch.group(5)!);
      if (day == null ||
          month == null ||
          year == null ||
          hour == null ||
          minute == null) {
        return null;
      }
      return DateTime(year, month, day, hour, minute);
    }

    return null;
  }

  String _formatDateTime(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year;
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');

    return '$day.$month.$year $hour:$minute';
  }

  Future<void> _setStart() async {
    setState(() {
      _startAt = DateTime.now();
    });
  }

  Future<void> _setEnd() async {
    setState(() {
      _endAt = DateTime.now();
    });
  }

  Future<void> _editDateTime({required bool isStart}) async {
    final current = isStart ? _startAt : _endAt;
    final controller = TextEditingController(
      text: current == null
          ? _formatDateTime(DateTime.now())
          : _formatDateTime(current),
    );

    final result = await showDialog<DateTime?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title:
              Text(isStart ? 'Изменить время старта' : 'Изменить время конца'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.datetime,
            decoration: const InputDecoration(
              hintText: 'DD.MM.YYYY HH:MM',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = _tryParseManualDateTime(controller.text);
                if (parsed == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Формат: DD.MM.YYYY HH:MM')),
                  );
                  return;
                }
                Navigator.pop(context, parsed);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );

    if (result == null) return;

    setState(() {
      if (isStart) {
        _startAt = result;
      } else {
        _endAt = result;
      }
    });
  }

  Future<void> _sendToDatabase() async {
    try {
      final db = await ShiftDatabase.database;

      await db.insert(
        'shifts',
        {
          'start_at': _startAt?.toIso8601String(),
          'end_at': _endAt?.toIso8601String(),
          'mileage': _mileageController.text.trim(),
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      if (!mounted) return;

      setState(() {
        _startAt = null;
        _endAt = null;
        _mileageController.clear();
        _isMileageEditing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Данные отправлены в БД')),
      );

      try {
        await ShiftDatabase.createCsvBackup();
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Данные сохранены, но резервная копия не создана'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка сохранения: $error')),
      );
    }
  }

  @override
  void dispose() {
    _mileageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SizedBox(
            width: 900,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          label: 'START',
                          color: Colors.green,
                          onPressed: _setStart,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: _DateBox(
                          dateTime: _startAt,
                          onTap: () => _editDateTime(isStart: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          label: 'END',
                          color: Colors.red,
                          onPressed: _setEnd,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: _DateBox(
                          dateTime: _endAt,
                          onTap: () => _editDateTime(isStart: false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: SizedBox(
                      width: 420,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _isMileageEditing = true;
                          });
                        },
                        child: _isMileageEditing
                            ? _MileageInput(controller: _mileageController)
                            : Container(
                                height: 90,
                                color: const Color(0xFFEFEFEF),
                                alignment: Alignment.center,
                                child: const Text(
                                  'KM',
                                  style: TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          label: 'SEND',
                          color: Colors.yellow,
                          onPressed: _sendToDatabase,
                          height: 120,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 90,
                    child: _ActionButton(
                      label: 'DAYS',
                      color: Colors.blue,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ShiftHistoryPage(),
                          ),
                        );
                      },
                      height: 90,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.color,
    required this.onPressed,
    this.height = 120,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.black,
          elevation: 0,
          padding: EdgeInsets.zero,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _DateBox extends StatelessWidget {
  const _DateBox({required this.dateTime, this.onTap});

  final DateTime? dateTime;
  final VoidCallback? onTap;

  String _formatDateTime(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year;
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 120,
        color: const Color(0xFFF1F1F1),
        alignment: Alignment.center,
        child: Text(
          dateTime == null ? '' : _formatDateTime(dateTime!),
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w500,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}

class _MileageInput extends StatelessWidget {
  const _MileageInput({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      color: const Color(0xFFEFEFEF),
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w500,
          color: Colors.black,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
