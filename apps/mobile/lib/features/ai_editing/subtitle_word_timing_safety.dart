final _meaningfulSubtitleText = RegExp(
  r'[\p{L}\p{N}\p{M}]',
  unicode: true,
);

/// Returns true when [text] contains only whitespace, punctuation, or symbols
/// that may remain visible without their own word-level timestamp.
bool containsOnlyUntimedSubtitleSeparators(String text) =>
    !_meaningfulSubtitleText.hasMatch(text);
