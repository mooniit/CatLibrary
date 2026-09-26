/// Converts an already selected eligible duration into whole-minute coins.
/// How separate records' remainders combine is still Q06; callers must resolve
/// that policy before using this helper for daily settlement.
int studyCoinsForDuration(Duration duration) {
  if (duration.isNegative) throw ArgumentError.value(duration, 'duration');
  return (duration.inMilliseconds ~/ Duration.millisecondsPerMinute) * 2;
}
