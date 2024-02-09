import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

class DataBase {
  static List<Expense> expenses = [];

  static void createInitialData() {
    expenses = [];
  }

  static void loadData() {
    debugPrint("json $json");

    loadExpenses().then((value) {
      expenses = Expense.listFromRawJson(json);
    });
  }

  void updateDatabase() {
    //_myBox.put("expenses", Expense.listToJson(expenses));
    Map<String, dynamic> newJson = {"expense": DataBase.expenses};
    saveExpenses(jsonEncode(newJson));
  }

  static String json = "[]"; // Initialize as empty string
  static File? expFile;

  static Future<String> loadExpenses() async {
    try {
      Directory path = await getApplicationDocumentsDirectory();

      final file = await File('${path.path}/fins.txt')
          .create(recursive: true); // Create if not found
      expFile = file;
      final contents = await file.readAsString();
      debugPrint("contents $contents");
      json = contents.isEmpty
          ? jsonEncode({"expense": []})
          : contents; // Handle empty file
      expenses = Expense.listFromRawJson(json);
      debugPrint("json load $json");
      return contents.isEmpty ? jsonEncode({"expense": []}) : contents;
    } catch (e) {
      debugPrint("Error loading expenses: $e");
      json = "[]"; // Set to empty string on error
    }
    return "[]";
  }

  static Future<void> saveExpenses(String newJson) async {
    try {
      Directory path = await getApplicationDocumentsDirectory();
      debugPrint(path.path);
      await File('${path.path}/fins.txt').writeAsString(newJson);
      expFile = File('${path.path}/fins.txt');
      debugPrint("write file \n\n\n\n");
    } catch (e) {
      debugPrint("Error saving expenses: $e");
    }
  }
}

class Expense {
  String? name;
  List<String>? label;
  String? id;
  String? date;
  String? amount;
  bool? isDebit;

  Expense({
    this.name,
    this.label,
    this.id,
    this.date,
    this.amount,
    this.isDebit = true,
  });

  factory Expense.fromRawJson(String str) => Expense.fromJson(json.decode(str));

  String toRawJson() => json.encode(toJson());

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        name: json["name"],
        label: json["label"] == null
            ? []
            : List<String>.from(json["label"]!.map((x) => x)),
        id: json["id"],
        date: json["date"],
        amount: json["amount"],
        isDebit: json["isDebit"],
      );

  Map<String, dynamic> toJson() => {
        "name": name,
        "label": label,
        "id": id,
        "date": date,
        "amount": amount,
        "isDebit": isDebit,
      };

  static List<Expense> listFromRawJson(String str) {
    Map<String, dynamic> jsonRes = json.decode(str);
    List list = jsonRes['expense'];
    return List<Expense>.from(list.map((item) => Expense.fromJson(item)));
  }

  static List<Map<String, dynamic>> listToJson(List<Expense> list) {
    List<Map<String, dynamic>> jsonList =
        List<Map<String, dynamic>>.from(list.map((item) => item.toJson()));
    return jsonList;
  }

  String getMonthYear() {
    // Convert ISO date to DateTime and then format it as "MMMM yyyy"
    DateTime dateTime = DateTime.parse(date!);
    return DateFormat.yMMMM().format(dateTime);
  }
}
