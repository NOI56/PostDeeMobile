import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/network/postdee_api_client.dart';
import '../../core/network/api_error_message.dart';
import '../../core/theme/app_theme.dart';
import '../platforms/connections_screen.dart' show connectablePlatforms;
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';
import '../shared/post_schedule_policy.dart';
import '../shared/post_delivery_outcome.dart';
import '../shared/postdee_notice.dart';
import '../shared/postdee_press_feedback.dart';
import '../shared/postdee_publishing_motion.dart';
import '../shared/postdee_skeleton.dart';
import '../shared/postdee_time_picker.dart';
import '../shared/publishing_availability.dart';
import 'calendar_cover_preview_cache.dart';

typedef ScheduledPostsLoader = Future<List<ScheduledPostResult>> Function();
typedef CalendarPostsLoader = Future<List<CalendarPostResult>> Function();
typedef ScheduledPostRescheduler = Future<ScheduledPostResult> Function(
  String postId,
  DateTime scheduledAt,
);
typedef ScheduledPostCanceller = Future<void> Function(String postId);
typedef CalendarTimeConverter = DateTime Function(DateTime value);
typedef CalendarSubscriptionLoader = Future<SubscriptionStatusResult>
    Function();

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    this.refreshToken = 0,
    this.isActive = true,
    this.loadScheduledPosts,
    this.loadCalendarPosts,
    this.reschedulePost,
    this.cancelPost,
    this.loadPost,
    this.loadCoverPost,
    this.extractLegacyCoverFrame,
    this.onAddPost,
    this.onAddPostForDate,
    this.ownerUserId,
    this.onOpenPostDetail,
    this.onOpenCalendarPostDetail,
    this.toLocalTime,
    this.now,
    this.loadSubscription,
  });

  final int refreshToken;
  final bool isActive;
  final ScheduledPostsLoader? loadScheduledPosts;
  final CalendarPostsLoader? loadCalendarPosts;
  final ScheduledPostRescheduler? reschedulePost;
  final ScheduledPostCanceller? cancelPost;
  final Future<PostSummaryResult?> Function(String postId)? loadPost;
  final Future<PostSummaryResult?> Function(String postId)? loadCoverPost;
  final CalendarLegacyCoverFrameLoader? extractLegacyCoverFrame;
  final CalendarTimeConverter? toLocalTime;
  final DateTime Function()? now;
  final CalendarSubscriptionLoader? loadSubscription;

  /// Jump to the upload flow to schedule a new post.
  final VoidCallback? onAddPost;
  final ValueChanged<DateTime>? onAddPostForDate;
  final String? ownerUserId;

  /// Open a read-only result for a post that has finished publishing.
  final ValueChanged<ScheduledPostResult>? onOpenPostDetail;
  final ValueChanged<CalendarPostResult>? onOpenCalendarPostDetail;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with WidgetsBindingObserver {
  static const _queuedRefreshInterval = Duration(seconds: 30);

  final _apiClient = PostDeeApiClient();
  late AuthSessionBinding _coverSession;
  late CalendarCoverPreviewCache _coverPreviews;
  bool _isLoading = true;
  bool _hasLoaded = false;
  bool _isRefreshing = false;
  bool _isWeekView = true;
  DateTime? _lastUpdated;
  int _ownerGeneration = 0;
  String? _ownerId;
  String? _sessionOwnerId;
  bool _loadInProgress = false;
  bool _reloadRequested = false;
  Future<void>? _activeLoad;
  int _postMutationGeneration = 0;
  bool _appIsResumed = true;
  String? _errorMessage;
  List<CalendarPostResult> _posts = const [];
  Timer? _queuedRefreshTimer;
  late DateTime _visibleMonth;
  DateTime? _selectedDay;
  String _platformFilter = 'all';
  String? _pendingActionPostId;
  String? _pendingActionLabel;

  @override
  void initState() {
    super.initState();
    _sessionOwnerId = PostDeeAuthSessionStore.instance.session.stableUserId;
    _ownerId = widget.ownerUserId ?? _sessionOwnerId;
    _coverPreviews = _createCoverPreviews();
    PostDeeAuthSessionStore.instance.addListener(_onSessionChanged);
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
    if (oldWidget.ownerUserId != widget.ownerUserId) {
      _resetOwner();
      if (widget.isActive) unawaited(_loadPosts());
      return;
    }
    if (oldWidget.loadCoverPost != widget.loadCoverPost ||
        oldWidget.extractLegacyCoverFrame != widget.extractLegacyCoverFrame) {
      _replaceCoverPreviews();
    }
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
    final resumed = state == AppLifecycleState.resumed;
    if (_appIsResumed != resumed) {
      setState(() => _appIsResumed = resumed);
    }
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
    _ownerGeneration++;
    _coverPreviews.dispose();
    PostDeeAuthSessionStore.instance.removeListener(_onSessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    _queuedRefreshTimer?.cancel();
    super.dispose();
  }

  void _onSessionChanged() {
    final owner = PostDeeAuthSessionStore.instance.session.stableUserId;
    if (_sessionOwnerId == owner) {
      if (!_coverSession.isCurrent) setState(_replaceCoverPreviews);
      return;
    }
    _sessionOwnerId = owner;
    _resetOwner();
    if (widget.isActive &&
        (widget.ownerUserId == null || widget.ownerUserId == owner)) {
      unawaited(_loadPosts());
    }
  }

  void _resetOwner() {
    _ownerGeneration++;
    _postMutationGeneration++;
    _ownerId = widget.ownerUserId ?? _sessionOwnerId;
    _replaceCoverPreviews();
    _queuedRefreshTimer?.cancel();
    _queuedRefreshTimer = null;
    _loadInProgress = false;
    _reloadRequested = false;
    _activeLoad = null;
    final now = _now();
    setState(() {
      _posts = const [];
      _selectedDay = null;
      _visibleMonth = DateTime(now.year, now.month);
      _hasLoaded = false;
      _isLoading = widget.isActive;
      _isRefreshing = false;
      _lastUpdated = null;
      _errorMessage = null;
      _pendingActionPostId = null;
      _pendingActionLabel = null;
    });
  }

  bool _loadStillOwned(int generation, String? sessionOwner) =>
      mounted &&
      generation == _ownerGeneration &&
      sessionOwner == PostDeeAuthSessionStore.instance.session.stableUserId;

  CalendarCoverPreviewCache _createCoverPreviews() {
    final session = PostDeeAuthSessionStore.instance.captureSession();
    _coverSession = session;
    final generation = _ownerGeneration;
    final api = PostDeeApiClient(sessionBinding: session);
    return CalendarCoverPreviewCache(
      extractFrame: widget.extractLegacyCoverFrame,
      loadPost: (id) =>
          widget.loadCoverPost?.call(id) ??
          api.getPostById(id, includeMedia: true),
      isCurrent: () =>
          mounted &&
          session.isCurrent &&
          generation == _ownerGeneration &&
          widget.isActive &&
          _appIsResumed,
    );
  }

  void _replaceCoverPreviews() {
    _coverPreviews.dispose();
    _coverPreviews = _createCoverPreviews();
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
    final generation = _ownerGeneration;
    final sessionOwner = PostDeeAuthSessionStore.instance.session.stableUserId;
    final owner = _ownerId;
    if (!silent) _replaceCoverPreviews();
    setState(() {
      _isLoading = !_hasLoaded;
      _isRefreshing = _hasLoaded;
      _errorMessage = null;
    });

    try {
      do {
        _reloadRequested = false;
        final mutationGeneration = _postMutationGeneration;
        try {
          final posts = await _loadCalendarPosts();

          if (!_loadStillOwned(generation, sessionOwner)) return;
          if (mutationGeneration != _postMutationGeneration) continue;

          final sorted = posts
              .where((post) =>
                  owner == null || post.userId == null || post.userId == owner)
              .toList()
            ..sort((left, right) =>
                _calendarTimeFor(left).compareTo(_calendarTimeFor(right)));

          setState(() {
            _posts = sorted;
            _hasLoaded = true;
            _lastUpdated = _now();
            _errorMessage = null;
            // Prefer upcoming posts in the visible month. Old scheduled
            // history must never pull the initial calendar into a past month.
            final today = _now();
            final firstInMonth = sorted.where((post) {
              final at = _calendarTimeFor(post);
              return at.year == _visibleMonth.year &&
                  at.month == _visibleMonth.month &&
                  !at.isBefore(DateTime(today.year, today.month, today.day));
            }).firstOrNull;
            if (_selectedDay == null && firstInMonth != null) {
              final first = _calendarTimeFor(firstInMonth);
              _selectedDay = DateTime(first.year, first.month, first.day);
            }
          });
        } on ApiException catch (error) {
          if (!_loadStillOwned(generation, sessionOwner)) return;
          setState(() => _errorMessage = apiErrorMessage(error,
              fallbackMessage:
                  'โหลดปฏิทินโพสต์ไม่สำเร็จ กรุณาลองใหม่อีกครั้ง'));
        } on SocketException {
          if (!_loadStillOwned(generation, sessionOwner)) return;
          setState(() => _errorMessage = 'เชื่อมต่อ PostDee API ไม่ได้');
        } catch (_) {
          if (!_loadStillOwned(generation, sessionOwner)) return;
          setState(() => _errorMessage = 'โหลดปฏิทินโพสต์ไม่สำเร็จ');
        }
      } while (_reloadRequested && _loadStillOwned(generation, sessionOwner));
    } finally {
      if (_loadStillOwned(generation, sessionOwner)) {
        _loadInProgress = false;
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
        _syncQueuedRefresh();
      }
    }
  }

  Future<List<CalendarPostResult>> _loadCalendarPosts() async {
    final loader = widget.loadCalendarPosts;
    if (loader != null) return loader();
    final legacyLoader = widget.loadScheduledPosts;
    if (legacyLoader != null) {
      return (await legacyLoader())
          .map(CalendarPostResult.fromScheduledPost)
          .toList();
    }
    return _apiClient.listCalendarPosts();
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

  DateTime _calendarTimeFor(CalendarPostResult post) {
    final status = post.status.toUpperCase();
    final isFinished = status == 'PUBLISHED' ||
        status == 'PARTIAL_PUBLISHED' ||
        status == 'FAILED';
    final timestamp = (isFinished ? post.publishedAt : null) ??
        post.scheduledAt ??
        post.createdAt;
    return _toLocalTime(timestamp);
  }

  DateTime _toLocalTime(DateTime value) =>
      widget.toLocalTime?.call(value) ?? value.toLocal();

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  // The prototype always keeps one day selected; default to today.
  DateTime get _activeDay {
    final day = (_selectedDay ?? _now()).toLocal();
    return DateTime(day.year, day.month, day.day);
  }

  String _dayKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

  List<CalendarPostResult> get _visiblePosts => _posts
      .where((p) =>
          _platformFilter == 'all' || p.platforms.contains(_platformFilter))
      .toList();

  Map<String, int> get _dayCounts {
    final counts = <String, int>{};
    for (final post in _visiblePosts) {
      final key = _dayKey(_calendarTimeFor(post));
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  List<CalendarPostResult> get _dayPosts => _visiblePosts
      .where((p) => _isSameDay(_calendarTimeFor(p), _activeDay))
      .toList();

  DateTime get _periodStart => _isWeekView
      ? DateTime(_activeDay.year, _activeDay.month,
          _activeDay.day - _activeDay.weekday + 1)
      : DateTime(_activeDay.year, _activeDay.month);

  DateTime get _periodEnd => _isWeekView
      ? DateTime(_periodStart.year, _periodStart.month, _periodStart.day + 6)
      : DateTime(_activeDay.year, _activeDay.month + 1, 0);

  void _changePeriod(int delta) {
    _selectDay(_isWeekView
        ? DateTime(
            _activeDay.year, _activeDay.month, _activeDay.day + 7 * delta)
        : DateTime(_activeDay.year, _activeDay.month + delta));
  }

  void _selectDay(DateTime date) {
    setState(() {
      _selectedDay = DateTime(date.year, date.month, date.day);
      _visibleMonth = DateTime(date.year, date.month);
    });
  }

  bool get _hasAddAction =>
      widget.onAddPostForDate != null || widget.onAddPost != null;
  bool get _isPastDay {
    final now = _now().toLocal();
    return _activeDay.isBefore(DateTime(now.year, now.month, now.day));
  }

  void _addPostForDay() {
    if (_isPastDay) {
      _showScheduleMessage('วันที่ผ่านมาแล้ว กรุณาเลือกวันนี้หรือวันถัดไป');
      return;
    }
    if (widget.onAddPostForDate != null) {
      widget.onAddPostForDate!(_activeDay);
    } else {
      widget.onAddPost?.call();
    }
  }

  VoidCallback? _postTapHandler(CalendarPostResult post) {
    if (_pendingActionPostId != null) return null;

    if (_canEditQueue(post)) {
      return () => _showPostActions(post);
    }

    if (_canOpenPostDetail(post)) {
      if (widget.onOpenCalendarPostDetail != null) {
        return () => widget.onOpenCalendarPostDetail!(post);
      }
      final scheduledPost = post.toScheduledPost();
      if (scheduledPost != null && widget.onOpenPostDetail != null) {
        return () => widget.onOpenPostDetail!(scheduledPost);
      }
    }

    return null;
  }

  Future<void> _showPostActions(CalendarPostResult post) async {
    if (!_canEditQueue(post)) return;
    final generation = _ownerGeneration;
    final owner = PostDeeAuthSessionStore.instance.session.stableUserId;

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
                if (!_loadStillOwned(generation, owner)) return;
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
                if (!_loadStillOwned(generation, owner)) return;
                _cancel(post);
              },
            ),
            const SizedBox(height: AppTheme.spaceSm),
          ],
        ),
      ),
    );
  }

  Future<void> _reschedule(CalendarPostResult post) async {
    if (!_canEditQueue(post) || _pendingActionPostId != null) return;
    final ownerUserId = PostDeeAuthSessionStore.instance.session.stableUserId;
    final generation = _ownerGeneration;

    setState(() {
      _pendingActionPostId = post.id;
      _pendingActionLabel = 'กำลังตรวจสอบแพ็กเกจ...';
    });
    try {
      final subscription = await _loadScheduleSubscription();
      if (!mounted || !_loadStillOwned(generation, ownerUserId)) return;
      final limit = postScheduleLimitForPlan(subscription.plan);
      if (!subscription.canSchedule || limit == null) {
        _showScheduleMessage(schedulePaidPlanMessage);
        return;
      }
      setState(() => _pendingActionLabel = null);
      await _rescheduleWhileLocked(post, limit, ownerUserId, generation);
    } catch (_) {
      if (mounted && _loadStillOwned(generation, ownerUserId)) {
        _showScheduleMessage(scheduleSubscriptionUnavailableMessage);
      }
    } finally {
      if (mounted && _loadStillOwned(generation, ownerUserId)) {
        setState(() {
          _pendingActionPostId = null;
          _pendingActionLabel = null;
        });
      }
    }
  }

  Future<SubscriptionStatusResult> _loadScheduleSubscription() =>
      (widget.loadSubscription ?? _apiClient.loadCurrentSubscription)();

  void _showScheduleMessage(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _rescheduleWhileLocked(CalendarPostResult post, Duration limit,
      String? ownerUserId, int generation) async {
    final current = _toLocalTime(post.scheduledAt!);
    final currentNow = _now();
    final today = DateTime(
      currentNow.year,
      currentNow.month,
      currentNow.day,
    );
    final lastDate = today.add(limit);
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
    if (date == null || !mounted || !_loadStillOwned(generation, ownerUserId)) {
      return;
    }

    final time = await showPostDeeTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      date: date,
    );
    if (time == null || !mounted || !_loadStillOwned(generation, ownerUserId)) {
      return;
    }

    final next =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final subscription = await _loadScheduleSubscription();
    if (!mounted || !_loadStillOwned(generation, ownerUserId)) return;
    if (!subscription.canSchedule ||
        postScheduleLimitForPlan(subscription.plan) == null) {
      _showScheduleMessage(schedulePaidPlanMessage);
      return;
    }
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
      plan: subscription.plan,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(postScheduleLimitMessage(subscription.plan,
                rescheduling: true))),
      );
      return;
    }

    setState(() {
      _pendingActionPostId = post.id;
      _pendingActionLabel = 'กำลังเลื่อนเวลา...';
    });

    try {
      final reschedulePost = widget.reschedulePost ?? _apiClient.reschedulePost;
      if (!mounted || !_loadStillOwned(generation, ownerUserId)) return;
      final updated = await reschedulePost(post.id, next);
      final updatedPost = CalendarPostResult(
        id: updated.id,
        caption: updated.caption,
        videoS3Key: updated.videoS3Key,
        platforms: updated.platforms,
        status: updated.status,
        createdAt: updated.createdAt,
        scheduledAt: updated.scheduledAt,
        publishedAt: updated.publishedAt,
        platformResults: updated.platformResults,
        userId: updated.userId,
        videoUrl: post.videoUrl,
        coverImageUrl: post.coverImageUrl,
        coverImageS3Key: post.coverImageS3Key,
        coverFrameTimeMs: post.coverFrameTimeMs,
      );
      if (!mounted || !_loadStillOwned(generation, ownerUserId)) return;
      if (updatedPost.userId != null && updatedPost.userId != _ownerId) return;
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
      if (mounted && _loadStillOwned(generation, ownerUserId)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isPublishingUnavailable(error)
                  ? publishingUnavailableActionMessage
                  : postScheduleApiErrorMessage(error,
                          plan: subscription.plan, rescheduling: true) ??
                      'เลื่อนเวลาไม่สำเร็จ ลองใหม่อีกครั้ง',
            ),
          ),
        );
      }
      return;
    } catch (_) {
      if (mounted && _loadStillOwned(generation, ownerUserId)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เลื่อนเวลาไม่สำเร็จ ลองใหม่อีกครั้ง')),
        );
      }
      return;
    }

    if (!mounted || !_loadStillOwned(generation, ownerUserId)) return;
    // Keep the action locked until refresh finishes, but stop the spinner
    // once the mutation itself has completed.
    setState(() => _pendingActionLabel = null);
    await _loadPosts();
    if (!mounted || !_loadStillOwned(generation, ownerUserId)) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('เลื่อนเป็น ${_formatThaiDate(next)} ${_formatTime(next)}')),
    );
  }

  Future<void> _cancel(CalendarPostResult post) async {
    if (!_canEditQueue(post) || _pendingActionPostId != null) return;
    final generation = _ownerGeneration;
    final ownerUserId = PostDeeAuthSessionStore.instance.session.stableUserId;

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

    if (confirmed != true ||
        !mounted ||
        !_loadStillOwned(generation, ownerUserId)) {
      return;
    }

    setState(() {
      _pendingActionPostId = post.id;
      _pendingActionLabel = 'กำลังยกเลิก...';
    });

    try {
      final cancelPost = widget.cancelPost ?? _apiClient.cancelPost;
      await cancelPost(post.id);
      if (!mounted || !_loadStillOwned(generation, ownerUserId)) return;
      _postMutationGeneration += 1;
    } catch (_) {
      if (mounted && _loadStillOwned(generation, ownerUserId)) {
        // A missing response does not prove that cancellation failed. Read the
        // same owned row without retrying the mutation or sending any video.
        String message;
        try {
          final latest = await (widget.loadPost?.call(post.id) ??
              _apiClient.getPostById(post.id));
          if (!mounted || !_loadStillOwned(generation, ownerUserId)) return;
          if (latest != null && latest.id != post.id) {
            throw const ApiException('Post id mismatch');
          }
          final latestOwner =
              latest is CalendarPostResult ? latest.userId : null;
          if (latestOwner != null && latestOwner != _ownerId) {
            throw const ApiException('Post owner mismatch');
          }
          _postMutationGeneration++;
          setState(() {
            _posts = [
              for (final current in _posts)
                if (current.id != post.id)
                  current
                else if (latest != null)
                  CalendarPostResult(
                    id: latest.id,
                    caption: latest.caption,
                    videoS3Key: latest.videoS3Key,
                    platforms: latest.platforms,
                    status: latest.status,
                    createdAt: latest.createdAt,
                    scheduledAt: latest.scheduledAt,
                    publishedAt: latest.publishedAt,
                    platformResults: latest.platformResults,
                    userId: post.userId,
                    videoUrl: latest.videoUrl,
                    coverImageUrl: latest.coverImageUrl,
                    coverImageS3Key: latest.coverImageS3Key,
                    coverFrameTimeMs: latest.coverFrameTimeMs,
                  )
            ];
            _lastUpdated = _now();
          });
          message = latest == null
              ? 'ไม่พบโพสต์นี้ในรายการแล้ว อาจถูกยกเลิกหรือถูกนำออก'
              : latest.status.toUpperCase() == 'PUBLISHING'
                  ? 'โพสต์เริ่มส่งแล้ว จึงยกเลิกคิวไม่ได้ กรุณาติดตามผลล่าสุด'
                  : latest.status.toUpperCase() != 'QUEUED'
                      ? 'สถานะโพสต์เปลี่ยนแล้ว กำลังแสดงผลล่าสุด'
                      : 'รายการยังรอส่งตามเวลา ยังยืนยันการยกเลิกไม่ได้';
          _syncQueuedRefresh();
        } catch (_) {
          message = 'ยังยืนยันผลการยกเลิกไม่ได้ กรุณารีเฟรชเมื่อเชื่อมต่อได้';
        }
        if (!mounted || !_loadStillOwned(generation, ownerUserId)) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
      return;
    } finally {
      if (mounted && _loadStillOwned(generation, ownerUserId)) {
        setState(() {
          _pendingActionPostId = null;
          _pendingActionLabel = null;
        });
      }
    }

    if (!mounted || !_loadStillOwned(generation, ownerUserId)) return;
    setState(() => _posts = _posts.where((p) => p.id != post.id).toList());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ยกเลิกโพสต์แล้ว')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.sizeOf(context).width <= 360 ? 8.0 : 16.0;
    return TickerMode(
      enabled: _motionEnabled,
      child: RefreshIndicator(
        key: const ValueKey('calendar-pull-refresh'),
        onRefresh: _loadPosts,
        color: AppTheme.accent,
        child: SingleChildScrollView(
          key: const ValueKey('calendar-screen'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding:
              EdgeInsets.fromLTRB(padding, 8, padding, AppTheme.navOverlap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 12),
              Wrap(spacing: 5, runSpacing: 6, children: [
                _FilterChip(
                    key: const ValueKey('calendar-week-view'),
                    label: 'สัปดาห์',
                    animate: _motionEnabled,
                    selected: _isWeekView,
                    onTap: () => setState(() => _isWeekView = true)),
                _FilterChip(
                    key: const ValueKey('calendar-month-view'),
                    label: 'เดือน',
                    animate: _motionEnabled,
                    selected: !_isWeekView,
                    onTap: () => setState(() => _isWeekView = false)),
                PostDeePressFeedback(
                  enabled: _motionEnabled,
                  child: TextButton.icon(
                    key: const ValueKey('calendar-today'),
                    onPressed: () => _selectDay(_now().toLocal()),
                    icon: const Icon(Icons.today_outlined, size: 18),
                    label: const Text('วันนี้'),
                    style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        foregroundColor: AppTheme.accentCyanInk),
                  ),
                ),
              ]),
              const SizedBox(height: 9),
              _buildMonthCard(),
              const SizedBox(height: 10),
              _buildPeriodSummary(),
              const SizedBox(height: 10),
              _buildPlatformFilter(),
              const SizedBox(height: 16),
              _buildDayContent(),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: Semantics(
                  liveRegion: true,
                  child: Text(
                      _isRefreshing
                          ? 'กำลังอัปเดต · ข้อมูลเดิมยังแสดงอยู่'
                          : _lastUpdated == null
                              ? 'ยังไม่ได้อัปเดตข้อมูล'
                              : 'อัปเดตล่าสุด ${_formatTime(_lastUpdated!)}',
                      key: const ValueKey('calendar-update-status'),
                      style:
                          TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                )),
                PostDeePressFeedback(
                  enabled: _motionEnabled && !_isLoading && !_isRefreshing,
                  child: TextButton.icon(
                    key: const ValueKey('calendar-refresh'),
                    onPressed:
                        _isLoading || _isRefreshing ? null : () => _loadPosts(),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('รีเฟรช'),
                  ),
                ),
              ]),
              if (_hasAddAction && !_isPastDay)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: PostDeePressFeedback(
                    enabled: _motionEnabled,
                    child: FilledButton.icon(
                      key: const ValueKey('calendar-create-selected-day'),
                      onPressed: _addPostForDay,
                      icon: const Icon(Icons.add_outlined),
                      label:
                          Text('สร้างโพสต์ · ${_formatThaiDate(_activeDay)}'),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          minimumSize: const Size(48, 48)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _motionEnabled => widget.isActive && _appIsResumed;

  Widget _buildDayContent() => KeyedSubtree(
        // Keep only the current day/owner mounted, including during a fade.
        // Outgoing post controls must never remain actionable or readable.
        key: ValueKey(
            'calendar-content-$_ownerGeneration-${_dayKey(_activeDay)}-$_platformFilter-$_hasLoaded'),
        child: _CalendarDayTransition(
          key: const ValueKey('calendar-day-transition'),
          animate: _motionEnabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _buildDaySection(context),
          ),
        ),
      );

  Widget _buildHeader() {
    final title =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('ปฏิทินโพสต์',
          style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary)),
      const SizedBox(height: 2),
      Text('เห็นคิวชัด วางแผนได้ง่ายขึ้น',
          style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
    ]);
    if (MediaQuery.textScalerOf(context).scale(14) >= 21) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        title,
        if (_hasAddAction) ...[
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: _buildAddPostButton()),
        ],
      ]);
    }
    return Row(children: [
      Expanded(child: title),
      if (_hasAddAction) _buildAddPostButton(),
    ]);
  }

  Widget _buildAddPostButton() {
    return Semantics(
      key: const ValueKey('calendar-add-post'),
      label: 'สร้างโพสต์สำหรับ ${_formatThaiDate(_activeDay)}',
      button: true,
      enabled: !_isPastDay,
      onTap: _isPastDay ? null : _addPostForDay,
      child: PostDeePressFeedback(
        enabled: _motionEnabled && !_isPastDay,
        child: ExcludeSemantics(
            child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _isPastDay ? null : _addPostForDay,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
                color: _isPastDay ? AppTheme.border : AppTheme.accent,
                borderRadius: BorderRadius.circular(12)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add_rounded, color: Colors.white, size: 21),
              SizedBox(width: 4),
              Text('สร้างโพสต์',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        )),
      ),
    );
  }

  Widget _buildMonthCard() {
    final counts = _dayCounts;
    final start = _periodStart;
    final end = _periodEnd;
    final days = _isWeekView ? 7 : end.day;
    final blanks = _isWeekView ? 0 : start.weekday - 1;
    final narrow = MediaQuery.sizeOf(context).width <= 360;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: narrow ? 0 : 8, vertical: 10),
      decoration: BoxDecoration(
          color: AppTheme.glass,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: AppTheme.border)),
      child: Column(children: [
        Row(children: [
          _MonthNavButton(
              key: const ValueKey('calendar-previous-period'),
              animate: _motionEnabled,
              icon: Icons.chevron_left,
              label: _isWeekView ? 'สัปดาห์ก่อนหน้า' : 'เดือนก่อนหน้า',
              onTap: () => _changePeriod(-1)),
          Expanded(
              child: Column(children: [
            Text('${_thaiMonthsFull[_activeDay.month - 1]} ${_activeDay.year}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
            if (_isWeekView)
              Text(
                  '${start.day} ${_thaiMonthsShort[start.month - 1]} – ${end.day} ${_thaiMonthsShort[end.month - 1]}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          ])),
          _MonthNavButton(
              key: const ValueKey('calendar-next-period'),
              animate: _motionEnabled,
              icon: Icons.chevron_right,
              label: _isWeekView ? 'สัปดาห์ถัดไป' : 'เดือนถัดไป',
              onTap: () => _changePeriod(1)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          for (final label in _weekdayLabels)
            Expanded(
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted))),
        ]),
        const SizedBox(height: 5),
        _CalendarPeriodSize(
          animate: _motionEnabled,
          child: GridView.count(
            crossAxisCount: 7,
            childAspectRatio: 1,
            mainAxisSpacing: 2,
            crossAxisSpacing: 1,
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < blanks; i++) const SizedBox.shrink(),
              for (var offset = 0; offset < days; offset++)
                _dayCell(DateTime(start.year, start.month, start.day + offset),
                    counts),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _dayCell(DateTime date, Map<String, int> counts) {
    final selected = _isSameDay(date, _activeDay);
    final count = counts[_dayKey(date)] ?? 0;
    final today = _isSameDay(date, _now().toLocal());
    final shortCount = MediaQuery.sizeOf(context).width <= 360 ||
        MediaQuery.textScalerOf(context).scale(11) > 14;
    return Semantics(
      key: ValueKey(
          'calendar-day-${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'),
      label:
          '${_formatThaiDate(date)}${today ? ' วันนี้' : ''} มี $count โพสต์',
      button: true,
      selected: selected,
      onTap: () => _selectDay(date),
      child: PostDeePressFeedback(
        key: ValueKey('calendar-day-feedback-${_dayKey(date)}'),
        enabled: _motionEnabled,
        child: ExcludeSemantics(
            child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => _selectDay(date),
          child: _CalendarSelectionDecoration(
            animate: _motionEnabled,
            decoration: BoxDecoration(
                color: selected ? AppTheme.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(11)),
            child: Column(children: [
              Expanded(
                  child: Center(
                      child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('${date.day}',
                    maxLines: 1,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected || today
                            ? FontWeight.w700
                            : FontWeight.w500,
                        decoration: today && !selected
                            ? TextDecoration.underline
                            : null,
                        color: selected ? Colors.white : AppTheme.textPrimary)),
              ))),
              Expanded(
                  child: Center(
                      child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                    count == 0
                        ? ''
                        : shortCount
                            ? '$count'
                            : '$count โพสต์',
                    style: TextStyle(
                        fontSize: 11,
                        color: selected ? Colors.white : AppTheme.textMuted)),
              ))),
            ]),
          ),
        )),
      ),
    );
  }

  Widget _buildPeriodSummary() {
    if (!_hasLoaded) return const SizedBox.shrink();
    final period = _visiblePosts.where((post) {
      final date = _calendarTimeFor(post);
      return !date.isBefore(_periodStart) &&
          date.isBefore(
              DateTime(_periodEnd.year, _periodEnd.month, _periodEnd.day + 1));
    }).toList();
    final queued =
        period.where((post) => post.status.toUpperCase() == 'QUEUED').length;
    final review = period
        .where((post) =>
            const ['FAILED', 'PARTIAL_PUBLISHED']
                .contains(post.status.toUpperCase()) ||
            hasUnconfirmedDeliveryOutcome(post.platformResults))
        .length;
    final now = _now().toLocal();
    final current = _isWeekView
        ? !now.isBefore(_periodStart) &&
            now.isBefore(_periodEnd.add(const Duration(days: 1)))
        : now.year == _activeDay.year && now.month == _activeDay.month;
    final label = _isWeekView
        ? (current ? 'สัปดาห์นี้' : 'สัปดาห์ที่เลือก')
        : (current ? 'เดือนนี้' : 'เดือนที่เลือก');
    return Text(
        '$label ${period.length} โพสต์ · รอส่ง $queued${review > 0 ? ' · ต้องตรวจสอบ $review' : ''}',
        key: const ValueKey('calendar-period-summary'),
        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary));
  }

  Widget _buildPlatformFilter() {
    final buttons = [
      _PlatformFilterButton(
          key: const ValueKey('calendar-filter-all'),
          label: 'ทั้งหมด',
          animate: _motionEnabled,
          selected: _platformFilter == 'all',
          onTap: () => setState(() => _platformFilter = 'all')),
      for (final platform in connectablePlatforms)
        _PlatformFilterButton(
            key: ValueKey('calendar-filter-${platform.apiValue}'),
            label: platform.shortLabel,
            animate: _motionEnabled,
            platform: platform,
            selected: _platformFilter == platform.apiValue,
            onTap: () => setState(() => _platformFilter = platform.apiValue)),
    ];
    return LayoutBuilder(
      key: const ValueKey('calendar-platform-filters'),
      builder: (context, constraints) {
        if (MediaQuery.textScalerOf(context).scale(11) > 14.3) {
          return Wrap(spacing: 6, runSpacing: 6, children: [
            for (final button in buttons)
              SizedBox(width: (constraints.maxWidth - 12) / 3, child: button),
          ]);
        }
        return IntrinsicHeight(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Expanded(child: buttons[i]),
          ],
        ]));
      },
    );
  }

  List<Widget> _buildDaySection(BuildContext context) {
    if (_isLoading && !_hasLoaded) {
      return [
        Semantics(
          key: const ValueKey('calendar-loading'),
          label: 'กำลังโหลดปฏิทินโพสต์...',
          liveRegion: true,
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: PostDeeSkeleton(
                      width: 140, height: 14, animate: _motionEnabled),
                ),
                const SizedBox(height: 14),
                PostDeeSkeleton(
                    height: 76, radius: 13, animate: _motionEnabled),
                const SizedBox(height: 10),
                PostDeeSkeleton(
                    height: 76, radius: 13, animate: _motionEnabled),
              ],
            ),
          ),
        ),
      ];
    }
    final dayPosts = _dayPosts;
    _coverPreviews.retain(dayPosts.map((post) => post.id));
    return [
      if (_errorMessage != null) ...[
        PostDeeNotice(
            key: const ValueKey('calendar-error'),
            icon: Icons.error_outline,
            message: _hasLoaded
                ? 'อัปเดตไม่สำเร็จ กำลังแสดงข้อมูลเดิม\n$_errorMessage'
                : _errorMessage!,
            color: Theme.of(context).colorScheme.error,
            actionLabel: 'ลองใหม่',
            onAction: _loadPosts),
        const SizedBox(height: 10),
      ],
      if (_hasLoaded) ...[
        Row(children: [
          Expanded(
              child: Text(_formatThaiDate(_activeDay),
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary))),
          Text('${dayPosts.length} โพสต์',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
        ]),
        const SizedBox(height: 10),
        if (dayPosts.isEmpty)
          _EmptyDayCard(
            key: const ValueKey('calendar-empty'),
            animate: _motionEnabled,
            title: _platformFilter == 'all'
                ? 'วันที่เลือกยังไม่มีโพสต์'
                : 'ไม่มีโพสต์สำหรับช่องทางนี้',
            actionLabel: _isPastDay ? 'กลับไปวันนี้' : 'สร้างโพสต์วันที่นี้',
            onTap: _isPastDay
                ? () => _selectDay(_now().toLocal())
                : _hasAddAction
                    ? _addPostForDay
                    : null,
          )
        else
          for (final post in dayPosts)
            _DayPostRow(
                post: post,
                coverPreviews: _coverPreviews,
                animate: _motionEnabled,
                displayAt: _calendarTimeFor(post),
                onTap: _postTapHandler(post),
                busyLabel: _pendingActionPostId == post.id
                    ? _pendingActionLabel
                    : null),
      ],
    ];
  }
}

