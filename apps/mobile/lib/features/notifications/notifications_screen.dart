import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../shared/postdee_card.dart';
import 'push_notification.dart';

class NotificationItem {
  const NotificationItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.time,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String time;
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

  NotificationItem _toItem(PostDeeNotification notification) => NotificationItem(
        icon: Icons.notifications_none,
        color: AppTheme.accent,
        title: notification.title,
        body: notification.body,
        time: _relativeTime(notification.receivedAt),
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
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: DecoratedBox(
          decoration: AppTheme.screenBackground,
          child: data.isEmpty
              ? const _NotificationsEmptyState()
              : ListView.separated(
                  padding: AppTheme.screenPadding,
                  itemCount: data.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppTheme.spaceSm),
                  itemBuilder: (context, index) =>
                      _NotificationTile(item: data[index]),
                ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item});

  final NotificationItem item;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return PostDeeCard(
      padding: const EdgeInsets.all(AppTheme.spaceMd),
      glowColor: item.color,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppTheme.tileRadius),
              border: Border.all(color: item.color.withValues(alpha: 0.3)),
            ),
            child: SizedBox(
              width: 38,
              height: 38,
              child: Icon(item.icon, color: item.color, size: 20),
            ),
          ),
          const SizedBox(width: AppTheme.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      item.time,
                      style: textTheme.labelSmall
                          ?.copyWith(color: AppTheme.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spaceXs),
                Text(
                  item.body,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                    height: 1.3,
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
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_off_outlined,
                color: AppTheme.textMuted, size: 40),
            const SizedBox(height: AppTheme.spaceMd),
            Text(
              'ยังไม่มีการแจ้งเตือน',
              style:
                  textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppTheme.spaceXs),
            Text(
              'เมื่อมีโพสต์เผยแพร่หรือคลิปมาแรง จะแจ้งให้ทราบที่นี่',
              textAlign: TextAlign.center,
              style:
                  textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
