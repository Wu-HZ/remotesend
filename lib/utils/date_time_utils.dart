/// Returns the number of local calendar-day boundaries between [value] and
/// [now]. A value from yesterday returns 1 even when it is less than 24 hours
/// old.
int localCalendarDayDifference(DateTime now, DateTime value) {
  final localNow = now.toLocal();
  final localValue = value.toLocal();
  final today = DateTime.utc(localNow.year, localNow.month, localNow.day);
  final valueDay = DateTime.utc(
    localValue.year,
    localValue.month,
    localValue.day,
  );
  return today.difference(valueDay).inDays;
}
