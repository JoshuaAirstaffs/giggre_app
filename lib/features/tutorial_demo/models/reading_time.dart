/// Comfortable pace for a *passively watched* (recorded) video — slower
/// than silent reading speed since the viewer is also taking in the
/// surrounding UI, not just the words. ~155 words/minute.
const _wordsPerSecond = 2.6;

/// Fixed overhead added on top of the raw reading time — covers the
/// staggered entrance animation settling and a beat to actually look at
/// the screen before it cuts to the next step.
const _settlePadding = Duration(milliseconds: 1400);

const _minimumDuration = Duration(seconds: 3);

/// Ceiling so one very text-dense step doesn't stall the whole demo —
/// most viewers skim rather than read every word once everything's on
/// screen at once.
const _maximumDuration = Duration(seconds: 10);

/// A step's on-screen duration, proportional to how much text it shows —
/// more text, more time. Replaces guessing a flat number per step so
/// viewers watching a recording (there's no pause button) have a real
/// chance to read everything before the automatic cut.
Duration readingDuration(String text, {Duration? minimum}) {
  final wordCount = text.trim().isEmpty
      ? 0
      : text.trim().split(RegExp(r'\s+')).length;
  final readTime = Duration(
    milliseconds: (wordCount / _wordsPerSecond * 1000).round(),
  );
  final computed = readTime + _settlePadding;
  final floor = minimum ?? _minimumDuration;
  if (computed < floor) return floor;
  if (computed > _maximumDuration) return _maximumDuration;
  return computed;
}

/// [readingDuration] for a step whose text is spread across several
/// fragments (a title, several bullets, a footnote, ...) — combines them
/// before measuring so the total reading load is what sets the duration.
Duration readingDurationFor(List<String> texts, {Duration? minimum}) {
  return readingDuration(texts.join(' '), minimum: minimum);
}