class _CalendarDayTransition extends StatefulWidget {
  const _CalendarDayTransition({
    super.key,
    required this.animate,
    required this.child,
  });

  final bool animate;
  final Widget child;

  @override
  State<_CalendarDayTransition> createState() => _CalendarDayTransitionState();
}

class _CalendarDayTransitionState extends State<_CalendarDayTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  bool get _allowed =>
      widget.animate &&
      TickerMode.valuesOf(context).enabled &&
      !MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant _CalendarDayTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  void _syncMotion() {
    if (!_allowed) {
      _controller.stop();
      _controller.value = 1;
    } else if (!_started) {
      _controller.forward();
    }
    _started = true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final progress = Curves.easeOutCubic.transform(_controller.value);
          return Transform.translate(
            offset: Offset(0, 8 * (1 - progress)),
            transformHitTests: false,
            child: Opacity(
              key: const ValueKey('calendar-day-content-opacity'),
              opacity: progress,
              child: child,
            ),
          );
        },
        child: widget.child,
      );
}

/// Retargets the visible decoration, and settles it immediately when the tab,
/// parent ticker or accessibility setting blocks motion.
class _CalendarSelectionDecoration extends StatefulWidget {
  const _CalendarSelectionDecoration({
    required this.animate,
    required this.decoration,
    required this.child,
    this.constraints,
    this.padding,
  });

