import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_defaults_store.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

AuthSession _session(String owner) => AuthSession.authenticated(
      userId: owner,
      idToken: 'test-token-$owner',
    );

PlatformPublishDefaultsScope _scope({
  String owner = 'owner-a',
  String endpoint = 'https://staging.example.test/v1',
  SocialPlatform platform = SocialPlatform.youtubeShorts,
  String channel = 'channel-a',
  String revision = 'revision-a',
}) =>
    PlatformPublishDefaultsScope.fromConnection(
      apiBaseUrl: endpoint,
      ownerUserId: owner,
      platform: platform,
      connection: SocialConnectionResult(
        platform: platform.apiValue,
        connected: true,
        connectionId: channel,
        connectionRevision: revision,
        externalAccountId: 'external-$channel',
        displayName: 'Same display name',
      ),
    )!;

const _chosen = PlatformPublishSettings(
  tiktokPublishMode: TikTokPublishMode.directPost,
  tiktokPrivacyLevel: TikTokPrivacyLevel.publicToEveryone,
  tiktokCreatorInfoRevision: 'fresh-only-for-original-clip',
  tiktokAllowComment: true,
  tiktokAllowDuet: true,
  tiktokAllowStitch: true,
  tiktokBrandContentToggle: true,
  tiktokBrandOrganicToggle: true,
  tiktokIsAigc: true,
  tiktokMusicUsageConfirmed: true,
  tiktokBrandedContentPolicyConfirmed: true,
  tiktokVideoDurationSeconds: 12,
  youtubeTitle: 'Original clip title',
  youtubeVisibility: YouTubeVisibility.public,
  youtubeMadeForKids: false,
  youtubeContainsSyntheticMedia: true,
  youtubeCommunityGuidelinesCertified: true,
  instagramShareToFeed: false,
  instagramIsAiGenerated: true,
  facebookPublishMode: FacebookPublishMode.publish,
  facebookIsAiGenerated: true,
);

class _PendingWritePreferences implements SharedPreferences {
  final values = <String, String>{};
  final writeStarted = Completer<void>();
  final releaseWrite = Completer<void>();
  int writes = 0;

