import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../platforms/connections_screen.dart' show connectablePlatforms;
import '../platforms/social_platform.dart';
import '../shared/post_schedule_policy.dart';
import '../shared/post_delivery_outcome.dart';
import '../shared/postdee_notice.dart';
import '../shared/publishing_availability.dart';

typedef ScheduledPostsLoader = Future<List<ScheduledPostResult>> Function();
typedef ScheduledPostRescheduler = Future<ScheduledPostResult> Function(
  String postId,
  DateTime scheduledAt,
);
typedef ScheduledPostCanceller = Future<void> Function(String postId);
typedef CalendarTimeConverter = DateTime Function(DateTime value);

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    this.refreshToken = 0,
    this.isActive = true,
    this.loadScheduledPosts,
    this.reschedulePost,
    this.cancelPost,
    this.onAddPost,
    this.onOpenPostDetail,
    this.toLocalTime,
    this.now,
  });

  final int refreshToken;
  final bool isActive;
  final ScheduledPostsLoader? loadScheduledPosts;
  final ScheduledPostRescheduler? reschedulePost;
  final ScheduledPostCanceller? cancelPost;
  final CalendarTimeConverter? toLocalTime;
  final DateTime Function()? now;

  /// Jump to the upload flow to schedule a new post.
  final VoidCallback? onAddPost;

  /// Open a read-only result for a post that has finished publishing.
  final ValueChanged<ScheduledPostResult>? onOpenPostDetail;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with WidgetsBindingObserver {
  static const _queuedRefreshInterval = Duration(seconds: 30);

  final _apiClient = PostDeeApiClient();
  bool _isLoading = true;
  bool _loadInProgress = false;
  bool _reloadRequested = false;
  Future<void>? _activeLoad;
  int _postMutationGeneration = 0;
  bool _appIsResumed = true;
  String? _errorMessage;
  List<ScheduledPostResult> _posts = const [];
  Timer? _queuedRefreshTimer;
  late DateTime _visibleMonth;
  DateTime? _selectedDay;
  String _platformFilter = 'all';
  String? _pendingActionPostId;
  String? _pendingActionLabel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _appIsResumed =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    final now = _now();
    _visibleMonth = DateTime(now.year, now.month);
    if (widget.isActive) {
      unawaited(_loadPosts());
    } else {
      _isLoading = false;
    }
  }

  @override
  void didUpdateWidget(covariant CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final becameActive = !oldWidget.isActive && widget.isActive;
    final refreshRequested = oldWidget.refreshToken != widget.refreshToken;

    if (!widget.isActive) {
      _queuedRefreshTimer?.cancel();
      _queuedRefreshTimer = null;
    } else if (becameActive || refreshRequested) {
      unawaited(_loadPosts(silent: _posts.isNotEmpty));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appIsResumed = state == AppLifecycleState.resumed;
    if (!_appIsResumed) {
      _queuedRefreshTimer?.cancel();
      _queuedRefreshTimer = null;
      return;
    }

    if (widget.isActive) {
      unawaited(_loadPosts(silent: _posts.isNotEmpty));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _queuedRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPosts({bool silent = false}) async {
    if (_loadInProgress) {
      _reloadRequested = true;
      final activeLoad = _activeLoad;
      if (activeLoad != null) await activeLoad;
      return;
    }
    _loadInProgress = true;

    late final Future<void> load;
    load = _performLoadPosts(silent: silent);
    _activeLoad = load;
    try {
      await load;
    } finally {
      if (identical(_activeLoad, load)) _activeLoad = null;
    }
  }

  Future<void> _performLoadPosts({required bool silent}) async {
    var currentLoadIsSilent = silent;

    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      do {
        _reloadRequested = false;
        final mutationGeneration = _postMutationGeneration;
        try {
          final loader =
              widget.loadScheduledPosts ?? _apiClient.listScheduledPosts;
          final posts = await loader();

          if (!mounted) return;
          if (mutationGeneration != _postMutationGeneration) continue;

          final sorted = [...posts]..sort((left, right) =>
              _calendarTimeFor(left).compareTo(_calendarTimeFor(right)));

          setState(() {
            _posts = sorted;
            _errorMessage = null;
            // Until the user picks a day, follow the first scheduled post so
            // the day list below the grid is never pointlessly empty.
            if (_selectedDay == null && sorted.isNotEmpty) {
              final first = _calendarTimeFor(sorted.first);
              _selectedDay = DateTime(first.year, first.month, first.day);
              _visibleMonth = DateTime(first.year, first.month);
            }
          });
        } on ApiException catch (error) {
          if (!mounted) return;
          if (!currentLoadIsSilent || _posts.isEmpty) {
            setState(() => _errorMessage = error.message);
          }
        } on SocketException {
          if (!mounted) return;
          if (!currentLoadIsSilent || _posts.isEmpty) {
            setState(() => _errorMessage = 'เชื่อมต่อ PostDee API ไม่ได้');
          }
        } catch (_) {
          if (!mounted) return;
          if (!currentLoadIsSilent || _posts.isEmpty) {
            setState(() => _errorMessage = 'โหลดปฏิทินโพสต์ไม่สำเร็จ');
          }
        }
        currentLoadIsSilent = _posts.isNotEmpty;
      } while (_reloadRequested && mounted);
    } finally {
      _loadInProgress = false;
      if (mounted) {
        setState(() => _isLoading = false);
        _syncQueuedRefresh();
      }
    }
  }

  void _syncQueuedRefresh() {
    _queuedRefreshTimer?.cancel();
    _queuedRefreshTimer = null;

    final hasPendingPost = _posts.any(_needsStatusRefresh);
    if (!mounted || !_appIsResumed || !widget.isActive || !hasPendingPost) {
      return;
    }

    _queuedRefreshTimer = Timer(_queuedRefreshInterval, () {
      _queuedRefreshTimer = null;
      if (mounted && _appIsResumed && widget.isActive) {
        unawaited(_loadPosts(silent: true));
      }
    });
  }

  DateTime _calendarTimeFor(ScheduledPostResult post) {
    final status = post.status.toUpperCase();
    final isPublished = status == 'PUBLISHED' || status == 'PARTIAL_PUBLISHED';
    final timestamp =
        isPublished ? post.publishedAt ?? post.scheduledAt : post.scheduledAt;
    return _toLocalTime(timestamp);
  }

  DateTime _toLocalTime(DateTime value) =>
      widget.toLocalTime?.call(value) ?? value.toLocal();

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  // The prototype always keeps one day selected; default to today.
  DateTime get _activeDay {
    final day = _selectedDay ?? _now();
    return DateTime(day.year, day.month, day.day);
  }

  String _dayKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

  List<ScheduledPostResult> get _visiblePosts => _posts
      .where((p) =>
          _platformFilter == 'all' || p.platforms.contains(_platformFilter))
      .toList();

  /// First matching platform color per day, for the dot under the day number.
  Map<String, Color> get _dayDotColors {
    final colors = <String, Color>{};
    for (final post in _visiblePosts) {
      final key = _dayKey(_calendarTimeFor(post));
      if (colors.containsKey(key)) continue;
      final platform = _platformFor(post.platforms.firstOrNull ?? '');
      colors[key] = platform?.displayColor ?? AppTheme.accent;
    }
    return colors;
  }

  List<ScheduledPostResult> get _dayPosts => _visiblePosts
      .where((p) => _isSameDay(_calendarTimeFor(p), _activeDay))
      .toList();

  void _changeMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
  }

  void _selectDay(DateTime date) {
    setState(() => _selectedDay = date);
  }

  VoidCallback? _postTapHandler(ScheduledPostResult post) {
    if (_pendingActionPostId != null) return null;

    if (_canEditQueue(post)) {
      return () => _showPostActions(post);
    }

    if (_canOpenPostDetail(post) && widget.onOpenPostDetail != null) {
      return () => widget.onOpenPostDetail!(post);
    }

    return null;
  }

  Future<void> _showPostActions(ScheduledPostResult post) async {
    if (!_canEditQueue(post)) return;

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
              leading:
                  const Icon(Icons.delete_outline, color: Colors.redAccent),
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
    if (!_canEditQueue(post) || _pendingActionPostId != null) return;

    final current = _toLocalTime(post.scheduledAt);
    final currentNow = _now();
    final today = DateTime(
      currentNow.year,
      currentNow.month,
      currentNow.day,
    );
    final lastDate = today.add(postScheduleLimit);
    final currentDate = DateTime(current.year, current.month, current.day);
    final initialDate = currentDate.isBefore(today)
        ? today
        : currentDate.isAfter(lastDate)
            ? lastDate
            : currentDate;
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: lastDate,
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;

    final next =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final validationNow = _now();

    if (!next.isAfter(validationNow)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เวลาที่เลื่อนต้องเป็นเวลาในอนาคต')),
      );
      return;
    }

    if (!isPostScheduleWithinLimit(
      scheduledAt: next,
      now: validationNow,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เลื่อนเวลาได้ล่วงหน้าสูงสุด 30 วัน')),
      );
      return;
    }

    setState(() {
      _pendingActionPostId = post.id;
      _pendingActionLabel = 'กำลังเลื่อนเวลา...';
    });

    try {
      final reschedulePost = widget.reschedulePost ?? _apiClient.reschedulePost;
      final updatedPost = await reschedulePost(post.id, next);
      _postMutationGeneration += 1;
      if (mounted) {
        final updatedTime = _calendarTimeFor(updatedPost);
        setState(() {
          _posts = [
            for (final currentPost in _posts)
              if (currentPost.id == updatedPost.id)
                updatedPost
              else
                currentPost,
          ]..sort((left, right) =>
              _calendarTimeFor(left).compareTo(_calendarTimeFor(right)));
          _selectedDay = DateTime(
            updatedTime.year,
            updatedTime.month,
            updatedTime.day,
          );
          _visibleMonth = DateTime(updatedTime.year, updatedTime.month);
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isPublishingUnavailable(error)
                  ? publishingUnavailableActionMessage
                  : 'เลื่อนเวลาไม่สำเร็จ ลองใหม่อีกครั้ง',
            ),
          ),
        );
      }
      return;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เลื่อนเวลาไม่สำเร็จ ลองใหม่อีกครั้ง')),
        );
      }
      return;
    } finally {
      if (mounted) {
        setState(() {
          _pendingActionPostId = null;
          _pendingActionLabel = null;
        });
      }
    }

    if (!mounted) return;
    await _loadPosts();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('เลื่อนเป็น ${_formatThaiDate(next)} ${_formatTime(next)}')),
    );
  }

  Future<void> _cancel(ScheduledPostResult post) async {
    if (!_canEditQueue(post) || _pendingActionPostId != null) return;

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

    setState(() {
      _pendingActionPostId = post.id;
      _pendingActionLabel = 'กำลังยกเลิก...';
    });

    try {
      final cancelPost = widget.cancelPost ?? _apiClient.cancelPost;
      await cancelPost(post.id);
      _postMutationGeneration += 1;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ยกเลิกโพสต์ไม่สำเร็จ ลองใหม่อีกครั้ง')),
        );
      }
      return;
    } finally {
      if (mounted) {
        setState(() {
          _pendingActionPostId = null;
          _pendingActionLabel = null;
        });
      }
    }

    if (!mounted) return;
    setState(() => _posts = _posts.where((p) => p.id != post.id).toList());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ยกเลิกโพสต์แล้ว')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding =
        MediaQuery.sizeOf(context).width <= 360 ? 8.0 : 16.0;
    return RefreshIndicator(
      onRefresh: _loadPosts,
      color: AppTheme.accent,
      child: SingleChildScrollView(
        key: const ValueKey('calendar-screen'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          8,
          horizontalPadding,
          AppTheme.navOverlap,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ปฏิทินโพสต์',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'แตะวันเพื่อดูหรือสร้างโพสต์',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.onAddPost != null)
                  Semantics(
                    label: 'ตั้งเวลาโพสต์ใหม่',
                    button: true,
                    child: ExcludeSemantics(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: widget.onAddPost,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppTheme.accent,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.accent.withValues(alpha: 0.6),
                                blurRadius: 18,
                                spreadRadius: -8,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            color: Colors.white,
                            size: 23,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _buildMonthCard(),
            const SizedBox(height: 12),
            _buildLegend(),
            const SizedBox(height: 14),
            _buildPlatformFilter(),
            const SizedBox(height: 16),
            ..._buildDaySection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthCard() {
    final dotColors = _dayDotColors;
    final usesLargeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final usesNarrowCalendar = MediaQuery.sizeOf(context).width <= 360;
    final daysInMonth =
        DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final leadingBlanks =
        DateTime(_visibleMonth.year, _visibleMonth.month, 1).weekday - 1;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: usesNarrowCalendar ? 0 : 8,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        color: AppTheme.glass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF122018).withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _MonthNavButton(
                icon: Icons.chevron_left,
                label: 'เดือนก่อนหน้า',
                onTap: () => _changeMonth(-1),
              ),
              Expanded(
                child: Text(
                  '${_thaiMonthsFull[_visibleMonth.month - 1]} ${_visibleMonth.year}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              _MonthNavButton(
                icon: Icons.chevron_right,
                label: 'เดือนถัดไป',
                onTap: () => _changeMonth(1),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final label in _weekdayLabels)
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 7,
            childAspectRatio: usesLargeText ? 0.9 : 1,
            mainAxisSpacing: 2,
            crossAxisSpacing: 1,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < leadingBlanks; i += 1)
                const SizedBox.shrink(),
              for (var d = 1; d <= daysInMonth; d += 1)
                _dayCell(
                  DateTime(_visibleMonth.year, _visibleMonth.month, d),
                  dotColors,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime date, Map<String, Color> dotColors) {
    final isSelected = _isSameDay(date, _activeDay);
    final dotColor = dotColors[_dayKey(date)];

    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: () => _selectDay(date),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${date.day}',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? Colors.white : AppTheme.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor == null
                    ? Colors.transparent
                    : isSelected
                        ? Colors.white
                        : dotColor,
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Wrap(
        spacing: 14,
        runSpacing: 7,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'จุดสี = ช่องทาง',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
            ),
          ),
          for (final platform in connectablePlatforms)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: platform.displayColor,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  platform.shortLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPlatformFilter() {
    return SizedBox(
      height: 52,
      child: Stack(
        children: [
          ListView(
            key: const ValueKey('calendar-platform-filters'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 42),
            children: [
              _FilterChip(
                label: 'ทั้งหมด',
                selected: _platformFilter == 'all',
                onTap: () => setState(() => _platformFilter = 'all'),
              ),
              for (final platform in connectablePlatforms) ...[
                const SizedBox(width: 8),
                _FilterChip(
                  label: platform.shortLabel,
                  selected: _platformFilter == platform.apiValue,
                  onTap: () =>
                      setState(() => _platformFilter = platform.apiValue),
                ),
              ],
            ],
          ),
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                width: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.glass.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppTheme.borderSoft),
                ),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDaySection(BuildContext context) {
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

    final dayPosts = _dayPosts;

    return [
      Text(
        _formatThaiDate(_activeDay),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary,
        ),
      ),
      const SizedBox(height: 10),
      if (dayPosts.isEmpty)
        _EmptyDayCard(
          key: const ValueKey('calendar-empty'),
          onTap: widget.onAddPost,
        )
      else
        for (final post in dayPosts) ...[
          _DayPostRow(
            post: post,
            displayAt: _calendarTimeFor(post),
            onTap: _postTapHandler(post),
            busyLabel:
                _pendingActionPostId == post.id ? _pendingActionLabel : null,
          ),
          const SizedBox(height: 9),
        ],
    ];
  }
}

class _MonthNavButton extends StatelessWidget {
  const _MonthNavButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.glass,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Icon(icon, size: 19, color: AppTheme.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent : AppTheme.glass,
          borderRadius: BorderRadius.circular(999),
          border: selected ? null : Border.all(color: AppTheme.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _DayPostRow extends StatelessWidget {
  const _DayPostRow({
    required this.post,
    required this.displayAt,
    required this.onTap,
    required this.busyLabel,
  });

  final ScheduledPostResult post;
  final DateTime displayAt;
  final VoidCallback? onTap;
  final String? busyLabel;

  @override
  Widget build(BuildContext context) {
    final platform = _platformFor(post.platforms.firstOrNull ?? '');
    final tint = platform?.displayColor ?? AppTheme.accent;
    final isScheduled = post.status == 'QUEUED';

    return Semantics(
      button: onTap != null,
      label: post.caption,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: AppTheme.glass,
            borderRadius: BorderRadius.circular(15),
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
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  isScheduled ? Icons.schedule : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      busyLabel ??
                          '${_statusLabel(post)} · ${_formatTime(displayAt)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: busyLabel == null
                            ? FontWeight.normal
                            : FontWeight.w700,
                        color: busyLabel == null
                            ? AppTheme.textMuted
                            : AppTheme.accentCyanInk,
                      ),
                    ),
                  ],
                ),
              ),
              if (busyLabel != null)
                const SizedBox(
                  key: ValueKey('calendar-post-action-progress'),
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else if (onTap != null)
                Icon(Icons.chevron_right, size: 20, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyDayCard extends StatelessWidget {
  const _EmptyDayCard({super.key, required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'ยังไม่มีโพสต์ในวันนี้ — แตะเพื่อสร้าง',
      child: GestureDetector(
        onTap: onTap,
        child: CustomPaint(
          foregroundPainter: _DashedRRectBorderPainter(
            color: AppTheme.border,
            radius: 15,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppTheme.glass,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.add_circle_outline,
                  size: 28,
                  color: AppTheme.accentCyanInk,
                ),
                const SizedBox(height: 8),
                Text(
                  'ยังไม่มีโพสต์ในวันนี้ — แตะเพื่อสร้าง',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRRectBorderPainter extends CustomPainter {
  const _DashedRRectBorderPainter({
    required this.color,
    required this.radius,
  })  : dash = 7,
        gap = 6,
        strokeWidth = 1;

  final Color color;
  final double radius;
  final double dash;
  final double gap;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dash;
        canvas.drawPath(
          metric.extractPath(
            distance,
            next > metric.length ? metric.length : next,
          ),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}

SocialPlatform? _platformFor(String apiValue) {
  for (final platform in SocialPlatform.values) {
    if (platform.apiValue == apiValue) {
      return platform;
    }
  }
  return null;
}

bool _isSameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

bool _canEditQueue(ScheduledPostResult post) =>
    post.status.toUpperCase() == 'QUEUED';

bool _canOpenPostDetail(ScheduledPostResult post) {
  final status = post.status.toUpperCase();
  return status == 'PUBLISHED' ||
      status == 'PARTIAL_PUBLISHED' ||
      status == 'FAILED';
}

bool _needsStatusRefresh(ScheduledPostResult post) {
  final status = post.status.toUpperCase();
  return status == 'QUEUED' || status == 'PUBLISHING';
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

String _statusLabel(ScheduledPostResult post) {
  final deliveryLabel = aggregatePostDeliveryOutcomeLabel(
    post.platformResults,
    compact: true,
  );
  if (deliveryLabel != null) return deliveryLabel;

  switch (post.status.toUpperCase()) {
    case 'QUEUED':
      return 'รอส่งตามเวลา';
    case 'PUBLISHING':
      return 'กำลังส่ง';
    case 'PUBLISHED':
      return 'ส่งสำเร็จ';
    case 'PARTIAL_PUBLISHED':
      return 'ส่งสำเร็จบางช่องทาง';
    case 'FAILED':
      return 'ส่งไม่สำเร็จ';
    default:
      return post.status;
  }
}
