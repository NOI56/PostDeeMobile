import '../../core/network/postdee_api_client.dart';

const schedulePaidPlanMessage =
    'การตั้งเวลาโพสต์ต้องใช้แพ็กเกจ Starter 199 หรือ Pro 299';
const scheduleSubscriptionUnavailableMessage =
    'ตรวจสอบแพ็กเกจไม่สำเร็จ กรุณาลองใหม่ก่อนตั้งเวลา';
const schedulePlanSummary = 'Starter ตั้งเวลาล่วงหน้าได้ 14 วัน · Pro 30 วัน';

Duration? postScheduleLimitForPlan(String? plan) => switch (plan) {
      'STARTER' => const Duration(days: 14),
      'PRO' => const Duration(days: 30),
      _ => null,
    };

bool isPostScheduleWithinLimit({
  required DateTime scheduledAt,
  required DateTime now,
  required String? plan,
}) {
  final limit = postScheduleLimitForPlan(plan);
  return limit != null &&
      scheduledAt.isAfter(now) &&
      !scheduledAt.isAfter(now.add(limit));
}

String postScheduleLimitMessage(String? plan, {bool rescheduling = false}) {
  final days = postScheduleLimitForPlan(plan)?.inDays;
  if (days == null) return schedulePaidPlanMessage;
  final action =
      rescheduling ? 'เลื่อนเวลาได้ล่วงหน้า' : 'ตั้งเวลาโพสต์ล่วงหน้าได้';
  return '$actionสูงสุด $days วัน กรุณาเลือกเวลาใหม่';
}

String? postScheduleApiErrorMessage(ApiException error,
    {String? plan, bool rescheduling = false}) {
  if (error.code == 'PAID_PLAN_REQUIRED') return schedulePaidPlanMessage;
  if (error.code == 'SCHEDULE_MUST_BE_FUTURE') {
    return rescheduling
        ? 'เวลาที่เลื่อนต้องเป็นเวลาในอนาคต'
        : 'เวลาตั้งโพสต์ต้องเป็นเวลาในอนาคต';
  }
  if (error.code != 'SCHEDULE_LIMIT_EXCEEDED') return null;
  // The server may have observed a newer entitlement than this screen.
  // Accept only the two known policy limits, never a cached Pro allowance.
  final days = RegExp(r'\b(14|30) days\b').firstMatch(error.message)?.group(1);
  if (days != null) {
    final action =
        rescheduling ? 'เลื่อนเวลาได้ล่วงหน้า' : 'ตั้งเวลาโพสต์ล่วงหน้าได้';
    return '$actionสูงสุด $days วัน กรุณาเลือกเวลาใหม่';
  }
  return 'Starter ตั้งเวลาล่วงหน้าได้ 14 วัน และ Pro 30 วัน กรุณาเลือกเวลาใหม่';
}
