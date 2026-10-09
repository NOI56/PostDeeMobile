import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../../core/auth/auth_session.dart';
import '../../core/auth/firebase_bootstrap.dart';
import '../../core/config/app_config.dart';
import 'push_messaging_gateway.dart';
import 'push_notification.dart';

/// A plain push message, decoupled from the firebase_messaging SDK so the
/// gateway logic can be unit-tested with a fake client.
class PushNotificationMessage {
  const PushNotificationMessage({
    required this.title,
    required this.body,
    this.postId,
    this.userId,
  });

  final String title;
  final String body;
  final String? postId;
  final String? userId;
}

/// Thin, testable wrapper over the parts of firebase_messaging we use.
abstract class FirebaseMessagingClient {
  Future<bool> hasPermission();
  Future<bool> requestPermission();

  Future<String?> getToken();
  Future<void> deleteToken();
  Future<PushNotificationMessage?> getInitialMessage();
  Stream<String> get onTokenRefresh;

  /// Messages received while the app is in the foreground.
  Stream<PushNotificationMessage> get onForegroundMessage;

  /// Messages tapped by the user to open the app from background.
  Stream<PushNotificationMessage> get onMessageOpenedApp;
}

/// Real Apple/Google push gateway backed by FCM. The platform calls are hidden
/// behind [FirebaseMessagingClient] so the mapping logic stays unit-testable.
///
/// Requires configured Firebase Cloud Messaging and, on iOS, an APNs key and
/// push capability. Account changes rotate the SDK token before registering it
/// to the new owner; SDK/network failures must be retried on the next bell tap.
class FirebasePushMessagingGateway
    implements PushMessagingGateway, PushMessagingLifecycle {
  FirebasePushMessagingGateway({
    required FirebaseMessagingClient client,
    PostDeeNotificationCenter? center,
    void Function(String token)? onToken,
    PostDeeAuthSessionStore? sessionStore,
    Future<void> Function(String token, AuthSession session)? registerToken,
    Future<void> Function(String token, AuthSession session)? unregisterToken,
    void Function(String postId)? onOpenPost,
    Duration operationTimeout = const Duration(seconds: 5),
    DateTime Function() now = DateTime.now,
  })  : assert(operationTimeout > Duration.zero),
        _client = client,
        _center = center ?? PostDeeNotificationCenter.instance,
        _onToken = onToken,
        _sessionStore = sessionStore ?? PostDeeAuthSessionStore.instance,
        _registerToken = registerToken,
        _unregisterToken = unregisterToken,
        _onOpenPost = onOpenPost,
        _operationTimeout = operationTimeout,
        _now = now;

  final FirebaseMessagingClient _client;
  final PostDeeNotificationCenter _center;
  final void Function(String token)? _onToken;
  final DateTime Function() _now;
  final PostDeeAuthSessionStore _sessionStore;
  final Future<void> Function(String token, AuthSession session)?
      _registerToken;
  final Future<void> Function(String token, AuthSession session)?
      _unregisterToken;
  final void Function(String postId)? _onOpenPost;
  final Duration _operationTimeout;

  bool _started = false;
  bool _disposed = false;
  bool _permissionGranted = false;
  int _accountGeneration = 0;
  int _tokenRevision = 0;
  bool _needsTokenRotation = false;
  Future<void>? _rotationFuture;
  String? _ownerUserId;
  String? _latestToken;
  String? _registeredToken;
  AuthSession? _registeredSession;
  PushNotificationMessage? _pendingInitialMessage;
  Future<void> _syncFuture = Future<void>.value();
  Future<void>? _startFuture;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<PushNotificationMessage>? _foregroundSubscription;
  StreamSubscription<PushNotificationMessage>? _openedSubscription;

  @override
  Future<void> initialize() async {
    await start();
    if (_disposed) return;
    // Recheck permission on an explicit bell tap, including a previously denied
    // permission that the user later enabled in system settings.
    _permissionGranted = await _client.requestPermission();
    await _scheduleSync();
  }

  @override
  Future<void> start() => _startFuture ??= _start();

  Future<void> _start() async {
    if (_disposed) return;
    _started = true;
    _ownerUserId = _sessionStore.session.stableUserId;
    _sessionStore.addListener(_handleSessionChanged);
    _foregroundSubscription = _client.onForegroundMessage.listen(
      (message) => _handleMessage(message),
    );
    _openedSubscription = _client.onMessageOpenedApp.listen(
      (message) => _handleMessage(message, opened: true),
    );
    _tokenSubscription = _client.onTokenRefresh.listen((_) {
      // A refresh event may have been queued before a logout or rotation. Read
      // the SDK's current token rather than trusting that event's old value.
      _latestToken = null;
      _tokenRevision += 1;
      unawaited(_scheduleSync());
    });
    try {
      _permissionGranted =
          await _client.hasPermission().timeout(_operationTimeout);
      final initial =
          await _client.getInitialMessage().timeout(_operationTimeout);
      if (!_disposed && initial != null) {
        _pendingInitialMessage = initial;
        _consumeInitialMessage();
      }
    } catch (_) {
      // Push is optional; unavailable platform services do not block the shell.
    }
    await _scheduleSync();
  }

  void _handleSessionChanged() {
    final session = _sessionStore.session;
    final owner = session.isSignedIn ? session.stableUserId : null;
    if (owner != _ownerUserId) {
      if (_ownerUserId != null) {
        _needsTokenRotation = true;
        _latestToken = null;
        _tokenRevision += 1;
      }
      _ownerUserId = owner;
      _accountGeneration += 1;
      _center.clear();
      unawaited(_scheduleSync());
    }
    _consumeInitialMessage();
  }

  void _consumeInitialMessage() {
    final message = _pendingInitialMessage;
    final session = _sessionStore.session;
    if (message == null || !session.isSignedIn) return;
    _pendingInitialMessage = null;
    _handleMessage(message, opened: true);
  }

  Future<void> _scheduleSync() {
    _syncFuture = _syncFuture.then((_) => _syncAccount()).catchError((_) {});
    return _syncFuture;
  }

  Future<void> _syncAccount() async {
    if (!_started || _disposed) return;
    final generation = _accountGeneration;
    final revision = _tokenRevision;
    final session = _sessionStore.session;
    final owner = session.isSignedIn ? session.stableUserId : null;
    final oldToken = _registeredToken;
    final oldSession = _registeredSession;
    if (oldToken != null &&
        (oldSession?.stableUserId != owner ||
            (_latestToken != null && oldToken != _latestToken))) {
      _registeredToken = null;
      _registeredSession = null;
      try {
        await _unregisterToken
            ?.call(oldToken, oldSession!)
            .timeout(_operationTimeout);
      } catch (_) {
        // The caller-scoped API and payload UID check remain safe on a retry.
      }
    }
    if (_needsTokenRotation) {
      await _rotateToken();
    }
    if (_disposed ||
        generation != _accountGeneration ||
        revision != _tokenRevision ||
        owner == null ||
        !_permissionGranted) {
      return;
    }
    final token =
        (_latestToken ?? await _client.getToken().timeout(_operationTimeout))
            ?.trim();
    if (_disposed ||
        generation != _accountGeneration ||
        revision != _tokenRevision ||
        token == null ||
        token.isEmpty) {
      return;
    }
    if (_registeredToken == token &&
        _registeredSession?.stableUserId == owner) {
      return;
    }
    _latestToken = token;
    _registeredToken = token;
    _registeredSession = session;
    _onToken?.call(token);
    final register = _registerToken;
    if (register == null) return;
    final pending = register(token, session);
    // A timed-out request can still complete at the server. Clean up with its
    // original credentials, then reassert the current owner after completion.
    unawaited(pending.then((_) async {
      if (generation == _accountGeneration || _disposed) return;
      try {
        await _unregisterToken?.call(token, session).timeout(_operationTimeout);
      } catch (_) {}
      _registeredToken = null;
      _registeredSession = null;
      await _scheduleSync();
    }).catchError((_) {}));
    try {
      await pending.timeout(_operationTimeout);
    } catch (_) {
      if (_registeredToken == token &&
          _registeredSession?.stableUserId == owner) {
        _registeredToken = null;
        _registeredSession = null;
      }
      rethrow;
    }
  }

  Future<void> _rotateToken() async {
    var rotation = _rotationFuture;
    if (rotation == null) {
      rotation = _client.deleteToken();
      _rotationFuture = rotation;
      final currentRotation = rotation;
      rotation.then<void>((_) {
        if (!identical(_rotationFuture, currentRotation)) return;
        _rotationFuture = null;
        _needsTokenRotation = false;
        _latestToken = null;
        if (!_disposed) unawaited(_scheduleSync());
      }, onError: (Object _, StackTrace __) {
        if (identical(_rotationFuture, currentRotation)) _rotationFuture = null;
      });
    }
    // Keep sharing an unfinished SDK delete after the UI deadline. Registering
    // a new owner is blocked until token rotation succeeds.
    await rotation.timeout(_operationTimeout);
  }

  void _handleMessage(PushNotificationMessage message, {bool opened = false}) {
    final session = _sessionStore.session;
    // UID is required: unscoped legacy payloads cannot safely identify the
    // owner of a message delayed across logout or an account switch.
    if (_disposed ||
        !session.isSignedIn ||
        message.userId != session.stableUserId ||
        (!opened && !_permissionGranted)) {
      return;
    }
    final title = message.title.trim();
    final body = message.body.trim();

    if (title.isEmpty && body.isEmpty) {
      return;
    }

    _center.add(
      PostDeeNotification(
        title: title.isEmpty ? 'การแจ้งเตือน' : title,
        body: body,
        receivedAt: _now(),
        postId: message.postId,
      ),
    );
    final postId = message.postId?.trim();
    if (opened && postId != null && postId.isNotEmpty) {
      _onOpenPost?.call(postId);
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _sessionStore.removeListener(_handleSessionChanged);
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _tokenSubscription?.cancel();
    _foregroundSubscription = null;
    _openedSubscription = null;
  }
}

/// Real client wired to `FirebaseMessaging.instance`.
class FirebaseMessagingPackageClient implements FirebaseMessagingClient {
  FirebaseMessagingPackageClient({FirebaseMessaging? messaging})
      : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  @override
  Future<bool> hasPermission() async {
    final status =
        (await _messaging.getNotificationSettings()).authorizationStatus;
    return status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
  }

  @override
  Future<void> deleteToken() => _messaging.deleteToken();

  @override
  Future<PushNotificationMessage?> getInitialMessage() async {
    final message = await _messaging.getInitialMessage();
    return message == null ? null : _mapMessage(message);
  }

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    final status = settings.authorizationStatus;

    return status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<PushNotificationMessage> get onForegroundMessage =>
      FirebaseMessaging.onMessage.map(_mapMessage);

  @override
  Stream<PushNotificationMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp.map(_mapMessage);

  PushNotificationMessage _mapMessage(RemoteMessage message) =>
      PushNotificationMessage(
        title: message.notification?.title ?? '',
        body: message.notification?.body ?? '',
        postId: message.data['postId'] is String
            ? message.data['postId'] as String
            : null,
        userId: message.data['userId'] is String
            ? message.data['userId'] as String
            : null,
      );
}

/// Builds the push messaging gateway for the current configuration. Returns the
/// real FCM gateway only when Firebase Auth is enabled and initialized;
/// otherwise a no-op gateway so local dev and tests are unaffected.
PushMessagingGateway createPushMessagingGatewayFromConfig({
  bool enableFirebaseAuth = AppConfig.enableFirebaseAuth,
  FirebaseBootstrapResult? firebaseBootstrapResult,
  PostDeeNotificationCenter? center,
  void Function(String token)? onToken,
  Future<void> Function(String token, AuthSession session)? registerToken,
  Future<void> Function(String token, AuthSession session)? unregisterToken,
  void Function(String postId)? onOpenPost,
}) {
  if (!enableFirebaseAuth) {
    return const DisabledPushMessagingGateway();
  }

  final bootstrap =
      firebaseBootstrapResult ?? FirebaseBootstrapResult.initialized;

  if (!bootstrap.isInitialized) {
    return const DisabledPushMessagingGateway();
  }

  return FirebasePushMessagingGateway(
    client: FirebaseMessagingPackageClient(),
    center: center,
    onToken: onToken,
    registerToken: registerToken,
    unregisterToken: unregisterToken,
    onOpenPost: onOpenPost,
  );
}
