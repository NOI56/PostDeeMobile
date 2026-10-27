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
    this.userId,
  });

  final String title;
  final String body;
  final String? userId;
}

/// Thin, testable wrapper over the parts of firebase_messaging we use.
abstract class FirebaseMessagingClient {
  Future<bool> requestPermission();

  Future<String?> getToken();

  /// Invalidates this device's token; the next [getToken] returns a new one.
  Future<void> deleteToken();

  /// Messages received while the app is in the foreground.
  Stream<PushNotificationMessage> get onForegroundMessage;

  /// Messages tapped by the user to open the app from background.
  Stream<PushNotificationMessage> get onMessageOpenedApp;
}

/// Real Apple/Google push gateway backed by FCM. The platform calls are hidden
/// behind [FirebaseMessagingClient] so the mapping logic stays unit-testable.
///
/// Requires the FCM setup that is still pending: Firebase project with Cloud
/// Messaging, iOS APNs key + push capability, and a backend that stores the
/// device token and sends messages (see ROADMAP store-services notes).
class FirebasePushMessagingGateway implements PushMessagingGateway {
  FirebasePushMessagingGateway({
    required FirebaseMessagingClient client,
    PostDeeNotificationCenter? center,
    PostDeeAuthSessionStore? sessionStore,
    Future<void> Function(String token, AuthSessionBinding sessionBinding)?
        onToken,
    DateTime Function() now = DateTime.now,
  })  : _client = client,
        _center = center ?? PostDeeNotificationCenter.instance,
        _sessionStore = sessionStore ?? PostDeeAuthSessionStore.instance,
        _onToken = onToken,
        _now = now {
    _sessionBinding = _sessionStore.captureSession();
    _center.clear();
    _sessionStore.addListener(_handleSessionChanged);
  }

  final FirebaseMessagingClient _client;
  final PostDeeNotificationCenter _center;
  final PostDeeAuthSessionStore _sessionStore;
  final Future<void> Function(String token, AuthSessionBinding sessionBinding)?
      _onToken;
  final DateTime Function() _now;

  late AuthSessionBinding _sessionBinding;
  int _generation = 0;
  bool _disposed = false;
  bool _permissionGranted = false;
  bool _initialized = false;
  bool _hasDeviceToken = false;
  Future<void>? _pendingInitialization;
  Future<void>? _pendingTokenDeletion;
  StreamSubscription<PushNotificationMessage>? _foregroundSubscription;
  StreamSubscription<PushNotificationMessage>? _openedSubscription;

  @override
  Future<void> initialize() {
    if (_disposed || !_sessionStore.session.isSignedIn || _initialized) {
      return Future<void>.value();
    }
    final pending = _pendingInitialization;
    if (pending != null) return pending;

    final generation = _generation;
    final binding = _sessionBinding;
    final userId = _sessionStore.session.userId;
    final initialization = _initializeFor(generation, binding, userId);
    _pendingInitialization = initialization;
    return initialization;
  }

  bool _isCurrent(int generation, AuthSessionBinding binding) =>
      !_disposed &&
      _generation == generation &&
      binding.isCurrent &&
      _sessionStore.session.isSignedIn;

  Future<void> _initializeFor(
    int generation,
    AuthSessionBinding binding,
    String? userId,
  ) async {
    try {
      if (!_permissionGranted) {
        final granted = await _client.requestPermission();
        if (!_isCurrent(generation, binding) || !granted) return;
        _permissionGranted = true;
      }

      // Never fetch before the previous account's token is gone, or FCM could
      // hand back the same token that is still registered to that account.
      final tokenDeletion = _pendingTokenDeletion;
      if (tokenDeletion != null) {
        await tokenDeletion;
        if (!_isCurrent(generation, binding)) return;
      }

      final token = (await _client.getToken())?.trim();
      if (!_isCurrent(generation, binding)) return;
      if (token != null && token.isNotEmpty) {
        _hasDeviceToken = true;
        // The callback must use this binding for its API auth headers. A late
        // token or registration response cannot retarget a later account.
        final registerToken = _onToken;
        if (registerToken != null) {
          // Best-effort registration must not delay delivery or the screen
          // while an API request is pending.
          unawaited(
            Future<void>.sync(() => registerToken(token, binding))
                .catchError((_) {}),
          );
        }
      }
      if (!_isCurrent(generation, binding)) return;

      void handleMessage(PushNotificationMessage message) {
        if (!_isCurrent(generation, binding) ||
            userId == null ||
            userId.trim().isEmpty ||
            message.userId != userId) {
          return;
        }
        _handleMessage(message);
      }

      _foregroundSubscription =
          _client.onForegroundMessage.listen(handleMessage);
      _openedSubscription = _client.onMessageOpenedApp.listen(handleMessage);
      _initialized = true;
    } finally {
      if (_generation == generation) _pendingInitialization = null;
    }
  }

  void _handleSessionChanged() {
    if (_sessionBinding.isCurrent) return;
    _generation += 1;
    _sessionBinding = _sessionStore.captureSession();
    _pendingInitialization = null;
    _initialized = false;
    _center.clear();
    unawaited(_cancelSubscriptions().catchError((_) {}));

    // The backend still maps this device's token to the previous account, so
    // its publish pushes would keep arriving after sign-out. Delete the token;
    // a later sign-in fetches and registers a fresh one.
    if (_hasDeviceToken) {
      _hasDeviceToken = false;
      _pendingTokenDeletion =
          Future<void>.sync(_client.deleteToken).catchError((_) {});
    }

    // Once granted, permission belongs to the device. Re-register its token
    // for a later sign-in without waiting for another bell tap. An unanswered
    // or denied prompt from the previous account does not authorize this.
    if (_permissionGranted && _sessionStore.session.isSignedIn) {
      unawaited(initialize().catchError((_) {}));
    }
  }

  void _handleMessage(PushNotificationMessage message) {
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
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
    _sessionStore.removeListener(_handleSessionChanged);
    _pendingInitialization = null;
    _initialized = false;
    _center.clear();
    await _cancelSubscriptions();
  }

  Future<void> _cancelSubscriptions() async {
    final foreground = _foregroundSubscription;
    final opened = _openedSubscription;
    _foregroundSubscription = null;
    _openedSubscription = null;
    await Future.wait([
      if (foreground != null) foreground.cancel(),
      if (opened != null) opened.cancel(),
    ]);
  }
}

/// Real client wired to `FirebaseMessaging.instance`.
class FirebaseMessagingPackageClient implements FirebaseMessagingClient {
  FirebaseMessagingPackageClient({FirebaseMessaging? messaging})
      : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

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
  Future<void> deleteToken() => _messaging.deleteToken();

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
  PostDeeAuthSessionStore? sessionStore,
  Future<void> Function(String token, AuthSessionBinding sessionBinding)? onToken,
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
    sessionStore: sessionStore,
    onToken: onToken,
  );
}
