import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';
import '../shared/postdee_card.dart';
import '../shared/postdee_notice.dart';

typedef ScheduledPostsLoader = Future<List<ScheduledPostResult>> Function();

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    this.refreshToken = 0,
    this.loadScheduledPosts,
    this.onAddPost,
  });

  final int refreshToken;
  final ScheduledPostsLoader? loadScheduledPosts;

  /// Jump to the upload flow to schedule a new post.
  final VoidCallback? onAddPost;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _apiClient = PostDeeApiClient();
  bool _isLoading = true;
  String? _errorMessage;
  List<ScheduledPostResult> _posts = const [];
  late DateTime _visibleMonth;
  DateTime? _selectedDay;
  String _platformFilter = 'all';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    _loadPosts();
  }

  @override
  void didUpdateWidget(covariant CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _loadPosts();
    }
  }

  Future<void> _loadPosts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final loader = widget.loadScheduledPosts ?? _apiClient.listScheduledPosts;
      final posts = await loader();

      if (!mounted) {
        return;
      }

      final sorted = [...posts]
        ..sort((left, right) => left.scheduledAt.compareTo(right.scheduledAt));

      setState(() {
        _posts = sorted;
        if (sorted.isNotEmpty) {
          final first = sorted.first.scheduledAt.toLocal();
          _visibleMonth = DateTime(first.year, first.month);
        }
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } on SocketException {
      if (!mounted) return;
      setState(() => _errorMessage = 'เชื่อมต่อ PostDee API ไม่ได้');
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'โหลดปฏิทินโพสต์ไม่สำเร็จ');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _dayKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

  Set<String> get _daysWithPosts => _posts
      .where((p) =>
          _platformFilter == 'all' || p.platforms.contains(_platformFilter))
      .map((p) => _dayKey(p.scheduledAt.toLocal()))
      .toSet();

  List<ScheduledPostResult> get _filteredPosts => _posts.where((p) {
        if (_platformFilter != 'all' &&
            !p.platforms.contains(_platformFilter)) {
          return false;
        }
        if (_selectedDay != null &&
            !_isSameDay(p.scheduledAt.toLocal(), _selectedDay!)) {
          return false;
        }
        return true;
      }).toList();

  void _changeMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
  }

  void _selectDay(DateTime date) {
    setState(() {
      _selectedDay =
          (_selectedDay != null && _isSameDay(_selectedDay!, date)) ? null : date;
    });
  }

  Future<void> _showPostActions(ScheduledPostResult post) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.charcoal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppTheme.spaceSm),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            ListTile(
              leading: Icon(Icons.schedule, color: AppTheme.accentCyanInk),
              title: const Text('เลื่อนเวลา'),
              onTap: () {
                Navigator.of(context).pop();
                _reschedule(post);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppTheme.accent),
              title: const Text('แก้ไขโพสต์'),
              onTap: () {
                Navigator.of(context).pop();
                widget.onAddPost?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('ยกเลิกโพสต์',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.of(context).pop();
                _cancel(post);
              },
            ),
            const SizedBox(height: AppTheme.spaceSm),
          ],
        ),
      ),
    );
  }

  Future<void> _reschedule(ScheduledPostResult post) async {
    final current = post.scheduledAt.toLocal();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;

    final next = DateTime(
        date.year, date.month, date.day, time.hour, time.minute);

    try {
      await _apiClient.reschedulePost(post.id, next);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เลื่อนเวลาไม่สำเร็จ ลองใหม่อีกครั้ง')),
        );
      }
      return;
    }

    if (!mounted) return;
    await _loadPosts();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('เลื่อนเป็น ${_formatThaiDate(next)} ${_formatTime(next)}')),
    );
  }

  Future<void> _cancel(ScheduledPostResult post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.charcoal,
        title: const Text('ยกเลิกโพสต์นี้?'),
        content: const Text('โพสต์ที่ตั้งเวลาไว้จะถูกนำออกจากปฏิทิน'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ไม่'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ยกเลิกโพสต์',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _apiClient.cancelPost(post.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ยกเลิกโพสต์ไม่สำเร็จ ลองใหม่อีกครั้ง')),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() => _posts = _posts.where((p) => p.id != post.id).toList());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ยกเลิกโพสต์แล้ว')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      key: const ValueKey('calendar-screen'),
      padding: AppTheme.screenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'ปฏิทินโพสต์',
                style: textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            if (widget.onAddPost != null)
              IconButton(
                onPressed: widget.onAddPost,
                icon: const Icon(Icons.add),
                tooltip: 'ตั้งเวลาโพสต์ใหม่',
              ),
            IconButton(
              onPressed: _isLoading ? null : _loadPosts,
              icon: const Icon(Icons.refresh),
              tooltip: 'รีเฟรชปฏิทิน',
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spaceSm),
        Text(
          'แตะวันในปฏิทินเพื่อดูเฉพาะวันนั้น หรือแตะโพสต์เพื่อจัดการ',
          style: textTheme.bodyMedium?.copyWith(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppTheme.spaceLg),
        _buildCalendar(context),
        const SizedBox(height: AppTheme.spaceLg),
        _buildPlatformFilter(),
        const SizedBox(height: AppTheme.spaceLg),
        ..._buildContent(context),
        ],
      ),
    );
  }

  Widget _buildCalendar(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final daysWithPosts = _daysWithPosts;
    final first = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final daysInMonth =
        DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final leadingBlanks = first.weekday - 1; // Monday-first grid

    final cells = <Widget>[
      for (var i = 0; i < leadingBlanks; i += 1) const SizedBox.shrink(),
      for (var d = 1; d <= daysInMonth; d += 1)
        _dayCell(
          DateTime(_visibleMonth.year, _visibleMonth.month, d),
          daysWithPosts,
        ),
    ];

    return PostDeeCard(
      glowColor: AppTheme.accent,
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => _changeMonth(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '${_thaiMonthsFull[_visibleMonth.month - 1]} ${_visibleMonth.year}',
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: () => _changeMonth(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Row(
            children: [
              for (final label in _weekdayLabels)
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: textTheme.labelSmall?.copyWith(
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppTheme.spaceXs),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: cells,
          ),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime date, Set<String> daysWithPosts) {
    final isToday = _isSameDay(date, DateTime.now());
    final isSelected =
        _selectedDay != null && _isSameDay(date, _selectedDay!);
    final hasPosts = daysWithPosts.contains(_dayKey(date));

    return GestureDetector(
      onTap: () => _selectDay(date),
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accent : Colors.transparent,
          shape: BoxShape.circle,
          border: isToday && !isSelected
              ? Border.all(color: AppTheme.accent)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}',
              style: TextStyle(
                color: isSelected ? Colors.white : AppTheme.textPrimary,
                fontWeight: isToday ? FontWeight.w900 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasPosts
                    ? (isSelected ? Colors.white : AppTheme.accentCyan)
                    : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformFilter() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _FilterPill(
            selected: _platformFilter == 'all',
            onTap: () => setState(() => _platformFilter = 'all'),
            child: const Text('ทั้งหมด',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: AppTheme.spaceSm),
          for (final platform in SocialPlatform.values) ...[
            _FilterPill(
              selected: _platformFilter == platform.apiValue,
              onTap: () =>
                  setState(() => _platformFilter = platform.apiValue),
              child: SocialPlatformLogo(platform: platform, size: 20),
            ),
            const SizedBox(width: AppTheme.spaceSm),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildContent(BuildContext context) {
    if (_isLoading) {
      return const [
        PostDeeNotice(
          key: ValueKey('calendar-loading'),
          icon: Icons.hourglass_top,
          message: 'กำลังโหลดปฏิทินโพสต์...',
          color: AppTheme.accent,
        ),
      ];
    }

    if (_errorMessage != null) {
      return [
        PostDeeNotice(
          key: const ValueKey('calendar-error'),
          icon: Icons.error_outline,
          message: _errorMessage!,
          color: Theme.of(context).colorScheme.error,
          actionLabel: 'ลองใหม่',
          onAction: _loadPosts,
        ),
      ];
    }

    if (_posts.isEmpty) {
      return [
        PostDeeNotice(
          key: const ValueKey('calendar-empty'),
          icon: Icons.event_available,
          message: 'ยังไม่มีคลิปที่ตั้งเวลาไว้',
          color: AppTheme.accentCyan,
          actionLabel: widget.onAddPost != null ? 'ตั้งเวลาโพสต์' : null,
          onAction: widget.onAddPost,
        ),
      ];
    }

    final filtered = _filteredPosts;

    if (filtered.isEmpty) {
      return [
        Row(
          children: [
            Expanded(
              child: Text(
                _selectedDay != null
                    ? 'ไม่มีโพสต์ในวันที่เลือก'
                    : 'ไม่มีโพสต์ตามตัวกรองนี้',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            if (_selectedDay != null)
              TextButton(
                onPressed: () => setState(() => _selectedDay = null),
                child: const Text('ดูทั้งหมด'),
              ),
          ],
        ),
      ];
    }

    // Day-selected view: a single header + that day's posts.
    if (_selectedDay != null) {
      return [
        Row(
          children: [
            Expanded(
              child: Text(
                _dayHeaderLabel(_selectedDay!),
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _selectedDay = null),
              child: const Text('ดูทั้งหมด'),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spaceSm),
        for (final post in filtered) ...[
          _ScheduledPostCard(post: post, onTap: () => _showPostActions(post)),
          const SizedBox(height: AppTheme.spaceMd),
        ],
      ];
    }

    // Grouped-by-day view.
    final groups = <DateTime, List<ScheduledPostResult>>{};
    for (final post in filtered) {
      final local = post.scheduledAt.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      groups.putIfAbsent(day, () => []).add(post);
    }
    final sortedDays = groups.keys.toList()..sort();

    return [
      for (final day in sortedDays) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.spaceSm),
          child: Text(
            _dayHeaderLabel(day),
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        for (final post in groups[day]!) ...[
          _ScheduledPostCard(post: post, onTap: () => _showPostActions(post)),
          const SizedBox(height: AppTheme.spaceMd),
        ],
      ],
    ];
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.pillRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent.withValues(alpha: 0.2)
              : AppTheme.glassDeep,
          borderRadius: BorderRadius.circular(AppTheme.pillRadius),
          border: Border.all(
            color: selected ? AppTheme.accent : AppTheme.border,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _ScheduledPostCard extends StatelessWidget {
  const _ScheduledPostCard({required this.post, required this.onTap});

  final ScheduledPostResult post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheduledAt = post.scheduledAt.toLocal();

    return GestureDetector(
      onTap: onTap,
      child: PostDeeCard(
        padding: const EdgeInsets.all(14),
        glowColor: AppTheme.accent,
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppTheme.tileRadius),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    const Icon(Icons.schedule,
                        color: AppTheme.accent, size: 18),
                    const SizedBox(height: 6),
                    Text(
                      _formatTime(scheduledAt),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: AppTheme.spaceXs),
                  Text(
                    '${_formatThaiDate(scheduledAt)} • ${_statusLabel(post.status)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: AppTheme.spaceSm),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final platform in post.platforms)
                        _PlatformBadge(data: _platformBadgeFor(platform)),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.more_vert, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _PlatformBadge extends StatelessWidget {
  const _PlatformBadge({required this.data});

  final _PlatformBadgeData data;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: data.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        border: Border.all(color: data.color.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (data.platform != null) ...[
              SocialPlatformLogo(platform: data.platform!, size: 16),
              const SizedBox(width: 5),
            ],
            Text(
              data.label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}


class _PlatformBadgeData {
  const _PlatformBadgeData({
    required this.label,
    required this.color,
    this.platform,
  });

  final String label;
  final Color color;
  final SocialPlatform? platform;
}

_PlatformBadgeData _platformBadgeFor(String apiValue) {
  for (final platform in SocialPlatform.values) {
    if (platform.apiValue == apiValue) {
      return _PlatformBadgeData(
        label: platform.label,
        color: platform.color,
        platform: platform,
      );
    }
  }

  return _PlatformBadgeData(label: apiValue, color: AppTheme.textMuted);
}

bool _isSameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _dayHeaderLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = DateTime(date.year, date.month, date.day).difference(today).inDays;
  if (diff == 0) return 'วันนี้ · ${_formatThaiDate(date)}';
  if (diff == 1) return 'พรุ่งนี้ · ${_formatThaiDate(date)}';
  return _formatThaiDate(date);
}

String _formatTime(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

const _weekdayLabels = ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];

const _thaiMonthsFull = [
  'มกราคม',
  'กุมภาพันธ์',
  'มีนาคม',
  'เมษายน',
  'พฤษภาคม',
  'มิถุนายน',
  'กรกฎาคม',
  'สิงหาคม',
  'กันยายน',
  'ตุลาคม',
  'พฤศจิกายน',
  'ธันวาคม',
];

const _thaiMonthsShort = [
  'ม.ค.',
  'ก.พ.',
  'มี.ค.',
  'เม.ย.',
  'พ.ค.',
  'มิ.ย.',
  'ก.ค.',
  'ส.ค.',
  'ก.ย.',
  'ต.ค.',
  'พ.ย.',
  'ธ.ค.',
];

String _formatThaiDate(DateTime date) =>
    '${date.day} ${_thaiMonthsShort[date.month - 1]} ${date.year}';

String _statusLabel(String status) {
  switch (status) {
    case 'QUEUED':
      return 'ตั้งเวลาแล้ว';
    case 'PUBLISHING':
      return 'กำลังโพสต์';
    case 'PUBLISHED':
      return 'โพสต์แล้ว';
    case 'FAILED':
      return 'โพสต์ไม่สำเร็จ';
    default:
      return status;
  }
}
