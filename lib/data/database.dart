import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:personal_bahi_khata/data/import_export_expenses.dart';
import 'package:personal_bahi_khata/data/import_matching.dart';
import 'package:personal_bahi_khata/data/pbke_file.dart';
import 'package:personal_bahi_khata/data/sms_api.dart';
import 'package:personal_bahi_khata/data/expenses.dart';

class DataBase {
  static const String applicationId = "com.vins.personal_bahi_khata";
  static const String unsupportedFileTypeMessage = "unsupported file type";
  static const String unsupportedFileMessage = PbkeFile.unsupportedFileMessage;
  static const List<String> expenseFileKeys = Expense.csvHeaders;
  static const List<String> privateExpenseFileKeys = Expense.privateCsvHeaders;
  static List<Expense> expenses = [];
  static Set<String> uniqueTags = {};
  static List<String> selectedTags = [];
  static DateTime? selectedDate;
  static Set<int> uniqueyears = {};
  static String filepath = '';
  static bool smsExpensesEnabled = false;

  static const String signature = PbkeFile.signature;
  static const String version = PbkeFile.version;

  static bool isPermitted = false;

  static String json = """{"expenses":[]}""";
  static File? expFile;
  static Future<void> Function(String newJson, DateTime? date)?
  saveExpensesHook;

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
        "$home/.local/state/$applicationId",
      ).create(recursive: true);
    }

    return (await getApplicationSupportDirectory()).create(recursive: true);
  }

  static String getFileExtension(String filePath) {
    final lastDot = filePath.lastIndexOf(".");
    if (lastDot == -1 || lastDot == filePath.length - 1) {
      return "";
    }
    debugPrint(" Extension : ${filePath.substring(lastDot + 1).toLowerCase()}");
    return filePath.substring(lastDot + 1).toLowerCase();
  }

  static void validateImportFileType(String filePath) {
    ImportExportExpenses.validateImportFileType(filePath);
  }

  static void sortExpensesByDate(List<Expense> items) {
    items.sort((a, b) {
      final dateA = DateTime.parse(a.date!);
      final dateB = DateTime.parse(b.date!);
      return dateB.compareTo(dateA);
    });
  }

  static String expenseIdentity(Expense expense) {
    if ((expense.id ?? "").isNotEmpty) {
      return "id:${expense.id}";
    }
    return [
      expense.name ?? "",
      expense.date ?? "",
      expense.amount ?? "",
      expense.isDebit?.toString() ?? "",
      expense.isSMS.toString(),
    ].join("|");
  }

  static String buildStorageJson([List<Expense>? items]) {
    return jsonEncode({
      "expenses": Expense.listToJson(items ?? expenses),
      "smsEnabled": smsExpensesEnabled,
    });
  }

  static Future<void> persistCurrentExpenses({DateTime? date}) async {
    sortExpensesByDate(expenses);
    if (expenses.isNotEmpty) {
      json = buildStorageJson(expenses);
      await saveExpenses(json, date ?? SmsApi.lastDate);
    }
  }

  static Future<void> setSmsExpensesEnabled(bool enabled) async {
    smsExpensesEnabled = enabled;
    if (!enabled) {
      expenses = expenses.where((expense) => !expense.isSMS).toList();
    }
    sortExpensesByDate(expenses);
    await persistCurrentExpenses();
  }

  static String exportJsonList() {
    return ImportExportExpenses.exportJsonList();
  }

  static String exportCsv() {
    return ImportExportExpenses.exportCsv();
  }

  static String exportPrivateMonthlyCsv(DateTime month) {
    return ImportExportExpenses.exportPrivateMonthlyCsv(month);
  }

  static String exportPrivateMonthlyCsvWithTags(
    DateTime month, {
    Set<String>? selectedTags,
  }) {
    return ImportExportExpenses.exportPrivateMonthlyCsvWithTags(
      month,
      selectedTags: selectedTags,
    );
  }

  static Future<File> exportPrivateMonthlyCsvFile(DateTime month) async {
    return ImportExportExpenses.exportPrivateMonthlyCsvFile(month);
  }

  static Future<File> exportPrivateMonthlyCsvFileWithTags(
    DateTime month, {
    Set<String>? selectedTags,
  }) async {
    return ImportExportExpenses.exportPrivateMonthlyCsvFileWithTags(
      month,
      selectedTags: selectedTags,
    );
  }

  static Future<File> exportExpensesFile(String format) async {
    return ImportExportExpenses.exportExpensesFile(format);
  }

  static Future<List<Expense>> importExpensesFromFile(
    String filePath, {
    DuplicateDecision? onDuplicate,
  }) async {
    return ImportExportExpenses.importExpensesFromFile(
      filePath,
      onDuplicate: onDuplicate,
    );
  }

  static Future<String> loadExpenses() async {
    try {
      Directory path = await _getStorageDirectory();
      final file = await File(
        '${path.path}/fins.pbke',
      ).create(recursive: true); // Create if not found
      filepath = file.path;
      expFile = file;
      debugPrint("[DB] loadExpenses path=${file.path} size=${await file.length()}");
      final pbkeData = await PbkeFile.readPbkeFile(file.path);
      if (pbkeData != null) {
        SmsApi.lastDate = pbkeData.lastDate;
        debugPrint("[DB] loadExpenses decrypted keys=${pbkeData.data.keys.toList()}");
        smsExpensesEnabled = pbkeData.data["smsEnabled"] ?? false;
        json = jsonEncode(pbkeData.data);
      } else {
        debugPrint("[DB] loadExpenses pbkeData is null, keeping in-memory json");
      }

      expenses = Expense.listFromRawJson(json);
      for (final expense in expenses) {
        expense.label = ImportExportExpenses.normalizeLabels(expense.label);
      }
      sortExpensesByDate(expenses);
      debugPrint("[DB] loadExpenses loaded expenses=${expenses.length}");
      return json;
    } catch (e, st) {
      debugPrint("[DB] Error loading expenses: $e");
      debugPrintStack(label: "[DB] loadExpenses stack", stackTrace: st);
    }
    return json;
  }

  static Future<void> saveExpenses(String newJson, DateTime? date) async {
    try {
      if (saveExpensesHook != null) {
        await saveExpensesHook!(newJson, date);
        return;
      }
      Directory path = await _getStorageDirectory();
      var file = await PbkeFile.writePbkeFile(
        '${path.path}/fins.pbke',
        newJson,
        date,
        fileVersion: version,
      );
      filepath = file.path;
      expFile = File('${path.path}/fins.pbke');
    } catch (e) {
      debugPrint("Error saving expenses: $e");
    }
  }
}
