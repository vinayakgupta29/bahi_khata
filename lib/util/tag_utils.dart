import 'package:flutter/services.dart';

const List<String> defaultTags = [
  "FOOD",
  "FAST FOOD",
  "DONATION",
  "TRAVEL",
  "OTHER",
];

String normalizeTag(String value) {
  final upper = value.toUpperCase().replaceAll(RegExp(r'[^A-Z ]'), '');
  return upper.replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<String> normalizeTags(Iterable<dynamic>? values) {
  if (values == null) {
    return <String>[];
  }

  final normalized = <String>[];
  for (final value in values) {
    final tag = normalizeTag(value.toString());
    if (tag.isNotEmpty && !normalized.contains(tag)) {
      normalized.add(tag);
    }
  }
  return normalized;
}

class UppercaseTagInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalizedText = normalizeTag(newValue.text);
    return TextEditingValue(
      text: normalizedText,
      selection: TextSelection.collapsed(offset: normalizedText.length),
    );
  }
}
