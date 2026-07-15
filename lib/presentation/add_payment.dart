import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:personal_bahi_khata/data/database.dart';
import 'package:personal_bahi_khata/data/expenses.dart';
import 'package:personal_bahi_khata/main.dart';
import 'package:personal_bahi_khata/util/constants.dart';
import 'package:personal_bahi_khata/util/tag_utils.dart';

class AddPaymentPage extends StatefulWidget {
  const AddPaymentPage({super.key, this.onClose, this.embedded = false});

  final VoidCallback? onClose;
  final bool embedded;

  @override
  State<AddPaymentPage> createState() => _AddPaymentPageState();
}

class _AddPaymentPageState extends State<AddPaymentPage>
    with TickerProviderStateMixin {
  var tags = List<String>.from(defaultTags);
  List<String> selectedTags = [];
  final List<Expense> _foundExpense = [];
  final _titlecontroller = TextEditingController();
  final _amountController = TextEditingController();
  bool _isDebit = true;
  DateTime now = DateTime.now();
  DateTime _selectedDate = DateTime.now();

  bool _validate = false;

  late TextEditingController _selectedTagController;

  late Animation _creditAnimation;
  late Animation _debitAnimation;

  late AnimationController _creditAnimationController;
  late AnimationController _debitAnimationController;

  InputDecoration _fieldDecoration({required String label, String? errorText}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: hintcol),
      errorText: errorText,
      filled: true,
      fillColor: itemcolor,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: floatingButtonColor, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
      ),
    );
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(2200),
      initialDate: _selectedDate,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: floatingButtonColor,
              onPrimary: buttonTextColor,
              surface: bgcolor,
              onSurface: textcolor,
            ),
            dialogTheme: const DialogThemeData(backgroundColor: bgcolor),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }
  // checkbox was tapped
  // void checkBoxChanged(Expense exp) {
  //   setState(() {
  //     exp.isDebit = !(exp.isDebit ?? false);
  //   });
  //   db.updateDatabase();
  // }

  // save new task
  void saveNewExpense() {
    setState(() {
      DataBase.expenses.add(
        Expense(
          name: _titlecontroller.text,
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          date: _selectedDate.toIso8601String(),
          amount: double.parse(_amountController.text).toString(),
          label: normalizeTags(selectedTags),
          isDebit: _isDebit,
        ),
      );
      _titlecontroller.clear();
      _amountController.clear();
      // db.updateDatabase();

      expenseNotifier.update(DataBase.expenses);
      debugPrint("new expenses ${DataBase.expenses.length}");
      DataBase.persistCurrentExpenses();
    });
    for (var tag in selectedTags) {
      if (!DataBase.uniqueTags.contains(tag)) {
        DataBase.uniqueTags.add(tag);
      }
    }
    if (!DataBase.uniqueyears.contains(_selectedDate.year)) {
      DataBase.uniqueyears.add(_selectedDate.year);
    }
    DataBase.selectedTags = [];
    DataBase.selectedDate = null;
    _close();
  }

  void _close() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
      return;
    }

    Navigator.of(context).pop();
  }

  @override
  void initState() {
    super.initState();
    _creditAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _debitAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _creditAnimation = Tween(
      begin: 0.0,
      end: -10.0,
    ).animate(_creditAnimationController);
    _debitAnimation = Tween(
      begin: 0.0,
      end: 10.0,
    ).animate(_debitAnimationController);
    _creditAnimationController.reset();
  }

  void _animatePlusIcon() {
    // Forward, reverse, reset the animation for each loop
    _creditAnimationController.forward();
    Future.delayed(const Duration(milliseconds: 250), () {
      _creditAnimationController.reverse();
      Future.delayed(const Duration(milliseconds: 250), () {
        _creditAnimationController.reset();
      });
    });
  }

  void _animateMinusIcon() {
    // Forward, reverse, reset the animation for each loop
    _debitAnimationController.forward();
    Future.delayed(const Duration(milliseconds: 250), () {
      _debitAnimationController.reverse();
      Future.delayed(const Duration(milliseconds: 250), () {
        _debitAnimationController.reset();
      });
    });
  }

  @override
  void dispose() {
    super.dispose();
    _creditAnimationController.dispose();
    _debitAnimationController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      child: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: _close,
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: textcolor,
                        ),
                      ),
                    ),
                    const Center(
                      child: Text(
                        "Add Page",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      "Add Expense",
                      style: TextStyle(
                        color: textcolor,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextFormField(
                    controller: _titlecontroller,
                    style: const TextStyle(color: textcolor),
                    inputFormatters: [LengthLimitingTextInputFormatter(50)],
                    decoration: _fieldDecoration(
                      label: "Name",
                      errorText: _validate ? "Please Fill the Name" : null,
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter some text';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextFormField(
                    controller: _amountController,
                    style: const TextStyle(color: textcolor),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}$'),
                      ),
                    ],
                    decoration: _fieldDecoration(
                      label: "Amount",
                      errorText: _validate ? "Please Fill the Amount" : null,
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: Autocomplete<String>(
                    optionsViewBuilder: (
                      BuildContext context,
                      AutocompleteOnSelected<String> onSelected,
                      Iterable<String> options,
                    ) {
                      return SizedBox(
                        height: 200,
                        child: Material(
                          type: MaterialType.canvas,
                          color: itemcolor,
                          child: ListView(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            children:
                                options.map((opt) {
                                  return InkWell(
                                    onTap: () {
                                      onSelected(opt);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        right: 25.0,
                                      ),
                                      child: Card(
                                        color: bgcolor,
                                        child: Container(
                                          padding: const EdgeInsets.all(10),
                                          child: Text(
                                            opt,
                                            style: const TextStyle(
                                              color: textcolor,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                          ),
                        ),
                      );
                    },
                    fieldViewBuilder: (
                      BuildContext context,
                      TextEditingController selectedTagController,
                      FocusNode focusNode,
                      VoidCallback onFieldSubmitted,
                    ) {
                      _selectedTagController = selectedTagController;
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: const Text(
                                  "Tags",
                                  style: TextStyle(
                                    color: textcolor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Wrap(
                                spacing:
                                    8.0, // Horizontal spacing between widgets
                                runSpacing:
                                    8.0, // Vertical spacing between lines
                                children:
                                    selectedTags
                                        .map(
                                          (e) => Chip(
                                            backgroundColor: chipColor,
                                            labelPadding: const EdgeInsets.only(
                                              left: 8.0,
                                            ),
                                            label: Text(
                                              e,
                                              style: const TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                            shape: RoundedRectangleBorder(
                                              side: const BorderSide(
                                                width: 0.5,
                                                color: Colors.white54,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            deleteIcon: const Icon(
                                              Icons.close,
                                              size: 18,
                                              color: Colors.yellow,
                                            ),
                                            onDeleted: () {
                                              setState(() {
                                                selectedTags.remove(e);
                                              });
                                            },
                                          ),
                                        )
                                        .toList(),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: TextField(
                                  style: const TextStyle(color: textcolor),
                                  inputFormatters: [
                                    LengthLimitingTextInputFormatter(30),
                                    UppercaseTagInputFormatter(),
                                  ],
                                  decoration: _fieldDecoration(
                                    label: "Enter Tag",
                                  ),
                                  controller: selectedTagController,
                                  focusNode: focusNode,
                                  onSubmitted: (String value) {
                                    final normalizedValue = normalizeTag(value);
                                    if (!selectedTags.contains(
                                      normalizedValue,
                                    )) {
                                      if (normalizedValue.isNotEmpty) {
                                        setState(() {
                                          selectedTags.add(normalizedValue);
                                        });
                                      }
                                      selectedTagController.clear();
                                      FocusManager.instance.primaryFocus
                                          ?.unfocus();
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text == '') {
                        return tags;
                      } else {
                        List<String> matches = <String>[];
                        matches.addAll(tags);

                        matches.retainWhere((s) {
                          return s.contains(
                            textEditingValue.text.toUpperCase(),
                          );
                        });
                        return matches;
                      }
                    },
                    onSelected: (String option) {
                      if (!selectedTags.contains(option)) {
                        setState(() {
                          selectedTags.add(normalizeTag(option));
                          _selectedTagController.clear();
                        });
                      }
                    },
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: textcolor),
                  onPressed: _selectDate,
                  child: Text(DateFormat('dd/MM/yyyy').format(_selectedDate)),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 10.0),
                        child: Row(
                          children: [
                            Text(
                              "Credit",
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight:
                                    _isDebit
                                        ? FontWeight.normal
                                        : FontWeight.bold,
                              ),
                            ),
                            AnimatedBuilder(
                              animation: _creditAnimation,
                              builder: (context, child) {
                                return Transform.translate(
                                  offset: Offset(0.0, _creditAnimation.value),
                                  child: Text(
                                    String.fromCharCode(
                                      Icons.keyboard_arrow_up_rounded.codePoint,
                                    ),
                                    style: TextStyle(
                                      inherit: false,
                                      color: Colors.green,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                      fontFamily:
                                          Icons.keyboard_arrow_down.fontFamily,
                                      package:
                                          Icons.keyboard_arrow_down.fontPackage,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        thumbIcon: const WidgetStatePropertyAll(
                          Icon(Icons.attach_money, color: Color(0xff663399)),
                        ),
                        activeTrackColor: Colors.red,
                        inactiveTrackColor: Colors.green,
                        thumbColor: const WidgetStatePropertyAll(Colors.yellow),
                        overlayColor: const WidgetStatePropertyAll(
                          Colors.green,
                        ),
                        trackOutlineColor: WidgetStatePropertyAll(
                          _isDebit ? Colors.red : Colors.green,
                        ),
                        key: UniqueKey(),
                        value: _isDebit,
                        onChanged: (val) {
                          val ? _animateMinusIcon() : _animatePlusIcon();
                          setState(() {
                            _isDebit = val;
                          });
                          debugPrint("$_isDebit");
                        },
                      ),
                      // Checkbox(
                      //     value: _isDebit,
                      //     onChanged: (newVal) {
                      //       setState(() {
                      //         _isDebit = newVal ?? false;
                      //       });
                      //     }),
                      Padding(
                        padding: const EdgeInsets.only(left: 10.0),
                        child: Row(
                          children: [
                            Text(
                              "Debit",
                              style: TextStyle(
                                fontWeight:
                                    _isDebit
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                color: Colors.white70,
                              ),
                            ),
                            AnimatedBuilder(
                              animation: _debitAnimation,
                              builder:
                                  (context, child) => Transform.translate(
                                    offset: Offset(0.0, _debitAnimation.value),
                                    child: Text(
                                      String.fromCharCode(
                                        Icons
                                            .keyboard_arrow_down_rounded
                                            .codePoint,
                                      ),
                                      style: TextStyle(
                                        inherit: false,
                                        color: Colors.red,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w700,
                                        fontFamily:
                                            Icons
                                                .keyboard_arrow_down
                                                .fontFamily,
                                        package:
                                            Icons
                                                .keyboard_arrow_down
                                                .fontPackage,
                                      ),
                                    ),
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        style: ButtonStyle(
                          backgroundColor: WidgetStatePropertyAll(
                            floatingButtonColor,
                          ),
                          foregroundColor: const WidgetStatePropertyAll(
                            buttonTextColor,
                          ),
                        ),
                        onPressed: () {
                          setState(() {
                            _validate = _amountController.text.isEmpty;
                          });
                          _validate ? null : saveNewExpense();
                          debugPrint("$_foundExpense");
                        },
                        child: const Text(
                          "Add",
                          style: TextStyle(color: buttonTextColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.embedded) {
      return Material(color: bgcolor, child: content);
    }

    return Scaffold(backgroundColor: bgcolor, body: content);
  }
}
