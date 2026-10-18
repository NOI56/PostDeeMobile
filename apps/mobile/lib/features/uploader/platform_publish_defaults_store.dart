import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/auth_session.dart';
import '../../core/network/postdee_api_client.dart';
import '../platforms/social_platform.dart';
import 'platform_publish_settings.dart';

const _storagePrefix = 'postdee.platform_publish_defaults.v1.';

bool _supportsDefaults(SocialPlatform platform) => switch (platform) {
      SocialPlatform.tiktok ||
      SocialPlatform.youtubeShorts ||
      SocialPlatform.instagramReels ||
      SocialPlatform.facebookReels =>
        true,
      _ => false,
    };

/// Local preferences belong to one app environment, owner and channel binding.
/// Display names are deliberately excluded: different channels can share them.
class PlatformPublishDefaultsScope {
  const PlatformPublishDefaultsScope._({
    required this.ownerUserId,
    required this.platform,
    required this.storageKey,
  });

  final String ownerUserId;
  final SocialPlatform platform;
  final String storageKey;

  static PlatformPublishDefaultsScope? fromConnection({
    required String apiBaseUrl,
    required String ownerUserId,
    required SocialPlatform platform,
    required SocialConnectionResult? connection,
  }) {
    final owner = ownerUserId.trim();
    final base = Uri.tryParse(apiBaseUrl.trim());
    final connectionId = connection?.connectionId?.trim() ?? '';
    final revision = connection?.connectionRevision?.trim() ?? '';
    final externalId = connection?.externalAccountId?.trim() ?? '';
    if (owner.isEmpty ||
        !_supportsDefaults(platform) ||
        base == null ||
        !const {'http', 'https'}.contains(base.scheme.toLowerCase()) ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        connection?.connected != true ||
        connection?.platform != platform.apiValue ||
        connectionId.isEmpty ||
        (revision.isEmpty && externalId.isEmpty)) {
      return null;
    }
    final path = base.normalizePath().path.replaceFirst(RegExp(r'/+$'), '');
    final endpoint = '${base.origin}$path';
    final identity = base64Url
        .encode(utf8.encode(jsonEncode([
          endpoint,
          platform.apiValue,
          connectionId,
          revision,
          externalId,
        ])))
        .replaceAll('=', '');
    return PlatformPublishDefaultsScope._(
      ownerUserId: owner,
      platform: platform,
      storageKey: '${_ownerPrefix(owner)}$identity',
    );
  }

  static String _ownerPrefix(String owner) =>
      '$_storagePrefix${base64Url.encode(utf8.encode(owner)).replaceAll('=', '')}.';

  @override
  bool operator ==(Object other) =>
      other is PlatformPublishDefaultsScope && storageKey == other.storageKey;

  @override
  int get hashCode => storageKey.hashCode;
}

/// An explicit allowlist of reusable choices, separate from same-clip drafts.
/// TikTok privacy/interactions must be selected by the user for each new clip.
/// Content declarations, titles, capabilities and confirmations never enter it.
class PlatformPublishDefaults {
  const PlatformPublishDefaults._(this.platform, this._settings);

  factory PlatformPublishDefaults.fromSettings(
    SocialPlatform platform,
    PlatformPublishSettings settings,
  ) {
    final reusable = switch (platform) {
      SocialPlatform.tiktok =>
        PlatformPublishSettings(tiktokPublishMode: settings.tiktokPublishMode),
      SocialPlatform.youtubeShorts => PlatformPublishSettings(
          youtubeVisibility: settings.youtubeVisibility,
          youtubeMadeForKids: settings.youtubeMadeForKids),
      SocialPlatform.instagramReels => PlatformPublishSettings(
          instagramShareToFeed: settings.instagramShareToFeed),
      SocialPlatform.facebookReels => PlatformPublishSettings(
          facebookPublishMode: settings.facebookPublishMode),
      _ => throw ArgumentError('Platform does not support publishing defaults'),
    };
    return PlatformPublishDefaults._(platform, reusable);
  }

  final SocialPlatform platform;
  final PlatformPublishSettings _settings;

  PlatformPublishSettings applyTo(PlatformPublishSettings current) =>
      switch (platform) {
        SocialPlatform.tiktok =>
          current.copyWith(tiktokPublishMode: _settings.tiktokPublishMode),
        SocialPlatform.youtubeShorts => current.copyWith(
            youtubeVisibility: _settings.youtubeVisibility,
            youtubeMadeForKids: _settings.youtubeMadeForKids,
          ),
        SocialPlatform.instagramReels => current.copyWith(
            instagramShareToFeed: _settings.instagramShareToFeed),
        SocialPlatform.facebookReels =>
          current.copyWith(facebookPublishMode: _settings.facebookPublishMode),
        _ => current,
      };

