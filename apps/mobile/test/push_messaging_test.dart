import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/auth/firebase_bootstrap.dart';
import 'package:postdee_mobile/features/notifications/firebase_push_messaging_gateway.dart';
import 'package:postdee_mobile/features/notifications/push_messaging_gateway.dart';
import 'package:postdee_mobile/features/notifications/push_notification.dart';

class FakeFirebaseMessagingClient implements FirebaseMessagingClient {
  FakeFirebaseMessagingClient({
    this.permissionGranted = true,
    this.token = 'device-token',
  });

  bool permissionGranted;
  final String? token;
  Future<bool> Function()? permissionHandler;
  Future<String?> Function()? tokenHandler;
  final foreground = StreamController<PushNotificationMessage>.broadcast();
  final opened = StreamController<PushNotificationMessage>.broadcast();
  var permissionRequests = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests += 1;
    return permissionHandler == null
        ? permissionGranted
        : await permissionHandler!();
  }

  @override
  Future<String?> getToken() async =>
      tokenHandler == null ? token : await tokenHandler!();

  Future<void> Function()? deleteTokenHandler;
  var deleteTokenCalls = 0;

  @override
  Future<void> deleteToken() async {
    deleteTokenCalls += 1;
    if (deleteTokenHandler != null) await deleteTokenHandler!();
  }

  @override
  Stream<PushNotificationMessage> get onForegroundMessage => foreground.stream;

  @override
  Stream<PushNotificationMessage> get onMessageOpenedApp => opened.stream;
}

