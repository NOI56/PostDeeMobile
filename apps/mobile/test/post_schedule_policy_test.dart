import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/shared/post_schedule_policy.dart';
import 'package:postdee_mobile/features/shared/publishing_availability.dart';

void main() {
  test('English scheduling copy keeps package prices and limits unchanged', () {
    expect(getSchedulePaidPlanMessage(languageCode: 'en'),
        'Scheduling requires Starter (199 THB) or Pro (299 THB).');
    expect(getScheduleSubscriptionUnavailableMessage(languageCode: 'en'),
        'Could not verify your plan. Try again before scheduling.');
    expect(getSchedulePlanSummary(languageCode: 'en'),
        'Starter: schedule up to 14 days ahead · Pro: 30 days');
    expect(getPublishingUnavailableActionMessage(languageCode: 'en'),
        'Publishing is temporarily unavailable. Please try again later.');
    expect(getSchedulePaidPlanMessage(), schedulePaidPlanMessage);
    expect(getScheduleSubscriptionUnavailableMessage(),
        scheduleSubscriptionUnavailableMessage);
    expect(getSchedulePlanSummary(), schedulePlanSummary);
    expect(getPublishingUnavailableActionMessage(),
        publishingUnavailableActionMessage);
    expect(postScheduleLimitMessage('STARTER', languageCode: 'en'),
        'You can schedule posts up to 14 days ahead. Choose another time.');
    expect(
        postScheduleLimitMessage('PRO', rescheduling: true, languageCode: 'en'),
        'You can reschedule up to 30 days ahead. Choose another time.');
    expect(postScheduleLimitMessage('BASIC', languageCode: 'en'),
        getSchedulePaidPlanMessage(languageCode: 'en'));
  });

  test('English API schedule errors use authoritative bounds and fail closed',
      () {
    expect(
        postScheduleApiErrorMessage(
            const ApiException(
                'Posts can be scheduled up to 14 days in advance',
                code: 'SCHEDULE_LIMIT_EXCEEDED'),
            plan: 'PRO',
            rescheduling: true,
            languageCode: 'en'),
        'You can reschedule up to 14 days ahead. Choose another time.');
    expect(
        postScheduleApiErrorMessage(
            const ApiException('up to 99 days',
                code: 'SCHEDULE_LIMIT_EXCEEDED'),
            languageCode: 'en'),
        'Starter allows scheduling up to 14 days ahead and Pro up to 30 days. Choose another time.');
    expect(
        postScheduleApiErrorMessage(
            const ApiException('paid', code: 'PAID_PLAN_REQUIRED'),
            languageCode: 'en'),
        getSchedulePaidPlanMessage(languageCode: 'en'));
    expect(
        postScheduleApiErrorMessage(
            const ApiException('future', code: 'SCHEDULE_MUST_BE_FUTURE'),
            rescheduling: true,
            languageCode: 'en'),
        'The rescheduled time must be in the future.');
    expect(
        postScheduleApiErrorMessage(
            const ApiException('future', code: 'SCHEDULE_MUST_BE_FUTURE'),
            languageCode: 'en'),
        'The posting time must be in the future.');
    expect(
        postScheduleApiErrorMessage(const ApiException('unrelated'),
            languageCode: 'en'),
        isNull);
  });

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