  Map<String, Object?> toJson() => {
        'version': 1,
        'platform': platform.apiValue,
        'values': switch (platform) {
          SocialPlatform.tiktok => {'mode': _settings.tiktokPublishMode.name},
          SocialPlatform.youtubeShorts => {
              'visibility': _settings.youtubeVisibility.name,
              'madeForKids': _settings.youtubeMadeForKids,
            },
          SocialPlatform.instagramReels => {
              'shareToFeed': _settings.instagramShareToFeed,
            },
          SocialPlatform.facebookReels => {
              'mode': _settings.facebookPublishMode?.name,
            },
          _ => <String, Object?>{},
        },
      };

  static PlatformPublishDefaults? fromJson(Map<String, Object?> json) {
    if (!_hasExactlyKeys(json, const {'version', 'platform', 'values'}) ||
        json['version'] is! int ||
        json['version'] != 1 ||
        json['values'] is! Map) {
      return null;
    }
    final values = json['values'] as Map;
    switch (json['platform']) {
      case 'TIKTOK':
        if (!_hasExactlyKeys(values, const {'mode'})) return null;
        final mode = _enumValue(TikTokPublishMode.values, values['mode']);
        return mode == null
            ? null
            : PlatformPublishDefaults.fromSettings(SocialPlatform.tiktok,
                PlatformPublishSettings(tiktokPublishMode: mode));
      case 'YOUTUBE_SHORTS':
        if (!_hasExactlyKeys(values, const {'visibility', 'madeForKids'})) {
          return null;
        }
        final visibility =
            _enumValue(YouTubeVisibility.values, values['visibility']);
        final audience = values['madeForKids'];
        if (visibility == null || (audience != null && audience is! bool)) {
          return null;
        }
        return PlatformPublishDefaults.fromSettings(
          SocialPlatform.youtubeShorts,
          PlatformPublishSettings(
              youtubeVisibility: visibility,
              youtubeMadeForKids: audience as bool?),
        );
      case 'INSTAGRAM_REELS':
        if (!_hasExactlyKeys(values, const {'shareToFeed'}) ||
            values['shareToFeed'] is! bool) {
          return null;
        }
        return PlatformPublishDefaults.fromSettings(
          SocialPlatform.instagramReels,
          PlatformPublishSettings(
              instagramShareToFeed: values['shareToFeed'] as bool),
        );
      case 'FACEBOOK_REELS':
        if (!_hasExactlyKeys(values, const {'mode'})) return null;
        final rawMode = values['mode'];
        final mode = _enumValue(FacebookPublishMode.values, rawMode);
        if (rawMode != null && mode == null) return null;
        return PlatformPublishDefaults.fromSettings(
            SocialPlatform.facebookReels,
            PlatformPublishSettings(facebookPublishMode: mode));
      default:
        return null;
    }
  }

  static bool _hasExactlyKeys(Map values, Set<String> keys) =>
      values.length == keys.length && values.keys.every(keys.contains);

