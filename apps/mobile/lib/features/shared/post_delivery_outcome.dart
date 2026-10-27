import '../../core/network/postdee_api_client.dart';

String? postDeliveryOutcomeLabel(
  String? value, {
  bool compact = false,
  String languageCode = 'th',
}) {
  if (value == null) return null;
  final isThai = languageCode == 'th';
  return switch (value.trim().toUpperCase()) {
    'DRAFT' => isThai ? 'ส่งเป็นร่างแล้ว' : 'Sent as draft',
    'PRIVATE' => isThai ? 'ส่วนตัว' : 'Private',
    'UNLISTED' => isThai ? 'ไม่แสดงในรายการ' : 'Unlisted',
    'LIVE' => isThai ? (compact ? 'เผยแพร่' : 'เผยแพร่แล้ว') : 'Published',
    _ => isThai ? 'ผลยังไม่ยืนยัน' : 'Delivery unconfirmed',
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
  String languageCode = 'th',
}) {
  final isThai = languageCode == 'th';
  final resultList = results.toList(growable: false);
  final publishedCount = resultList
      .where((result) => result.status.trim().toUpperCase() == 'PUBLISHED')
      .length;
  final failedCount = resultList
      .where((result) => result.status.trim().toUpperCase() == 'FAILED')
      .length;

  if (publishedCount > 0 && failedCount > 0) {
    return isThai
        ? (compact ? 'ส่งบางส่วน' : 'ส่งสำเร็จบางช่องทาง')
        : (compact ? 'Partially delivered' : 'Delivered to some channels');
  }
  if (resultList.isEmpty || publishedCount != resultList.length) {
    return null;
  }

  if (hasUnconfirmedDeliveryOutcome(resultList)) {
    return isThai ? 'ผลยังไม่ยืนยัน' : 'Delivery unconfirmed';
  }

  final outcomes = resultList
      .map((result) => result.deliveryOutcome?.trim().toUpperCase())
      .whereType<String>()
      .where((value) => value.isNotEmpty)
      .toSet();
  if (outcomes.isEmpty) return null;
  if (outcomes.length == 1) {
    return postDeliveryOutcomeLabel(outcomes.single,
        compact: compact, languageCode: languageCode);
  }
  return isThai
      ? (compact ? 'ส่งสำเร็จ' : 'ส่งสำเร็จหลายรูปแบบ')
      : (compact ? 'Delivered' : 'Delivered with different visibility');
}

bool isProviderDraftOutcome(String? value) =>
    value?.trim().toUpperCase() == 'DRAFT';