  final bool animate;
  final BoxDecoration decoration;
  final Widget child;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;

  @override
  State<_CalendarSelectionDecoration> createState() =>
      _CalendarSelectionDecorationState();
}

class _CalendarSelectionDecorationState
    extends State<_CalendarSelectionDecoration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late DecorationTween _decoration;

  bool get _allowed =>
      widget.animate &&
      TickerMode.valuesOf(context).enabled &&
      !MediaQuery.disableAnimationsOf(context);

  Decoration? get _visibleDecoration =>
      _decoration.transform(Curves.easeOutCubic.transform(_controller.value));

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
      value: 1,
    );
    _decoration =
        DecorationTween(begin: widget.decoration, end: widget.decoration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _finishIfBlocked();
  }

  @override
  void didUpdateWidget(covariant _CalendarSelectionDecoration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_allowed) {
      _finishIfBlocked();
    } else if (oldWidget.decoration != widget.decoration) {
      _decoration =
          DecorationTween(begin: _visibleDecoration, end: widget.decoration);
      _controller.forward(from: 0);
    }
  }

  void _finishIfBlocked() {
    if (_allowed) return;
    _controller.stop();
    _decoration =
        DecorationTween(begin: widget.decoration, end: widget.decoration);
    _controller.value = 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Container(
          constraints: widget.constraints,
          padding: widget.padding,
          decoration: _visibleDecoration,
          child: child,
        ),
        child: widget.child,
      );
}

