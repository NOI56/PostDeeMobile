import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

class _DelayedOpenClient implements HttpClient {
  final opened = Completer<HttpClientRequest>();
  final requested = Completer<void>();
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    requested.complete();
    return opened.future;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnsentRequest implements HttpClientRequest {
  final _done = Completer<HttpClientResponse>();
  bool aborted = false;
  int closeCalls = 0;
  @override
  Future<HttpClientResponse> get done => _done.future;
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    aborted = true;
    if (!_done.isCompleted) _done.completeError(exception ?? StateError('aborted'));
  }
  @override
  Future<HttpClientResponse> close() {
    closeCalls++;
    throw StateError('A stale request must not be sent');
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final method in ['DELETE', 'POST']) {
    test('bound $method aborts an opened request after the account changes', () async {
      final store = PostDeeAuthSessionStore(initialSession: const AuthSession(userId: 'a', idToken: 'token-a'));
      final transport = _DelayedOpenClient();
      final request = _UnsentRequest();
      final client = PostDeeApiClient(httpClient: transport, baseUrl: 'http://fixture.invalid', sessionBinding: store.captureSession());
      final operation = method == 'DELETE' ? client.deleteAccount() : client.prepareSubscriptionPurchase();
      final rejected = expectLater(operation, throwsA(isA<AuthSessionChangedException>()));
      await transport.requested.future;
      store.signIn(const AuthSession(userId: 'b', idToken: 'token-b'));
      transport.opened.complete(request);
      await rejected;
      expect(request.aborted, isTrue);
      expect(request.closeCalls, 0);
    });
  }

  test('late DELETE success cannot be accepted by a later session', () async {
    final store = PostDeeAuthSessionStore(initialSession: const AuthSession(userId: 'a', idToken: 'token-a'));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final arrived = Completer<HttpRequest>();
    final listener = server.listen(arrived.complete);
    try {
      final client = PostDeeApiClient(baseUrl: 'http://${server.address.address}:${server.port}', sessionBinding: store.captureSession());
      final deletion = client.deleteAccount();
      final rejected = expectLater(deletion, throwsA(isA<AuthSessionChangedException>()));
      final request = await arrived.future;
      expect(request.headers.value(HttpHeaders.authorizationHeader), 'Bearer token-a');
      store.signIn(const AuthSession(userId: 'b', idToken: 'token-b'));
      await request.drain<void>();
      request.response..headers.contentType = ContentType.json..write(jsonEncode({'status': 'ok'}));
      await request.response.close();
      await rejected;
    } finally {
      await listener.cancel();
      await server.close(force: true);
    }
  });
}
