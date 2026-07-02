import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';
import 'package:personal_bahi_khata/data/database.dart';
import 'package:personal_bahi_khata/data/expenses.dart';
import 'package:personal_bahi_khata/data/pbke_file.dart';
import 'package:platform/platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MethodChannelPathProvider pathProvider;
  String? lastSavedJson;
  DateTime? lastSavedDate;

  Expense buildExpense({
    required String id,
    required String date,
    String amount = '10.0',
    bool isDebit = true,
    bool isSMS = false,
    List<String> label = const ['Food'],
  }) {
    return Expense(
      name: 'Expense $id',
      id: id,
      date: date,
      amount: amount,
      isDebit: isDebit,
      isSMS: isSMS,
      label: label,
    );
  }

  Future<File> createImportFile(String name, String content) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsString(content);
    return file;
  }

  setUpAll(() {
    pathProvider = MethodChannelPathProvider();
    pathProvider.setMockPathProviderPlatform(
      FakePlatform(operatingSystem: 'android'),
    );
    PathProviderPlatform.instance = pathProvider;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pbk_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider.methodChannel, (
          MethodCall methodCall,
        ) async {
          switch (methodCall.method) {
            case 'getTemporaryDirectory':
              return tempDir.path;
            case 'getStorageDirectory':
              return tempDir.path;
            default:
              return null;
          }
        });

    DataBase.expenses = [];
    DataBase.uniqueTags = {};
    DataBase.selectedTags = [];
    DataBase.selectedDate = null;
    DataBase.uniqueyears = {};
    DataBase.filepath = '';
    DataBase.expFile = null;
    DataBase.json = """{"expenses":[]}""";
    DataBase.smsExpensesEnabled = false;
    DataBase.saveExpensesHook = (newJson, date) async {
      lastSavedJson = newJson;
      lastSavedDate = date;
    };
    lastSavedJson = null;
    lastSavedDate = null;
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider.methodChannel, null);
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
    DataBase.saveExpensesHook = null;
  });

  test('validateFileHeader accepts matching signatures', () {
    final validHeader = <int>[
      ...utf8.encode(DataBase.signature),
      ...utf8.encode(DataBase.version),
      0,
      0,
      0,
      0,
      0,
      0,
    ];

    expect(() => PbkeFile.validateFileHeader(validHeader), returnsNormally);
  });

  test('validateFileHeader rejects a non-matching signature', () {
    final invalidSignatureHeader = <int>[
      ...utf8.encode('%WRNG%'),
      ...utf8.encode(DataBase.version),
      0,
      0,
      0,
      0,
      0,
      0,
    ];
    expect(
      () => PbkeFile.validateFileHeader(invalidSignatureHeader),
      throwsFormatException,
    );
  });

  test('buildFileHeader writes the latest pbke version header', () {
    final bytes = PbkeFile.buildFileHeader(null);
    final versionStart = PbkeFile.signature.length;
    final versionEnd = versionStart + PbkeFile.version.length;
    final storedVersion = utf8.decode(bytes.sublist(versionStart, versionEnd));

    expect(storedVersion, PbkeFile.version);
  });

  test('readFileVersion falls back to previous version when header has no version', () {
    final legacyHeader = <int>[
      ...utf8.encode(PbkeFile.signature),
      0,
      0,
      0,
      0,
      ...List<int>.filled(13, 0),
    ];

    expect(PbkeFile.readFileVersion(legacyHeader), '');
  });

  test(
    'pbke 01_10 round trips with encrypted payload and iv+key footer',
    () async {
      final file = File('${tempDir.path}/roundtrip.pbke');
      final inputJson = jsonEncode({
        'expenses': [
          buildExpense(id: 'pbke1', date: '2025-03-01T00:00:00.000').toJson(),
        ],
        'smsEnabled': true,
      });

      await PbkeFile.writePbkeFile(
        file.path,
        inputJson,
        DateTime.utc(2025, 3, 1),
        fileVersion: PbkeFile.version,
      );

      final bytes = await file.readAsBytes();
      final footerLength = PbkeFile.footerLengthForMode(
        PbkeFormatMode.v_01_10,
      );
      final encryptedPayload = PbkeFile.extractEncryptedPayload(bytes);

      expect(
        utf8.decode(bytes.sublist(0, PbkeFile.signature.length)),
        PbkeFile.signature,
      );
      expect(PbkeFile.readFileVersion(bytes), PbkeFile.version);
      expect(
        encryptedPayload.length,
        bytes.length - PbkeFile.headerSize - footerLength,
      );

      final readResult = await PbkeFile.readPbkeFile(file.path);

      expect(readResult, isNotNull);
      expect(readResult!.version, PbkeFile.version);
      expect(readResult.data['smsEnabled'], isTrue);
      expect((readResult.data['expenses'] as List), hasLength(1));
    },
    skip:
        'zstandard test plugin is unavailable in this host test environment',
  );

  test('json import merges into current db and keeps descending date order', () async {
    DataBase.expenses = [
      buildExpense(id: 'base', date: '2024-01-01T00:00:00.000'),
    ];

    final file = await createImportFile(
      'import.json',
      jsonEncode([
        buildExpense(id: 'newer', date: '2025-03-01T00:00:00.000').toJson(),
        buildExpense(id: 'middle', date: '2024-06-01T00:00:00.000').toJson(),
      ]),
    );

    final imported = await DataBase.importExpensesFromFile(file.path);

    expect(imported.map((expense) => expense.id), ['newer', 'middle', 'base']);
  });

  test('json import rejects data that is not a valid expense type', () async {
    final file = await createImportFile(
      'invalid.json',
      jsonEncode([
        {
          'name': 'Broken',
          'label': ['Food'],
          'id': 'bad',
          'date': '2025-01-01T00:00:00.000',
          'amount': '10',
          'isDebit': 'true',
          'isSMS': false,
        },
      ]),
    );

    expect(
      () => DataBase.importExpensesFromFile(file.path),
      throwsFormatException,
    );
  });

  test('json import accepts missing id and assigns a new one', () async {
    final file = await createImportFile(
      'missing_id.json',
      jsonEncode([
        {
          'name': 'No Id',
          'label': ['Food'],
          'date': '2025-04-01T00:00:00.000',
          'amount': '10',
          'isDebit': true,
          'isSMS': false,
        },
      ]),
    );

    final imported = await DataBase.importExpensesFromFile(file.path);

    expect(imported, hasLength(1));
    expect(imported.first.id, isNotNull);
    expect(imported.first.id, isNotEmpty);
  });

  test('csv import accepts expense columns and parses labels', () async {
    final file = await createImportFile(
      'import.csv',
      [
        DataBase.expenseFileKeys.join(','),
        '"Lunch","Food|Office","csv1","2025-02-01T00:00:00.000","150.0","true","false"',
      ].join('\n'),
    );

    final imported = await DataBase.importExpensesFromFile(file.path);

    expect(imported, hasLength(1));
    expect(imported.first.label, ['FOOD', 'OFFICE']);
    expect(imported.first.id, 'csv1');
  });

  test('csv import accepts rows without an id column and assigns a new one', () async {
    final file = await createImportFile(
      'import_without_id.csv',
      [
        'name,label,date,amount,isDebit,isSMS',
        '"Lunch","Food|Office","2025-02-01T00:00:00.000","150.0","true","false"',
      ].join('\n'),
    );

    final imported = await DataBase.importExpensesFromFile(file.path);

    expect(imported, hasLength(1));
    expect(imported.first.id, isNotNull);
    expect(imported.first.id, isNotEmpty);
    expect(imported.first.label, ['FOOD', 'OFFICE']);
  });

  test('csv import rejects invalid headers or types', () async {
    final file = await createImportFile(
      'invalid.csv',
      [
        'name,label,id,date,amount,isDebit',
        '"Lunch","Food","csv1","invalid-date","150.0","true"',
      ].join('\n'),
    );

    expect(
      () => DataBase.importExpensesFromFile(file.path),
      throwsFormatException,
    );
  });

  test('duplicate imported expense is skipped when user rejects it', () async {
    DataBase.expenses = [
      buildExpense(id: '1', date: '2025-02-01T00:00:00.000', amount: '150.0'),
    ];

    final file = await createImportFile(
      'duplicate.json',
      jsonEncode([
        buildExpense(id: '99', date: '2025-02-01T00:00:00.000', amount: '150.0')
            .copyWith(name: 'Expense 1')
            .toJson(),
      ]),
    );

    final imported = await DataBase.importExpensesFromFile(
      file.path,
      onDuplicate: (_, __) async => false,
    );

    expect(imported, hasLength(1));
    expect(imported.first.id, '1');
  });

  test('duplicate imported expense is added with a new incremental id when approved', () async {
    DataBase.expenses = [
      buildExpense(id: '7', date: '2025-02-01T00:00:00.000', amount: '150.0'),
    ];

    final file = await createImportFile(
      'duplicate_add.json',
      jsonEncode([
        buildExpense(id: '7', date: '2025-02-01T00:00:00.000', amount: '150.0')
            .copyWith(name: 'Expense 7')
            .toJson(),
      ]),
    );

    final imported = await DataBase.importExpensesFromFile(
      file.path,
      onDuplicate: (_, __) async => true,
    );

    expect(imported, hasLength(2));
    expect(imported.map((expense) => expense.id).toSet(), {'7', '8'});
  });

  test('id collision only gets a new incremental id automatically', () async {
    DataBase.expenses = [
      buildExpense(id: '10', date: '2025-02-01T00:00:00.000', amount: '150.0'),
    ];

    final file = await createImportFile(
      'id_collision.json',
      jsonEncode([
        buildExpense(
          id: '10',
          date: '2025-02-03T00:00:00.000',
          amount: '200.0',
        ).toJson(),
      ]),
    );

    final imported = await DataBase.importExpensesFromFile(file.path);

    expect(imported, hasLength(2));
    expect(imported.map((expense) => expense.id).toSet(), {'10', '11'});
  });

  test('pbke import validates the file version before merging', () async {
    final fileBytes = <int>[
      ...utf8.encode(DataBase.signature),
      ...utf8.encode('00.99'),
      0,
      0,
      0,
      0,
      0,
      0,
      ...List<int>.filled(PbkeFile.footerLengthForMode(PbkeFormatMode.legacy) + 4, 1),
    ];
    final tamperedFile = File('${tempDir.path}/invalid.pbke');
    await tamperedFile.writeAsBytes(fileBytes);

    expect(
      () => DataBase.importExpensesFromFile(tamperedFile.path),
      throwsFormatException,
    );
  });

  test('disabling sms removes sms expenses from the stored db', () async {
    DataBase.expenses = [
      buildExpense(id: 'sms', date: '2025-01-02T00:00:00.000', isSMS: true),
      buildExpense(id: 'manual', date: '2025-01-01T00:00:00.000'),
    ];
    DataBase.smsExpensesEnabled = true;

    await DataBase.setSmsExpensesEnabled(false);

    expect(DataBase.smsExpensesEnabled, isFalse);
    expect(DataBase.expenses.map((expense) => expense.id), ['manual']);
    expect(lastSavedJson, isNotNull);

    final decoded = jsonDecode(lastSavedJson!) as Map<String, dynamic>;
    expect(decoded['smsEnabled'], isFalse);
    expect((decoded['expenses'] as List).map((item) => item['id']), ['manual']);
  });
}
