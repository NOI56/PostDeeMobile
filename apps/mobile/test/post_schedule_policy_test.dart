import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/shared/post_schedule_policy.dart';

void main() {
  for (final entry in {'STARTER': 14, 'PRO': 30}.entries) {
    test('${entry.key} includes its exact scheduling boundary', () {
      final now = DateTime.utc(2026, 10, 8, 9);
      final boundary = now.add(Duration(days: entry.value));
      expect(postScheduleLimitForPlan(entry.key), Duration(days: entry.value));
      expect(
          isPostScheduleWithinLimit(
              scheduledAt: boundary, now: now, plan: entry.key),
          isTrue);
      expect(
          isPostScheduleWithinLimit(
              scheduledAt: boundary.add(const Duration(milliseconds: 1)),
              now: now,
              plan: entry.key),
          isFalse);
      expect(
          isPostScheduleWithinLimit(
              scheduledAt: now, now: now, plan: entry.key),
          isFalse);
    });
  }

  for (final plan in <String?>[null, 'BASIC', 'FREE', 'UNKNOWN']) {
    test('does not grant scheduling to $plan', () {
      final now = DateTime.utc(2026, 10, 8, 9);
      expect(postScheduleLimitForPlan(plan), isNull);
      expect(
          isPostScheduleWithinLimit(
              scheduledAt: now.add(const Duration(days: 1)),
              now: now,
              plan: plan),
          isFalse);
    });
  }

  test('uses the backend limit when a cached Pro entitlement became Starter',
      () {
    expect(
        postScheduleApiErrorMessage(
            const ApiException(
                'Posts can be scheduled up to 14 days in advance',
                statusCode: 400,
                code: 'SCHEDULE_LIMIT_EXCEEDED'),
            plan: 'PRO'),
        'ตั้งเวลาโพสต์ล่วงหน้าได้สูงสุด 14 วัน กรุณาเลือกเวลาใหม่');
    expect(
        postScheduleApiErrorMessage(
            const ApiException(
                'Posts can be scheduled up to 30 days in advance',
                statusCode: 400,
                code: 'SCHEDULE_LIMIT_EXCEEDED'),
            rescheduling: true),
        'เลื่อนเวลาได้ล่วงหน้าสูงสุด 30 วัน กรุณาเลือกเวลาใหม่');
  });

  test('keeps unknown backend limits fail closed and paid-plan errors Thai',
      () {
    expect(
        postScheduleApiErrorMessage(
            const ApiException('unexpected', code: 'SCHEDULE_LIMIT_EXCEEDED')),
        'Starter ตั้งเวลาล่วงหน้าได้ 14 วัน และ Pro 30 วัน กรุณาเลือกเวลาใหม่');
    expect(
        postScheduleApiErrorMessage(const ApiException('paid plan',
            statusCode: 402, code: 'PAID_PLAN_REQUIRED')),
        'การตั้งเวลาโพสต์ต้องใช้แพ็กเกจ Starter 199 หรือ Pro 299');
    expect(
        postScheduleApiErrorMessage(const ApiException('unrelated')), isNull);
  });
}
