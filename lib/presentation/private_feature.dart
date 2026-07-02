import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:personal_bahi_khata/data/database.dart';
import 'package:personal_bahi_khata/util/constants.dart';
import 'package:personal_bahi_khata/util/tag_utils.dart';
import 'package:share_plus/share_plus.dart';

class _PrivateExportSelection {
  const _PrivateExportSelection({
    required this.month,
    required this.selectedTags,
  });

  final DateTime month;
  final Set<String> selectedTags;
}

class PrivateFeatureTile extends StatelessWidget {
  const PrivateFeatureTile({super.key});

  static bool isPrime(int value) {
    if (value < 2) {
      return false;
    }
    for (int i = 2; i * i <= value; i++) {
      if (value % i == 0) {
        return false;
      }
    }
    return true;
  }

  Future<void> _showMessageDialog(
    BuildContext context,
    String title,
    String message,
  ) async {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              backgroundColor: bgcolor,
              title: Text(title, style: const TextStyle(color: textcolor)),
              content: Text(message, style: const TextStyle(color: textcolor)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text("OK"),
                ),
              ],
            ),
      );
    }
  }

  Future<bool> _unlockPrivateExport(BuildContext context) async {
    final controller = TextEditingController();
    final enteredPassword = await showDialog<String>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            backgroundColor: bgcolor,
            title: const Text(
              "Private Export",
              style: TextStyle(color: textcolor),
            ),
            content: TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              style: const TextStyle(color: textcolor),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: "Enter password",
                hintStyle: TextStyle(color: hintcol),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(controller.text);
                },
                child: const Text("Unlock"),
              ),
            ],
        ),
    );
    controller.dispose();
    return isPrime(int.tryParse(enteredPassword?.trim() ?? "") ?? 0);
  }

  Future<_PrivateExportSelection?> _pickMonth(BuildContext context) async {
    final availableYears = DataBase.uniqueyears.toList()..sort();
    if (availableYears.isEmpty) {
      availableYears.add(DateTime.now().year);
    }
    int selectedMonth = DateTime.now().month;
    int selectedYear = availableYears.last;
    final selectedTags = <String>{};
    final availableTags = DataBase.uniqueTags.toList()..sort();

    return showDialog<_PrivateExportSelection>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (dialogContext, setDialogState) => AlertDialog(
                  backgroundColor: bgcolor,
                  title: const Text(
                    "Select Month",
                    style: TextStyle(color: textcolor),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          DropdownButton<int>(
                            value: selectedMonth,
                            elevation: 16,
                            style: const TextStyle(color: Colors.white),
                            underline: Container(height: 2, color: Colors.indigo),
                            dropdownColor: bgcolor,
                            menuMaxHeight: 300,
                            onChanged: (int? value) {
                              setDialogState(() {
                                selectedMonth = value ?? 1;
                              });
                            },
                            items: const [
                              DropdownMenuItem<int>(value: 1, child: Text("January")),
                              DropdownMenuItem<int>(value: 2, child: Text("February")),
                              DropdownMenuItem<int>(value: 3, child: Text("March")),
                              DropdownMenuItem<int>(value: 4, child: Text("April")),
                              DropdownMenuItem<int>(value: 5, child: Text("May")),
                              DropdownMenuItem<int>(value: 6, child: Text("June")),
                              DropdownMenuItem<int>(value: 7, child: Text("July")),
                              DropdownMenuItem<int>(value: 8, child: Text("August")),
                              DropdownMenuItem<int>(value: 9, child: Text("September")),
                              DropdownMenuItem<int>(value: 10, child: Text("October")),
                              DropdownMenuItem<int>(value: 11, child: Text("November")),
                              DropdownMenuItem<int>(value: 12, child: Text("December")),
                            ],
                          ),
                          DropdownButton<int>(
                            value: selectedYear,
                            elevation: 16,
                            style: const TextStyle(color: Colors.white),
                            underline: Container(height: 2, color: Colors.indigo),
                            dropdownColor: bgcolor,
                            menuMaxHeight: 300,
                            items:
                                availableYears
                                    .map(
                                      (year) => DropdownMenuItem<int>(
                                        value: year,
                                        child: Text(year.toString()),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (int? value) {
                              setDialogState(() {
                                selectedYear = value ?? selectedYear;
                              });
                            },
                          ),
                        ],
                      ),
                      if (availableTags.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "FILTER TAGS",
                            style: TextStyle(
                              color: textcolor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 140,
                          child: SingleChildScrollView(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children:
                                  availableTags.map((tag) {
                                    final normalizedTag = normalizeTag(tag);
                                    return FilterChip(
                                      label: Text(normalizedTag),
                                      selected: selectedTags.contains(normalizedTag),
                                      onSelected: (selected) {
                                        setDialogState(() {
                                          if (selected) {
                                            selectedTags.add(normalizedTag);
                                          } else {
                                            selectedTags.remove(normalizedTag);
                                          }
                                        });
                                      },
                                    );
                                  }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text("Cancel"),
                    ),
                    TextButton(
                      onPressed:
                          () => Navigator.of(
                            dialogContext,
                          ).pop(
                            _PrivateExportSelection(
                              month: DateTime(selectedYear, selectedMonth),
                              selectedTags: Set<String>.from(selectedTags),
                            ),
                          ),
                      child: const Text("Export"),
                    ),
                  ],
                ),
          ),
    );
  }

  Future<void> _handlePrivateExport(BuildContext context) async {
    final isUnlocked = await _unlockPrivateExport(context);
    if (!isUnlocked) {
      if (context.mounted) {
        await _showMessageDialog(
          context,
          "Private Export",
          "Incorrect password",
        );
      }
      return;
    }

    final selection = await _pickMonth(context);
    if (selection == null) {
      return;
    }

    try {
      final exportedFile = await DataBase.exportPrivateMonthlyCsvFileWithTags(
        selection.month,
        selectedTags: selection.selectedTags,
      );
      final monthLabel = DateFormat("MMMM yyyy").format(selection.month);

      if (Platform.isLinux) {
        if (context.mounted) {
          await _showMessageDialog(
            context,
            "Private Export",
            "$monthLabel exported to ${exportedFile.path}",
          );
        }
        return;
      }

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(exportedFile.path, mimeType: "text/csv")],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        final message =
            e is FormatException ? e.message : DataBase.unsupportedFileMessage;
        await _showMessageDialog(context, "Private Export", message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.lock_outline, color: Colors.white),
      title: const Text("Private Export", style: TextStyle(color: textcolor)),
      subtitle: const Text(
        "Locked monthly CSV export",
        style: TextStyle(color: hintcol),
      ),
      onTap: () async {
        final rootContext = Navigator.of(context, rootNavigator: true).context;
        Navigator.of(context).pop();
        if (rootContext.mounted) {
          await _handlePrivateExport(rootContext);
        }
      },
    );
  }
}
