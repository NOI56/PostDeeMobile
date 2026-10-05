bool isValidLinkInBioSlug(String slug) =>
    slug.length >= 3 &&
    slug.length <= 40 &&
    RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(slug);

String? linkInBioLinkError(String title, String url) {
  if (title.trim().isEmpty || title.length > 80) {
    return 'กรอกชื่อปุ่ม 1–80 ตัวอักษร';
  }
  final uri = Uri.tryParse(url);
  if (url.length > 2048 ||
      RegExp(r'\s').hasMatch(url) ||
      uri == null ||
      !uri.isAbsolute ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      !const {'http', 'https'}.contains(uri.scheme) ||
      uri.userInfo.isNotEmpty) {
    return 'ใช้ URL เต็มที่ขึ้นต้นด้วย https:// หรือ http:// และไม่มีชื่อผู้ใช้หรือรหัสผ่าน';
  }
  return null;
}
