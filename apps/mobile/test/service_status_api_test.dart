import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

void main() {
  test('loadServiceStatus reads open notices and skips malformed ones',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final paths = <String>[];
    final serverTask = () async {
      await for (final request in server) {
        paths.add('${request.method} ${request.uri.path}');
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'status': 'ok',
            'checkedAt': '2026-10-28T08:00:00.000Z',
            'incidents': [
              {
                'id': 'incident-1',
                'title': 'TikTok ส่งช้า',
                'message': 'กำลังตรวจสอบ',
                'platforms': ['TIKTOK', 'MYSPACE'],
                'stage': 'INVESTIGATING',
                'startedAt': '2026-10-28T07:00:00.000Z',
                'updatedAt': '2026-10-28T07:30:00.000Z',
              },
              {'id': 'incident-2', 'title': 'ไม่มีสถานะ', 'message': 'x'},
              {
                'id': 'incident-3',
                'title': 'ปิดแล้ว',
                'message': 'ไม่ควรแสดง',
                'platforms': <String>[],
                'stage': 'RESOLVED',
                'updatedAt': '2026-10-28T07:30:00.000Z',
              },
            ],
          }));
        await request.response.close();
      }
    }();

    try {
      final incidents = await PostDeeApiClient(
        baseUrl: 'http://${server.address.address}:${server.port}',
      ).loadServiceStatus();
      expect(paths, ['GET /support/status']);
      expect(incidents, hasLength(1));
      expect(incidents.single.id, 'incident-1');
      expect(incidents.single.platforms, ['TIKTOK']);
      expect(incidents.single.updatedAt,
          DateTime.utc(2026, 10, 28, 7, 30).toLocal());
    } finally {
      await server.close(force: true);
      await serverTask;
    }
  });
}
