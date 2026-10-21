import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/features/billing/addon_pending_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _api = 'https://staging.example.test';
AuthSession _session(String owner) =>
    AuthSession(userId: owner, idToken: 'test-token');
AddonPendingRecord _record(String intent, {String? transaction}) =>
    AddonPendingRecord(
        productId: 'postdee_post100_caption50',
        intentId: intent,
        transactionId: transaction,
        baselineTransactionIds: ['previous-transaction']);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PostDeeAuthSessionStore sessions;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sessions = PostDeeAuthSessionStore(initialSession: _session('owner-a'));
  });
  SharedPreferencesAddonPendingStore store(
          {String api = _api,
          Future<SharedPreferences> Function()? loadPreferences}) =>
      SharedPreferencesAddonPendingStore(
          sessionStore: sessions,
          apiBaseUrl: api,
          loadPreferences: loadPreferences);

  test('strict records round-trip and never retain a mutable baseline', () {
    final source = ['old'];
    final pending = AddonPendingRecord(
        productId: 'sku', intentId: 'intent', baselineTransactionIds: source);
    source.add('changed');
    expect(pending.baselineTransactionIds, ['old']);
    expect(AddonPendingRecord.fromJson(pending.toJson()).toJson(),
        pending.toJson());
    for (final invalid in [
      {...pending.toJson(), 'token': 'secret'},
      {...pending.toJson(), 'version': 2},
      {...pending.toJson(), 'intentId': ''},
      {...pending.toJson(), 'transactionId': ' '},
      {
        ...pending.toJson(),
        'baselineTransactionIds': ['same', 'same']
      },
      {
        ...pending.toJson(),
        'baselineTransactionIds': [1]
      },
    ]) {
      expect(() => AddonPendingRecord.fromJson(invalid),
          throwsA(isA<AddonPendingDataException>()));
    }
  });

  test(
      'legacy receipts default to STORE and RevenueCat selectors retain their namespace',
      () {
    final legacy = AddonPendingRecord.fromJson({
      'version': 1,
      'productId': 'sku',
      'intentId': 'legacy',
      'transactionId': 'old-id'
    });
    expect(legacy.transactionIdKind, 'STORE');
    final history = AddonPendingRecord(
        productId: 'sku',
        intentId: 'history',
        transactionId: 'rc-internal-id',
        transactionIdKind: 'REVENUECAT');
    expect(AddonPendingRecord.fromJson(history.toJson()).transactionIdKind,
        'REVENUECAT');
    for (final invalid in [
      {...history.toJson(), 'transactionIdKind': 'UNKNOWN'},
      {...history.toJson(), 'transactionIdKind': 1},
      {
        'version': 1,
        'productId': 'sku',
        'intentId': 'intent',
        'transactionIdKind': 'REVENUECAT'
      },
    ]) {
      expect(() => AddonPendingRecord.fromJson(invalid),
          throwsA(isA<AddonPendingDataException>()));
    }
    expect(
        () => AddonPendingRecord(
            productId: 'sku',
            intentId: 'intent',
            transactionIdKind: 'REVENUECAT'),
        throwsA(isA<AddonPendingDataException>()));
  });

  test(
      'an existing receipt cannot be overwritten with the same ID in another namespace',
      () async {
    final pending = store();
    await pending.save(_record('intent', transaction: 'same-id'));
    await expectLater(
        pending.save(AddonPendingRecord(
            productId: 'postdee_post100_caption50',
            intentId: 'intent',
            transactionId: 'same-id',
            transactionIdKind: 'REVENUECAT')),
        throwsA(isA<AddonPendingConflictException>()));
    expect((await pending.load())?.transactionIdKind, 'STORE');
  });

  test(
      'persists a receipt across store recreation and scopes the exact API and owner',
      () async {
    await store().save(_record('intent-1', transaction: 'store-txn'));
    expect((await store().load())?.transactionId, 'store-txn');
    expect(await store(api: 'https://production.example.test').load(), isNull);
    sessions.signIn(_session('owner-b'));
    expect(await store().load(), isNull);
    await store().save(_record('intent-b'));
    sessions.signIn(_session('owner-a'));
    expect((await store().load())?.intentId, 'intent-1');
  });

  test('claims only one intent across simultaneous service instances',
      () async {
    final one = store(), two = store();
    final results = await Future.wait([
      one.save(_record('one')),
      two.save(_record('two'))
    ].map((operation) async {
      try {
        await operation;
        return true;
      } on AddonPendingConflictException {
        return false;
      }
    }));
    expect(results.where((result) => result), hasLength(1));
    expect((await store().load())?.intentId, 'one');
  });

  test(
      'updates only the claimed intent and compare-and-clear preserves a later purchase',
      () async {
    final pending = store();
    await pending.save(_record('one'));
    await pending.save(_record('one', transaction: 'receipt'));
    await pending.clear(intentId: 'different');
    expect((await pending.load())?.transactionId, 'receipt');
    await pending.clear(intentId: 'one');
    await store().save(_record('two'));
    await pending.clear(intentId: 'one');
    expect((await pending.load())?.intentId, 'two');
  });

  test('corrupt persisted data blocks load, overwrite and ordinary clear',
      () async {
    await store().save(_record('one'));
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getKeys().single;
    await prefs.setString(key, '{broken-json');
    await expectLater(
        store().load(), throwsA(isA<AddonPendingDataException>()));
    await expectLater(store().save(_record('two')),
        throwsA(isA<AddonPendingDataException>()));
    await expectLater(store().clear(intentId: 'one'),
        throwsA(isA<AddonPendingDataException>()));
    expect(prefs.getString(key), '{broken-json');
  });

  test('a delayed old session cannot write after logout and same-owner login',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final loader = Completer<SharedPreferences>();
    final old = store(loadPreferences: () => loader.future);
    final saving = old.save(_record('old-session'));
    final failed =
        expectLater(saving, throwsA(isA<AuthSessionChangedException>()));
    await Future<void>.delayed(Duration.zero);
    sessions.signOut();
    sessions.signIn(_session('owner-a'));
    loader.complete(prefs);
    await failed;
    expect(await store().load(), isNull);
  });

  test('stale bindings cannot clear pending data belonging to a new login',
      () async {
    final old = store();
    await old.save(_record('retained'));
    sessions.signIn(_session('owner-a'));
    await expectLater(old.clear(intentId: 'retained'),
        throwsA(isA<AuthSessionChangedException>()));
    expect((await store().load())?.intentId, 'retained');
  });

  test(
      'missing stable UID never writes and records contain no auth credentials',
      () async {
    sessions.signIn(const AuthSession(idToken: 'secret-only-token'));
    await expectLater(store().save(_record('missing-uid')),
        throwsA(isA<AuthSessionChangedException>()));
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    sessions.signIn(_session('owner-a'));
    await store().save(_record('one'));
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefs.getKeys().single)!;
    expect(raw, isNot(contains('test-token')));
    expect(jsonDecode(raw), isNot(contains('owner-a')));
  });

  test(
      'verified account deletion clears only its API and owner key even if corrupt',
      () async {
    await store().save(_record('staging'));
    await store(api: 'https://production.example.test')
        .save(_record('production'));
    sessions.signIn(_session('owner-b'));
    await store().save(_record('other-owner'));
    sessions.signIn(_session('owner-a'));
    final target = store();
    final prefs = await SharedPreferences.getInstance();
    final targetKey = prefs.getKeys().singleWhere((key) =>
        prefs.getString(key)?.contains('"intentId":"staging"') ?? false);
    await prefs.setString(targetKey, '{corrupt');
    await target.clearForDeletedAccount();
    expect(await target.load(), isNull);
    expect(
        (await store(api: 'https://production.example.test').load())?.intentId,
        'production');
    sessions.signIn(_session('owner-b'));
    expect((await store().load())?.intentId, 'other-owner');
  });

  test('in-memory adapter also claims and compare-clears intents', () async {
    final pending = InMemoryAddonPendingStore();
    await pending.save(_record('one'));
    await expectLater(pending.save(_record('two')),
        throwsA(isA<AddonPendingConflictException>()));
    await pending.clear(intentId: 'other');
    expect((await pending.load())?.intentId, 'one');
    await pending.clear(intentId: 'one');
    expect(await pending.load(), isNull);
  });
}
