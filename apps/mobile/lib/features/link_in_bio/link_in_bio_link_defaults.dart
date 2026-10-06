import 'link_in_bio_validation.dart';

const _platformDomains = {
  'shopee': ['shopee.co.th', 'shopee.com', 'shope.ee'],
  'lazada': ['lazada.co.th', 'lazada.com'],
  'line': ['line.me', 'lin.ee'],
  'tiktok': ['tiktok.com'],
  'youtube': ['youtube.com', 'youtu.be'],
  'instagram': ['instagram.com'],
  'facebook': ['facebook.com', 'fb.com', 'fb.me'],
};

String bioPlatformId(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  for (final entry in _platformDomains.entries) {
    if (entry.value
        .any((domain) => host == domain || host.endsWith('.$domain'))) {
      return entry.key;
    }
  }
  return 'link';
}

String? suggestedBioLinkTitle(String rawUrl) {
  final url = rawUrl.trim();
  if (linkInBioLinkError('link', url) != null) return null;
  final platformName = switch (bioPlatformId(url)) {
    'shopee' => 'Shopee',
    'lazada' => 'Lazada',
    'line' => 'LINE',
    'tiktok' => 'TikTok',
    'youtube' => 'YouTube',
    'instagram' => 'Instagram',
    'facebook' => 'Facebook',
    _ => null,
  };
  if (platformName != null) return platformName;
  var host = Uri.parse(url).host.toLowerCase();
  if (host.startsWith('www.')) host = host.substring(4);
  return host.length > 80 ? host.substring(0, 80) : host;
}
