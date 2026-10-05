import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/link_in_bio_appearance.dart';

class LinkInBioCustomLink {
  const LinkInBioCustomLink({
    required this.id,
    required this.title,
    required this.url,
    this.category = '',
    this.icon = 'auto',
    this.font,
    this.textColor,
    this.buttonColor,
  });

  factory LinkInBioCustomLink.fromJson(Map<String, Object?> json) {
    final link = LinkInBioCustomLink(
      id: json['id'] as String,
      title: json['title'] as String,
      url: json['url'] as String,
      category: json['category'] as String? ?? '',
      icon: json['icon'] as String? ?? 'auto',
      font: json['font'] as String?,
      textColor: json['textColor'] as String?,
      buttonColor: json['buttonColor'] as String?,
    );
    validateLinkInBioLinkOptions(
        category: link.category,
        icon: link.icon,
        font: link.font,
        textColor: link.textColor,
        buttonColor: link.buttonColor);
    return link;
  }

  final String id;
  final String title;
  final String url;
  final String category;
  final String icon;
  final String? font;
  final String? textColor;
  final String? buttonColor;

  Map<String, Object?> toJson() {
    validateLinkInBioLinkOptions(
        category: category,
        icon: icon,
        font: font,
        textColor: textColor,
        buttonColor: buttonColor);
    return {
      'id': id,
      'title': title,
      'url': url,
      if (category.trim().isNotEmpty) 'category': category,
      if (icon != 'auto') 'icon': icon,
      if (font != null) 'font': font,
      if (textColor != null) 'textColor': textColor,
      if (buttonColor != null) 'buttonColor': buttonColor,
    };
  }
}

class LinkInBioDraft {
  const LinkInBioDraft({
    required this.storeName,
    required this.slug,
    required this.autoUpdateFromScheduledPosts,
    required this.enabledLinkIds,
    required this.customLinks,
    this.appearance = const LinkInBioAppearance(),
  });

  factory LinkInBioDraft.defaults() {
    return const LinkInBioDraft(
      storeName: 'ร้านของคุณ',
      slug: '',
      autoUpdateFromScheduledPosts: false,
      enabledLinkIds: {},
      customLinks: [],
    );
  }

  final String storeName;
  final String slug;
  final bool autoUpdateFromScheduledPosts;
  final Set<String> enabledLinkIds;
  final List<LinkInBioCustomLink> customLinks;
  final LinkInBioAppearance appearance;
}

abstract class LinkInBioDraftStore {
  Future<LinkInBioDraft?> loadDraft();

  Future<void> saveDraft(LinkInBioDraft draft);
}

class SharedPreferencesLinkInBioDraftStore implements LinkInBioDraftStore {
  const SharedPreferencesLinkInBioDraftStore({
    SharedPreferences? preferences,
    this.ownerUserId,
  }) : _preferences = preferences;

  static const storeNameKey = 'postdee_link_in_bio.store_name';
  static const slugKey = 'postdee_link_in_bio.slug';
  static const autoUpdateKey = 'postdee_link_in_bio.auto_update';
  static const enabledLinksKey = 'postdee_link_in_bio.enabled_links';
  static const customLinksKey = 'postdee_link_in_bio.custom_links';

  final SharedPreferences? _preferences;
  final String? ownerUserId;

  String? get _ownedKey {
    final owner = ownerUserId?.trim();
    return owner == null || owner.isEmpty
        ? null
        : 'postdee_link_in_bio.user.${Uri.encodeComponent(owner)}';
  }

  Future<SharedPreferences> get _activePreferences async =>
      _preferences ?? SharedPreferences.getInstance();

  @override
  Future<LinkInBioDraft?> loadDraft() async {
    final key = _ownedKey;
    if (key == null) return null;
    final preferences = await _activePreferences;
    final raw = preferences.getString(key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return LinkInBioDraft(
        storeName: json['storeName'] as String,
        slug: json['slug'] as String,
        autoUpdateFromScheduledPosts: false,
        enabledLinkIds: (json['enabledLinkIds'] as List).cast<String>().toSet(),
        customLinks:
            _decodeCustomLinks((json['customLinks'] as List).cast<String>()),
        appearance: json.containsKey('appearance')
            ? LinkInBioAppearance.fromJson(
                json['appearance'] as Map<String, Object?>)
            : const LinkInBioAppearance(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveDraft(LinkInBioDraft draft) async {
    final preferences = await _activePreferences;
    final key = _ownedKey;
    if (key == null) throw StateError('Link in Bio draft requires an owner');
    final enabledLinkIds = draft.enabledLinkIds.toList()..sort();
    final saved = await preferences.setString(
        key,
        jsonEncode({
          'storeName': draft.storeName,
          'slug': draft.slug,
          'enabledLinkIds': enabledLinkIds,
          'customLinks': draft.customLinks
              .map((link) => jsonEncode(link.toJson()))
              .toList(),
          'appearance': draft.appearance.toJson(),
        }));
    if (!saved) throw StateError('Link in Bio draft could not be saved');
  }

  Future<void> clearDraft() async {
    final key = _ownedKey;
    if (key == null) return;
    final preferences = await _activePreferences;
    if (!await preferences.remove(key)) {
      throw StateError('Link in Bio draft could not be removed');
    }
  }

  List<LinkInBioCustomLink> _decodeCustomLinks(List<String> rawLinks) {
    final links = <LinkInBioCustomLink>[];

    for (final rawLink in rawLinks) {
      try {
        final decoded = jsonDecode(rawLink);
        if (decoded is Map<String, Object?>) {
          links.add(LinkInBioCustomLink.fromJson(decoded));
        }
      } catch (_) {
        continue;
      }
    }

    return links;
  }
}

Future<void> clearLinkInBioDraftForUser(String ownerUserId) =>
    SharedPreferencesLinkInBioDraftStore(ownerUserId: ownerUserId).clearDraft();
