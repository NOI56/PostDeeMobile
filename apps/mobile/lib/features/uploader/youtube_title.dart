const youtubeTitleMaxLength = 100;

String deriveYoutubeTitle(String caption) {
  final cleanedCaption = caption.replaceAll(RegExp(r'[<>]'), '').trim();
  if (cleanedCaption.isEmpty) return '';

  final firstLine = cleanedCaption
      .split(RegExp(r'[\r\n]+'))
      .firstWhere((line) => line.trim().isNotEmpty)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final sentenceEnd = RegExp(r'[.!?。！？](?:\s|$)').firstMatch(firstLine);
  final sentence = sentenceEnd == null
      ? firstLine
      : firstLine.substring(0, sentenceEnd.start + 1);

  return String.fromCharCodes(sentence.runes.take(youtubeTitleMaxLength))
      .trim();
}

String? validateYoutubeTitle(String title) {
  final trimmedTitle = title.trim();
  if (trimmedTitle.runes.length > youtubeTitleMaxLength) {
    return 'ชื่อวิดีโอ YouTube ต้องไม่เกิน 100 ตัวอักษร';
  }
  if (RegExp(r'[<>]').hasMatch(trimmedTitle)) {
    return 'ชื่อวิดีโอ YouTube ห้ามมีเครื่องหมาย < หรือ >';
  }
  return null;
}
