import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/platforms/connections_screen.dart';

class _StatusApiClient extends PostDeeApiClient {
  _StatusApiClient({required this.list, this.refresh});

  final Future<List<SocialConnectionResult>> Function() list;
  final Future<List<SocialConnectionResult>> Function()? refresh;

  @override
  Future<List<SocialConnectionResult>> listSocialConnections() => list();

  @override
  Future<List<SocialConnectionResult>> refreshSocialConnections() =>
      (refresh ?? list)();
}

void main() {
  testWidgets('loading social status does not claim zero connected accounts',
      (tester) async {
    final result = Completer<List<SocialConnectionResult>>();
    await tester.pumpWidget(MaterialApp(
      home: ConnectionsScreen(
        apiClient: _StatusApiClient(list: () => result.future),
      ),
    ));
    await tester.pump();

    expect(find.text('เชื่อมต่อแล้ว 0/4 ช่องทาง'), findsNothing);
    expect(find.text('กำลังตรวจสอบช่องทาง...'), findsOneWidget);
    expect(find.text('เชื่อม'), findsNothing);

    result.complete(const []);
    await tester.pumpAndSettle();
    expect(find.text('เชื่อมต่อแล้ว 0/4 ช่องทาง'), findsOneWidget);
  });

  testWidgets('failed status is unknown and retry confirms real accounts',
      (tester) async {
    var calls = 0;
    final changes = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: ConnectionsScreen(
        onConnectionsChanged: changes.add,
        apiClient: _StatusApiClient(list: () async {
          calls += 1;
          if (calls == 1) {
            throw const ApiException('Request failed', statusCode: 503);
          }
          return const [
            SocialConnectionResult(
              platform: 'TIKTOK',
              connected: true,
              displayName: '@seller',
            ),
          ];
        }),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('เชื่อมต่อแล้ว 0/4 ช่องทาง'), findsNothing);
    expect(find.text('0/4'), findsNothing);
    expect(find.text('ตรวจสอบช่องทางไม่ได้'), findsOneWidget);
    expect(find.text('เชื่อม'), findsNothing);
    expect(changes, isEmpty);
    expect(find.textContaining('Request failed'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('profile-platforms-retry')));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(changes, [1]);
    expect(find.text('เชื่อมต่อแล้ว 1/4 ช่องทาง'), findsOneWidget);
    expect(find.text('@seller'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-platform-disconnect-TIKTOK')),
        findsOneWidget);
  });

  testWidgets('failed refresh hides stale account claims and locks mutations',
      (tester) async {
    final changes = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: ConnectionsScreen(
        onConnectionsChanged: changes.add,
        apiClient: _StatusApiClient(
          list: () async => const [
            SocialConnectionResult(
              platform: 'TIKTOK',
              connected: true,
              displayName: '@seller',
            ),
          ],
          refresh: () async =>
              throw const ApiException('Request failed', statusCode: 503),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-platforms-refresh')));
    await tester.pumpAndSettle();

    expect(find.text('ตรวจสอบช่องทางไม่ได้'), findsOneWidget);
    expect(find.text('เชื่อมต่อแล้ว 1/4 ช่องทาง'), findsNothing);
    expect(find.text('@seller'), findsNothing);
    expect(find.byKey(const ValueKey('profile-platform-disconnect-TIKTOK')),
        findsNothing);
    expect(find.text('เชื่อม'), findsNothing);
    expect(changes, [1]);

    await tester.tap(find.byKey(const ValueKey('profile-platforms-retry')));
    await tester.pumpAndSettle();
    expect(find.text('เชื่อมต่อแล้ว 1/4 ช่องทาง'), findsOneWidget);
    expect(changes, [1, 1]);
  });
}
