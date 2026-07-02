import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:personal_bahi_khata/data/database.dart';
import 'package:personal_bahi_khata/data/expenses.dart';
import 'package:personal_bahi_khata/data/import_matching.dart';
import 'package:personal_bahi_khata/data/pbke_file.dart';
import 'package:personal_bahi_khata/data/sms_api.dart';
import 'package:personal_bahi_khata/util/tag_utils.dart';

class ImportExportExpenses {
  static void _log(String message) {
    debugPrint("[PBKE-IMPORT] $message");
  }

  static Future<Directory> _getStorageDirectory() async {
    if (Platform.isAndroid) {
      final directory = await getExternalStorageDirectory();
      if (directory == null) {
        throw const FileSystemException("Storage directory is unavailable");
      }
      return directory;
    }

    if (Platform.isLinux) {
      final home = Platform.environment["HOME"];
      if (home == null || home.isEmpty) {
        throw const FileSystemException("HOME is not available");
      }
      return Directory(
        "$home/.local/state/${DataBase.applicationId}",
      ).create(recursive: true);
    }

    return (await getApplicationSupportDirectory()).create(recursive: true);
  }

  static Future<Directory> _getExportDirectory() async {
    if (Platform.isLinux) {
      final exportDirectory = Directory(
        "${(await _getStorageDirectory()).path}/exports",
      );
      return exportDirectory.create(recursive: true);
    }

    return await getTemporaryDirectory();
  }

  static void validateImportFileType(String filePath) {
    final extension = DataBase.getFileExtension(filePath);
    if (extension != "json" && extension != "pbke" && extension != "csv") {
      throw const FormatException(DataBase.unsupportedFileTypeMessage);
    }
  }

  static Map<String, dynamic> _normalizeImportedExpenseMap(
    Map<String, dynamic> item,
  ) {
    final normalized = Map<String, dynamic>.from(item);

    if (normalized["id"] != null && normalized["id"].toString().trim().isNotEmpty) {
      normalized["id"] = normalized["id"].toString();
    } else {
      normalized.remove("id");
    }
    if (normalized["amount"] != null) {
      normalized["amount"] = normalized["amount"].toString();
    }

    if (normalized["label"] is String) {
      normalized["label"] = normalizeTags((normalized["label"] as String).split("|"));
    }

    if (normalized["label"] == null) {
      normalized["label"] = <String>[];
    }

    normalized["label"] = normalizeTags(normalized["label"] as Iterable<dynamic>?);

    if (!normalized.containsKey("isSMS")) {
      normalized["isSMS"] = false;
    }

    return normalized;
  }

  static String _stripUtf8Bom(String content) {
    if (content.isNotEmpty && content.codeUnitAt(0) == 0xFEFF) {
      return content.substring(1);
    }
    return content;
  }

  static List<dynamic> _extractJsonExpenseItems(dynamic decodedJson) {
    if (decodedJson is List) {
      return decodedJson;
    }

    if (decodedJson is Map<String, dynamic> &&
        decodedJson["expenses"] is List) {
      return List<dynamic>.from(decodedJson["expenses"] as List);
    }

    throw const FormatException(DataBase.unsupportedFileMessage);
  }

  static void _validateExpenseMap(
    Map<String, dynamic> item, {
    required bool requireExactKeys,
  }) {
    if (requireExactKeys) {
      const requiredKeys = {"name", "label", "date", "amount", "isDebit"};
      final itemKeys = item.keys.toSet();
      if (!itemKeys.containsAll(requiredKeys)) {
        throw const FormatException(DataBase.unsupportedFileMessage);
      }
    }

    if (item["name"] is! String ||
        item["date"] is! String ||
        item["amount"] is! String ||
        item["isDebit"] is! bool ||
        item["isSMS"] is! bool) {
      throw const FormatException(DataBase.unsupportedFileMessage);
    }

    if (item.containsKey("id") && item["id"] != null && item["id"] is! String) {
      throw const FormatException(DataBase.unsupportedFileMessage);
    }

    final label = item["label"];
    if (label != null &&
        (label is! List || label.any((value) => value is! String))) {
      throw const FormatException(DataBase.unsupportedFileMessage);
    }

    try {
      DateTime.parse(item["date"] as String);
      double.parse(item["amount"] as String);
    } catch (_) {
      throw const FormatException(DataBase.unsupportedFileMessage);
    }
  }

