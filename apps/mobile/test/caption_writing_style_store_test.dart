import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/models/caption_writing_style.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/captions/caption_writing_style_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

AuthSession _session(String owner) => AuthSession.authenticated(
      userId: owner,
      idToken: 'test-token-$owner',
    );

class _PendingWritePreferences implements SharedPreferences {
  final values = <String, String>{};
  final pendingWrite = Completer<void>();
  int writes = 0;
  int removals = 0;

  @override
  Future<bool> setString(String key, String value) async {
    writes++;
    if (writes == 1) await pendingWrite.future;
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    removals++;
    values.remove(key);
    return true;
  }

  @override
  String? getString(String key) => values[key];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('old caption requests omit writingStyle', () {
    expect(
      const GenerateRealClipCaptionRequest(videoS3Key: 'uploads/a/clip.mp4')
          .toJson(),
      {'videoS3Key': 'uploads/a/clip.mp4'},
    );
  });

  test('caption requests carry chosen style and bounded human examples', () {
    const style = CaptionWritingStyle(
      tone: CaptionWritingTone.directReview,
      length: CaptionWritingLength.short,
      emoji: CaptionWritingEmoji.none,
      examples: ['  ใช้จริงแล้วชอบตรงนี้ครับ  '],
    );
    expect(
      const GenerateRealClipCaptionRequest(
        videoS3Key: 'uploads/a/clip.mp4',
        writingStyle: style,
      ).toJson()['writingStyle'],
      {
        'tone': 'direct_review',
        'length': 'short',
        'emoji': 'none',
        'examples': ['ใช้จริงแล้วชอบตรงนี้ครับ'],
      },
    );
  });

  test('learning keeps only three distinct recent confirmed captions', () {
    var profile = const CaptionWritingStyleProfile();
    for (final caption in ['หนึ่ง', 'สอง', 'สาม', 'สี่', '  สอง  ', '']) {
      profile = profile.withLearnedCaption(caption);
    }
    expect(profile.style.examples, ['สอง', 'สี่', 'สาม']);
    expect(profile.style.tone, CaptionWritingTone.auto);
  });

  test('learning bounds long captions without splitting emoji surrogate', () {
    final text = '${'ก' * 499}😀จบ';
    final profile = const CaptionWritingStyleProfile().withLearnedCaption(text);
    expect(profile.style.examples.single, 'ก' * 499);
    expect(profile.style.examples.single.length, lessThanOrEqualTo(500));
  });

  test('turning memory off neither learns nor sends existing examples', () {
    const profile = CaptionWritingStyleProfile(
      rememberEdits: false,
      style: CaptionWritingStyle(
        tone: CaptionWritingTone.friendly,
        examples: ['ตัวอย่างเดิม'],
      ),
    );
    expect(profile.withLearnedCaption('ใหม่').style.examples, ['ตัวอย่างเดิม']);
    expect(profile.forGeneration.examples, isEmpty);
    expect(profile.forGeneration.tone, CaptionWritingTone.friendly);
  });

