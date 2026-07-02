import 'package:personal_bahi_khata/data/expenses.dart';

/// Hash-based import merge helpers.
///
/// Why this approach:
/// - Duplicate lookup needs to be fast while importing many rows.
/// - A hash map gives average O(1) lookup per expense.
/// - Building the index is O(n) for existing expenses.
/// - Processing imported expenses is O(m).
/// - Total duplicate detection cost is O(n + m), which is the fastest practical
///   approach here because we avoid nested scans.
///
/// Sorting:
/// - We keep using Dart's built-in [List.sort] in the database layer.
/// - That is already the optimized platform/library sort available to us, so we
///   do not replace it with a custom slower implementation.
///
/// Duplicate rules:
/// - "Real duplicate": same normalized content key
///   (name + labels + date + amount + debit/sms flags).
///   These require a user decision.
/// - "ID collision only": same id, different content.
///   These are auto-resolved by assigning a new incremental id.

typedef DuplicateDecision =
    Future<bool> Function(Expense incoming, Expense existing);

class ImportMergeResult {
  const ImportMergeResult(this.expenses);

  final List<Expense> expenses;
}

class IncrementalIdAllocator {
  IncrementalIdAllocator(Iterable<String?> ids) {
    for (final rawId in ids) {
      final id = rawId?.trim();
      if (id == null || id.isEmpty) {
        continue;
      }
      _usedIds.add(id);
      final numericId = int.tryParse(id);
      if (numericId != null && numericId > _maxNumericId) {
        _maxNumericId = numericId;
      }
    }
  }

  final Set<String> _usedIds = <String>{};
  int _maxNumericId = 0;

  bool contains(String? id) {
    final trimmed = id?.trim();
    return trimmed != null && trimmed.isNotEmpty && _usedIds.contains(trimmed);
  }

  void reserve(String? id) {
    final trimmed = id?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return;
    }
    _usedIds.add(trimmed);
    final numericId = int.tryParse(trimmed);
    if (numericId != null && numericId > _maxNumericId) {
      _maxNumericId = numericId;
    }
  }

  String nextId() {
    do {
      _maxNumericId++;
    } while (_usedIds.contains(_maxNumericId.toString()));
    final next = _maxNumericId.toString();
    _usedIds.add(next);
    return next;
  }
}

class ImportMatching {
  static String contentKey(Expense expense) {
    final normalizedLabels =
        List<String>.from(expense.label ?? const <String>[])
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [
      expense.name?.trim().toLowerCase() ?? "",
      normalizedLabels.map((label) => label.trim().toLowerCase()).join("|"),
      expense.date?.trim() ?? "",
      expense.amount?.trim() ?? "",
      (expense.isDebit ?? true).toString(),
      expense.isSMS.toString(),
    ].join("||");
  }

  static Future<ImportMergeResult> mergeExpenses({
    required List<Expense> existingExpenses,
    required List<Expense> importedExpenses,
    DuplicateDecision? onDuplicate,
  }) async {
    final mergedExpenses = List<Expense>.from(existingExpenses);
    final idAllocator = IncrementalIdAllocator(
      mergedExpenses.map((expense) => expense.id),
    );
    final contentIndex = <String, Expense>{};

    for (final expense in mergedExpenses) {
      contentIndex[contentKey(expense)] = expense;
    }

    for (final importedExpense in importedExpenses) {
      final duplicateKey = contentKey(importedExpense);
      final duplicateExpense = contentIndex[duplicateKey];

      if (duplicateExpense != null) {
        final shouldAdd =
            onDuplicate == null
                ? false
                : await onDuplicate(importedExpense, duplicateExpense);
        if (!shouldAdd) {
          continue;
        }

        final duplicatedExpense = importedExpense.copyWith(
          id: idAllocator.nextId(),
        );
        mergedExpenses.add(duplicatedExpense);
        contentIndex[contentKey(duplicatedExpense)] = duplicatedExpense;
        continue;
      }

      Expense normalizedExpense = importedExpense;
      final incomingId = importedExpense.id?.trim();
      if (incomingId == null || incomingId.isEmpty) {
        normalizedExpense = importedExpense.copyWith(id: idAllocator.nextId());
      } else if (idAllocator.contains(importedExpense.id)) {
        normalizedExpense = importedExpense.copyWith(id: idAllocator.nextId());
      } else {
        idAllocator.reserve(importedExpense.id);
      }

      mergedExpenses.add(normalizedExpense);
      contentIndex[contentKey(normalizedExpense)] = normalizedExpense;
    }

    return ImportMergeResult(mergedExpenses);
  }
}