  static List<Expense> _decodeExpenseList(dynamic decodedJson) {
    final expenseItems = _extractJsonExpenseItems(decodedJson);

    return List<Expense>.from(
      expenseItems.map((item) {
        if (item is! Map) {
          throw const FormatException(DataBase.unsupportedFileMessage);
        }
        final expenseMap = _normalizeImportedExpenseMap(
          Map<String, dynamic>.from(item),
        );
        _validateExpenseMap(expenseMap, requireExactKeys: true);
        return Expense.fromJson(expenseMap);
      }),
    );
  }

  static List<Expense> _decodePbkeExpenses(dynamic decodedJson) {
    if (decodedJson is! Map<String, dynamic> ||
        decodedJson["expenses"] is! List) {
      _log(
        "_decodePbkeExpenses invalid top-level shape type=${decodedJson.runtimeType}",
      );
      throw const FormatException(DataBase.unsupportedFileMessage);
    }

    _log(
      "_decodePbkeExpenses keys=${decodedJson.keys.toList()} expensesCount=${(decodedJson["expenses"] as List).length}",
    );

    return List<Expense>.from(
      (decodedJson["expenses"] as List).map((item) {
        if (item is! Map) {
          _log("_decodePbkeExpenses invalid item type=${item.runtimeType}");
          throw const FormatException(DataBase.unsupportedFileMessage);
        }
        final expenseMap = Map<String, dynamic>.from(item);
        _log(
          "_decodePbkeExpenses validating expense keys=${expenseMap.keys.toList()}",
        );
        _validateExpenseMap(expenseMap, requireExactKeys: false);
        return Expense.fromJson(expenseMap);
      }),
    );
  }

  static void _normalizeExpenseLabelsInPlace(List<Expense> items) {
    for (final expense in items) {
      expense.label = normalizeTags(expense.label);
    }
  }

  static List<String> normalizeLabels(Iterable<dynamic>? labels) {
    return normalizeTags(labels);
  }

  static Future<List<Expense>> _readJsonExpenses(String filePath) async {
    final content = _stripUtf8Bom(await File(filePath).readAsString());

    try {
      return _decodeExpenseList(jsonDecode(content));
    } catch (e) {
      if (e is FormatException) {
        rethrow;
      }
      throw const FormatException(DataBase.unsupportedFileMessage);
    }
  }

  static Future<List<Expense>> _readPbkeExpenses(String filePath) async {
    _log("_readPbkeExpenses path=$filePath");
    final pbkeData = await PbkeFile.readPbkeFile(filePath);
    if (pbkeData == null) {
      _log("_readPbkeExpenses no data returned");
      throw const FormatException(DataBase.unsupportedFileMessage);
    }
    _log(
      "_readPbkeExpenses version=${pbkeData.version.isEmpty ? "<legacy>" : pbkeData.version} lastDate=${pbkeData.lastDate} keys=${pbkeData.data.keys.toList()}",
    );
    SmsApi.lastDate = pbkeData.lastDate;
    return _decodePbkeExpenses(pbkeData.data);
  }

  static Future<List<Expense>> _readCsvExpenses(String filePath) async {
    final content = await File(filePath).readAsString();
    return Expense.fromCSVString(content);
  }

  static String exportJsonList() {
    return jsonEncode(Expense.listToJson(DataBase.expenses));
  }

  static String exportCsv() {
    return Expense.toCSVString(DataBase.expenses);
  }

  static String exportPrivateMonthlyCsv(DateTime month) {
    return exportPrivateMonthlyCsvWithTags(month);
  }

