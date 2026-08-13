import '../../core/network/postdee_api_client.dart';

String? postDeliveryOutcomeLabel(
  String? value, {
  bool compact = false,
}) {
  if (value == null) return null;
  return switch (value.trim().toUpperCase()) {
    'DRAFT' => 'ส่งเป็นร่างแล้ว',
    'PRIVATE' => 'ส่วนตัว',
    'UNLISTED' => 'ไม่แสดงในรายการ',
    'LIVE' => compact ? 'เผยแพร่' : 'เผยแพร่แล้ว',
    _ => 'ผลยังไม่ยืนยัน',
  };
}

bool isKnownDeliveryOutcome(String? value) => const {
      'DRAFT',
      'PRIVATE',
      'UNLISTED',
      'LIVE',
    }.contains(value?.trim().toUpperCase());

bool isPublishedDeliveryOutcome(String? value) => const {
      'PRIVATE',
      'UNLISTED',
      'LIVE',
    }.contains(value?.trim().toUpperCase());

bool hasUnconfirmedDeliveryOutcome(Iterable<PostPlatformResult> results) =>
    results.any(
      (result) =>
          result.deliveryOutcome != null &&
          !isKnownDeliveryOutcome(result.deliveryOutcome),
    );

String? aggregatePostDeliveryOutcomeLabel(
  Iterable<PostPlatformResult> results, {
  bool compact = false,
}) {
  final resultList = results.toList(growable: false);
  final publishedCount = resultList
      .where((result) => result.status.trim().toUpperCase() == 'PUBLISHED')
      .length;
  final failedCount = resultList
      .where((result) => result.status.trim().toUpperCase() == 'FAILED')
      .length;

  if (publishedCount > 0 && failedCount > 0) {
    return compact ? 'ส่งบางส่วน' : 'ส่งสำเร็จบางช่องทาง';
  }
  if (resultList.isEmpty || publishedCount != resultList.length) {
    return null;
  }

  if (hasUnconfirmedDeliveryOutcome(resultList)) {
    return 'ผลยังไม่ยืนยัน';
  }

  final outcomes = resultList
      .map((result) => result.deliveryOutcome?.trim().toUpperCase())
      .whereType<String>()
      .where((value) => value.isNotEmpty)
      .toSet();
  if (outcomes.isEmpty) return null;
  if (outcomes.length == 1) {
    return postDeliveryOutcomeLabel(outcomes.single, compact: compact);
  }
  return compact ? 'ส่งสำเร็จ' : 'ส่งสำเร็จหลายรูปแบบ';
}

bool isProviderDraftOutcome(String? value) =>
    value?.trim().toUpperCase() == 'DRAFT';
