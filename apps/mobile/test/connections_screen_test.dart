import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/platforms/connections_screen.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/platforms/social_platform_logo.dart';

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
  for (final inlineCard in [false, true]) {
    testWidgets(
        '${inlineCard ? 'inline connection card' : 'connections page'} hides unavailable destinations while retaining connected accounts',
        (tester) async {
      final changes = <int>[];
      final client = _StatusApiClient(
        list: () async => const [
          SocialConnectionResult(
            platform: 'YOUTUBE_SHORTS',
            connected: true,
            displayName: '@seller',
          ),
          SocialConnectionResult(platform: 'SHOPEE_VIDEO', connected: true),
          SocialConnectionResult(platform: 'LAZADA_VIDEO', connected: true),
        ],
      );
      await tester.pumpWidget(MaterialApp(
        home: inlineCard
            ? Scaffold(
                body: ListView(children: [
                  ConnectedPlatformsCard(
                    apiClient: client,
                    onConnectionsChanged: changes.add,
                  ),
                ]),
              )
            : ConnectionsScreen(
                apiClient: client,
                onConnectionsChanged: changes.add,
              ),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Facebook Video'), 250);
      await tester.pumpAndSettle();

      expect(find.text('TikTok'), findsOneWidget);
      expect(find.text('YouTube Shorts'), findsOneWidget);
      expect(find.text('Instagram Reels'), findsOneWidget);
      expect(find.text('Facebook Video'), findsOneWidget);
      expect(
        tester
            .widgetList<SocialPlatformLogo>(find.byType(SocialPlatformLogo))
            .map((logo) => logo.platform),
        [
          SocialPlatform.tiktok,
          SocialPlatform.youtubeShorts,
          SocialPlatform.instagramReels,
          SocialPlatform.facebookReels,
        ],
      );
      expect(find.text('Shopee Video'), findsNothing);
      expect(find.text('Lazada Video'), findsNothing);
      expect(find.text('เร็วๆ นี้'), findsNothing);
      expect(find.text('เชื่อมต่อแล้ว 1/4 ช่องทาง'), findsOneWidget);
      expect(find.text('@seller'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('profile-platform-disconnect-YOUTUBE_SHORTS')),
        findsOneWidget,
      );
      expect(find.text('เชื่อม'), findsNWidgets(3));
      expect(changes, [1]);
    });
  }

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