class _CalendarPeriodSize extends StatelessWidget {
  const _CalendarPeriodSize({required this.animate, required this.child});

  final bool animate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = _calendarMotionDuration(context, animate, 220);
    // Bypass resizing entirely when disabled. A zero-duration AnimatedSize can
    // mutate its own render object during layout when the grid changes height.
    if (duration == Duration.zero) {
      return KeyedSubtree(
          key: const ValueKey('calendar-period-size'), child: child);
    }
    return AnimatedSize(
      key: const ValueKey('calendar-period-size'),
      duration: duration,
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}

class _MonthNavButton extends StatelessWidget {
  const _MonthNavButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.animate,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      onTap: onTap,
      child: PostDeePressFeedback(
        enabled: animate,
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
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.animate,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return Semantics(
        label: label,
        button: true,
        selected: selected,
        onTap: onTap,
        child: PostDeePressFeedback(
            enabled: animate,
            child: ExcludeSemantics(
                child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(999),
              child: _CalendarSelectionDecoration(
                animate: animate,
                constraints: const BoxConstraints(minHeight: 48),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? AppTheme.accent : AppTheme.glass,
                  borderRadius: BorderRadius.circular(999),
                  border: selected ? null : Border.all(color: AppTheme.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? Colors.white : AppTheme.textSecondary,
                    ),
                  ),
                ]),
              ),
            ))));
  }
}

