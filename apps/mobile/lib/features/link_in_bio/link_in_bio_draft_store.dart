import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LinkInBioCustomLink {
  const LinkInBioCustomLink({
    required this.id,
    required this.title,
    required this.url,
  });

  factory LinkInBioCustomLink.fromJson(Map<String, Object?> json) {
    return LinkInBioCustomLink(
      id: json['id'] as String,
      title: json['title'] as String,
      url: json['url'] as String,
    );
  }

  final String id;
  final String title;
  final String url;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': title,
      'url': url,
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
  });

  factory LinkInBioDraft.defaults() {
    return const LinkInBioDraft(
      storeName: 'ร้านของคุณ',
      slug: 'ร้านของคุณ',
      autoUpdateFromScheduledPosts: true,
      enabledLinkIds: {
        'recommended_product',
        'daily_campaign',
      },
      customLinks: [],
    );
  }

  final String storeName;
  final String slug;
  final bool autoUpdateFromScheduledPosts;
  final Set<String> enabledLinkIds;
  final List<LinkInBioCustomLink> customLinks;
}

abstract class LinkInBioDraftStore {
  Future<LinkInBioDraft?> loadDraft();

  Future<void> saveDraft(LinkInBioDraft draft);
}

class SharedPreferencesLinkInBioDraftStore implements LinkInBioDraftStore {
  const SharedPreferencesLinkInBioDraftStore({
    SharedPreferences? preferences,
  }) : _preferences = preferences;

  static const storeNameKey = 'postdee_link_in_bio.store_name';
  static const slugKey = 'postdee_link_in_bio.slug';
  static const autoUpdateKey = 'postdee_link_in_bio.auto_update';
  static const enabledLinksKey = 'postdee_link_in_bio.enabled_links';
  static const customLinksKey = 'postdee_link_in_bio.custom_links';

  final SharedPreferences? _preferences;

  Future<SharedPreferences> get _activePreferences async =>
      _preferences ?? SharedPreferences.getInstance();

  @override
  Future<LinkInBioDraft?> loadDraft() async {
    final preferences = await _activePreferences;
    final hasSavedDraft = preferences.containsKey(storeNameKey) ||
        preferences.containsKey(slugKey) ||
        preferences.containsKey(autoUpdateKey) ||
        preferences.containsKey(enabledLinksKey) ||
        preferences.containsKey(customLinksKey);

    if (!hasSavedDraft) {
      return null;
    }

    final defaults = LinkInBioDraft.defaults();

    return LinkInBioDraft(
      storeName: preferences.getString(storeNameKey) ?? defaults.storeName,
      slug: preferences.getString(slugKey) ?? defaults.slug,
      autoUpdateFromScheduledPosts:
          preferences.getBool(autoUpdateKey) ??
              defaults.autoUpdateFromScheduledPosts,
      enabledLinkIds:
          (preferences.getStringList(enabledLinksKey) ??
                  defaults.enabledLinkIds.toList())
              .toSet(),
      customLinks: _decodeCustomLinks(
        preferences.getStringList(customLinksKey) ?? const [],
      ),
    );
  }

  @override
  Future<void> saveDraft(LinkInBioDraft draft) async {
    final preferences = await _activePreferences;
    final enabledLinkIds = draft.enabledLinkIds.toList()..sort();

    await preferences.setString(storeNameKey, draft.storeName);
    await preferences.setString(slugKey, draft.slug);
    await preferences.setBool(
      autoUpdateKey,
      draft.autoUpdateFromScheduledPosts,
    );
    await preferences.setStringList(enabledLinksKey, enabledLinkIds);
    await preferences.setStringList(
      customLinksKey,
      draft.customLinks
          .map((link) => jsonEncode(link.toJson()))
          .toList(growable: false),
    );
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
