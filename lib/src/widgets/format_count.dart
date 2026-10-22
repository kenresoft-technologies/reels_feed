/// Shortens a count for display: `999`, `1.2K`, `34K`, `1.5M`, `2B`.
///
/// Counts are cut, not rounded, so a count never shows higher than it is
/// (1,999 is `1.9K`).
String formatReelCount(int count) {
  if (count < 0) return '-${formatReelCount(-count)}';
  if (count < 1000) return '$count';
  const units = <(int, String)>[(1000000000, 'B'), (1000000, 'M'), (1000, 'K')];
  for (final (size, suffix) in units) {
    if (count >= size) {
      final whole = count ~/ size;
      if (whole >= 10) return '$whole$suffix';
      final tenth = (count % size) * 10 ~/ size;
      return tenth == 0 ? '$whole$suffix' : '$whole.$tenth$suffix';
    }
  }
  return '$count';
}
