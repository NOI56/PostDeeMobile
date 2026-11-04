import 'clip_group_caption_context.dart';

const _keepClipGroupValue = Object();
final _clipGroupIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,80}$');

bool isValidClipGroupId(String? value) =>
    value != null && _clipGroupIdPattern.hasMatch(value);

enum ClipGroupDeliveryMode { immediate, scheduled }

class ClipGroupItem {
  ClipGroupItem({
    required this.draftId,
    required this.index,
    required this.sourceStartSeconds,
    required this.sourceEndSeconds,
    required Set<String> platformApiValues,
    this.usesSharedCaption = true,
    this.scheduledAt,
    this.acceptedPostId,
    this.acceptedPostStatus,
    this.acceptedScheduledAt,
  }) : platformApiValues = Set.unmodifiable(platformApiValues);

  final String draftId;
  final int index;
  final double sourceStartSeconds;
  final double sourceEndSeconds;

  /// Immutable split destinations. Member editing may change their settings,
  /// but not silently change the planned set of channels or source interval.
  final Set<String> platformApiValues;
  final bool usesSharedCaption;

  /// Remembered independent choice, retained when the group switches to Now.
  final DateTime? scheduledAt;

  /// Durable acknowledgement, written before a submitted child is deleted.
  final String? acceptedPostId;
  final String? acceptedPostStatus;
  final DateTime? acceptedScheduledAt;
  bool get isAccepted => acceptedPostId != null;
  double get durationSeconds => sourceEndSeconds - sourceStartSeconds;

  ClipGroupItem copyWith({
    bool? usesSharedCaption,
    Object? scheduledAt = _keepClipGroupValue,
    Object? acceptedPostId = _keepClipGroupValue,
    Object? acceptedPostStatus = _keepClipGroupValue,
    Object? acceptedScheduledAt = _keepClipGroupValue,
  }) =>
      ClipGroupItem(
        draftId: draftId,
        index: index,
        sourceStartSeconds: sourceStartSeconds,
        sourceEndSeconds: sourceEndSeconds,
        platformApiValues: platformApiValues,
        usesSharedCaption: usesSharedCaption ?? this.usesSharedCaption,
        scheduledAt: identical(scheduledAt, _keepClipGroupValue)
            ? this.scheduledAt
            : scheduledAt as DateTime?,
        acceptedPostId: identical(acceptedPostId, _keepClipGroupValue)
            ? this.acceptedPostId
            : acceptedPostId as String?,
        acceptedPostStatus: identical(acceptedPostStatus, _keepClipGroupValue)
            ? this.acceptedPostStatus
            : acceptedPostStatus as String?,
        acceptedScheduledAt: identical(acceptedScheduledAt, _keepClipGroupValue)
            ? this.acceptedScheduledAt
            : acceptedScheduledAt as DateTime?,
      );

  Map<String, Object?> toJson() => {
        'draftId': draftId,
        'index': index,
        'sourceStartSeconds': sourceStartSeconds,
        'sourceEndSeconds': sourceEndSeconds,
        'platformApiValues': platformApiValues.toList()..sort(),
        'usesSharedCaption': usesSharedCaption,
        'scheduledAt': scheduledAt?.toUtc().toIso8601String(),
        'acceptedPostId': acceptedPostId,
        'acceptedPostStatus': acceptedPostStatus,
        'acceptedScheduledAt': acceptedScheduledAt?.toUtc().toIso8601String(),
      };

  factory ClipGroupItem.fromJson(Map<String, dynamic> json) {
    final platforms = json['platformApiValues'];
    if (json['draftId'] is! String ||
        json['index'] is! int ||
        json['sourceStartSeconds'] is! num ||
        json['sourceEndSeconds'] is! num ||
        platforms is! List ||
        platforms.any((value) => value is! String) ||
        json['usesSharedCaption'] is! bool ||
        (json['acceptedPostId'] != null && json['acceptedPostId'] is! String) ||
        (json['acceptedPostStatus'] != null &&
            json['acceptedPostStatus'] is! String)) {
      throw const FormatException('Invalid clip group item');
    }
    return ClipGroupItem(
      draftId: json['draftId'] as String,
      index: json['index'] as int,
      sourceStartSeconds: (json['sourceStartSeconds'] as num).toDouble(),
      sourceEndSeconds: (json['sourceEndSeconds'] as num).toDouble(),
      platformApiValues: platforms.cast<String>().toSet(),
      usesSharedCaption: json['usesSharedCaption'] as bool,
      scheduledAt: _optionalDate(json['scheduledAt']),
      acceptedPostId: json['acceptedPostId'] as String?,
      acceptedPostStatus: json['acceptedPostStatus'] as String?,
      acceptedScheduledAt: _optionalDate(json['acceptedScheduledAt']),
    );
  }
}

class ClipGroupDraft {
  ClipGroupDraft({
    required this.id,
    required this.ownerUserId,
    required this.sourceDraftId,
    required this.title,
    required this.sharedCaption,
    required this.deliveryMode,
    required List<ClipGroupItem> items,
    required this.createdAt,
    required this.updatedAt,
    this.revision = 0,
    this.captionContext,
  }) : items = List.unmodifiable(items);

