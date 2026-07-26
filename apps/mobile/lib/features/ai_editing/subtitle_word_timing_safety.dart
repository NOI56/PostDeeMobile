final _meaningfulSubtitleText = RegExp(
  r'[\p{L}\p{N}\p{M}]',
  unicode: true,
);

/// Returns true when [text] contains only whitespace, punctuation, or symbols
/// that may remain visible without their own word-level timestamp.
///
/// Thai abbreviation and repetition marks are Unicode letters, so they remain
/// semantic text and must be covered by a timed word.
bool containsOnlyUntimedSubtitleSeparators(String text) =>
    !_meaningfulSubtitleText.hasMatch(text);