  static T? _enumValue<T extends Enum>(List<T> values, Object? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

abstract interface class PlatformPublishDefaultsStore {
  Future<PlatformPublishDefaults?> load(PlatformPublishDefaultsScope scope);

  Future<void> save(
    PlatformPublishDefaultsScope scope,
    PlatformPublishDefaults defaults, {
    bool Function()? isCurrent,
  });

  Future<void> clearForDeletedAccount(String capturedOwnerUserId);
}

class SharedPreferencesPlatformPublishDefaultsStore
    implements PlatformPublishDefaultsStore {
  const SharedPreferencesPlatformPublishDefaultsStore({
    SharedPreferences? preferences,
    PostDeeAuthSessionStore? sessionStore,
    Future<SharedPreferences> Function()? loadPreferences,
  })  : _preferences = preferences,
        _sessionStore = sessionStore,
        _loadPreferences = loadPreferences;

  final SharedPreferences? _preferences;
  final PostDeeAuthSessionStore? _sessionStore;
  final Future<SharedPreferences> Function()? _loadPreferences;
  static final Map<String, int> _deletionGenerations = {};
  static final Map<String, Future<void>> _ownerMutationTails = {};
  static final Expando<Map<String, AuthSessionBinding>>
      _deletedSessionBindings = Expando('deleted publishing defaults sessions');

  PostDeeAuthSessionStore get _sessions =>
      _sessionStore ?? PostDeeAuthSessionStore.instance;

  Future<SharedPreferences> get _activePreferences async =>
      _preferences ??
      await (_loadPreferences ?? SharedPreferences.getInstance)();

  void _requireCurrent(
    String owner,
    AuthSessionBinding binding,
    int deletionGeneration, {
    bool Function()? isCurrent,
  }) {
    binding.ensureCurrent();
    final session = _sessions.session;
    if (owner.isEmpty ||
        !session.isSignedIn ||
        session.stableUserId != owner ||
        (_deletionGenerations[owner] ?? 0) != deletionGeneration ||
        (_deletedSessionBindings[_sessions]?[owner]?.isCurrent ?? false) ||
        (isCurrent != null && !isCurrent())) {
      throw const AuthSessionChangedException();
    }
  }

  Future<void> _serializeOwnerMutation(
      String owner, Future<void> Function() mutation) {
    final previous = _ownerMutationTails[owner] ?? Future<void>.value();
    final operation = previous.then((_) => mutation());
    final tail =
        operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _ownerMutationTails[owner] = tail;
    return operation.whenComplete(() {
      if (identical(_ownerMutationTails[owner], tail)) {
        _ownerMutationTails.remove(owner);
      }
    });
  }

  @override
  Future<PlatformPublishDefaults?> load(
      PlatformPublishDefaultsScope scope) async {
    final owner = scope.ownerUserId;
    final binding = _sessions.captureSession();
    final generation = _deletionGenerations[owner] ?? 0;
    _requireCurrent(owner, binding, generation);
    await (_ownerMutationTails[owner] ?? Future<void>.value());
    _requireCurrent(owner, binding, generation);
    final preferences = await _activePreferences;
    _requireCurrent(owner, binding, generation);
    try {
      final value = preferences.getString(scope.storageKey);
      if (value == null) return null;
      final json = jsonDecode(value);
      if (json is! Map<String, dynamic>) return null;
      final defaults = PlatformPublishDefaults.fromJson(json);
      return defaults?.platform == scope.platform ? defaults : null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  Future<void> save(
    PlatformPublishDefaultsScope scope,
    PlatformPublishDefaults defaults, {
    bool Function()? isCurrent,
  }) async {
    if (scope.platform != defaults.platform) {
      throw ArgumentError('Publishing defaults do not match the channel scope');
    }
    final owner = scope.ownerUserId;
    final binding = _sessions.captureSession();
    final generation = _deletionGenerations[owner] ?? 0;
    void requireCurrent() =>
        _requireCurrent(owner, binding, generation, isCurrent: isCurrent);
    requireCurrent();
    // Queue before opening preferences so two saves retain user-action order.
    await _serializeOwnerMutation(owner, () async {
      requireCurrent();
      final preferences = await _activePreferences;
      requireCurrent();
      String? previousValue;
      try {
        previousValue = preferences.getString(scope.storageKey);
      } on TypeError {
        // Invalid old preference types do not prevent a fresh explicit save.
      }
      if (!await preferences.setString(
          scope.storageKey, jsonEncode(defaults.toJson()))) {
        throw StateError('Publishing defaults could not be saved');
      }
      try {
        requireCurrent();
      } on AuthSessionChangedException {
        // A native preference write cannot be cancelled after it starts.
        // Restore only this captured scope before later writes/deletion run.
        final restored = previousValue == null
            ? await preferences.remove(scope.storageKey)
            : await preferences.setString(scope.storageKey, previousValue);
        if (!restored) {
          throw StateError('Publishing defaults could not be restored');
        }
        rethrow;
      }
    });
  }

  @override
  Future<void> clearForDeletedAccount(String capturedOwnerUserId) async {
    final owner = capturedOwnerUserId.trim();
    if (owner.isEmpty) {
      throw ArgumentError('Deleting publishing defaults requires an owner');
    }
    _deletionGenerations[owner] = (_deletionGenerations[owner] ?? 0) + 1;
    if (_sessions.session.stableUserId == owner) {
      (_deletedSessionBindings[_sessions] ??= {})[owner] =
          _sessions.captureSession();
    }
    await _serializeOwnerMutation(owner, () async {
      final preferences = await _activePreferences;
      final prefix = PlatformPublishDefaultsScope._ownerPrefix(owner);
      final keys = preferences.getKeys().where((key) => key.startsWith(prefix));
      for (final key in keys.toList()) {
        if (!await preferences.remove(key)) {
          throw StateError(
              'Deleted account publishing defaults could not be cleared');
        }
      }
    });
  }
}