  static String exportPrivateMonthlyCsvWithTags(
    DateTime month, {
    Set<String>? selectedTags,
  }) {
    final normalizedSelectedTags = normalizeTags(selectedTags ?? <String>[]);
    final selectedTagSet = normalizedSelectedTags.toSet();
    final monthExpenses =
        DataBase.expenses.where((expense) {
          if (expense.date == null) {
            return false;
          }
          final expenseDate = DateTime.parse(expense.date!);
          final matchesMonth =
              expenseDate.year == month.year && expenseDate.month == month.month;
          if (!matchesMonth) {
            return false;
          }
          if (selectedTagSet.isEmpty) {
            return true;
          }
          final expenseTags = normalizeTags(expense.label).toSet();
          return expenseTags.any(selectedTagSet.contains);
        }).toList();

    DataBase.sortExpensesByDate(monthExpenses);

    final rows = <List<dynamic>>[
      DataBase.privateExpenseFileKeys,
      ...monthExpenses.map((expense) {
        return <dynamic>[
          expense.name ?? "",
          (expense.label ?? <String>[]).join("|"),
          expense.date ?? "",
          expense.amount ?? "",
        ];
      }),
    ];
    return csv.encode(rows);
  }

  static Future<File> exportPrivateMonthlyCsvFile(DateTime month) async {
    return exportPrivateMonthlyCsvFileWithTags(month);
  }

  static Future<File> exportPrivateMonthlyCsvFileWithTags(
    DateTime month, {
    Set<String>? selectedTags,
  }) async {
    final exportDir = await _getExportDirectory();
    final fileName =
        "private_${month.year}_${month.month.toString().padLeft(2, '0')}.csv";
    final exportFile = File("${exportDir.path}/$fileName");
    final content = exportPrivateMonthlyCsvWithTags(
      month,
      selectedTags: selectedTags,
    );
    return exportFile.writeAsString(content);
  }

  static Future<File> exportExpensesFile(String format) async {
    if (format != "json" && format != "pbke" && format != "csv") {
      throw const FormatException(DataBase.unsupportedFileTypeMessage);
    }

    DataBase.sortExpensesByDate(DataBase.expenses);
    await DataBase.persistCurrentExpenses();

    final tempDir = await _getExportDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final exportFile = File('${tempDir.path}/expenses_$timestamp.$format');

    if (format == "pbke") {
      final sourcePath = DataBase.expFile?.path ?? DataBase.filepath;
      if (sourcePath.isEmpty || !File(sourcePath).existsSync()) {
        throw const FormatException(DataBase.unsupportedFileMessage);
      }
      return File(sourcePath).copy(exportFile.path);
    }

    final content = format == "json" ? exportJsonList() : exportCsv();
    return exportFile.writeAsString(content);
  }

  static Future<List<Expense>> importExpensesFromFile(
    String filePath, {
    DuplicateDecision? onDuplicate,
  }) async {
    validateImportFileType(filePath);

    final extension = DataBase.getFileExtension(filePath);
    _log("importExpensesFromFile path=$filePath extension=$extension");

    final List<Expense> importedExpenses;
    try {
      importedExpenses =
          extension == "json"
              ? await _readJsonExpenses(filePath)
              : extension == "csv"
              ? await _readCsvExpenses(filePath)
              : await _readPbkeExpenses(filePath);
      _log("importExpensesFromFile decodedExpenses=${importedExpenses.length}");
    } catch (e, st) {
      _log("importExpensesFromFile decode failed: $e");
      debugPrintStack(
        label: "[PBKE-IMPORT] importExpensesFromFile stack",
        stackTrace: st,
      );
      rethrow;
    }

    final mergeResult = await ImportMatching.mergeExpenses(
      existingExpenses: DataBase.expenses,
      importedExpenses: importedExpenses,
      onDuplicate: onDuplicate,
    );
    _log("importExpensesFromFile mergedExpenses=${mergeResult.expenses.length}");
    DataBase.expenses = mergeResult.expenses;
    _normalizeExpenseLabelsInPlace(DataBase.expenses);
    await DataBase.persistCurrentExpenses();
    _log("importExpensesFromFile persist complete");
    return DataBase.expenses;
  }
}