  @override
  Future<bool> setString(String key, String value) async {
    writes++;
    if (writes == 1) {
      writeStarted.complete();
      await releaseWrite.future;
    }
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Set<String> getKeys() => values.keys.toSet();

  @override
  String? getString(String key) => values[key];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('scope isolates owner, API environment, channel, platform and revision',
      () {
    final base = _scope();
    expect(base, _scope(endpoint: 'https://staging.example.test/v1/'));
    expect(base, isNot(_scope(owner: 'owner-b')));
    expect(base, isNot(_scope(endpoint: 'https://production.example.test/v1')));
    expect(base, isNot(_scope(endpoint: 'https://staging.example.test/v2')));
    expect(base, isNot(_scope(channel: 'channel-b')));
    expect(base, isNot(_scope(revision: 'revision-b')));
    expect(base, isNot(_scope(platform: SocialPlatform.tiktok)));
  });

  test('display name edits do not change a known channel scope', () {
    PlatformPublishDefaultsScope scope(String name) =>
        PlatformPublishDefaultsScope.fromConnection(
          apiBaseUrl: 'https://staging.example.test/v1',
          ownerUserId: 'owner-a',
          platform: SocialPlatform.youtubeShorts,
          connection: SocialConnectionResult(
            platform: 'YOUTUBE_SHORTS',
            connected: true,
            connectionId: 'channel-a',
            connectionRevision: 'revision-a',
            displayName: name,
          ),
        )!;
    expect(scope('Before'), scope('After'));
  });

  test('scope requires a connected matching supported platform and identity',
      () {
    PlatformPublishDefaultsScope? scope(SocialConnectionResult? connection,
            {String owner = 'owner-a',
            String endpoint = 'https://api.example.test',
            SocialPlatform platform = SocialPlatform.youtubeShorts}) =>
        PlatformPublishDefaultsScope.fromConnection(
          apiBaseUrl: endpoint,
          ownerUserId: owner,
          platform: platform,
          connection: connection,
        );
    const known = SocialConnectionResult(
      platform: 'YOUTUBE_SHORTS',
      connected: true,
      connectionId: 'connection-a',
      connectionRevision: 'revision-a',
    );
    expect(scope(known), isNotNull);
    expect(scope(null), isNull);
    expect(scope(known, owner: ' '), isNull);
    expect(scope(known, endpoint: 'file:///local'), isNull);
    expect(scope(known, endpoint: 'https://user:password@api.example.test'),
        isNull);
    expect(scope(known, endpoint: 'https://api.example.test?secret=value'),
        isNull);
    expect(scope(known, platform: SocialPlatform.shopeeVideo), isNull);
    expect(
      scope(const SocialConnectionResult(
        platform: 'TIKTOK',
        connected: true,
        connectionId: 'connection-a',
        connectionRevision: 'revision-a',
      )),
      isNull,
    );
    expect(
      scope(const SocialConnectionResult(
        platform: 'YOUTUBE_SHORTS',
        connected: false,
        connectionId: 'connection-a',
        connectionRevision: 'revision-a',
      )),
      isNull,
    );
    expect(
      scope(const SocialConnectionResult(
        platform: 'YOUTUBE_SHORTS',
        connected: true,
        displayName: 'A channel name is not an identity',
      )),
      isNull,
    );
    expect(
      scope(const SocialConnectionResult(
        platform: 'YOUTUBE_SHORTS',
        connected: true,
        connectionId: 'legacy-connection',
        externalAccountId: 'legacy-external-account',
      )),
      isNotNull,
    );
  });

  test('only reusable choices are copied to a new clip for each platform', () {
    for (final platform in [
      SocialPlatform.tiktok,
      SocialPlatform.youtubeShorts,
      SocialPlatform.instagramReels,
      SocialPlatform.facebookReels,
    ]) {
      final defaults = PlatformPublishDefaults.fromSettings(platform, _chosen);
      final restored = defaults.applyTo(const PlatformPublishSettings());
      final expected = switch (platform) {
        SocialPlatform.tiktok => const PlatformPublishSettings(
            tiktokPublishMode: TikTokPublishMode.directPost),
        SocialPlatform.youtubeShorts => const PlatformPublishSettings(
            youtubeVisibility: YouTubeVisibility.public,
            youtubeMadeForKids: false),
        SocialPlatform.instagramReels =>
          const PlatformPublishSettings(instagramShareToFeed: false),
        SocialPlatform.facebookReels => const PlatformPublishSettings(
            facebookPublishMode: FacebookPublishMode.publish),
        _ => throw StateError('Unexpected test platform'),
      };
      expect(restored, expected, reason: platform.apiValue);
      expect(
          PlatformPublishDefaults.fromJson(defaults.toJson())
              ?.applyTo(const PlatformPublishSettings()),
          expected);
    }
  });

  test('applying defaults preserves all other current clip choices', () {
    final defaults = PlatformPublishDefaults.fromSettings(
      SocialPlatform.instagramReels,
      const PlatformPublishSettings(instagramShareToFeed: true),
    );
    expect(defaults.applyTo(_chosen),
        _chosen.copyWith(instagramShareToFeed: true));
  });

  test('nullable audience and Facebook mode retain their unset values', () {
    for (final platform in [
      SocialPlatform.youtubeShorts,
      SocialPlatform.facebookReels,
    ]) {
      final defaults = PlatformPublishDefaults.fromSettings(
          platform, const PlatformPublishSettings());
      final restored = PlatformPublishDefaults.fromJson(defaults.toJson())!;
      if (platform == SocialPlatform.youtubeShorts) {
        expect(restored.applyTo(_chosen).youtubeMadeForKids, isNull);
      } else {
        expect(restored.applyTo(_chosen).facebookPublishMode, isNull);
      }
    }
  });

  test('unsupported platforms cannot produce defaults', () {
    expect(
      () => PlatformPublishDefaults.fromSettings(
          SocialPlatform.shopeeVideo, _chosen),
      throwsArgumentError,
    );
  });

  test('unknown schema, fields, enums and wrong types are rejected', () {
    final valid = PlatformPublishDefaults.fromSettings(
            SocialPlatform.youtubeShorts, _chosen)
        .toJson();
    for (final invalid in <Map<String, Object?>>[
      {...valid, 'version': 99},
      {...valid, 'platform': 'SHOPEE_VIDEO'},
      {...valid, 'youtubeTitle': 'Do not replay this'},
      {
        ...valid,
        'values': {'visibility': 'surprise', 'madeForKids': false}
      },
      {
        ...valid,
        'values': {'visibility': 'public', 'madeForKids': 'false'}
      },
      {
        ...valid,
        'values': {'visibility': 'public'}
      },
      {
        ...valid,
        'values': {
          'visibility': 'public',
          'madeForKids': false,
          'containsSyntheticMedia': true,
        },
      },
    ]) {
      expect(PlatformPublishDefaults.fromJson(invalid), isNull);
    }
  });

  test('saved defaults survive store recreation but stay within their scope',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final sessions =
        PostDeeAuthSessionStore(initialSession: _session('owner-a'));
    final store = SharedPreferencesPlatformPublishDefaultsStore(
        preferences: preferences, sessionStore: sessions);
    final defaults = PlatformPublishDefaults.fromSettings(
        SocialPlatform.youtubeShorts, _chosen);
    await store.save(_scope(), defaults);
    final reopened = SharedPreferencesPlatformPublishDefaultsStore(
        preferences: preferences, sessionStore: sessions);
    expect((await reopened.load(_scope()))?.toJson(), defaults.toJson());
    expect(await reopened.load(_scope(channel: 'channel-b')), isNull);
    expect(await reopened.load(_scope(revision: 'revision-b')), isNull);
    expect(
        await reopened
            .load(_scope(endpoint: 'https://production.example.test')),
        isNull);
    sessions.signIn(_session('owner-b'));
    expect(await reopened.load(_scope(owner: 'owner-b')), isNull);
    await expectLater(
        reopened.load(_scope()), throwsA(isA<AuthSessionChangedException>()));
  });

