import '../../core/models/profile_platform_catalog.generated.dart';
import 'link_in_bio_validation.dart';

String bioPlatformId(String url) {
  if (!isSafeLinkInBioDestination(url)) return 'link';
  final uri = Uri.parse(url);
  if (uri.scheme.toLowerCase() == 'mailto') return 'email';
  if (uri.scheme.toLowerCase() == 'tel') return 'phone';
  final host = uri.host.toLowerCase();
  // Uri.path decodes escapes; the public API matches the escaped URL path.
  final path = RegExp(r'^https?://[^/?#]+([^?#]*)', caseSensitive: false)
          .firstMatch(url)
          ?.group(1) ??
      '';
  bool isDomain(String domain) => host == domain || host.endsWith('.$domain');
  // Specific shared-host routes take precedence over broad brand domains.
  for (final platform in profilePlatformCatalog) {
    for (final match in platform.matches) {
      if ((match.subdomains ? isDomain(match.host) : host == match.host) &&
          (path == match.pathPrefix ||
              path.startsWith('${match.pathPrefix}/'))) {
        return platform.id;
      }
    }
  }
  for (final platform in profilePlatformCatalog) {
    if (platform.domains.any(isDomain)) {
      return platform.id;
    }
  }
  return 'website';
}

String? suggestedBioLinkTitle(String rawUrl) {
  final url = normalizeBioLinkInput(rawUrl);
  if (linkInBioLinkError('link', url) != null) return null;
  final id = bioPlatformId(url);
  final platformName = profilePlatformNames[id] ??
      switch (id) {
        'email' => 'ส่งอีเมล',
        'phone' => 'โทรหาร้าน',
        _ => null,
      };
  if (platformName != null) return platformName;
  var host = Uri.parse(url).host.toLowerCase();
  if (host.startsWith('www.')) host = host.substring(4);
  return host.length > 80 ? host.substring(0, 80) : host;
}
