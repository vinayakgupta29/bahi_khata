import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import 'package:personal_bahi_khata/util/constants.dart';
import 'package:personal_bahi_khata/data/database.dart';
import 'package:personal_bahi_khata/data/expenses.dart';
import 'package:personal_bahi_khata/data/pbke_file.dart';
import 'package:personal_bahi_khata/data/telephony_service.dart';
import 'package:personal_bahi_khata/data/sms_api.dart';
import 'package:personal_bahi_khata/main.dart';
import 'package:personal_bahi_khata/presentation/add_payment.dart';
import 'package:personal_bahi_khata/presentation/edit_page.dart';
import 'package:personal_bahi_khata/presentation/private_feature.dart';
import 'package:personal_bahi_khata/presentation/searchpage.dart';
import 'package:personal_bahi_khata/presentation/splash_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  var tags = ["Food", "TRANSPORT", "Fast Food", "Donation", "Travel", "Other"];
  List<Expense> _foundExpense = [];
  List<Widget> widgets = [];
  File? file;
  bool _showAddPaymentPane = false;
  // text controller
  String json = """[
    
  {
    "name": "Expense1",
    "label": null,
    "id": "1641345460000",
    "date": "2023-01-01T00:00:00.000Z",
    "amount": "100",
    "isDebit": true
  },
  {
    "name": "Expense2",
    "label": null,
    "id": "1642246460000",
    "date": "2023-01-15T00:00:00.000Z",
    "amount": "150",
    "isDebit": false
  },
  {
    "name": "Expense3",
    "label": null,
    "id": "1643751060000",
    "date": "2023-02-02T00:00:00.000Z",
    "amount": "80",
    "isDebit": true
  },
  {
    "name": "Expense4",
    "label": null,
    "id": "1645395260000",
    "date": "2023-02-20T00:00:00.000Z",
    "amount": "120",
    "isDebit": false
  },
  {
    "name": "Expense5",
    "label": null,
    "id": "1646549460000",
    "date": "2023-03-05T00:00:00.000Z",
    "amount": "200",
    "isDebit": true
  },
  {
    "name": "Expense6",
    "label": null,
    "id": "1647747060000",
    "date": "2023-03-18T00:00:00.000Z",
    "amount": "90",
    "isDebit": false
  },
  {
    "name": "Expense7",
    "label": null,
    "id": "1649107260000",
    "date": "2023-04-10T00:00:00.000Z",
    "amount": "180",
    "isDebit": true
  },
  {
    "name": "Expense8",
    "label": null,
    "id": "1650015060000",
    "date": "2023-04-25T00:00:00.000Z",
    "amount": "130",
    "isDebit": false
  },
  {
    "name": "Expense9",
    "label": null,
    "id": "1651403860000",
    "date": "2023-05-08T00:00:00.000Z",
    "amount": "160",
    "isDebit": true
  },
  {
    "name": "Expense10",
    "label": null,
    "id": "1652305460000",
    "date": "2023-05-22T00:00:00.000Z",
    "amount": "110",
    "isDebit": false
  },{
    "name":"expense11",
    "label":"",
    "id":"001",
    "date":"2024-01-07T00:00:00.000Z",
    "amount":"15",
    "isDebit":true
  },{
    "name":"expense12",
    "label":"",
    "id":"002",
    "date":"2024-01-08T00:00:00.000Z",
    "amount":"75",
    "isDebit":true
  }
]
""";

  // delete task
  void deleteExpense(String id) {
    setState(() {
      DataBase.expenses.removeWhere((item) => item.id == id);
    });
    DataBase.persistCurrentExpenses();
    debugPrint(DataBase.expenses.toString());
    setState(() {
      expenseNotifier.update(DataBase.expenses);
    });
  }

  requestStoragePermission() async {
    bool isGranted = await Permission.storage.isGranted;
    if (!isGranted && mounted) {
      await Permission.storage.request();
    }
    var status = await Permission.accessMediaLocation.status;

    if (status == PermissionStatus.granted && mounted) {
      setState(() {
        DataBase.isPermitted = true;
      });
    } else {
      setState(() {
        DataBase.isPermitted = false;
      });
      openAppSettings();
    }
  }

  void _syncLocalExpenseState() {
    List<String> allTags = [];
    DataBase.uniqueyears.clear();
    for (Expense obj in DataBase.expenses) {
      if (obj.date != null) {
        DataBase.uniqueyears.add(DateTime.parse(obj.date!).year);
      }
      if (obj.label != null) {
        allTags.addAll(obj.label!);
      }
    }
    DataBase.uniqueTags = Set<String>.from(allTags);
    expenseNotifier.update(List<Expense>.from(DataBase.expenses));
  }

  Future<void> _showMessageDialog(String title, String message) async {
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: bgcolor,
            title: Text(title, style: const TextStyle(color: textcolor)),
            content: Text(message, style: const TextStyle(color: textcolor)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("OK"),
              ),
            ],
          ),
    );
  }

  Future<bool> _showDuplicateImportDialog(
    Expense incoming,
    Expense existing,
  ) async {
    if (!mounted) {
      return false;
    }

    final labels =
        (incoming.label ?? const <String>[]).isEmpty
            ? "-"
            : incoming.label!.join(", ");

    return await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                backgroundColor: bgcolor,
                title: const Text(
                  "Duplicate Expense",
                  style: TextStyle(color: textcolor),
                ),
                content: Text(
                  "A matching expense already exists.\n\n"
                  "Name: ${incoming.name ?? "-"}\n"
                  "Amount: ${incoming.amount ?? "-"}\n"
                  "Date: ${incoming.date ?? "-"}\n"
                  "Labels: $labels\n\n"
                  "Add it anyway with a new id?",
                  style: const TextStyle(color: textcolor),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text("Skip"),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text("Add"),
                  ),
                ],
              ),
        ) ??
        false;
  }

  Future<String?> _showFormatDialog(String title) async {
    if (!mounted) {
      return null;
    }

    return showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: bgcolor,
            title: Text(title, style: const TextStyle(color: textcolor)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text("PBKE", style: TextStyle(color: textcolor)),
                  onTap: () => Navigator.of(context).pop("pbke"),
                ),
                ListTile(
                  title: const Text("JSON", style: TextStyle(color: textcolor)),
                  onTap: () => Navigator.of(context).pop("json"),
                ),
                ListTile(
                  title: const Text("CSV", style: TextStyle(color: textcolor)),
                  onTap: () => Navigator.of(context).pop("csv"),
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _openSearch() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => SearchPage(
              onPopCallback: () {
                setState(() {});
              },
            ),
      ),
    );
  }

  bool _isLandscapeTablet(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    debugPrint("${mediaQuery.size.height}, ${mediaQuery.size.width}");
    return mediaQuery.orientation == Orientation.landscape &&
        mediaQuery.size.width >= 840;
  }

  void _openAddPayment({required bool inPane}) {
    if (inPane) {
      setState(() {
        _showAddPaymentPane = true;
      });
      return;
    }

    Navigator.push(context, _createAddPaymentRoute());
  }

  void _closeAddPaymentPane() {
    if (!mounted) {
      return;
    }

    setState(() {
      _showAddPaymentPane = false;
    });
  }

  Future<void> _importExpenses() async {
    final selectedFormat = await _showFormatDialog("Import");
    if (selectedFormat == null) {
      return;
    }

    final result = await FilePicker.pickFiles(type: FileType.any);

    if (result == null || result.files.single.path == null) {
      return;
    }

    final pickedPath = result.files.single.path!;
    if (DataBase.getFileExtension(pickedPath) != selectedFormat) {
      await _showMessageDialog("Import", DataBase.unsupportedFileTypeMessage);
      return;
    }

    try {
      await DataBase.importExpensesFromFile(
        pickedPath,
        onDuplicate: (incoming, existing) {
          return _showDuplicateImportDialog(incoming, existing);
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _syncLocalExpenseState();
      });
    } catch (e, st) {
      debugPrint("[IMPORT-UI] Import failed for $pickedPath: $e");
      debugPrintStack(label: "[IMPORT-UI] stack", stackTrace: st);
      final message =
          e is FormatException ? e.message : DataBase.unsupportedFileMessage;
      await _showMessageDialog("Import", message);
    }
  }

  Future<void> _exportExpenses() async {
    final selectedFormat = await _showFormatDialog("Export");
    if (selectedFormat == null) {
      return;
    }

    try {
      final exportedFile = await DataBase.exportExpensesFile(selectedFormat);
      if (Platform.isLinux) {
        await _showMessageDialog("Export", "Exported to ${exportedFile.path}");
        return;
      }

      final mimeType =
          selectedFormat == "csv"
              ? "text/csv"
              : selectedFormat == "json"
              ? "application/json"
              : PbkeFile.mimeType;

      await SharePlus.instance.share(
        ShareParams(files: [XFile(exportedFile.path, mimeType: mimeType)]),
      );
    } catch (e) {
      final message =
          e is FormatException ? e.message : DataBase.unsupportedFileMessage;
      await _showMessageDialog("Export", message);
    }
  }

  Future<void> _toggleSmsExpenses(bool enabled) async {
    try {
      if (Platform.isAndroid) {
        if (enabled) {
          final hasPermission = await SmsApi.ensureSmsPermission();
          if (!hasPermission) {
            await _showMessageDialog(
              "SMS",
              "SMS permission is required to enable SMS expenses",
            );
            return;
          }
        }

        await DataBase.setSmsExpensesEnabled(enabled);
        _syncLocalExpenseState();

        if (enabled) {
          await SmsApi.filterSms();
          _syncLocalExpenseState();
        }
      } else {
        await _showMessageDialog("SMS", "This is an android Specific Feature");
      }
    } catch (e) {
      final message =
          e is FormatException ? DataBase.unsupportedFileMessage : e.toString();
      await _showMessageDialog("SMS", message);
    }
  }

  @override
  void initState() {
    DataBase.loadExpenses().then((value) {
      setState(() {
        json = value;
        debugPrint(json);
        DataBase.expenses = Expense.listFromRawJson(json);
        _syncLocalExpenseState();
      });
      if (Platform.isAndroid && DataBase.smsExpensesEnabled) {
        TelephonyService().isTelephonyAvailable().then((val) {
          SmsApi.filterSms().then((_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _syncLocalExpenseState();
            });
          });
        });
      }
    });

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(" is lanscape ${_isLandscapeTablet(context)}");
    return StreamBuilder<List<Expense>>(
      stream: expenseNotifier.stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }
        _foundExpense = snapshot.data ?? [];
        debugPrint("found length ${DataBase.expenses.length}");
        _foundExpense.sort((a, b) {
          DateTime dateA = DateTime.parse(a.date!);
          DateTime dateB = DateTime.parse(b.date!);
          return dateB.compareTo(dateA);
        });
        var filterObjects =
            _foundExpense.where((obj) {
              // Return true if all tags in the object's list are contained within DB.selectedTags
              return ((DataBase.selectedTags.isNotEmpty
                      ? obj.label?.any(
                            (tag) => DataBase.selectedTags.contains(tag),
                          ) ??
                          true
                      : true) &&
                  (dateFilter(obj)));
            }).toList();
        debugPrint("selected ${DataBase.selectedTags} filter $filterObjects");
        // // Group objects by month and year
        Map<String, List<Expense>> groupedObjects = {};
        for (Expense obj in filterObjects) {
          String monthYear = obj.getMonthYear();
          if (!groupedObjects.containsKey(monthYear)) {
            groupedObjects[monthYear] = [];
          }
          groupedObjects[monthYear]!.add(obj);
        }
        // // Create a list of widgets for ListView.builder
        // double sum = 0;
        // groupedObjects.forEach((monthYear, objects) {
        //   for (var obj in objects) {
        //     obj.isDebit ?? true
        //         ? sum -= double.parse(obj.amount ?? "0")
        //         : sum += double.parse(obj.amount ?? "0");
        //   }

        //   widgets.add(
        //     Container(
        //       color: bgcolor,
        //       child: Column(
        //         crossAxisAlignment: CrossAxisAlignment.start,
        //         children: [
        //           // Header with month and year
        //           Row(
        //             children: [
        //               Text(
        //                 monthYear,
        //                 style: const TextStyle(
        //                     fontSize: 20,
        //                     fontWeight: FontWeight.bold,
        //                     color: textcolor),
        //               ),
        //               const Spacer(),
        //               Padding(
        //                 padding: const EdgeInsets.only(right: 8.0),
        //                 child: Text(
        //                   sum.toString(),
        //                   style: const TextStyle(
        //                       fontSize: 20,
        //                       fontWeight: FontWeight.bold,
        //                       color: textcolor),
        //                 ),
        //               )
        //             ],
        //           ),
        //           const Divider(
        //             thickness: 0.5,
        //           ),
        //           // List of items for that month and year
        //           for (Expense obj in objects)
        //             ListTile(
        //               key: Key(obj.id ?? ""),
        //               tileColor: itemcolor,
        //               title: Text(
        //                 obj.name ?? "hi",
        //                 style: const TextStyle(color: textcolor),
        //               ),
        //               subtitle: Text(
        //                 DateFormat.yMEd().format(
        //                   DateTime.parse(obj.date!),
        //                 ),
        //                 style: const TextStyle(color: textcolor),
        //               ),
        //               trailing: Text(
        //                 (obj.isDebit ?? false ? "- " : "+ ") +
        //                     (obj.amount ?? "N/A"),
        //                 style: TextStyle(
        //                     fontSize: 20,
        //                     fontWeight: FontWeight.w900,
        //                     color:
        //                         (obj.isDebit ?? false) ? Colors.red : Colors.green),
        //               ),
        //             ),
        //           // Divider between months
        //           const Divider(
        //             thickness: 2,
        //           ),
        //         ],
        //       ),
        //     ),
        //   );
        // });

        return Scaffold(
          backgroundColor: bgcolor,
          drawer: Drawer(
            backgroundColor: bgcolor,
            child: SafeArea(
              child: ListView(
                children: [
                  const DrawerHeader(
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Text(
                        "Personal Bahi Khata",
                        style: TextStyle(
                          color: textcolor,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.file_upload_outlined,
                      color: Colors.white,
                    ),
                    title: const Text(
                      "Import",
                      style: TextStyle(color: textcolor),
                    ),
                    onTap: () async {
                      Navigator.of(context).pop();
                      await _importExpenses();
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.file_download_outlined,
                      color: Colors.white,
                    ),
                    title: const Text(
                      "Export",
                      style: TextStyle(color: textcolor),
                    ),
                    onTap: () async {
                      Navigator.of(context).pop();
                      await _exportExpenses();
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.search_outlined,
                      color: Colors.white,
                    ),
                    title: const Text(
                      "Search",
                      style: TextStyle(color: textcolor),
                    ),
                    onTap: () async {
                      Navigator.of(context).pop();
                      await _openSearch();
                    },
                  ),
                  const PrivateFeatureTile(),
                  Platform.isAndroid
                      ? SwitchListTile(
                        activeThumbColor: Colors.green,
                        title: const Text(
                          "SMS Expenses",
                          style: TextStyle(color: textcolor),
                        ),
                        subtitle: const Text(
                          "Enable or remove SMS-based expenses",
                          style: TextStyle(color: hintcol),
                        ),
                        value: DataBase.smsExpensesEnabled,
                        onChanged: (value) async {
                          Navigator.of(context).pop();
                          await _toggleSmsExpenses(value);
                        },
                      )
                      : Container(),
                ],
              ),
            ),
          ),
          appBar: AppBar(
            title: const Text(
              "Expenses",
              style: TextStyle(
                color: textcolor,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            elevation: 10,
            actions: [
              IconButton(
                onPressed: _importExpenses,
                icon: const Icon(
                  Icons.file_upload_outlined,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              IconButton(
                onPressed: _exportExpenses,
                icon: const Icon(
                  Icons.file_download_outlined,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              IconButton(
                onPressed: () {
                  _openSearch();
                },
                icon: const Icon(
                  Icons.search_outlined,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final expensesList = Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: groupedObjects.length * 2, // *2 for dividers
                        itemBuilder: (context, index) {
                          if (index.isOdd) {
                            // Divider
                            return Container(height: 0.000005);
                          }

                          // Header or List Item
                          int headerIndex = index ~/ 2;
                          String monthYear = groupedObjects.keys.elementAt(
                            headerIndex,
                          );
                          List<Expense> objects = groupedObjects[monthYear]!;

                          double sum = 0;
                          for (var obj in objects) {
                            obj.isDebit ?? true
                                ? sum -= (double.parse(obj.amount ?? "0") * 100)
                                : sum +=
                                    (double.parse(obj.amount ?? "0") * 100);
                          }
                          sum /= 100;
                          return Container(
                            color: bgcolor,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header with month and year
                                SizedBox(
                                  height: 50,
                                  width: double.infinity,
                                  child: Card(
                                    color: headerColor,
                                    elevation: 10,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Row(
                                        children: [
                                          Text(
                                            monthYear,
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: textcolor,
                                            ),
                                          ),
                                          const Spacer(),
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: 8.0,
                                            ),
                                            child: Text(
                                              sum.toString(),
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color:
                                                    sum >= 0
                                                        ? Colors.green
                                                        : Colors.red,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                // const Divider(
                                //   thickness: 0.5,
                                // ),
                                // List of items for that month and year
                                for (Expense obj in objects)
                                  Column(
                                    key: ValueKey(
                                      "expense-${DataBase.expenseIdentity(obj)}",
                                    ),
                                    children: [
                                      Slidable(
                                        key: ValueKey(
                                          "slidable-${DataBase.expenseIdentity(obj)}",
                                        ),
                                        endActionPane: ActionPane(
                                          motion: const StretchMotion(),
                                          children: [
                                            SlidableAction(
                                              onPressed:
                                                  (context) => deleteExpense(
                                                    obj.id ?? "",
                                                  ),
                                              label: "DELETE",
                                              backgroundColor: Colors.red,
                                            ),
                                          ],
                                        ),
                                        startActionPane: ActionPane(
                                          motion: const StretchMotion(),
                                          children: [
                                            SlidableAction(
                                              onPressed:
                                                  (context) => Navigator.of(
                                                    context,
                                                  ).push(_createEditRoute(obj)),
                                              label: "EDIT",
                                              backgroundColor: Colors.blue,
                                            ),
                                          ],
                                        ),
                                        child: ListTile(
                                          tileColor: itemcolor,
                                          title: Text(
                                            obj.name ?? "hi",
                                            style: const TextStyle(
                                              color: textcolor,
                                            ),
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                DateFormat(
                                                  'E dd/MM/yyyy',
                                                ).format(
                                                  DateTime.parse(obj.date!),
                                                ),
                                                style: const TextStyle(
                                                  color: textcolor,
                                                ),
                                              ),
                                              SizedBox(
                                                height: 50,
                                                width: double.infinity,
                                                child: ListView.builder(
                                                  shrinkWrap: true,
                                                  scrollDirection:
                                                      Axis.horizontal,
                                                  itemCount:
                                                      obj.label?.length ?? 0,
                                                  itemBuilder:
                                                      (context, ind) => Padding(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8.0,
                                                            ),
                                                        child: Chip(
                                                          labelStyle:
                                                              const TextStyle(
                                                                fontSize: 12,
                                                              ),
                                                          label: Text(
                                                            obj.label?[ind] ??
                                                                "hi",
                                                          ),
                                                        ),
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          trailing: Text(
                                            (obj.isDebit ?? false
                                                    ? "- "
                                                    : "+ ") +
                                                (obj.amount ?? "N/A"),
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w900,
                                              color:
                                                  (obj.isDebit ?? false)
                                                      ? Colors.red
                                                      : Colors.green,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const Divider(color: hintcol),
                                    ],
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );

                final showAddPaymentPane =
                    _showAddPaymentPane && _isLandscapeTablet(context);
                if (!showAddPaymentPane) {
                  return expensesList;
                }

                final paneWidth = (constraints.maxWidth * 0.5).clamp(
                  360.0,
                  480.0,
                );

                return Row(
                  children: [
                    Expanded(child: expensesList),
                    const VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: Colors.white12,
                    ),
                    SizedBox(
                      width: paneWidth,
                      child: AddPaymentPage(
                        embedded: true,
                        onClose: _closeAddPaymentPane,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // ListView.builder(
          //     itemCount: _foundExpense.length,
          //     itemBuilder: (context, ind) {
          //       return
          //     }),
          floatingActionButton:
              _showAddPaymentPane && _isLandscapeTablet(context)
                  ? null
                  : Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).size.height * 0.07,
                      right: 10,
                    ),
                    child: FloatingActionButton(
                      backgroundColor: floatingButtonColor,
                      onPressed: () {
                        _openAddPayment(inPane: _isLandscapeTablet(context));
                      },
                      child: const Icon(Icons.add, color: buttonTextColor),
                    ),
                  ),
        );
      },
    );
  }

  bool dateFilter(Expense obj) {
    if (DataBase.selectedDate != null) {
      var selectedDate = DataBase.selectedDate;
      DateTime date = DateTime.parse(obj.date!);
      return (date.year == selectedDate?.year) &&
          (date.month == selectedDate?.month);
    } else {
      return true;
    }
  }

  Route _createAddPaymentRoute() {
    return PageRouteBuilder(
      pageBuilder:
          (context, animation, secondaryAnimation) => const AddPaymentPage(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.8, 0.8);
        const end = Offset.zero;
        const curve = Curves.fastEaseInToSlowEaseOut;
        var tween = Tween(
          begin: begin,
          end: end,
        ).chain(CurveTween(curve: curve));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }

  Route _createEditRoute(Expense expense) {
    return PageRouteBuilder(
      pageBuilder:
          (context, animation, secondaryAnimation) =>
              EditPage(expense: expense),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0); // Start from the right
        const end = Offset.zero; // End at the center
        const curve = Curves.easeInOut;

        // Create a tween animation
        var tween = Tween(
          begin: begin,
          end: end,
        ).chain(CurveTween(curve: curve));
        var offsetAnimation = animation.drive(tween);

        // Use SlideTransition to animate the transition
        return SlideTransition(position: offsetAnimation, child: child);
      },
    );
  }
}
