import 'package:flutter/material.dart';

import '../../core/localization/postdee_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../posts/posts_screen.dart';
import 'push_notification.dart';

class NotificationItem {
  const NotificationItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.time,
    this.isUnread = false,
    this.postId,
    this.sourceNotification,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String time;
  final bool isUnread;
  final String? postId;
  final PostDeeNotification? sourceNotification;
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen(
      {super.key,
      this.items,
      this.center,
      this.onOpenPost,
      this.onOpenAllPosts});
  final ValueChanged<String>? onOpenPost;
  final VoidCallback? onOpenAllPosts;

  /// Explicit list override (used by tests). When null the screen shows the
  /// live notifications from [center].
  final List<NotificationItem>? items;

  /// Live notification store. Defaults to the shared app instance.
  final PostDeeNotificationCenter? center;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final PostDeeNotificationCenter _center =
      widget.center ?? PostDeeNotificationCenter.instance;

  bool get _usesLiveCenter => widget.items == null;

  String _text(String thai, String english) =>
      _notificationsText(context, thai, english);

  @override
  void initState() {
    super.initState();
    if (_usesLiveCenter) {
      _center.addListener(_handleCenterChanged);
    }
  }

  @override
  void dispose() {
    if (_usesLiveCenter) {
      _center.removeListener(_handleCenterChanged);
    }
    super.dispose();
  }

  void _handleCenterChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  List<NotificationItem> _resolveItems() {
    if (widget.items != null) {
      return widget.items!;
    }

    return _center.items.map(_toItem).toList();
  }

  bool get _hasUnread => _usesLiveCenter
      ? _center.hasUnread
      : _resolveItems().any((item) => item.isUnread);

  NotificationItem _toItem(PostDeeNotification notification) {
    final copy = _notificationMessageCopy(notification,
        languageCode: _notificationsLanguageCode(context));
    return NotificationItem(
      icon: Icons.notifications_none,
      color: AppTheme.accentCyanInk,
      title: copy.title,
      body: copy.body,
      time: _relativeTime(notification.receivedAt),
      isUnread: _center.isUnread(notification),
      postId: notification.postId,
      sourceNotification: notification,
    );
  }

  void _openPost(NotificationItem item) {
    final source = item.sourceNotification;
    if (_usesLiveCenter && source != null) _center.markRead(source);
    widget.onOpenPost?.call(item.postId!);
  }

