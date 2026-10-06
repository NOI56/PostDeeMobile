import 'link_in_bio_validation.dart';

const _platformDomains = {
  'shopee': ['shopee.co.th', 'shopee.com', 'shope.ee'],
  'lazada': ['lazada.co.th', 'lazada.com'],
  'line': ['line.me', 'lin.ee'],
  'tiktok': ['tiktok.com'],
  'youtube': ['youtube.com', 'youtu.be'],
  'instagram': ['instagram.com'],
  'facebook': ['facebook.com', 'fb.com', 'fb.me'],
  'messenger': ['m.me', 'messenger.com'],
  'whatsapp': ['wa.me', 'whatsapp.com'],
  'google_maps': ['maps.app.goo.gl', 'maps.google.com', 'maps.google.co.th'],
};

String bioPlatformId(String url) {
  if (!isSafeLinkInBioDestination(url)) return 'link';
  final uri = Uri.parse(url);
  if (uri.scheme.toLowerCase() == 'mailto') return 'email';
  if (uri.scheme.toLowerCase() == 'tel') return 'phone';
  final host = uri.host.toLowerCase();
  bool isDomain(String domain) => host == domain || host.endsWith('.$domain');
  if (isDomain('facebook.com') &&
      RegExp(r'^/messages(?:/|$)').hasMatch(uri.path)) {
    return 'messenger';
  }
  if ((const {
            'google.com',
            'www.google.com',
            'google.co.th',
            'www.google.co.th'
          }.contains(host) &&
          RegExp(r'^/maps(?:/|$)').hasMatch(uri.path)) ||
      (host == 'goo.gl' && RegExp(r'^/maps(?:/|$)').hasMatch(uri.path))) {
    return 'google_maps';
  }
  for (final entry in _platformDomains.entries) {
    if (entry.value
        .any((domain) => host == domain || host.endsWith('.$domain'))) {
      return entry.key;
    }
  }
  return 'website';
}

String? suggestedBioLinkTitle(String rawUrl) {
  final url = normalizeBioLinkInput(rawUrl);
  if (linkInBioLinkError('link', url) != null) return null;
  final platformName = switch (bioPlatformId(url)) {
    'shopee' => 'Shopee',
    'lazada' => 'Lazada',
    'line' => 'LINE',
    'tiktok' => 'TikTok',
    'youtube' => 'YouTube',
    'instagram' => 'Instagram',
    'facebook' => 'Facebook',
    'messenger' => 'Messenger',
    'whatsapp' => 'WhatsApp',
    'google_maps' => 'Google Maps',
    'email' => 'ส่งอีเมล',
    'phone' => 'โทรหาร้าน',
    _ => null,
  };
  if (platformName != null) return platformName;
  var host = Uri.parse(url).host.toLowerCase();
  if (host.startsWith('www.')) host = host.substring(4);
  return host.length > 80 ? host.substring(0, 80) : host;
}
