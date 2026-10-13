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
    this.initialMessage,
  });

  bool permissionGranted;
  String? token;
  final PushNotificationMessage? initialMessage;
  Future<bool> Function()? permissionHandler;
  Future<String?> Function()? tokenHandler;
  final foreground = StreamController<PushNotificationMessage>.broadcast();
  final opened = StreamController<PushNotificationMessage>.broadcast();
  final refreshed = StreamController<String>.broadcast();
  var permissionRequests = 0;
  var tokenDeletes = 0;

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<PushNotificationMessage?> getInitialMessage() async => initialMessage;

  @override
  Stream<String> get onTokenRefresh => refreshed.stream;

  @override
  Future<void> deleteToken() async {
    tokenDeletes += 1;
    token = 'rotated-device-token-$tokenDeletes';
  }

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

  @override
  Stream<PushNotificationMessage> get onForegroundMessage => foreground.stream;

  @override
  Stream<PushNotificationMessage> get onMessageOpenedApp => opened.stream;
}

class _RetryRotationClient extends FakeFirebaseMessagingClient {
  var attempts = 0;
  @override
  Future<void> deleteToken() async {
    attempts += 1;
    if (attempts == 1) throw StateError('SDK offline');
    await super.deleteToken();
  }
}

void main() {
  test('recipientless push cannot belong to a session without a stable UID', () async {
    final sessions = PostDeeAuthSessionStore(initialSession: const AuthSession(idToken: 'token'));
    final client = FakeFirebaseMessagingClient();
    final center = PostDeeNotificationCenter();
    final gateway = FirebasePushMessagingGateway(client: client, center: center, sessionStore: sessions);
    await gateway.start();
    client.foreground.add(const PushNotificationMessage(title: 'legacy', body: 'unscoped'));
    await Future<void>.delayed(Duration.zero);
    expect(center.items, isEmpty);
    await gateway.dispose();
  });

  test('a failed SDK rotation blocks new ownership until a retry succeeds',
      () async {
    final client = _RetryRotationClient();
    final session = PostDeeAuthSessionStore(
        initialSession: const AuthSession(userId: 'owner', idToken: 'token'));
    final registrations = <String>[];
    final gateway = FirebasePushMessagingGateway(
      client: client,
      sessionStore: session,
      center: PostDeeNotificationCenter(),
      registerToken: (token, owner) async =>
          registrations.add('${owner.userId}:$token'),
    );
    await gateway.start();
    session.signIn(const AuthSession(userId: 'other', idToken: 'other-token'));
    await Future<void>.delayed(Duration.zero);
    expect(registrations, ['owner:device-token']);
    await gateway.initialize();
    expect(client.attempts, 2);
    expect(registrations.last, 'other:rotated-device-token-1');
    await gateway.dispose();
  });
  test('fast logout and switch rotates the OS token even if unregister fails',
      () async {
    final client = FakeFirebaseMessagingClient();
    final session = PostDeeAuthSessionStore(
        initialSession: const AuthSession(userId: 'owner', idToken: 'token'));
    final registrations = <String>[];
    final gateway = FirebasePushMessagingGateway(
      client: client,
      sessionStore: session,
      center: PostDeeNotificationCenter(),
      registerToken: (token, owner) async =>
          registrations.add('${owner.userId}:$token'),
      unregisterToken: (_, __) async => throw StateError('offline'),
    );
    await gateway.start();
    session.clear();
    session.signIn(const AuthSession(userId: 'other', idToken: 'other-token'));
    await Future<void>.delayed(Duration.zero);
    expect(client.tokenDeletes, 1);
    expect(registrations.last, 'other:rotated-device-token-1');
    client.refreshed.add('stale-owner-token');
    await Future<void>.delayed(Duration.zero);
    expect(registrations.last, 'other:rotated-device-token-1');
    expect(registrations.any((value) => value.contains('stale-owner-token')),
        isFalse);
    await gateway.dispose();
  });
  test('a late timed-out registration reasserts the current account', () async {
    const ownerSession = AuthSession(userId: 'owner', idToken: 'owner-token');
    final store = PostDeeAuthSessionStore(initialSession: ownerSession);
    final pending = Completer<void>();
    final registrations = <String>[];
    final removals = <String>[];
    final gateway = FirebasePushMessagingGateway(
      client: FakeFirebaseMessagingClient(),
      center: PostDeeNotificationCenter(),
      sessionStore: store,
      operationTimeout: const Duration(milliseconds: 10),
      registerToken: (token, session) {
        registrations.add(session.userId!);
        return session.userId == 'owner'
            ? pending.future
            : Future<void>.value();
      },
      unregisterToken: (token, session) async => removals.add(session.userId!),
    );
    await gateway.start();
    store.signIn(const AuthSession(userId: 'other', idToken: 'other-token'));
    await Future<void>.delayed(Duration.zero);
    expect(registrations.last, 'other');
    pending.complete();
    await Future<void>.delayed(Duration.zero);
    expect(removals, contains('owner'));
    expect(registrations, ['owner', 'other', 'other']);
    await gateway.dispose();
  });
  test('a failed device registration can retry on the next bell tap', () async {
    var registrations = 0;
    final gateway = FirebasePushMessagingGateway(
      client: FakeFirebaseMessagingClient(),
      sessionStore: PostDeeAuthSessionStore(
          initialSession:
              const AuthSession(userId: 'owner', idToken: 'owner-token')),
      center: PostDeeNotificationCenter(),
      registerToken: (_, __) async {
        registrations += 1;
        if (registrations == 1) throw StateError('offline');
      },
    );
    await gateway.start();
    await gateway.initialize();
    expect(registrations, 2);
    await gateway.dispose();
  });
  const owner = AuthSession(userId: 'owner', idToken: 'owner-token');
  test('push rebinds refreshed tokens and isolates account changes', () async {
    final store = PostDeeAuthSessionStore(initialSession: owner);
    final center = PostDeeNotificationCenter();
    final client = FakeFirebaseMessagingClient();
    final bindings = <String>[];
    final removals = <String>[];
    final gateway = FirebasePushMessagingGateway(
      client: client,
      center: center,
      sessionStore: store,
      registerToken: (token, session) async =>
          bindings.add('${session.userId}:$token'),
      unregisterToken: (token, session) async =>
          removals.add('${session.userId}:$token'),
    );
    await gateway.start();
    expect(client.permissionRequests, 0);
    expect(bindings, ['owner:device-token']);
    client.token = 'new-token';
    client.refreshed.add('new-token');
    await Future<void>.delayed(Duration.zero);
    expect(bindings.last, 'owner:new-token');
    client.foreground.add(const PushNotificationMessage(
        title: 'owner', body: '', userId: 'owner', postId: 'post-1'));
    await Future<void>.delayed(Duration.zero);
    expect(center.items.single.postId, 'post-1');
    store.signIn(const AuthSession(userId: 'other', idToken: 'other-token'));
    expect(center.items, isEmpty);
    await Future<void>.delayed(Duration.zero);
    client.foreground.add(const PushNotificationMessage(
        title: 'old owner', body: '', userId: 'owner'));
    await Future<void>.delayed(Duration.zero);
    expect(center.items, isEmpty);
    expect(bindings.last, startsWith('other:'));
    expect(removals, contains('owner:new-token'));
    store.clear();
    await Future<void>.delayed(Duration.zero);
    expect(client.tokenDeletes, 2);
    await gateway.dispose();
  });

  test('cold-start tap keeps post identity and opens once for matching account',
      () async {
    final store = PostDeeAuthSessionStore();
    final openedPosts = <String>[];
    final gateway = FirebasePushMessagingGateway(
      client: FakeFirebaseMessagingClient(
          initialMessage: const PushNotificationMessage(
        title: 'published',
        body: 'done',
        postId: 'post-1',
        userId: 'owner',
      )),
      center: PostDeeNotificationCenter(),
      sessionStore: store,
      onOpenPost: openedPosts.add,
    );
    await gateway.start();
    expect(openedPosts, isEmpty);
    store.signIn(owner);
    await Future<void>.delayed(Duration.zero);
    expect(openedPosts, ['post-1']);
    store.updateDisplayName('Name');
    expect(openedPosts, ['post-1']);
    await gateway.dispose();
  });

  test('cold-start tap is discarded for the first mismatched signed-in owner',
      () async {
    final store = PostDeeAuthSessionStore();
    final center = PostDeeNotificationCenter();
    final openedPosts = <String>[];
    final gateway = FirebasePushMessagingGateway(
      client: FakeFirebaseMessagingClient(
          initialMessage: const PushNotificationMessage(
        title: 'published',
        body: 'done',
        postId: 'owner-post',
        userId: 'owner',
      )),
      center: center,
      sessionStore: store,
      onOpenPost: openedPosts.add,
    );
    await gateway.start();
    store.signIn(const AuthSession(userId: 'other', idToken: 'other-token'));
    await Future<void>.delayed(Duration.zero);
    expect(openedPosts, isEmpty);
    expect(center.items, isEmpty);
    store.clear();
    store.signIn(owner);
    await Future<void>.delayed(Duration.zero);
    expect(openedPosts, isEmpty);
    expect(center.items, isEmpty);
    await gateway.dispose();
  });

  test('messages received after logout are discarded rather than deferred',
      () async {
    final store = PostDeeAuthSessionStore(initialSession: owner);
    final center = PostDeeNotificationCenter();
    final client = FakeFirebaseMessagingClient();
    final openedPosts = <String>[];
    final gateway = FirebasePushMessagingGateway(
      client: client,
      center: center,
      sessionStore: store,
      onOpenPost: openedPosts.add,
    );
    await gateway.start();
    store.clear();
    const message = PushNotificationMessage(
        title: 'published',
        body: 'done',
        postId: 'owner-post',
        userId: 'owner');
    client.foreground.add(message);
    client.opened.add(message);
    await Future<void>.delayed(Duration.zero);
    store.signIn(owner);
    await Future<void>.delayed(Duration.zero);
    expect(openedPosts, isEmpty);
    expect(center.items, isEmpty);
    await gateway.dispose();
  });

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

  test(
      'FirebasePushMessagingGateway forwards the token and foreground messages',
      () async {
    final center = PostDeeNotificationCenter();
    final client = FakeFirebaseMessagingClient();
    String? receivedToken;
    final gateway = FirebasePushMessagingGateway(
      client: client,
      center: center,
      sessionStore: PostDeeAuthSessionStore(initialSession: owner),
      onToken: (token) => receivedToken = token,
      now: () => DateTime(2026, 6, 24),
    );

    await gateway.initialize();

    expect(client.permissionRequests, 1);
    expect(receivedToken, 'device-token');

    client.foreground.add(
      const PushNotificationMessage(
          title: 'โพสต์เผยแพร่แล้ว', body: 'TikTok', userId: 'owner'),
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
        sessionStore: PostDeeAuthSessionStore(initialSession: owner));

    await gateway.initialize();
    client.foreground.add(
      const PushNotificationMessage(title: 'x', body: 'y'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(center.items, isEmpty);

    await gateway.dispose();
  });

  test('same-UID new sign-in invalidates registration binding and clears history', () async {
    final sessions = PostDeeAuthSessionStore(initialSession: const AuthSession(userId: 'owner', idToken: 'token'));
    final client = FakeFirebaseMessagingClient();
    final center = PostDeeNotificationCenter();
    final bindings = <AuthSessionBinding>[];
    final gateway = FirebasePushMessagingGateway(client: client, center: center, sessionStore: sessions,
      registerBoundToken: (token, binding) async { bindings.add(binding); });
    await gateway.start();
    center.add(PostDeeNotification(title: 'private', body: 'old', receivedAt: DateTime(2026)));
    sessions.signIn(const AuthSession(userId: 'owner', idToken: 'new-token'));
    expect(center.items, isEmpty);
    expect(bindings.first.isCurrent, isFalse);
    await gateway.initialize();
    expect(bindings.last.isCurrent, isTrue);
    expect(client.tokenDeletes, 1);
    await gateway.dispose();
  });

  test('bound registration keeps its original lifecycle while cleanup reasserts a new owner', () async {
    final sessions = PostDeeAuthSessionStore(initialSession: const AuthSession(userId: 'owner', idToken: 'token'));
    final client = FakeFirebaseMessagingClient();
    final registered = Completer<void>();
    final started = Completer<void>();
    final bindings = <AuthSessionBinding>[];
    final gateway = FirebasePushMessagingGateway(client: client, sessionStore: sessions,
      registerBoundToken: (token, binding) {
        bindings.add(binding);
        if (bindings.length == 1) { started.complete(); return registered.future; }
        return Future<void>.value();
      }, unregisterToken: (_, __) async {});
    final starting = gateway.start();
    await started.future;
    sessions.signIn(const AuthSession(userId: 'next', idToken: 'next-token'));
    expect(bindings.first.isCurrent, isFalse);
    registered.complete();
    await starting;
    await gateway.initialize();
    expect(bindings.last.isCurrent, isTrue);
    await gateway.dispose();
  });

  test('a delayed explicit permission response cannot initialize a later sign-in', () async {
    final permission = Completer<bool>();
    final sessions = PostDeeAuthSessionStore(initialSession: const AuthSession(userId: 'owner', idToken: 'token'));
    final client = FakeFirebaseMessagingClient(permissionGranted: false)..permissionHandler = () => permission.future;
    var registrations = 0;
    final gateway = FirebasePushMessagingGateway(client: client, sessionStore: sessions,
      registerBoundToken: (_, __) async { registrations++; });
    await gateway.start();
    final initialize = gateway.initialize();
    await Future<void>.delayed(Duration.zero);
    sessions.signIn(const AuthSession(userId: 'next', idToken: 'next-token'));
    permission.complete(true);
    await initialize;
    expect(registrations, 0);
    await gateway.dispose();
  });

  test('createPushMessagingGatewayFromConfig is disabled without Firebase', () {
    expect(
      createPushMessagingGatewayFromConfig(enableFirebaseAuth: false),
      isA<DisabledPushMessagingGateway>(),
    );
  });

  test('createPushMessagingGatewayFromConfig is disabled when bootstrap fails',
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
