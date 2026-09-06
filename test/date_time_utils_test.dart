import 'package:flutter_test/flutter_test.dart';

import 'package:remote_send/utils/date_time_utils.dart';

void main() {
  test('yesterday is detected by calendar date, not elapsed 24 hours', () {
    final now = DateTime(2026, 9, 2, 12);
    final yesterdayEvening = DateTime(2026, 9, 1, 20);

    expect(localCalendarDayDifference(now, yesterdayEvening), 1);
  });

  test('times on the same local date have a zero day difference', () {
    final now = DateTime(2026, 9, 2, 23, 59);
    final morning = DateTime(2026, 9, 2, 0, 1);

    expect(localCalendarDayDifference(now, morning), 0);
  });

  test('calendar day difference handles older and future dates', () {
    final now = DateTime(2026, 9, 8, 12);

    expect(localCalendarDayDifference(now, DateTime(2026, 9, 2, 20)), 6);
    expect(localCalendarDayDifference(now, DateTime(2026, 9, 9, 8)), -1);
  });
}
