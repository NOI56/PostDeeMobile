import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'push_notification.dart';

class NotificationItem {
  const NotificationItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.time,
    this.isUnread = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String time;
  final bool isUnread;
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.items, this.center});

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

  NotificationItem _toItem(PostDeeNotification notification) =>
      NotificationItem(
        icon: Icons.notifications_none,
        color: AppTheme.accentCyanInk,
        title: notification.title,
        body: notification.body,
        time: _relativeTime(notification.receivedAt),
        isUnread: _center.isUnread(notification),
      );

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time.toLocal());

    if (diff.inDays >= 1) return '${diff.inDays} วันก่อน';
    if (diff.inHours >= 1) return '${diff.inHours} ชม.ก่อน';
    if (diff.inMinutes >= 1) return '${diff.inMinutes} นาทีก่อน';
    return 'เมื่อสักครู่';
  }

  @override
  Widget build(BuildContext context) {
    final data = _resolveItems();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'การแจ้งเตือน',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_hasUnread && _usesLiveCenter)
            TextButton(
              onPressed: _center.markAllRead,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.accentCyanInk,
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('อ่านทั้งหมด'),
            ),
        ],
      ),
      body: SafeArea(
        child: DecoratedBox(
          decoration: AppTheme.screenBackground,
          child: Column(
            children: [
              const _NotificationSessionNotice(),
              Expanded(
                child: data.isEmpty
                    ? const _NotificationsEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                        itemCount: data.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            _NotificationTile(item: data[index]),
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
              'รายการที่ได้รับบนอุปกรณ์นี้ในรอบการใช้งานนี้',
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
  const _NotificationTile({required this.item});

  final NotificationItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
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
                Row(
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              item.isUnread ? FontWeight.w700 : FontWeight.w600,
                          color: item.isUnread
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.time,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
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
              'ไม่มีการแจ้งเตือน',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'เมื่อได้รับผลการเผยแพร่โพสต์บนอุปกรณ์นี้ จะแสดงที่นี่',
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