  void _openAllPosts() {
    final callback = widget.onOpenAllPosts;
    if (callback != null) {
      callback();
      return;
    }
    Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => const PostsScreen()));
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time.toLocal());

    if (diff.inDays >= 1) {
      return _text('${diff.inDays} วันก่อน',
          '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago');
    }
    if (diff.inHours >= 1) {
      return _text('${diff.inHours} ชม.ก่อน',
          '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago');
    }
    if (diff.inMinutes >= 1) {
      return _text('${diff.inMinutes} นาทีก่อน',
          '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago');
    }
    return _text('เมื่อสักครู่', 'Just now');
  }

  @override
  Widget build(BuildContext context) {
    final data = _resolveItems();
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    final canMarkAllRead = _hasUnread && _usesLiveCenter;
    final markAllRead = TextButton(
      onPressed: _center.markAllRead,
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.accentCyanInk,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: Text(_text('อ่านทั้งหมด', 'Mark all as read')),
    );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: largeText
            ? kToolbarHeight * MediaQuery.textScalerOf(context).scale(16) / 16
            : null,
        title: Text(
          _text('การแจ้งเตือน', 'Notifications'),
          maxLines: largeText ? 2 : 1,
          softWrap: largeText,
          overflow: largeText ? TextOverflow.visible : TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (canMarkAllRead && !largeText) markAllRead,
        ],
      ),
      body: SafeArea(
        child: DecoratedBox(
          decoration: AppTheme.screenBackground,
          child: Column(
            children: [
              const _NotificationSessionNotice(),
              if (canMarkAllRead && largeText)
                Align(alignment: Alignment.centerRight, child: markAllRead),
              Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const ValueKey('notifications-open-posts'),
                    onPressed: _openAllPosts,
                    icon: const Icon(Icons.video_library_outlined),
                    label: Text(_text('ดูโพสต์ทั้งหมด', 'View all posts')),
                  )),
              Expanded(
                child: data.isEmpty
                    ? const SingleChildScrollView(
                        child: _NotificationsEmptyState())
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                        itemCount: data.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) => _NotificationTile(
                          item: data[index],
                          onTap: data[index].postId == null ||
                                  widget.onOpenPost == null
                              ? null
                              : () => _openPost(data[index]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationSessionNotice extends StatelessWidget {
  const _NotificationSessionNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.mint,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.phone_android_rounded,
            size: 18,
            color: AppTheme.accentCyanInk,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _notificationsText(
                  context,
                  'รายการที่ได้รับบนอุปกรณ์นี้ในรอบการใช้งานนี้',
                  'Received on this device during this session'),
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, this.onTap});

  final NotificationItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    final title = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (item.isUnread) ...[
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppTheme.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
        ],
        Expanded(
          child: Text(
            item.title,
            maxLines: largeText ? null : 1,
            overflow: largeText ? null : TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: item.isUnread ? FontWeight.w700 : FontWeight.w600,
              color:
                  item.isUnread ? AppTheme.textPrimary : AppTheme.textSecondary,
            ),
          ),
        ),
      ],
    );
    final time = Text(
      item.time,
      style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.glass,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF122018).withValues(alpha: 0.04),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item.icon, color: item.color, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (largeText)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, const SizedBox(height: 4), time],
                    )
                  else
                    Row(children: [
                      Expanded(child: title),
                      const SizedBox(width: 8),
                      time,
                    ]),
                  const SizedBox(height: 4),
                  Text(
                    item.body,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsEmptyState extends StatelessWidget {
  const _NotificationsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 50, 24, 50),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: AppTheme.glassDeep,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.notifications_off_outlined,
                color: AppTheme.textMuted,
                size: 34,
              ),
            ),
            const SizedBox(height: 15),
            Text(
              _notificationsText(
                  context, 'ไม่มีการแจ้งเตือน', 'No notifications'),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _notificationsText(
                  context,
                  'เมื่อได้รับผลการเผยแพร่โพสต์บนอุปกรณ์นี้ จะแสดงที่นี่',
                  'Post delivery results received on this device will appear here.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _notificationsLanguageCode(BuildContext context) =>
    Localizations.of<PostDeeLocalizations>(context, PostDeeLocalizations)
        ?.locale
        .languageCode ??
    'th';

String _notificationsText(BuildContext context, String thai, String english) =>
    _notificationsLanguageCode(context) == 'th' ? thai : english;

({String title, String body}) _notificationMessageCopy(
  PostDeeNotification notification, {
  required String languageCode,
}) {
  if (languageCode == 'th') {
    return (title: notification.title, body: notification.body);
  }
  // Translate known receipt templates at display time, retaining read identity.
  return switch ((notification.title, notification.body)) {
    (
      'ส่งคลิปสำเร็จ',
      'ระบบส่งคลิปไปยังช่องทางที่เลือกเรียบร้อยแล้ว แตะเพื่อดูผลลัพธ์'
    ) =>
      (
        title: 'Video delivered',
        body:
            'Your video was sent to the selected channels. Tap to view the result.',
      ),
    (
      'ส่งคลิปสำเร็จบางช่องทาง',
      'บางช่องทางส่งคลิปไม่สำเร็จ แตะเพื่อดูรายละเอียด'
    ) =>
      (
        title: 'Video partially delivered',
        body: 'Your video could not be sent to some channels. Tap for details.',
      ),
    (
      'ส่งคลิปไม่สำเร็จ',
      'ส่งคลิปไปยังช่องทางที่เลือกไม่สำเร็จ แตะเพื่อดูรายละเอียด'
    ) =>
      (
        title: 'Video delivery failed',
        body:
            'Your video could not be sent to the selected channels. Tap for details.',
      ),
    _ => (title: notification.title, body: notification.body),
  };
}
