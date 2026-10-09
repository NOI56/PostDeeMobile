import 'dart:convert';
import 'dart:async';
import 'dart:math';

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
    await withLinkInBioDraftMutationForUser(ownerUserId!, () async {
      final preferences = await _activePreferences;
      for (final ownedKey in [
        key,
        '$key.image_reference',
        '$key.image_revision',
        '$key.protected_images'
      ]) {
        if (!await preferences.remove(ownedKey)) {
          throw StateError('Link in Bio draft could not be removed');
        }
      }
    });
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

Future<String> linkInBioDraftReferenceIdForUser(String ownerUserId) async {
  if (ownerUserId.trim().isEmpty) {
    throw StateError('Draft reference requires an owner');
  }
  final preferences = await SharedPreferences.getInstance();
  final key =
      'postdee_link_in_bio.user.${Uri.encodeComponent(ownerUserId)}.image_reference';
  final existing = preferences.getString(key);
  if (existing != null && RegExp(r'^[a-f0-9]{32}$').hasMatch(existing)) {
    return existing;
  }
  final random = Random.secure();
  final value = List.generate(
      16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  if (!await preferences.setString(key, value)) {
    throw StateError('Draft reference could not be saved');
  }
  return value;
}

Future<String?> existingLinkInBioDraftReferenceIdForUser(
    String ownerUserId) async {
  final preferences = await SharedPreferences.getInstance();
  final value = preferences.getString(
      'postdee_link_in_bio.user.${Uri.encodeComponent(ownerUserId)}.image_reference');
  return value != null && RegExp(r'^[a-f0-9]{32}$').hasMatch(value)
      ? value
      : null;
}

// Call inside the owner mutation queue, before sending any protection request.
Future<int> nextLinkInBioDraftRevisionForUser(String ownerUserId) async {
  if (ownerUserId.trim().isEmpty) {
    throw StateError('Draft revision requires an owner');
  }
  final preferences = await SharedPreferences.getInstance();
  final key =
      'postdee_link_in_bio.user.${Uri.encodeComponent(ownerUserId)}.image_revision';
  final previous = preferences.getInt(key) ?? 0;
  if (previous < 0 || previous >= 9007199254740991) {
    throw StateError('Draft revision is invalid');
  }
  final revision = previous + 1;
  if (!await preferences.setInt(key, revision)) {
    throw StateError('Draft revision could not be saved');
  }
  return revision;
}

Future<Set<String>> loadLinkInBioProtectedImageKeysForUser(
    String ownerUserId) async {
  final preferences = await SharedPreferences.getInstance();
  return (preferences.getStringList(
              'postdee_link_in_bio.user.${Uri.encodeComponent(ownerUserId)}.protected_images') ??
          [])
      .toSet();
}

Future<void> saveLinkInBioProtectedImageKeysForUser(
    String ownerUserId, Set<String> keys) async {
  final preferences = await SharedPreferences.getInstance();
  final sorted = keys.toList()..sort();
  if (!await preferences.setStringList(
      'postdee_link_in_bio.user.${Uri.encodeComponent(ownerUserId)}.protected_images',
      sorted)) {
    throw StateError('Draft image protection confirmation could not be saved');
  }
}

final _linkInBioDraftMutations = <String, Future<void>>{};

Future<T> withLinkInBioDraftMutationForUser<T>(
    String ownerUserId, Future<T> Function() operation) async {
  final previous =
      _linkInBioDraftMutations[ownerUserId] ?? Future<void>.value();
  final release = Completer<void>();
  final queued = previous.then((_) => release.future);
  _linkInBioDraftMutations[ownerUserId] = queued;
  await previous;
  try {
    return await operation();
  } finally {
    release.complete();
    if (identical(_linkInBioDraftMutations[ownerUserId], queued)) {
      _linkInBioDraftMutations.remove(ownerUserId);
    }
  }
}
