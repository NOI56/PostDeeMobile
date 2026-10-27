import '../../core/network/postdee_api_client.dart';

const schedulePaidPlanMessage =
    'การตั้งเวลาโพสต์ต้องใช้แพ็กเกจ Starter 199 หรือ Pro 299';
const scheduleSubscriptionUnavailableMessage =
    'ตรวจสอบแพ็กเกจไม่สำเร็จ กรุณาลองใหม่ก่อนตั้งเวลา';
const schedulePlanSummary = 'Starter ตั้งเวลาล่วงหน้าได้ 14 วัน · Pro 30 วัน';

String getSchedulePaidPlanMessage({String languageCode = 'th'}) =>
    languageCode == 'th'
        ? schedulePaidPlanMessage
        : 'Scheduling requires Starter (199 THB) or Pro (299 THB).';

String getScheduleSubscriptionUnavailableMessage(
        {String languageCode = 'th'}) =>
    languageCode == 'th'
        ? scheduleSubscriptionUnavailableMessage
        : 'Could not verify your plan. Try again before scheduling.';

String getSchedulePlanSummary({String languageCode = 'th'}) =>
    languageCode == 'th'
        ? schedulePlanSummary
        : 'Starter: schedule up to 14 days ahead · Pro: 30 days';

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

String postScheduleLimitMessage(String? plan,
    {bool rescheduling = false, String languageCode = 'th'}) {
  final days = postScheduleLimitForPlan(plan)?.inDays;
  if (days == null) {
    return getSchedulePaidPlanMessage(languageCode: languageCode);
  }
  if (languageCode != 'th') {
    return rescheduling
        ? 'You can reschedule up to $days days ahead. Choose another time.'
        : 'You can schedule posts up to $days days ahead. Choose another time.';
  }
  final action =
      rescheduling ? 'เลื่อนเวลาได้ล่วงหน้า' : 'ตั้งเวลาโพสต์ล่วงหน้าได้';
  return '$actionสูงสุด $days วัน กรุณาเลือกเวลาใหม่';
}

String? postScheduleApiErrorMessage(ApiException error,
    {String? plan, bool rescheduling = false, String languageCode = 'th'}) {
  if (error.code == 'PAID_PLAN_REQUIRED') {
    return getSchedulePaidPlanMessage(languageCode: languageCode);
  }
  if (error.code == 'SCHEDULE_MUST_BE_FUTURE') {
    if (languageCode != 'th') {
      return rescheduling
          ? 'The rescheduled time must be in the future.'
          : 'The posting time must be in the future.';
    }
    return rescheduling
        ? 'เวลาที่เลื่อนต้องเป็นเวลาในอนาคต'
        : 'เวลาตั้งโพสต์ต้องเป็นเวลาในอนาคต';
  }
  if (error.code != 'SCHEDULE_LIMIT_EXCEEDED') return null;
  // The server may have observed a newer entitlement than this screen.
  // Accept only the two known policy limits, never a cached Pro allowance.
  final days = RegExp(r'\b(14|30) days\b').firstMatch(error.message)?.group(1);
  if (days != null) {
    if (languageCode != 'th') {
      return rescheduling
          ? 'You can reschedule up to $days days ahead. Choose another time.'
          : 'You can schedule posts up to $days days ahead. Choose another time.';
    }
    final action =
        rescheduling ? 'เลื่อนเวลาได้ล่วงหน้า' : 'ตั้งเวลาโพสต์ล่วงหน้าได้';
    return '$actionสูงสุด $days วัน กรุณาเลือกเวลาใหม่';
  }
  return languageCode == 'th'
      ? 'Starter ตั้งเวลาล่วงหน้าได้ 14 วัน และ Pro 30 วัน กรุณาเลือกเวลาใหม่'
      : 'Starter allows scheduling up to 14 days ahead and Pro up to 30 days. Choose another time.';
}
