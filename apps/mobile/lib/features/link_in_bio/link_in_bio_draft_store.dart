import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/auth_session.dart';

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
    PostDeeAuthSessionStore? sessionStore,
    Future<SharedPreferences> Function()? preferencesLoader,
  })  : _preferences = preferences,
        _sessionStore = sessionStore,
        _preferencesLoader = preferencesLoader;

  // Legacy keys have no owner. Keep them untouched and never attribute them to
  // the next person who signs in on this device.
  static const storeNameKey = 'postdee_link_in_bio.store_name';
  static const slugKey = 'postdee_link_in_bio.slug';
  static const autoUpdateKey = 'postdee_link_in_bio.auto_update';
  static const enabledLinksKey = 'postdee_link_in_bio.enabled_links';
  static const customLinksKey = 'postdee_link_in_bio.custom_links';

  final SharedPreferences? _preferences;
  final PostDeeAuthSessionStore? _sessionStore;
  final Future<SharedPreferences> Function()? _preferencesLoader;

  PostDeeAuthSessionStore get _sessions =>
      _sessionStore ?? PostDeeAuthSessionStore.instance;

  Future<SharedPreferences> get _activePreferences async =>
      _preferences ??
      await (_preferencesLoader?.call() ?? SharedPreferences.getInstance());

  String? get _ownerId {
    final session = _sessions.session;
    final userId = session.userId;
    return session.isSignedIn && userId != null && userId.trim().isNotEmpty
        ? userId
        : null;
  }

  String _draftKey(String userId) =>
      'postdee_link_in_bio.account.${Uri.encodeComponent(userId)}';

  @override
  Future<LinkInBioDraft?> loadDraft() async {
    final binding = _sessions.captureSession();
    final ownerId = _ownerId;
    if (ownerId == null) {
      return null;
    }
    final preferences = await _activePreferences;
    binding.ensureCurrent();
    final rawDraft = preferences.getString(_draftKey(ownerId));
    if (rawDraft == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(rawDraft);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != 1 || decoded['userId'] != ownerId) {
        return null;
      }
      final defaults = LinkInBioDraft.defaults();
      return LinkInBioDraft(
        storeName: decoded['storeName'] as String? ?? defaults.storeName,
        slug: decoded['slug'] as String? ?? defaults.slug,
        autoUpdateFromScheduledPosts:
            decoded['autoUpdateFromScheduledPosts'] as bool? ??
                defaults.autoUpdateFromScheduledPosts,
        enabledLinkIds: decoded['enabledLinkIds'] is List
            ? (decoded['enabledLinkIds'] as List).cast<String>().toSet()
            : defaults.enabledLinkIds,
        customLinks: _decodeCustomLinks(decoded['customLinks']),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveDraft(LinkInBioDraft draft) async {
    final binding = _sessions.captureSession();
    final ownerId = _ownerId;
    if (ownerId == null) {
      throw StateError('A signed-in account UID is required for a local draft');
    }
    final preferences = await _activePreferences;
    binding.ensureCurrent();
    final enabledLinkIds = draft.enabledLinkIds.toList()..sort();
    final saved = await preferences.setString(_draftKey(ownerId), jsonEncode({
      'version': 1,
      'userId': ownerId,
      'storeName': draft.storeName,
      'slug': draft.slug,
      'autoUpdateFromScheduledPosts': draft.autoUpdateFromScheduledPosts,
      'enabledLinkIds': enabledLinkIds,
      'customLinks': draft.customLinks.map((link) => link.toJson()).toList(),
    }));
    binding.ensureCurrent();
    if (!saved) {
      throw StateError('The local draft could not be saved');
    }
  }

  List<LinkInBioCustomLink> _decodeCustomLinks(Object? rawLinks) {
    final links = <LinkInBioCustomLink>[];
    if (rawLinks is! List) {
      return links;
    }
    for (final rawLink in rawLinks) {
      try {
        if (rawLink is Map<String, Object?>) {
          links.add(LinkInBioCustomLink.fromJson(rawLink));
        }
      } catch (_) {
        continue;
      }
    }

    return links;
  }
}
