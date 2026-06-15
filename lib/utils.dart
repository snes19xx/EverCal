/// utils.dart
///
/// Contains global static formatters and shared utility functions.

import 'package:intl/intl.dart';

// Global Static Formatters
final DateFormat fmtMonth = DateFormat('MMMM');
final DateFormat fmtYear = DateFormat('yyyy');
final DateFormat fmtDayNum = DateFormat('d');
final DateFormat fmtDayName = DateFormat('EEE');
final DateFormat fmtTime = DateFormat('h:mm a');
final DateFormat fmtIcsTime = DateFormat('yyyyMMdd\'T\'HHmm00');
final DateFormat fmtIcsDate = DateFormat('yyyyMMdd');
final DateFormat fmtGridDay = DateFormat('MMM d');

// RFC 5545 TEXT escaping. Backslash must be escaped first on the way out.
String icsEscape(String input) {
  return input
      .replaceAll('\\', '\\\\')
      .replaceAll('\n', '\\n')
      .replaceAll(',', '\\,')
      .replaceAll(';', '\\;');
}

String icsUnescape(String input) {
  final out = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    if (ch == '\\' && i + 1 < input.length) {
      final next = input[i + 1];
      switch (next) {
        case 'n':
        case 'N':
          out.write('\n');
        case '\\':
          out.write('\\');
        case ',':
          out.write(',');
        case ';':
          out.write(';');
        default:
          out.write(next);
      }
      i++;
    } else {
      out.write(ch);
    }
  }
  return out.toString();
}

// A DTSTART/DTEND value with no time component (yyyymmdd) is an all-day date.
bool isDateOnly(String value) {
  final v = value.trim();
  return !v.contains('T') && v.length == 8;
}