class _PlatformFilterButton extends StatelessWidget {
  const _PlatformFilterButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.animate,
    this.platform,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool animate;
  final SocialPlatform? platform;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: platform?.label ?? label,
      button: true,
      selected: selected,
      onTap: onTap,
      child: PostDeePressFeedback(
        enabled: animate,
        child: ExcludeSemantics(
            child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: _CalendarSelectionDecoration(
            animate: animate,
            constraints: const BoxConstraints(minHeight: 58),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
            decoration: BoxDecoration(
                color: selected
                    ? AppTheme.accent.withValues(alpha: 0.12)
                    : AppTheme.glass,
                border: Border.all(
                    color: selected
                        ? AppTheme.accent.withValues(alpha: 0.4)
                        : AppTheme.border),
                borderRadius: BorderRadius.circular(11)),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (platform != null)
                    SocialPlatformLogo(platform: platform!, size: 16)
                  else
                    Icon(Icons.layers_outlined,
                        size: 16,
                        color: selected
                            ? AppTheme.accentCyanInk
                            : AppTheme.textMuted),
                  const SizedBox(height: 4),
                  Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11,
                          color: selected
                              ? AppTheme.accentCyanInk
                              : AppTheme.textSecondary,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500)),
                ]),
          ),
        )),
      ),
    );
  }
}

