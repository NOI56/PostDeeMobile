import 'dart:convert';

/// Matches the API's caption limit for every platform except YouTube
/// (Instagram's 2,200 characters, the strictest of them).
const postCaptionMaxLength = 2200;

/// YouTube sends the caption as the description, which the YouTube Data API
/// caps at 5,000 UTF-8 bytes (about 1,660 Thai characters) without < or >.
const youtubeDescriptionMaxBytes = 5000;

String _formatCount(int value) => value.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );

/// Mirrors the API rules, so the app never sends a caption the server would
/// reject after the upload finished. Code points match the API's count.
String? validatePostCaption(
  String caption, {
  bool includesYoutube = false,
  bool includesOtherPlatforms = true,
}) {
  final trimmed = caption.trim();
  final length = trimmed.runes.length;
  if (includesOtherPlatforms && length > postCaptionMaxLength) {
    return 'แคปชั่นต้องไม่เกิน ${_formatCount(postCaptionMaxLength)} ตัวอักษร '
        '(ตอนนี้ ${_formatCount(length)})';
  }
  if (includesYoutube) {
    if (utf8.encode(trimmed).length > youtubeDescriptionMaxBytes) {
      return 'แคปชั่นยาวเกินที่ YouTube รับได้ '
          '(สูงสุด ${_formatCount(youtubeDescriptionMaxBytes)} ไบต์ '
          'ภาษาไทยราว 1,660 ตัวอักษร)';
    }
    if (RegExp(r'[<>]').hasMatch(trimmed)) {
      return 'YouTube ไม่รับเครื่องหมาย < หรือ > ในแคปชั่น';
    }
  }
  return null;
}