  test('mismatched platform cannot be stored under another channel scope',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final sessions =
        PostDeeAuthSessionStore(initialSession: _session('owner-a'));
    final store = SharedPreferencesPlatformPublishDefaultsStore(
        preferences: preferences, sessionStore: sessions);
    await expectLater(
      store.save(_scope(),
          PlatformPublishDefaults.fromSettings(SocialPlatform.tiktok, _chosen)),
      throwsArgumentError,
    );
    expect(preferences.getKeys(), isEmpty);
  });

  test('corrupt or wrong-platform stored data returns no remembered values',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final sessions =
        PostDeeAuthSessionStore(initialSession: _session('owner-a'));
    final store = SharedPreferencesPlatformPublishDefaultsStore(
        preferences: preferences, sessionStore: sessions);
    await store.save(
        _scope(),
        PlatformPublishDefaults.fromSettings(
            SocialPlatform.youtubeShorts, _chosen));
    final key = preferences.getKeys().single;
    for (final invalid in [
      'broken JSON',
      '[]',
      jsonEncode(
          PlatformPublishDefaults.fromSettings(SocialPlatform.tiktok, _chosen)
              .toJson()),
    ]) {
      await preferences.setString(key, invalid);
      expect(await store.load(_scope()), isNull);
    }
    await preferences.setBool(key, true);
    expect(await store.load(_scope()), isNull);
  });

  test('unsigned sessions cannot access persisted defaults', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesPlatformPublishDefaultsStore(
      sessionStore: PostDeeAuthSessionStore(
          initialSession: const AuthSession(userId: 'owner-a')),
    );
    await expectLater(
        store.load(_scope()), throwsA(isA<AuthSessionChangedException>()));
  });

  for (final saving in [false, true]) {
    test(
        'A to B to A auth change invalidates pending ${saving ? 'save' : 'load'}',
        () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final sessions =
          PostDeeAuthSessionStore(initialSession: _session('owner-a'));
      final pending = Completer<SharedPreferences>();
      final store = SharedPreferencesPlatformPublishDefaultsStore(
          sessionStore: sessions, loadPreferences: () => pending.future);
      final operation = saving
          ? store.save(
              _scope(),
              PlatformPublishDefaults.fromSettings(
                  SocialPlatform.youtubeShorts, _chosen))
          : store.load(_scope());
      final assertion =
          expectLater(operation, throwsA(isA<AuthSessionChangedException>()));
      await Future<void>.delayed(Duration.zero);
      sessions.signIn(_session('owner-b'));
      sessions.signIn(_session('owner-a'));
      pending.complete(preferences);
      await assertion;
      expect(preferences.getKeys(), isEmpty);
    });
  }

  test('caller invalidation while opening preferences prevents save', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final sessions =
        PostDeeAuthSessionStore(initialSession: _session('owner-a'));
    final pending = Completer<SharedPreferences>();
    var current = true;
    final store = SharedPreferencesPlatformPublishDefaultsStore(
        sessionStore: sessions, loadPreferences: () => pending.future);
    final saving = store.save(
        _scope(),
        PlatformPublishDefaults.fromSettings(
            SocialPlatform.youtubeShorts, _chosen),
        isCurrent: () => current);
    final assertion =
        expectLater(saving, throwsA(isA<AuthSessionChangedException>()));
    await Future<void>.delayed(Duration.zero);
    current = false;
    pending.complete(preferences);
    await assertion;
    expect(preferences.getKeys(), isEmpty);
  });

  test(
      'late save rolls back when its form context changes during storage write',
      () async {
    final preferences = _PendingWritePreferences();
    final sessions =
        PostDeeAuthSessionStore(initialSession: _session('owner-a'));
    var current = true;
    final store = SharedPreferencesPlatformPublishDefaultsStore(
        preferences: preferences, sessionStore: sessions);
    final saving = store.save(
        _scope(),
        PlatformPublishDefaults.fromSettings(
            SocialPlatform.youtubeShorts, _chosen),
        isCurrent: () => current);
    final assertion =
        expectLater(saving, throwsA(isA<AuthSessionChangedException>()));
    await preferences.writeStarted.future;
    current = false;
    preferences.releaseWrite.complete();
    await assertion;
    expect(preferences.values, isEmpty);
  });

  test('save order follows user actions even when preference access is delayed',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final sessions =
        PostDeeAuthSessionStore(initialSession: _session('owner-a'));
    final pending = Completer<SharedPreferences>();
    var loads = 0;
    final store = SharedPreferencesPlatformPublishDefaultsStore(
      sessionStore: sessions,
      loadPreferences: () =>
          ++loads == 1 ? pending.future : Future.value(preferences),
    );
    final first = store.save(
        _scope(),
        PlatformPublishDefaults.fromSettings(
            SocialPlatform.youtubeShorts, _chosen));
    final second = store.save(
        _scope(),
        PlatformPublishDefaults.fromSettings(SocialPlatform.youtubeShorts,
            _chosen.copyWith(youtubeVisibility: YouTubeVisibility.private)));
    pending.complete(preferences);
    await Future.wait([first, second]);
    expect((await store.load(_scope()))?.applyTo(_chosen).youtubeVisibility,
        YouTubeVisibility.private);
  });

  test('account deletion clears all channels and endpoints for captured owner',
      () async {
    SharedPreferences.setMockInitialValues({'unrelated': 'keep'});
    final preferences = await SharedPreferences.getInstance();
    final sessions =
        PostDeeAuthSessionStore(initialSession: _session('owner-a'));
    final store = SharedPreferencesPlatformPublishDefaultsStore(
        preferences: preferences, sessionStore: sessions);
    final defaults = PlatformPublishDefaults.fromSettings(
        SocialPlatform.youtubeShorts, _chosen);
    await store.save(_scope(), defaults);
    await store.save(_scope(channel: 'channel-b'), defaults);
    await store.save(
        _scope(endpoint: 'https://production.example.test'), defaults);
    sessions.signIn(_session('owner-a.neighbor'));
    await store.save(_scope(owner: 'owner-a.neighbor'), defaults);
    sessions.signOut();
    await store.clearForDeletedAccount('owner-a');
    sessions.signIn(_session('owner-a'));
    expect(await store.load(_scope()), isNull);
    expect(await store.load(_scope(channel: 'channel-b')), isNull);
    sessions.signIn(_session('owner-a.neighbor'));
    expect(await store.load(_scope(owner: 'owner-a.neighbor')), isNotNull);
    expect(preferences.getString('unrelated'), 'keep');
  });

  test(
      'deletion invalidates a pending read and a pending write without revival',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final sessions =
        PostDeeAuthSessionStore(initialSession: _session('owner-a'));
    final pending = Completer<SharedPreferences>();
    final store = SharedPreferencesPlatformPublishDefaultsStore(
        sessionStore: sessions, loadPreferences: () => pending.future);
    final saving = store.save(
        _scope(),
        PlatformPublishDefaults.fromSettings(
            SocialPlatform.youtubeShorts, _chosen));
    final loading = store.load(_scope());
    final saveAssertion =
        expectLater(saving, throwsA(isA<AuthSessionChangedException>()));
    final loadAssertion =
        expectLater(loading, throwsA(isA<AuthSessionChangedException>()));
    await Future<void>.delayed(Duration.zero);
    sessions.signOut();
    final clearing = store.clearForDeletedAccount('owner-a');
    pending.complete(preferences);
    await Future.wait([saveAssertion, loadAssertion, clearing]);
    expect(preferences.getKeys(), isEmpty);
  });

  test('deletion after native write starts waits for it and leaves no defaults',
      () async {
    final preferences = _PendingWritePreferences();
    final sessions =
        PostDeeAuthSessionStore(initialSession: _session('owner-a'));
    final store = SharedPreferencesPlatformPublishDefaultsStore(
        preferences: preferences, sessionStore: sessions);
    final saving = store.save(
        _scope(),
        PlatformPublishDefaults.fromSettings(
            SocialPlatform.youtubeShorts, _chosen));
    final assertion =
        expectLater(saving, throwsA(isA<AuthSessionChangedException>()));
    await preferences.writeStarted.future;
    final clearing = store.clearForDeletedAccount('owner-a');
    preferences.releaseWrite.complete();
    await Future.wait([assertion, clearing]);
    expect(preferences.values, isEmpty);
    await expectLater(
        store.save(
            _scope(),
            PlatformPublishDefaults.fromSettings(
                SocialPlatform.youtubeShorts, _chosen)),
        throwsA(isA<AuthSessionChangedException>()));
    sessions.signIn(_session('owner-a'));
    expect(await store.load(_scope()), isNull);
  });
}