class _DayPostRow extends StatelessWidget {
  const _DayPostRow({
    required this.post,
    required this.coverPreviews,
    required this.displayAt,
    required this.onTap,
    required this.busyLabel,
    required this.animate,
  });

  final CalendarPostResult post;
  final CalendarCoverPreviewCache coverPreviews;
  final DateTime displayAt;
  final VoidCallback? onTap;
  final String? busyLabel;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final platforms = post.platforms
        .toSet()
        .map(_platformFor)
        .whereType<SocialPlatform>()
        .toList();
    final status = busyLabel ?? _statusLabel(post);
    final sending =
        post.status.toUpperCase() == 'PUBLISHING' && status == 'กำลังส่ง';
    final channelSummary = sending
        ? post.platforms.toSet().map((value) {
            final result = post.platformResults
                .where((result) => result.platform == value)
                .firstOrNull;
            return '${_platformFor(value)?.shortLabel ?? value} ${postPlatformDeliveryLabel(result)}';
          }).join(', ')
        : platforms.map((platform) => platform.shortLabel).join(', ');
    final failed = post.status.toUpperCase() == 'FAILED';
    final needsReview = post.status.toUpperCase() == 'PARTIAL_PUBLISHED' ||
        hasUnconfirmedDeliveryOutcome(post.platformResults);
    final color = failed
        ? Theme.of(context).colorScheme.error
        : needsReview
            ? AppTheme.accentPinkInk
            : AppTheme.accentCyanInk;
    return PostDeePublishingMotion(
      sending: sending,
      animate: animate,
      child: Semantics(
        key: ValueKey('calendar-post-${post.id}'),
        button: onTap != null,
        onTap: onTap,
        label:
            '${_formatTime(displayAt)} ${post.caption} $status $channelSummary',
        child: PostDeePressFeedback(
          enabled: animate && onTap != null,
          child: ExcludeSemantics(
              child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(13),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
              decoration: BoxDecoration(
                color: AppTheme.glass,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: AppTheme.border),
              ),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _CalendarPostCover(post: post, previews: coverPreviews),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(_formatTime(displayAt),
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary)),
                      const SizedBox(height: 4),
                      Text(post.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary)),
                      const SizedBox(height: 6),
                      if (sending)
                        PostDeePublishingBadge(
                          label: status,
                          background: color.withValues(alpha: .09),
                          foreground: color,
                          sending: true,
                        )
                      else
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.09),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(status,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: color))),
                      if (sending) ...[
                        const SizedBox(height: 10),
                        KeyedSubtree(
                          key: ValueKey('calendar-publishing-rail-${post.id}'),
                          child: PostDeePublishingRail(color: color),
                        ),
                        const SizedBox(height: 10),
                        KeyedSubtree(
                          key: ValueKey('calendar-channels-${post.id}'),
                          child: PostDeePlatformDeliveryRow(
                            platforms: post.platforms,
                            results: post.platformResults,
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 7),
                        Wrap(
                            key: ValueKey('calendar-channels-${post.id}'),
                            spacing: 8,
                            runSpacing: 5,
                            children: [
                              for (final platform in platforms)
                                Row(mainAxisSize: MainAxisSize.min, children: [
                                  SocialPlatformLogo(
                                      platform: platform, size: 15),
                                  const SizedBox(width: 4),
                                  Flexible(
                                      child: Text(platform.shortLabel,
                                          style: TextStyle(
                                              fontSize: 10.5,
                                              color: AppTheme.textMuted))),
                                ]),
                              for (final value in post.platforms.toSet().where(
                                  (value) => _platformFor(value) == null))
                                Text(value,
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        color: AppTheme.textMuted)),
                            ]),
                      ],
                    ])),
                if (busyLabel != null)
                  const SizedBox(
                      key: ValueKey('calendar-post-action-progress'),
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5))
                else if (onTap != null)
                  Icon(Icons.chevron_right,
                      size: 18, color: AppTheme.textMuted),
              ]),
            ),
          )),
        ),
      ),
    );
  }
}