void main() {
  test('notification center stores newest first and notifies listeners', () {
    final center = PostDeeNotificationCenter();
    var notifyCount = 0;
    center.addListener(() => notifyCount += 1);

    center.add(PostDeeNotification(
      title: 'a',
      body: '1',
      receivedAt: DateTime(2026, 1, 1),
    ));
    center.add(PostDeeNotification(
      title: 'b',
      body: '2',
      receivedAt: DateTime(2026, 1, 2),
    ));

    expect(center.items, hasLength(2));
    expect(center.items.first.title, 'b');
    expect(notifyCount, 2);

    center.clear();
    expect(center.items, isEmpty);
    expect(notifyCount, 3);
  });

  test('FirebasePushMessagingGateway forwards the token and foreground messages',
      () async {
    final center = PostDeeNotificationCenter();
    final client = FakeFirebaseMessagingClient();
    String? receivedToken;
    final gateway = FirebasePushMessagingGateway(
      client: client,
      center: center,
      sessionStore: _signedInStore(),
      onToken: (token, binding) async {
        receivedToken = token;
      },
      now: () => DateTime(2026, 6, 24),
    );

    await gateway.initialize();

    expect(client.permissionRequests, 1);
    expect(receivedToken, 'device-token');

    client.foreground.add(
      const PushNotificationMessage(
        title: 'โพสต์เผยแพร่แล้ว',
        body: 'TikTok',
        userId: 'account-a',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(center.items, hasLength(1));
    expect(center.items.first.title, 'โพสต์เผยแพร่แล้ว');
    expect(center.items.first.body, 'TikTok');

    await gateway.dispose();
  });

  test('FirebasePushMessagingGateway does nothing when permission is denied',
      () async {
    final center = PostDeeNotificationCenter();
    final client = FakeFirebaseMessagingClient(permissionGranted: false);
    final gateway = FirebasePushMessagingGateway(
      client: client,
      center: center,
      sessionStore: _signedInStore(),
    );

    await gateway.initialize();
    client.foreground.add(
      const PushNotificationMessage(title: 'x', body: 'y'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(center.items, isEmpty);

    await gateway.dispose();
  });

  test('account changes clear history immediately and register the new account',
      () async {
    final store = _signedInStore();
    final center = PostDeeNotificationCenter();
    final client = FakeFirebaseMessagingClient();
    final registrations = <String>[];
    final gateway = FirebasePushMessagingGateway(
      client: client,
      center: center,
      sessionStore: store,
      onToken: (token, binding) async {
        binding.ensureCurrent();
        registrations.add(store.session.userId!);
      },
    );
    await gateway.initialize();
    client.foreground.add(_messageFor('account-a'));
    await _flushEvents();
    expect(center.items, hasLength(1));

    store.clear();
    expect(center.items, isEmpty);
    client.foreground.add(_messageFor('account-a'));
    client.opened.add(_messageFor('account-a'));
    await _flushEvents();
    expect(center.items, isEmpty);

    store.signIn(const AuthSession(idToken: 'token-b', userId: 'account-b'));
    await _flushEvents();
    expect(registrations, ['account-a', 'account-b']);
    expect(client.permissionRequests, 1);
    client.foreground.add(_messageFor('account-a'));
    client.foreground.add(_messageFor('account-b'));
    client.opened.add(_messageFor('account-b'));
    await _flushEvents();
    expect(center.items, hasLength(2));
    expect(center.items.every((item) => item.body == 'account-b'), isTrue);
    await gateway.dispose();
  });

  test('pending permission from account A cannot initialize account B',
      () async {
    final store = _signedInStore();
    final permission = Completer<bool>();
    final client = FakeFirebaseMessagingClient()
      ..permissionHandler = () => permission.future;
    final center = PostDeeNotificationCenter();
    final registrations = <String>[];
    final gateway = FirebasePushMessagingGateway(
      client: client,
      center: center,
      sessionStore: store,
      onToken: (token, binding) async => registrations.add(token),
    );
    final pending = gateway.initialize();
    store.signIn(const AuthSession(idToken: 'token-b', userId: 'account-b'));
    permission.complete(true);
    await pending;
    client.foreground.add(_messageFor('account-b'));
    await _flushEvents();
    expect(registrations, isEmpty);
    expect(center.items, isEmpty);
    client.permissionHandler = null;
    await gateway.initialize();
    expect(registrations, ['device-token']);
    await gateway.dispose();
  });

  test('late token lookup cannot register a later account', () async {
    final store = _signedInStore();
    final tokens = <Completer<String?>>[];
    final client = FakeFirebaseMessagingClient()
      ..tokenHandler = () {
        final pending = Completer<String?>();
        tokens.add(pending);
        return pending.future;
      };
    final registrations = <String>[];
    final gateway = FirebasePushMessagingGateway(
      client: client,
      sessionStore: store,
      center: PostDeeNotificationCenter(),
      onToken: (token, binding) async {
        binding.ensureCurrent();
        registrations.add('${store.session.userId}:$token');
      },
    );
    final pendingA = gateway.initialize();
    await _flushEvents();
    store.signIn(const AuthSession(idToken: 'token-b', userId: 'account-b'));
    await _flushEvents();
    expect(tokens, hasLength(2));
    tokens[0].complete('old-token');
    await pendingA;
    expect(registrations, isEmpty);
    tokens[1].complete('new-token');
    await _flushEvents();
    expect(registrations, ['account-b:new-token']);
    await gateway.dispose();
  });

  test('pending token registration stays bound and does not delay delivery',
      () async {
    final store = _signedInStore();
    final registration = Completer<void>();
    AuthSessionBinding? original;
    final center = PostDeeNotificationCenter();
    final client = FakeFirebaseMessagingClient();
    final gateway = FirebasePushMessagingGateway(
      client: client,
      center: center,
      sessionStore: store,
      onToken: (token, binding) async {
        if (original == null) {
          original = binding;
          await registration.future;
          binding.ensureCurrent();
        }
      },
    );
    final pending = gateway.initialize();
    await pending;
    await _flushEvents();
    expect(original!.isCurrent, isTrue);
    client.foreground.add(_messageFor('account-a'));
    await _flushEvents();
    expect(center.items, hasLength(1));
    store.clear();
    expect(original!.isCurrent, isFalse);
    registration.complete();
    await _flushEvents();
    client.foreground.add(_messageFor('account-a'));
    await _flushEvents();
    expect(center.items, isEmpty);
    await gateway.dispose();
  });

  test('messages without a matching recipient are ignored', () async {
    final center = PostDeeNotificationCenter();
    final client = FakeFirebaseMessagingClient();
    final gateway = FirebasePushMessagingGateway(
      client: client,
      center: center,
      sessionStore: _signedInStore(),
    );
    await gateway.initialize();
    client.foreground.add(_messageFor('account-b'));
    client.opened.add(const PushNotificationMessage(title: 'old', body: 'data'));
    client.foreground.add(_messageFor('account-a'));
    await _flushEvents();
    expect(center.items, hasLength(1));
    await gateway.dispose();
  });

  test('recipient UID equality preserves leading and trailing spaces', () async {
    for (final userId in ['account-a', ' account-a ']) {
      final center = PostDeeNotificationCenter();
      final client = FakeFirebaseMessagingClient();
      final gateway = FirebasePushMessagingGateway(
        client: client,
        center: center,
        sessionStore: PostDeeAuthSessionStore(
          initialSession: AuthSession(idToken: 'token-a', userId: userId),
        ),
      );
      await gateway.initialize();
      client.foreground.add(_messageFor(
        userId == 'account-a' ? ' account-a ' : 'account-a',
      ));
      client.opened.add(PushNotificationMessage(
        title: 'Exact recipient',
        body: 'Publish result',
        userId: userId,
      ));
      await _flushEvents();

      expect(center.items, hasLength(1));
      expect(center.items.single.title, 'Exact recipient');
      await gateway.dispose();
    }
  });

  test('same-session calls share initialization and preserve history', () async {
    final store = _signedInStore();
    final permission = Completer<bool>();
    final client = FakeFirebaseMessagingClient()
      ..permissionHandler = () => permission.future;
    final center = PostDeeNotificationCenter();
    final gateway = FirebasePushMessagingGateway(
      client: client,
      center: center,
      sessionStore: store,
    );
    final first = gateway.initialize();
    final second = gateway.initialize();
    permission.complete(true);
    await Future.wait([first, second]);
    client.foreground.add(_messageFor('account-a'));
    await _flushEvents();
    store.updateDisplayName('Updated name');
    await gateway.initialize();
    expect(client.permissionRequests, 1);
    expect(center.items, hasLength(1));
    await gateway.dispose();
  });

  test('permission denial permits a later explicit retry', () async {
    final client = FakeFirebaseMessagingClient(permissionGranted: false);
    final registrations = <String>[];
    final gateway = FirebasePushMessagingGateway(
      client: client,
      center: PostDeeNotificationCenter(),
      sessionStore: _signedInStore(),
      onToken: (token, binding) async => registrations.add(token),
    );
    await gateway.initialize();
    expect(registrations, isEmpty);
    client.permissionGranted = true;
    await gateway.initialize();
    expect(client.permissionRequests, 2);
    expect(registrations, ['device-token']);
    await gateway.dispose();
  });

  test('initialization errors permit retry without duplicate delivery', () async {
    final client = FakeFirebaseMessagingClient()
      ..tokenHandler = () async => throw StateError('token unavailable');
    final center = PostDeeNotificationCenter();
    final gateway = FirebasePushMessagingGateway(
      client: client,
      center: center,
      sessionStore: _signedInStore(),
    );
    await expectLater(gateway.initialize(), throwsStateError);
    client.tokenHandler = null;
    await gateway.initialize();
    await gateway.initialize();
    client.foreground.add(_messageFor('account-a'));
    await _flushEvents();
    expect(center.items, hasLength(1));
    await gateway.dispose();
  });

  test('dispose during permission lookup prevents late registration', () async {
    final permission = Completer<bool>();
    final client = FakeFirebaseMessagingClient()
      ..permissionHandler = () => permission.future;
    final registrations = <String>[];
    final center = PostDeeNotificationCenter();
    final gateway = FirebasePushMessagingGateway(
      client: client,
      center: center,
      sessionStore: _signedInStore(),
      onToken: (token, binding) async => registrations.add(token),
    );
    final pending = gateway.initialize();
    await gateway.dispose();
    permission.complete(true);
    await pending;
    await gateway.initialize();
    client.foreground.add(_messageFor('account-a'));
    await _flushEvents();
    expect(registrations, isEmpty);
    expect(center.items, isEmpty);
  });

  test('sign-out deletes the device token so the old account stops receiving pushes',
      () async {
    final store = _signedInStore();
    final client = FakeFirebaseMessagingClient();
    final gateway = FirebasePushMessagingGateway(
      client: client,
      center: PostDeeNotificationCenter(),
      sessionStore: store,
      onToken: (_, __) async {},
    );
    await gateway.initialize();
    expect(client.deleteTokenCalls, 0);

    store.clear();
    await _flushEvents();

    expect(client.deleteTokenCalls, 1);
    await gateway.dispose();
  });

  test('the next account registers only after the old token is deleted',
      () async {
    final store = _signedInStore();
    final client = FakeFirebaseMessagingClient();
    final deletion = Completer<void>();
    client.deleteTokenHandler = () => deletion.future;
    final registrations = <String>[];
    final gateway = FirebasePushMessagingGateway(
      client: client,
      center: PostDeeNotificationCenter(),
      sessionStore: store,
      onToken: (token, binding) async {
        registrations.add(store.session.userId!);
      },
    );
    await gateway.initialize();

    store.clear();
    store.signIn(const AuthSession(idToken: 'token-b', userId: 'account-b'));
    await _flushEvents();
    expect(registrations, ['account-a']);

    deletion.complete();
    await _flushEvents();
    expect(registrations, ['account-a', 'account-b']);
    await gateway.dispose();
  });

  test('a failed token deletion does not block the next account', () async {
    final store = _signedInStore();
    final client = FakeFirebaseMessagingClient();
    client.deleteTokenHandler = () async => throw Exception('offline');
    final registrations = <String>[];
    final gateway = FirebasePushMessagingGateway(
      client: client,
      center: PostDeeNotificationCenter(),
      sessionStore: store,
      onToken: (token, binding) async {
        registrations.add(store.session.userId!);
      },
    );
    await gateway.initialize();

    store.clear();
    store.signIn(const AuthSession(idToken: 'token-b', userId: 'account-b'));
    await _flushEvents();

    expect(registrations, ['account-a', 'account-b']);
    await gateway.dispose();
  });

  test('sign-out without a fetched token deletes nothing', () async {
    final store = _signedInStore();
    final client = FakeFirebaseMessagingClient(permissionGranted: false);
    final gateway = FirebasePushMessagingGateway(
      client: client,
      center: PostDeeNotificationCenter(),
      sessionStore: store,
    );
    await gateway.initialize();

    store.clear();
    await _flushEvents();

    expect(client.deleteTokenCalls, 0);
    await gateway.dispose();
  });

  test('a signed-out account never initializes delivery', () async {
    final client = FakeFirebaseMessagingClient();
    final gateway = FirebasePushMessagingGateway(
      client: client,
      center: PostDeeNotificationCenter(),
      sessionStore: PostDeeAuthSessionStore(),
    );
    await gateway.initialize();
    expect(client.permissionRequests, 0);
    await gateway.dispose();
  });

  test('createPushMessagingGatewayFromConfig is disabled without Firebase', () {
    expect(
      createPushMessagingGatewayFromConfig(enableFirebaseAuth: false),
      isA<DisabledPushMessagingGateway>(),
    );
  });

  test(
      'createPushMessagingGatewayFromConfig is disabled when bootstrap fails',
      () {
    expect(
      createPushMessagingGatewayFromConfig(
        enableFirebaseAuth: true,
        firebaseBootstrapResult: const FirebaseBootstrapResult.setupError(
          'Firebase Auth is enabled but Firebase is not configured.',
        ),
      ),
      isA<DisabledPushMessagingGateway>(),
    );
  });
}

PostDeeAuthSessionStore _signedInStore() => PostDeeAuthSessionStore(
      initialSession: const AuthSession(idToken: 'token-a', userId: 'account-a'),
    );

PushNotificationMessage _messageFor(String userId) => PushNotificationMessage(
      title: 'Publish result',
      body: userId,
      userId: userId,
    );

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);