  final String id;
  final String ownerUserId;
  final String sourceDraftId;
  final String title;
  final String sharedCaption;
  final ClipGroupDeliveryMode deliveryMode;
  final List<ClipGroupItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int revision;
  final ClipGroupCaptionContext? captionContext;
  bool get isComplete =>
      items.isNotEmpty && items.every((item) => item.isAccepted);

  ClipGroupDraft copyWith({
    String? title,
    String? sharedCaption,
    ClipGroupDeliveryMode? deliveryMode,
    List<ClipGroupItem>? items,
    DateTime? updatedAt,
    int? revision,
    Object? captionContext = _keepClipGroupValue,
  }) =>
      ClipGroupDraft(
        id: id,
        ownerUserId: ownerUserId,
        sourceDraftId: sourceDraftId,
        title: title ?? this.title,
        sharedCaption: sharedCaption ?? this.sharedCaption,
        deliveryMode: deliveryMode ?? this.deliveryMode,
        items: items ?? this.items,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        revision: revision ?? this.revision,
        captionContext: identical(captionContext, _keepClipGroupValue)
            ? this.captionContext
            : captionContext as ClipGroupCaptionContext?,
      );

  Map<String, Object?> toJson() => {
        'version': 1,
        'id': id,
        'ownerUserId': ownerUserId,
        'sourceDraftId': sourceDraftId,
        'title': title,
        'sharedCaption': sharedCaption,
        if (captionContext != null) 'captionContext': captionContext!.toJson(),
        'deliveryMode': deliveryMode.name,
        'items': items.map((item) => item.toJson()).toList(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'revision': revision,
      };

  factory ClipGroupDraft.fromJson(Map<String, dynamic> json) {
    final mode = ClipGroupDeliveryMode.values
        .where((mode) => mode.name == json['deliveryMode'])
        .firstOrNull;
    final items = json['items'];
    final captionContext = json['captionContext'];
    if (json['version'] != 1 ||
        json['id'] is! String ||
        json['ownerUserId'] is! String ||
        json['sourceDraftId'] is! String ||
        json['title'] is! String ||
        json['sharedCaption'] is! String ||
        json['revision'] is! int ||
        (captionContext != null && captionContext is! Map<String, dynamic>) ||
        mode == null ||
        items is! List ||
        items.length > 64 ||
        items.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid clip group');
    }
    final group = ClipGroupDraft(
      id: json['id'] as String,
      ownerUserId: json['ownerUserId'] as String,
      sourceDraftId: json['sourceDraftId'] as String,
      title: json['title'] as String,
      sharedCaption: json['sharedCaption'] as String,
      deliveryMode: mode,
      items: items
          .map((item) => ClipGroupItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      createdAt: _requiredDate(json['createdAt']),
      updatedAt: _requiredDate(json['updatedAt']),
      revision: json['revision'] as int,
      captionContext: captionContext == null
          ? null
          : ClipGroupCaptionContext.fromJson(
              captionContext as Map<String, dynamic>),
    );
    validateClipGroupDraft(group);
    return group;
  }
}

void validateClipGroupDraft(ClipGroupDraft group) {
  if (!isValidClipGroupId(group.id) ||
      !isValidClipGroupId(group.sourceDraftId) ||
      group.ownerUserId.trim().isEmpty ||
      group.ownerUserId.length > 256 ||
      group.title.trim().isEmpty ||
      group.title.length > 1024 ||
      group.sharedCaption.length > 100000 ||
      group.items.isEmpty ||
      group.items.length > 64 ||
      group.revision < 0 ||
      group.createdAt.isAfter(group.updatedAt)) {
    throw const FormatException('Invalid clip group');
  }
  final ids = <String>{};
  if (group.captionContext != null) {
    validateClipGroupCaptionContext(group.captionContext!);
  }
  final posts = <String>{};
  const platforms = {
    'TIKTOK',
    'YOUTUBE_SHORTS',
    'INSTAGRAM_REELS',
    'FACEBOOK_REELS'
  };
  for (var i = 0; i < group.items.length; i++) {
    final item = group.items[i];
    if (!isValidClipGroupId(item.draftId) ||
        item.draftId == group.sourceDraftId ||
        !ids.add(item.draftId) ||
        item.index != i ||
        !item.sourceStartSeconds.isFinite ||
        !item.sourceEndSeconds.isFinite ||
        item.sourceStartSeconds < 0 ||
        item.sourceEndSeconds <= item.sourceStartSeconds ||
        item.platformApiValues.isEmpty ||
        !platforms.containsAll(item.platformApiValues) ||
        (item.acceptedPostId != null &&
            (item.acceptedPostId!.trim().isEmpty ||
                item.acceptedPostId!.length > 256 ||
                !posts.add(item.acceptedPostId!))) ||
        (item.acceptedPostStatus != null &&
            !RegExp(r'^[A-Z_]{1,40}$').hasMatch(item.acceptedPostStatus!)) ||
        (item.acceptedPostId == null &&
            (item.acceptedPostStatus != null ||
                item.acceptedScheduledAt != null))) {
      throw const FormatException('Invalid clip group item');
    }
  }
}

DateTime _requiredDate(Object? value) {
  if (value is! String) throw const FormatException('Invalid clip group date');
  return DateTime.parse(value);
}

DateTime? _optionalDate(Object? value) =>
    value == null ? null : _requiredDate(value);