class _CalendarPostCover extends StatelessWidget {
  const _CalendarPostCover({required this.post, required this.previews});

  final CalendarPostResult post;
  final CalendarCoverPreviewCache previews;

  @override
  Widget build(BuildContext context) => ClipRRect(
        key: ValueKey('calendar-post-cover-${post.id}'),
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 48,
          height: 48 * 16 / 9,
          child: FutureBuilder<CalendarCoverPreview?>(
            key: ValueKey((
              previews,
              post.id,
              post.coverImageS3Key,
              post.videoS3Key,
              post.coverFrameTimeMs
            )),
            future: previews.load(post),
            builder: (context, snapshot) {
              final preview = snapshot.data;
              final frameBytes = preview?.frameBytes;
              if (frameBytes != null) {
                return Image.memory(
                  frameBytes,
                  key: ValueKey('calendar-post-cover-image-${post.id}'),
                  fit: BoxFit.cover,
                  cacheWidth: 144,
                  excludeFromSemantics: true,
                  errorBuilder: (context, error, stackTrace) => _placeholder(),
                );
              }
              final cover = preview?.imageUrl;
              if (cover == null) return _placeholder();
              return Image.network(
                cover.toString(),
                key: ValueKey('calendar-post-cover-image-${post.id}'),
                fit: BoxFit.cover,
                cacheWidth: 144,
                excludeFromSemantics: true,
                frameBuilder: (context, child, frame, synchronouslyLoaded) =>
                    synchronouslyLoaded || frame != null
                        ? child
                        : _placeholder(),
                errorBuilder: (context, error, stackTrace) => _placeholder(),
              );
            },
          ),
        ),
      );

  Widget _placeholder() => ColoredBox(
        key: ValueKey('calendar-post-cover-placeholder-${post.id}'),
        color: AppTheme.mint,
        child: Icon(Icons.video_library_outlined,
            size: 23, color: AppTheme.textMuted),
      );
}

