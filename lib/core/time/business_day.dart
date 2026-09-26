/// Beijing business dates, independent of the device's local timezone.
Map<String, int> millisecondsByBusinessDay(DateTime start, DateTime end) {
  var cursor = start.toUtc();
  final until = end.toUtc();
  if (until.isBefore(cursor)) throw ArgumentError('End precedes start');
  final result = <String, int>{};
  while (cursor.isBefore(until)) {
    final shifted = cursor.add(const Duration(hours: 8));
    final day = shifted.toIso8601String().substring(0, 10);
    final boundary = DateTime.utc(
      shifted.year,
      shifted.month,
      shifted.day + 1,
    ).subtract(const Duration(hours: 8));
    final segmentEnd = until.isBefore(boundary) ? until : boundary;
    result[day] = segmentEnd.difference(cursor).inMilliseconds;
    cursor = segmentEnd;
  }
  return result;
}
