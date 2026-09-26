/// Whole minutes are counted after combining all eligible records for one day.
int studyCoinsForDuration(Duration duration) {
  if (duration.isNegative) throw ArgumentError.value(duration, 'duration');
  return (duration.inMilliseconds ~/ Duration.millisecondsPerMinute) * 2;
}

int dailyStudyCoins(Duration total) =>
    studyCoinsForDuration(total).clamp(0, 120);

int remainingStudyCoins(Duration total, int alreadyIssued) {
  if (alreadyIssued < 0 || alreadyIssued > 120) {
    throw ArgumentError.value(alreadyIssued, 'alreadyIssued');
  }
  return (dailyStudyCoins(total) - alreadyIssued).clamp(0, 120);
}