  test('profile storage restores preferences only for their owner', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final sessions = PostDeeAuthSessionStore(initialSession: _session('a'));
    final store = SharedPreferencesCaptionWritingStyleStore(
      preferences: preferences,
      sessionStore: sessions,
    );
    const profile = CaptionWritingStyleProfile(
      style: CaptionWritingStyle(
        tone: CaptionWritingTone.softSell,
        length: CaptionWritingLength.medium,
        emoji: CaptionWritingEmoji.light,
        examples: ['ข้อความของเอ'],
      ),
    );
    await store.save('a', profile);
    expect((await store.load('a')).style.toJson(), profile.style.toJson());
    sessions.signIn(_session('b'));
    expect((await store.load('b')).style.examples, isEmpty);
    await expectLater(
        store.load('a'), throwsA(isA<AuthSessionChangedException>()));
    await expectLater(
        store.save('a', profile), throwsA(isA<AuthSessionChangedException>()));
    await expectLater(
        store.clear('a'), throwsA(isA<AuthSessionChangedException>()));
    sessions.signIn(_session('a'));
    expect((await store.load('a')).style.examples, ['ข้อความของเอ']);
  });

  test('owner switch while preference access awaits prevents saving', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final pending = Completer<SharedPreferences>();
    final sessions = PostDeeAuthSessionStore(initialSession: _session('a'));
    final store = SharedPreferencesCaptionWritingStyleStore(
      sessionStore: sessions,
      loadPreferences: () => pending.future,
    );
    final saving = store.save('a', const CaptionWritingStyleProfile());
    final assertion =
        expectLater(saving, throwsA(isA<AuthSessionChangedException>()));
    sessions.signIn(_session('b'));
    pending.complete(preferences);
    await assertion;
    expect(preferences.getKeys(), isEmpty);
  });

  test('owner switch while preference access awaits prevents loading',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final pending = Completer<SharedPreferences>();
    final sessions = PostDeeAuthSessionStore(initialSession: _session('a'));
    final store = SharedPreferencesCaptionWritingStyleStore(
      sessionStore: sessions,
      loadPreferences: () => pending.future,
    );
    final loading = store.load('a');
    final assertion =
        expectLater(loading, throwsA(isA<AuthSessionChangedException>()));
    sessions.signOut();
    pending.complete(preferences);
    await assertion;
  });

  test('clearing memory preserves other accounts and unrelated local data',
      () async {
    SharedPreferences.setMockInitialValues({'other_setting': 'keep'});
    final preferences = await SharedPreferences.getInstance();
    final sessions = PostDeeAuthSessionStore(initialSession: _session('a'));
    final store = SharedPreferencesCaptionWritingStyleStore(
      preferences: preferences,
      sessionStore: sessions,
    );
    await store.save(
        'a', const CaptionWritingStyleProfile().withLearnedCaption('เอ'));
    sessions.signIn(_session('b'));
    await store.save(
        'b', const CaptionWritingStyleProfile().withLearnedCaption('บี'));
    sessions.signIn(_session('a'));
    await store.clear('a');
    expect((await store.load('a')).style.examples, isEmpty);
    expect(preferences.getString('other_setting'), 'keep');
    sessions.signIn(_session('b'));
    expect((await store.load('b')).style.examples, ['บี']);
  });

  test('corrupted or unsupported local profile falls back without leaking data',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final sessions = PostDeeAuthSessionStore(initialSession: _session('a'));
    final store = SharedPreferencesCaptionWritingStyleStore(
      preferences: preferences,
      sessionStore: sessions,
    );
    await store.save('a', const CaptionWritingStyleProfile());
    final key = preferences.getKeys().single;
    for (final invalid in [
      'broken json',
      jsonEncode({
        'version': 99,
        'style': {
          'examples': ['bad']
        }
      })
    ]) {
      await preferences.setString(key, invalid);
      expect((await store.load('a')).style.examples, isEmpty);
    }
  });

  test('successful account deletion clears captured owner after logout',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final sessions = PostDeeAuthSessionStore(initialSession: _session('a'));
    final store = SharedPreferencesCaptionWritingStyleStore(
      preferences: preferences,
      sessionStore: sessions,
    );
    await store.save(
        'a', const CaptionWritingStyleProfile().withLearnedCaption('เอ'));
    sessions.signIn(_session('b'));
    await store.save(
        'b', const CaptionWritingStyleProfile().withLearnedCaption('บี'));
    sessions.signOut();
    await store.clearForDeletedAccount('a');
    sessions.signIn(_session('a'));
    expect((await store.load('a')).style.examples, isEmpty);
    sessions.signIn(_session('b'));
    expect((await store.load('b')).style.examples, ['บี']);
  });

  test('account deletion invalidates a save waiting on local preferences',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final pending = Completer<SharedPreferences>();
    final sessions = PostDeeAuthSessionStore(initialSession: _session('a'));
    final waitingStore = SharedPreferencesCaptionWritingStyleStore(
      sessionStore: sessions,
      loadPreferences: () => pending.future,
    );
    final saving = waitingStore.save('a',
        const CaptionWritingStyleProfile().withLearnedCaption('ต้องไม่กลับมา'));
    final assertion =
        expectLater(saving, throwsA(isA<AuthSessionChangedException>()));
    await SharedPreferencesCaptionWritingStyleStore(preferences: preferences)
        .clearForDeletedAccount('a');
    pending.complete(preferences);
    await assertion;
    expect(preferences.getKeys(), isEmpty);
  });

  test('ordinary clear invalidates a save still waiting on preferences',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final pending = Completer<SharedPreferences>();
    final sessions = PostDeeAuthSessionStore(initialSession: _session('a'));
    final waitingStore = SharedPreferencesCaptionWritingStyleStore(
      sessionStore: sessions,
      loadPreferences: () => pending.future,
    );
    final clearingStore = SharedPreferencesCaptionWritingStyleStore(
      sessionStore: sessions,
      preferences: preferences,
    );
    final saving = waitingStore.save(
        'a', const CaptionWritingStyleProfile().withLearnedCaption('งานเก่า'));
    final assertion =
        expectLater(saving, throwsA(isA<AuthSessionChangedException>()));
    await clearingStore.clear('a');
    pending.complete(preferences);
    await assertion;
    expect(preferences.getKeys(), isEmpty);
    await clearingStore.save(
        'a', const CaptionWritingStyleProfile().withLearnedCaption('งานใหม่'));
    expect((await clearingStore.load('a')).style.examples, ['งานใหม่']);
  });

  for (final accountDeleted in [false, true]) {
    test(
        '${accountDeleted ? 'account deletion' : 'ordinary clear'} waits for a started write from another store instance',
        () async {
      final preferences = _PendingWritePreferences();
      final sessions = PostDeeAuthSessionStore(initialSession: _session('a'));
      final writingStore = SharedPreferencesCaptionWritingStyleStore(
        preferences: preferences,
        sessionStore: sessions,
      );
      final clearingStore = SharedPreferencesCaptionWritingStyleStore(
        preferences: preferences,
        sessionStore: sessions,
      );
      final saving = writingStore.save(
          'a',
          const CaptionWritingStyleProfile()
              .withLearnedCaption('งานที่เริ่มเขียนแล้ว'));
      final assertion =
          expectLater(saving, throwsA(isA<AuthSessionChangedException>()));
      await Future<void>.delayed(Duration.zero);
      expect(preferences.writes, 1);
      if (accountDeleted) sessions.signOut();
      final clearing = accountDeleted
          ? clearingStore.clearForDeletedAccount('a')
          : clearingStore.clear('a');
      await Future<void>.delayed(Duration.zero);
      final removalsBeforeWriteCompletes = preferences.removals;
      preferences.pendingWrite.complete();
      await assertion;
      await clearing;
      expect(removalsBeforeWriteCompletes, 0);
      expect(preferences.removals, 1);
      expect(preferences.values, isEmpty);
    });
  }
}
