bool isValidLinkInBioSlug(String slug) =>
    slug.length >= 3 &&
    slug.length <= 40 &&
    RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(slug);

bool isSafeLinkInBioDestination(String url) {
  if (url.isEmpty ||
      url.length > 2048 ||
      RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(url)) {
    return false;
  }
  if (RegExp(r'^mailto:', caseSensitive: false).hasMatch(url)) {
    final address = url.substring(7);
    final parts = address.split('@');
    return address.length <= 254 &&
        parts.length == 2 &&
        RegExp(r'^[a-zA-Z0-9._+-]{1,64}$').hasMatch(parts[0]) &&
        !parts[0].startsWith('.') &&
        !parts[0].endsWith('.') &&
        !parts[0].contains('..') &&
        RegExp(r'^(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$')
            .hasMatch(parts[1]);
  }
  if (RegExp(r'^tel:', caseSensitive: false).hasMatch(url)) {
    return RegExp(r'^tel:\+?[0-9]{7,15}$', caseSensitive: false).hasMatch(url);
  }
  final uri = Uri.tryParse(url);
  return RegExp(r'^https?://', caseSensitive: false).hasMatch(url) &&
      uri != null &&
      uri.isAbsolute &&
      uri.hasAuthority &&
      uri.host.isNotEmpty &&
      const {'http', 'https'}.contains(uri.scheme.toLowerCase()) &&
      uri.userInfo.isEmpty;
}

String normalizeBioLinkInput(String rawInput) {
  if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(rawInput)) return rawInput;
  final value = rawInput.trim();
  if (isSafeLinkInBioDestination(value)) return value;
  for (final scheme in ['mailto', 'tel']) {
    final destination = '$scheme:$value';
    if (isSafeLinkInBioDestination(destination)) return destination;
  }
  return value;
}

String? linkInBioLinkError(String title, String url) {
  if (title.trim().isEmpty || title.length > 80) {
    return 'กรอกชื่อปุ่ม 1–80 ตัวอักษร';
  }
  if (!isSafeLinkInBioDestination(url)) {
    return 'ใช้ URL เต็มที่ขึ้นต้นด้วย https:// หรือ http:// และไม่มีชื่อผู้ใช้หรือรหัสผ่าน หรือใช้ mailto:อีเมล / tel:เบอร์โทร';
  }
  return null;
}
