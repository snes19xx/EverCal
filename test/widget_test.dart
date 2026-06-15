// Unit tests for the ICS text helpers and all-day date detection added for
// escaping, all-day events, and import round-trips. Hard assertions on values.

import 'package:flutter_test/flutter_test.dart';

import 'package:ever_cal/utils.dart';

void main() {
  group('ICS text escaping', () {
    test('round-trips commas, semicolons, newlines and backslashes', () {
      const raw = 'Lunch, then meeting; line1\nline2 path C:\\tmp';
      expect(icsUnescape(icsEscape(raw)), raw);
    });

    test('escapes a newline as literal \\n (no real line break in output)', () {
      expect(icsEscape('a\nb'), 'a\\nb');
      expect(icsEscape('a\nb').contains('\n'), isFalse);
    });

    test('unescape keeps an escaped backslash before n as two chars', () {
      expect(icsUnescape('a\\\\nb'), 'a\\nb');
    });
  });

  group('isDateOnly', () {
    test('true for a date-only value', () {
      expect(isDateOnly('20260101'), isTrue);
    });

    test('false for a date-time value', () {
      expect(isDateOnly('20260101T090000'), isFalse);
    });
  });
}