class _EmptyDayCard extends StatelessWidget {
  const _EmptyDayCard({
    super.key,
    required this.onTap,
    required this.title,
    required this.actionLabel,
    required this.animate,
  });

  final VoidCallback? onTap;
  final String title;
  final String actionLabel;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter:
          _DashedRRectBorderPainter(color: AppTheme.border, radius: 15),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: AppTheme.glass, borderRadius: BorderRadius.circular(15)),
        child: Column(children: [
          Icon(Icons.event_available_outlined,
              size: 26, color: AppTheme.textMuted),
          const SizedBox(height: 8),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary)),
          if (onTap != null) ...[
            const SizedBox(height: 4),
            PostDeePressFeedback(
              enabled: animate,
              child: TextButton(
                  onPressed: onTap,
                  style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: AppTheme.accentCyanInk),
                  child: Text(actionLabel)),
            ),
          ],
        ]),
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

Duration _calendarMotionDuration(
        BuildContext context, bool enabled, int milliseconds) =>
    enabled &&
            TickerMode.valuesOf(context).enabled &&
            !MediaQuery.disableAnimationsOf(context)
        ? Duration(milliseconds: milliseconds)
        : Duration.zero;

bool _isSameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

bool _canEditQueue(CalendarPostResult post) =>
    post.scheduledAt != null && post.status.toUpperCase() == 'QUEUED';

bool _canOpenPostDetail(CalendarPostResult post) {
  final status = post.status.toUpperCase();
  return status == 'PUBLISHED' ||
      status == 'PARTIAL_PUBLISHED' ||
      status == 'FAILED';
}

bool _needsStatusRefresh(CalendarPostResult post) {
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

String _statusLabel(CalendarPostResult post) {
  if (post.status.toUpperCase() == 'PUBLISHING') {
    return hasUnconfirmedDeliveryOutcome(post.platformResults)
        ? 'ผลยังไม่ยืนยัน'
        : 'กำลังส่ง';
  }
  final deliveryLabel = aggregatePostDeliveryOutcomeLabel(
    post.platformResults,
    compact: true,
  );
  if (deliveryLabel != null) return deliveryLabel;

  switch (post.status.toUpperCase()) {
    case 'QUEUED':
      return post.scheduledAt == null ? 'รอส่ง' : 'รอส่งตามเวลา';
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
