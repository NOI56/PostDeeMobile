import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/features/billing/addon_pending_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _api = 'https://staging.example.test';
const _addonProductIds = [
  'postdee_post100_caption50',
  'postdee_post40_caption25',
  'postdee_post90_caption50',
  'postdee_post190_caption100',
];
const _grantSnapshots = <String, List<int>>{
  'postdee_post100_caption50': [100, 50],
  'postdee_post40_caption25': [40, 25],
  'postdee_post90_caption50': [90, 50],
  'postdee_post190_caption100': [190, 100],
};
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

  for (final productId in _addonProductIds) {
    test('v1 receipts retain exact $productId across restart and account scopes',
        () async {
      final receipt = AddonPendingRecord.fromJson({
        'version': 1,
        'productId': productId,
        'intentId': 'persisted-$productId',
        'transactionId': 'same-opaque-store-id',
        'baselineTransactionIds': ['older-transaction'],
      });
      await store().save(receipt);
      final restored = (await store().load())!;
      expect(restored.productId, productId);
      expect(restored.transactionId, 'same-opaque-store-id');
      expect(restored.transactionIdKind, 'STORE');
      expect(restored.baselineTransactionIds, ['older-transaction']);
      expect(restored.toJson()['version'], 1);
      expect(await store(api: 'https://production.example.test').load(), isNull);
      sessions.signIn(_session('owner-b'));
      expect(await store().load(), isNull);
      sessions.signIn(_session('owner-a'));
      expect((await store().load())!.toJson(), receipt.toJson());
    });
  }

  for (final grant in _grantSnapshots.entries) {
    test('v2 ${grant.key} snapshot survives intent and receipt persistence',
        () async {
      final intent = AddonPendingRecord(version: 2,
          productId: grant.key, intentId: 'snapshot-${grant.key}',
          expectedPostUnits: grant.value[0],
          expectedAiCaptions: grant.value[1],
          baselineTransactionIds: ['before-checkout']);
      final json = intent.toJson();
      expect(json['version'], 2);
      expect(json['expectedPostUnits'], grant.value[0]);
      expect(json['expectedAiCaptions'], grant.value[1]);
      expect(AddonPendingRecord.fromJson(json).toJson(), json);
      await store().save(intent);
      final restored = (await store().load())!;
      expect(restored.version, 2);
      expect(restored.expectedPostUnits, grant.value[0]);
      expect(restored.expectedAiCaptions, grant.value[1]);
      await store().save(AddonPendingRecord(version: restored.version,
          productId: restored.productId, intentId: restored.intentId,
          expectedPostUnits: restored.expectedPostUnits,
          expectedAiCaptions: restored.expectedAiCaptions,
          transactionId: 'snapshot-receipt', transactionIdKind: 'REVENUECAT',
          baselineTransactionIds: restored.baselineTransactionIds));
      final receipt = (await store().load())!;
      expect(receipt.transactionId, 'snapshot-receipt');
      expect(receipt.transactionIdKind, 'REVENUECAT');
      expect(receipt.expectedPostUnits, grant.value[0]);
      expect(receipt.expectedAiCaptions, grant.value[1]);
      expect(await store(api: 'https://production.example.test').load(), isNull);
    });
  }

  test('v1 serialization keeps its exact legacy shape without snapshots', () {
    final original = <String, Object?>{
      'version': 1, 'productId': 'unknown-historical-sku', 'intentId': 'legacy',
      'transactionId': 'legacy-receipt', 'transactionIdKind': 'STORE',
    };
    final restored = AddonPendingRecord.fromJson(original);
    expect(restored.version, 1);
    expect(restored.expectedPostUnits, isNull);
    expect(restored.expectedAiCaptions, isNull);
    expect(restored.toJson(), original);
  });

  test('snapshot schema rejects partial malformed or unbounded grants', () {
    final valid = <String, Object?>{
      'version': 2, 'productId': 'postdee_post40_caption25',
      'intentId': 'snapshot', 'expectedPostUnits': 40, 'expectedAiCaptions': 25,
    };
    for (final invalid in [
      {...valid}..remove('expectedPostUnits'),
      {...valid}..remove('expectedAiCaptions'),
      {...valid, 'version': 1},
      {...valid, 'version': 3},
      {...valid, 'version': 2.0},
      {...valid, 'arbitraryGrant': 100},
      for (final field in ['expectedPostUnits', 'expectedAiCaptions'])
        for (final value in [null, 0, -1, 1000001, 40.0, '40', true])
          {...valid, field: value},
    ]) {
      expect(() => AddonPendingRecord.fromJson(invalid),
          throwsA(isA<AddonPendingDataException>()), reason: '$invalid');
    }
    for (final field in ['expectedPostUnits', 'expectedAiCaptions']) {
      expect(() => AddonPendingRecord.fromJson({
        'version': 1, 'productId': 'old', 'intentId': 'old', field: null,
      }), throwsA(isA<AddonPendingDataException>()));
    }
    expect(() => AddonPendingRecord(version: 2,
        productId: 'sku', intentId: 'partial', expectedPostUnits: 40),
        throwsA(isA<AddonPendingDataException>()));
    expect(() => AddonPendingRecord(productId: 'sku', intentId: 'v1',
        expectedPostUnits: 40, expectedAiCaptions: 25),
        throwsA(isA<AddonPendingDataException>()));
    final bounded = AddonPendingRecord(version: 2,
        productId: 'sku', intentId: 'bounded',
        expectedPostUnits: 1000000, expectedAiCaptions: 1000000);
    expect(AddonPendingRecord.fromJson(bounded.toJson()).expectedPostUnits,
        1000000);
  });

  test('both stores keep grant snapshots immutable while a receipt is pending',
      () async {
    for (final pending in <AddonPendingStore>[
      store(), InMemoryAddonPendingStore(),
    ]) {
      final original = AddonPendingRecord(version: 2,
          productId: 'postdee_post40_caption25', intentId: 'immutable-snapshot',
          expectedPostUnits: 40, expectedAiCaptions: 25);
      await pending.save(original);
      for (final changed in [
        AddonPendingRecord(version: 2, productId: original.productId,
            intentId: original.intentId,
            expectedPostUnits: 90, expectedAiCaptions: 25),
        AddonPendingRecord(version: 2, productId: original.productId,
            intentId: original.intentId,
            expectedPostUnits: 40, expectedAiCaptions: 50),
        AddonPendingRecord(productId: original.productId,
            intentId: original.intentId),
      ]) {
        await expectLater(pending.save(changed),
            throwsA(isA<AddonPendingConflictException>()));
        expect((await pending.load())!.toJson(), original.toJson());
      }
      final receipt = AddonPendingRecord(version: 2,
          productId: original.productId, intentId: original.intentId,
          expectedPostUnits: 40, expectedAiCaptions: 25,
          transactionId: 'immutable-receipt');
      await pending.save(receipt);
      expect((await pending.load())!.toJson(), receipt.toJson());
      await expectLater(pending.save(AddonPendingRecord(
          productId: original.productId, intentId: original.intentId,
          transactionId: receipt.transactionId)),
          throwsA(isA<AddonPendingConflictException>()));
      expect((await pending.load())!.toJson(), receipt.toJson());
    }
  });

  test('an existing v1 intent cannot silently upgrade its recorded grant',
      () async {
    for (final pending in <AddonPendingStore>[
      store(), InMemoryAddonPendingStore(),
    ]) {
      final original = _record('retain-v1', transaction: 'old-receipt');
      await pending.save(original);
      await expectLater(pending.save(AddonPendingRecord(version: 2,
          productId: original.productId, intentId: original.intentId,
          transactionId: original.transactionId,
          expectedPostUnits: 100, expectedAiCaptions: 50)),
          throwsA(isA<AddonPendingConflictException>()));
      expect((await pending.load())!.toJson(), original.toJson());
    }
  });

  test('different SKU claims still share one persisted account-wide lock',
      () async {
    final results = await Future.wait(_addonProductIds.map((productId) async {
      try {
        await store().save(AddonPendingRecord(
            productId: productId, intentId: 'intent-$productId'));
        return productId;
      } on AddonPendingConflictException {
        return null;
      }
    }));
    final winner = results.whereType<String>().single;
    final claimed = (await store().load())!;
    expect(claimed.productId, winner);
    expect(claimed.intentId, 'intent-$winner');
    expect((await SharedPreferences.getInstance()).getKeys(), hasLength(1));
    await store().clear(intentId: 'different-intent');
    expect((await store().load())!.productId, winner);
  });

  test('a pending SKU cannot be replaced even when the intent ID matches',
      () async {
    final original = AddonPendingRecord(
        productId: _addonProductIds.first,
        intentId: 'shared-intent',
        transactionId: 'legacy-receipt');
    final persisted = store();
    final memory = InMemoryAddonPendingStore();
    for (final pending in <AddonPendingStore>[persisted, memory]) {
      await pending.save(original);
      for (final productId in _addonProductIds.skip(1)) {
        await expectLater(
            pending.save(AddonPendingRecord(
                productId: productId,
                intentId: original.intentId,
                transactionId: original.transactionId)),
            throwsA(isA<AddonPendingConflictException>()));
        expect((await pending.load())!.toJson(), original.toJson());
      }
    }
  });

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
