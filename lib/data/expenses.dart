import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:personal_bahi_khata/util/tag_utils.dart';

class Expense {
  Expense({
    this.name,
    this.label,
    this.id,
    this.date,
    this.amount,
    this.isDebit = true,
    this.isSMS = false,
  });

  static const List<String> csvHeaders = <String>[
    "name",
    "label",
    "id",
    "date",
    "amount",
    "isDebit",
    "isSMS",
  ];

  static const List<String> csvHeadersWithoutId = <String>[
    "name",
    "label",
    "date",
    "amount",
    "isDebit",
    "isSMS",
  ];

  static const List<String> privateCsvHeaders = <String>[
    "name",
    "label",
    "date",
    "amount",
  ];

  final String? name;
  List<String>? label;
  final String? id;
  final String? date;
  final String? amount;
  final bool? isDebit;
  final bool isSMS;

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
    name: json["name"]?.toString(),
    label:
        json["label"] == null
            ? <String>[]
            : normalizeTags(json["label"] as Iterable<dynamic>?),
    id: json["id"]?.toString(),
    date: json["date"]?.toString(),
    amount: json["amount"]?.toString(),
    isDebit: json["isDebit"] as bool?,
    isSMS: json["isSMS"] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    "name": name,
    "label": normalizeTags(label),
    "id": id,
    "date": date,
    "amount": amount,
    "isDebit": isDebit,
    "isSMS": isSMS,
  };

  Expense copyWith({
    String? name,
    List<String>? label,
    String? id,
    String? date,
    String? amount,
    bool? isDebit,
    bool? isSMS,
  }) {
    return Expense(
      name: name ?? this.name,
      label: label ?? List<String>.from(this.label ?? const <String>[]),
      id: id ?? this.id,
      date: date ?? this.date,
      amount: amount ?? this.amount,
      isDebit: isDebit ?? this.isDebit,
      isSMS: isSMS ?? this.isSMS,
    );
  }

  static List<Expense> listFromRawJson(String str) {
    final jsonRes = json.decode(str) as Map<String, dynamic>;
    final list = List<dynamic>.from(jsonRes['expenses'] as List? ?? const []);
    return List<Expense>.from(
      list.map((item) => Expense.fromJson(Map<String, dynamic>.from(item as Map))),
    );
  }

  static List<Map<String, dynamic>> listToJson(List<Expense> list) {
    return List<Map<String, dynamic>>.from(
      list.map((item) => item.toJson()),
    );
  }

  static String toCSVString(List<Expense> expenses) {
    final rows = <List<dynamic>>[
      csvHeaders,
      ...expenses.map((expense) {
        return <dynamic>[
          expense.name ?? "",
          normalizeTags(expense.label).join("|"),
          expense.id ?? "",
          expense.date ?? "",
          expense.amount ?? "",
          (expense.isDebit ?? true).toString(),
          expense.isSMS.toString(),
        ];
      }),
    ];
    return csv.encode(rows);
  }

  static List<Expense> fromCSVString(String csvString) {
    final rows = csv.decode(csvString);
    if (rows.isEmpty) {
      return <Expense>[];
    }

    final headers =
        rows.first.map((value) => value.toString().trim()).toList(growable: false);
    final hasIdColumn = _matchesHeaders(headers, csvHeaders);
    if (!hasIdColumn && !_matchesHeaders(headers, csvHeadersWithoutId)) {
      throw const FormatException("File is not-supported");
    }

    final usedIds = <String>{};

    return List<Expense>.from(rows.skip(1).map((row) {
      final rawDate = _requiredCell(row, headers, "date");
      final rawId = hasIdColumn ? _trimmedCell(row, headers, "id") : "";
      final resolvedId =
          rawId.isEmpty ? getIdFromDate(rawDate, usedIds) : _reserveUniqueId(rawId, usedIds);

      return Expense(
        name: _requiredCell(row, headers, "name"),
        label: _decodeCsvLabels(_trimmedCell(row, headers, "label")),
        id: resolvedId,
        date: rawDate,
        amount: _requiredCell(row, headers, "amount"),
        isDebit: _parseBool(_trimmedCell(row, headers, "isDebit"), defaultValue: true),
        isSMS: _parseBool(_trimmedCell(row, headers, "isSMS"), defaultValue: false),
      );
    }));
  }

  static String getIdFromDate(String date, Set<String> usedIds) {
    final parsedDate = DateTime.parse(date);
    var candidate = parsedDate.millisecondsSinceEpoch.toString();
    while (usedIds.contains(candidate)) {
      candidate = (int.parse(candidate) + 1).toString();
    }
    usedIds.add(candidate);
    return candidate;
  }

  static bool _matchesHeaders(List<String> actual, List<String> expected) {
    if (actual.length != expected.length) {
      return false;
    }
    for (int index = 0; index < expected.length; index++) {
      if (actual[index] != expected[index]) {
        return false;
      }
    }
    return true;
  }

  static String _trimmedCell(List<dynamic> row, List<String> headers, String key) {
    final index = headers.indexOf(key);
    if (index == -1 || index >= row.length) {
      return "";
    }
    return row[index].toString().trim();
  }

  static String _requiredCell(List<dynamic> row, List<String> headers, String key) {
    final value = _trimmedCell(row, headers, key);
    if (value.isEmpty) {
      throw const FormatException("File is not-supported");
    }
    return value;
  }

  static String _reserveUniqueId(String preferredId, Set<String> usedIds) {
    var candidate = preferredId;
    while (usedIds.contains(candidate)) {
      final parsed = int.tryParse(candidate);
      candidate =
          parsed == null ? "${preferredId}_${usedIds.length + 1}" : (parsed + 1).toString();
    }
    usedIds.add(candidate);
    return candidate;
  }

  static List<String> _decodeCsvLabels(String value) {
    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty) {
      return <String>[];
    }
    if (trimmedValue.startsWith("[") && trimmedValue.endsWith("]")) {
      return normalizeTags(List<String>.from(jsonDecode(trimmedValue) as List));
    }
    return normalizeTags(trimmedValue.split("|"));
  }

  static bool _parseBool(String value, {required bool defaultValue}) {
    if (value.isEmpty) {
      return defaultValue;
    }
    final normalized = value.toLowerCase();
    if (normalized == "true") {
      return true;
    }
    if (normalized == "false") {
      return false;
    }
    throw const FormatException("File is not-supported");
  }

  String getMonthYear() {
    return DateFormat.yMMMM().format(DateTime.parse(date!));
  }
}
