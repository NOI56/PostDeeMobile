import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../platforms/connections_screen.dart' show connectablePlatforms;
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';
import '../shared/postdee_press_feedback.dart';
import '../shared/postdee_skeleton.dart';
import '../uploader/publish_draft.dart';
import '../uploader/publish_draft_store_factory.dart';
import 'home_draft_thumbnail.dart';

typedef HomeDraftsLoader = Future<List<PublishDraft>> Function();
typedef HomeConnectionsLoader = Future<List<SocialConnectionResult>> Function();
typedef HomeUpcomingPostsLoader = Future<List<PostSummaryResult>> Function();

/// The next useful action and a small preview of the seller's own pending work.
/// Saved drafts are device-local; a connected account is not a readiness check.
class HomeActivitySection extends StatefulWidget {
  const HomeActivitySection({
    super.key,
    this.isActive = true,
    this.refreshToken = 0,
    this.hasPosts,
    this.loadDrafts,
    this.loadConnections,
    this.loadScheduledPosts,
    required this.onCreatePost,
    required this.onResumeDraft,
    this.onOpenConnections,
    this.onOpenCalendar,
    this.now,
    this.createDraftThumbnailController,
  });

  final bool isActive;
  final int refreshToken;
  final bool? hasPosts;
  final HomeDraftsLoader? loadDrafts;
  final HomeConnectionsLoader? loadConnections;
  final HomeUpcomingPostsLoader? loadScheduledPosts;
  final Future<void> Function() onCreatePost;
  final Future<void> Function(PublishDraft draft) onResumeDraft;
  final VoidCallback? onOpenConnections;
  final VoidCallback? onOpenCalendar;
  final DateTime Function()? now;
  final HomeDraftThumbnailControllerFactory? createDraftThumbnailController;

  @override
  State<HomeActivitySection> createState() => HomeActivitySectionState();
}

class HomeActivitySectionState extends State<HomeActivitySection>
    with WidgetsBindingObserver {
  final _apiClient = PostDeeApiClient();
  String? _ownerUserId;
  var _ownerGeneration = 0;
  var _draftGeneration = 0;
  var _connectionsGeneration = 0;
  var _upcomingGeneration = 0;
  bool _loadingDrafts = true;
  bool _loadingConnections = true;
  bool _loadingUpcoming = true;
  bool _draftError = false;
  bool _connectionsError = false;
  bool _upcomingError = false;
  bool _openingComposer = false;
  bool _hasLoadedDrafts = false;
  bool _hasLoadedConnections = false;
  bool _hasLoadedUpcoming = false;
  Future<bool>? _activeRefresh;
  PublishDraft? _latestDraft;
  String? _draftCoverPath;
  List<SocialPlatform> _connectedPlatforms = const [];
  List<PostSummaryResult> _scheduledPosts = const [];

  String? get _currentOwner {
    final session = PostDeeAuthSessionStore.instance.session;
    return session.isSignedIn ? session.stableUserId : null;
  }

  @override
  void initState() {
    super.initState();
    _ownerUserId = _currentOwner;
    WidgetsBinding.instance.addObserver(this);
    PostDeeAuthSessionStore.instance.addListener(_handleOwnerChanged);
    if (widget.isActive) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PostDeeAuthSessionStore.instance.removeListener(_handleOwnerChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HomeActivitySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive &&
        (!oldWidget.isActive ||
            widget.refreshToken != oldWidget.refreshToken ||
            widget.loadDrafts != oldWidget.loadDrafts ||
            widget.loadConnections != oldWidget.loadConnections ||
            widget.loadScheduledPosts != oldWidget.loadScheduledPosts)) {
      _refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.isActive &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      _refresh();
    }
  }

  void _handleOwnerChanged() {
    final owner = _currentOwner;
    if (!mounted || owner == _ownerUserId) return;
    _ownerGeneration++;
    _activeRefresh = null;
    setState(() {
      _ownerUserId = owner;
      _latestDraft = null;
      _draftCoverPath = null;
      _connectedPlatforms = const [];
      _scheduledPosts = const [];
      _draftError = false;
      _connectionsError = false;
      _upcomingError = false;
      _loadingDrafts = true;
      _loadingConnections = true;
      _loadingUpcoming = true;
      _openingComposer = false;
      _hasLoadedDrafts = false;
      _hasLoadedConnections = false;
      _hasLoadedUpcoming = false;
    });
    if (widget.isActive) _refresh();
  }

  bool _stillOwned(String owner, int generation) =>
      mounted &&
      owner == _currentOwner &&
      owner == _ownerUserId &&
      generation == _ownerGeneration;

  void _refresh() {
    unawaited(refresh());
  }

  /// Completes after every source responds. Calls for the same owner share the
  /// in-flight future; switching accounts immediately starts a separate load.
  Future<bool> refresh({bool preserveContent = true}) {
    final owner = _ownerUserId;
    if (!mounted ||
        !widget.isActive ||
        owner == null ||
        owner != _currentOwner) {
      return Future.value(false);
    }
    final active = _activeRefresh;
    if (active != null) return active;
    final completion = Completer<bool>();
    _activeRefresh = completion.future;
    unawaited(
        _completeRefresh(owner, _ownerGeneration, preserveContent, completion));
    return completion.future;
  }

  Future<void> _completeRefresh(String owner, int ownerGeneration,
      bool preserveContent, Completer<bool> completion) async {
    try {
      final results = await Future.wait([
        _loadDrafts(preserveContent: preserveContent),
        _loadConnections(preserveContent: preserveContent),
        _loadUpcoming(preserveContent: preserveContent),
      ]);
      completion.complete(_stillOwned(owner, ownerGeneration) &&
          results.every((success) => success));
    } catch (_) {
      completion.complete(false);
    } finally {
      if (identical(_activeRefresh, completion.future)) _activeRefresh = null;
    }
  }

  Future<bool> _loadDrafts({bool preserveContent = true}) async {
    final owner = _ownerUserId;
    if (owner == null) return false;
    final ownerGeneration = _ownerGeneration;
    final generation = ++_draftGeneration;
    setState(() {
      _loadingDrafts = true;
      _draftError = false;
      if (!preserveContent) {
        _latestDraft = null;
        _draftCoverPath = null;
        _hasLoadedDrafts = false;
      }
    });
    try {
      final loader = widget.loadDrafts;
      final List<PublishDraft> drafts;
      if (loader != null) {
        drafts = await loader();
      } else {
        final store = await createPublishDraftStoreForSession();
        if (!_stillOwned(owner, ownerGeneration) ||
            generation != _draftGeneration) {
          return false;
        }
        if (store == null) {
          throw StateError('Draft store is unavailable.');
        }
        drafts = await store.listDrafts();
      }
      if (!_stillOwned(owner, ownerGeneration) ||
          generation != _draftGeneration) {
        return false;
      }
      final ownedDrafts = drafts
          .where((draft) => draft.ownerUserId == owner)
          .toList()
        ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      final latest = ownedDrafts.isEmpty ? null : ownedDrafts.first;
      final coverPath = await _readableCoverPath(latest);
      if (!_stillOwned(owner, ownerGeneration) ||
          generation != _draftGeneration) {
        return false;
      }
      setState(() {
        _latestDraft = latest;
        _draftCoverPath = coverPath;
        _loadingDrafts = false;
        _hasLoadedDrafts = true;
      });
      return true;
    } catch (_) {
      if (!_stillOwned(owner, ownerGeneration) ||
          generation != _draftGeneration) {
        return false;
      }
      setState(() {
        _draftError = true;
        _loadingDrafts = false;
      });
      return false;
    }
  }

  Future<String?> _readableCoverPath(PublishDraft? draft) async {
    final path = draft?.cover?.imagePath;
    if (path == null || path.isEmpty) return null;
    RandomAccessFile? image;
    try {
      image = await File(path).open(mode: FileMode.read);
      return path;
    } catch (_) {
      return null;
    } finally {
      await image?.close();
    }
  }

  Future<bool> _loadConnections({bool preserveContent = true}) async {
    final owner = _ownerUserId;
    if (owner == null) return false;
    final ownerGeneration = _ownerGeneration;
    final generation = ++_connectionsGeneration;
    setState(() {
      _loadingConnections = true;
      _connectionsError = false;
      if (!preserveContent) {
        _connectedPlatforms = const [];
        _hasLoadedConnections = false;
      }
    });
    try {
      final results =
          await (widget.loadConnections ?? _apiClient.listSocialConnections)();
      if (!_stillOwned(owner, ownerGeneration) ||
          generation != _connectionsGeneration) {
        return false;
      }
      final connected = results
          .where((result) => result.connected)
          .map((result) => result.platform)
          .toSet();
      setState(() {
        _connectedPlatforms = connectablePlatforms
            .where((platform) => connected.contains(platform.apiValue))
            .toList();
        _loadingConnections = false;
        _hasLoadedConnections = true;
      });
      return true;
    } catch (_) {
      if (!_stillOwned(owner, ownerGeneration) ||
          generation != _connectionsGeneration) {
        return false;
      }
      setState(() {
        _connectionsError = true;
        _loadingConnections = false;
      });
      return false;
    }
  }

  Future<bool> _loadUpcoming({bool preserveContent = true}) async {
    final owner = _ownerUserId;
    if (owner == null) return false;
    final ownerGeneration = _ownerGeneration;
    final generation = ++_upcomingGeneration;
    setState(() {
      _loadingUpcoming = true;
      _upcomingError = false;
      if (!preserveContent) {
        _scheduledPosts = const [];
        _hasLoadedUpcoming = false;
      }
    });
    try {
      final loader = widget.loadScheduledPosts;
      final List<PostSummaryResult> posts;
      if (loader != null) {
        posts = await loader();
      } else {
        final scheduled = await _apiClient.listScheduledPosts();
        posts = scheduled
            .where((post) => post.userId == null || post.userId == owner)
            .map((post) => PostSummaryResult(
                  id: post.id,
                  caption: post.caption,
                  videoS3Key: post.videoS3Key,
                  platforms: post.platforms,
                  status: post.status,
                  createdAt: post.createdAt,
                  scheduledAt: post.scheduledAt,
                  publishedAt: post.publishedAt,
                  platformResults: post.platformResults,
                ))
            .toList();
      }
      if (!_stillOwned(owner, ownerGeneration) ||
          generation != _upcomingGeneration) {
        return false;
      }
      setState(() {
        _scheduledPosts = posts;
        _loadingUpcoming = false;
        _hasLoadedUpcoming = true;
      });
      return true;
    } catch (_) {
      if (!_stillOwned(owner, ownerGeneration) ||
          generation != _upcomingGeneration) {
        return false;
      }
      setState(() {
        _upcomingError = true;
        _loadingUpcoming = false;
      });
      return false;
    }
  }

  PostSummaryResult? get _upcomingPost {
    final now = (widget.now ?? DateTime.now)();
    final upcoming = _scheduledPosts
        .where((post) =>
            post.status.toUpperCase() == 'QUEUED' &&
            post.scheduledAt != null &&
            post.scheduledAt!.isAfter(now))
        .toList()
      ..sort((left, right) => left.scheduledAt!.compareTo(right.scheduledAt!));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  Future<void> _openComposer({PublishDraft? draft}) async {
    final owner = _ownerUserId;
    if (_openingComposer || owner == null || owner != _currentOwner) return;
    if (draft != null && draft.ownerUserId != owner) return;
    final ownerGeneration = _ownerGeneration;
    setState(() => _openingComposer = true);
    try {
      if (draft == null) {
        await widget.onCreatePost();
      } else {
        await widget.onResumeDraft(draft);
      }
    } catch (_) {
      if (mounted && _stillOwned(owner, ownerGeneration)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
          _text('เปิดหน้าโพสต์ไม่สำเร็จ กรุณาลองใหม่',
              'Could not open the post. Please retry.'),
        )));
      }
    } finally {
      if (_stillOwned(owner, ownerGeneration)) {
        setState(() => _openingComposer = false);
        _refresh();
      }
    }
  }

  String _text(String thai, String english) =>
      Localizations.localeOf(context).languageCode == 'th' ? thai : english;

  Widget _card({required Widget child, bool mint = false}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: mint ? AppTheme.mint : AppTheme.glass,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(
              color: mint
                  ? AppTheme.accent.withValues(alpha: 0.2)
                  : AppTheme.border),
        ),
        child: child,
      );

  Widget _loading(String label) => Semantics(
        label: label,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 10),
          PostDeeSkeleton(height: 14, animate: widget.isActive),
          const SizedBox(height: 7),
          Align(
              alignment: Alignment.centerLeft,
              child: PostDeeSkeleton(
                  width: 116, height: 10, animate: widget.isActive)),
        ]),
      );

  Widget _retry(String message, String key, VoidCallback onRetry) =>
      Row(children: [
        Expanded(
            child:
                Text(message, style: TextStyle(color: AppTheme.textSecondary))),
        const SizedBox(width: 8),
        TextButton(
            key: ValueKey(key),
            onPressed: onRetry,
            child: Text(_text('ลองใหม่', 'Retry'))),
      ]);

  Widget _buildHero() {
    if (_loadingDrafts && !_hasLoadedDrafts) {
      return _card(
          mint: true,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _loading(_text('กำลังตรวจสอบร่าง...', 'Checking saved drafts...')),
            const SizedBox(height: 12),
            PostDeeSkeleton(height: 144, radius: 12, animate: widget.isActive),
            const SizedBox(height: 12),
            _createNewPostButton(),
          ]));
    }
    if (_draftError && !_hasLoadedDrafts) {
      return _card(
          mint: true,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _retry(_text('ตรวจสอบร่างไม่ได้', 'Could not check saved drafts'),
                'home-retry-drafts', () => unawaited(_loadDrafts())),
            const SizedBox(height: 8),
            _createNewPostButton(),
          ]));
    }
    final draft = _latestDraft;
    final firstPost = widget.hasPosts == false;
    final title = draft != null
        ? _text('ทำโพสต์ต่อ', 'Continue your post')
        : firstPost
            ? _text('เริ่มโพสต์แรกของคุณ', 'Create your first post')
            : _text('สร้างโพสต์ใหม่', 'Create a new post');
    return _card(
        mint: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_draftError) ...[
              _retry(_text('ตรวจสอบร่างไม่ได้', 'Could not check saved drafts'),
                  'home-retry-drafts', () => unawaited(_loadDrafts())),
              const SizedBox(height: 8),
            ],
            if (draft == null) ...[
              const SizedBox(height: 14),
              Icon(Icons.upload_file_outlined,
                  color: AppTheme.accentCyanInk, size: 64),
              const SizedBox(height: 16),
            ],
            Text(title,
                textAlign: draft == null ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            if (draft != null)
              _savedDraftBody(draft)
            else ...[
              Text(
                  _text('เลือกคลิป แล้วโพสต์ได้หลายช่องทาง',
                      'Choose a clip and post to multiple channels'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppTheme.textSecondary)),
              const SizedBox(height: 17),
              _createNewPostButton(
                  label: firstPost
                      ? _text('สร้างโพสต์แรก', 'Create first post')
                      : _text('สร้างโพสต์ใหม่', 'Create a new post')),
              const SizedBox(height: 4),
            ],
          ],
        ));
  }

  ButtonStyle get _primaryButtonStyle => FilledButton.styleFrom(
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _createNewPostButton({String? label}) => PostDeePressFeedback(
      enabled: !_openingComposer,
      child: FilledButton(
        key: const ValueKey('home-create-post'),
        onPressed: _openingComposer ? null : () => unawaited(_openComposer()),
        style: _primaryButtonStyle,
        child: Text(label ?? _text('สร้างโพสต์ใหม่', 'Create a new post')),
      ));

  Widget _savedDraftBody(PublishDraft draft) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 120,
              child: HomeDraftThumbnail(
                key: ValueKey(
                    'home-draft-preview/$_ownerUserId/${draft.id}/${draft.videoPath}'),
                videoPath: draft.videoPath,
                coverPath: _draftCoverPath,
                isActive: widget.isActive,
                createController: widget.createDraftThumbnailController,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            draft.caption.trim().isEmpty
                ? draft.videoName
                : draft.caption.trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 8,
            runSpacing: 7,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(_text('ร่างที่บันทึกไว้', 'Saved draft on this device'),
                  style:
                      TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.glass,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  child: Text(
                      _text('ถัดไป: ${_nextDraftStep(draft)}',
                          'Next: ${_nextDraftStep(draft)}'),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accentCyanInk)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          LayoutBuilder(builder: (context, constraints) {
            final stack = constraints.maxWidth < 320 ||
                MediaQuery.textScalerOf(context).scale(14) > 18;
            final continueButton = PostDeePressFeedback(
              enabled: !_openingComposer,
              child: FilledButton(
                key: const ValueKey('home-resume-draft'),
                onPressed: _openingComposer
                    ? null
                    : () => unawaited(_openComposer(draft: draft)),
                style: _primaryButtonStyle,
                child: Text(_text('ทำต่อ', 'Continue')),
              ),
            );
            final newButton = PostDeePressFeedback(
              enabled: !_openingComposer,
              child: OutlinedButton(
                key: const ValueKey('home-create-post'),
                onPressed:
                    _openingComposer ? null : () => unawaited(_openComposer()),
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppTheme.glass,
                  minimumSize: const Size(0, 44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
                  side: BorderSide(
                      color: AppTheme.accent.withValues(alpha: 0.25)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(_text('สร้างโพสต์ใหม่', 'Create a new post'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textPrimary)),
              ),
            );
            if (stack) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    continueButton,
                    const SizedBox(height: 8),
                    newButton,
                  ]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: continueButton),
              const SizedBox(width: 10),
              Expanded(child: newButton),
            ]);
          }),
        ],
      );

  String _nextDraftStep(PublishDraft draft) {
    // Drafts persist fields, not a UI-step index. This is the next required
    // action inferred from those saved fields, not where the user last stopped.
    if (draft.caption.trim().isEmpty || draft.captionNeedsReview) {
      return _text('แคปชัน', 'Caption');
    }
    if (draft.platformApiValues.isEmpty) return _text('ช่องทาง', 'Channels');
    return _text('ตรวจทาน', 'Review');
  }

  Widget _buildConnections() {
    if (_loadingConnections && !_hasLoadedConnections) {
      return _card(
          child: _loading(
              _text('กำลังตรวจสอบช่องทาง...', 'Checking channels...')));
    }
    if (_connectionsError && !_hasLoadedConnections) {
      return _card(
          child: _retry(
              _text('ตรวจสอบช่องทางไม่ได้', 'Could not check channels'),
              'home-retry-connections',
              () => unawaited(_loadConnections())));
    }
    return _card(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_connectionsError) ...[
        _retry(_text('ตรวจสอบช่องทางไม่ได้', 'Could not check channels'),
            'home-retry-connections', () => unawaited(_loadConnections())),
        const SizedBox(height: 8),
      ],
      Row(children: [
        if (_connectedPlatforms.isEmpty)
          Icon(Icons.link_rounded, color: AppTheme.accentCyanInk, size: 23)
        else
          SizedBox(
              width: 48,
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final platform in _connectedPlatforms)
                  Semantics(
                      label: platform.label,
                      child: SocialPlatformLogo(platform: platform, size: 20)),
              ])),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              _text(
                  'เชื่อมแล้ว ${_connectedPlatforms.length}/${connectablePlatforms.length} ช่องทาง',
                  '${_connectedPlatforms.length}/${connectablePlatforms.length} channels connected'),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary)),
          if (_connectedPlatforms.isEmpty) ...[
            const SizedBox(height: 5),
            Text(
                _text('เชื่อมบัญชีสำหรับโพสต์บนโซเชียล',
                    'Connect your accounts to publish'),
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          ],
        ])),
        const SizedBox(width: 4),
        PostDeePressFeedback(
            enabled: widget.onOpenConnections != null,
            child: TextButton(
                key: const ValueKey('home-manage-connections'),
                onPressed: widget.onOpenConnections,
                child: Text(_text('จัดการ', 'Manage')))),
      ])
    ]));
  }

  String _scheduleLabel(DateTime time) {
    final local = time.toLocal();
    final today = (widget.now ?? DateTime.now)().toLocal();
    final isToday = local.year == today.year &&
        local.month == today.month &&
        local.day == today.day;
    final date = isToday
        ? _text('วันนี้', 'Today')
        : '${local.day}/${local.month}/${local.year}';
    return '$date · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildUpcoming() {
    if (_loadingUpcoming && !_hasLoadedUpcoming) {
      return _card(
          child: _loading(
              _text('กำลังโหลดคิวโพสต์...', 'Loading scheduled posts...')));
    }
    if (_upcomingError && (!_hasLoadedUpcoming || _upcomingPost == null)) {
      return _card(
          child: _retry(
              _text('โหลดคิวโพสต์ไม่สำเร็จ', 'Could not load scheduled posts'),
              'home-retry-upcoming',
              () => unawaited(_loadUpcoming())));
    }
    final post = _upcomingPost;
    if (post == null) return const SizedBox.shrink();
    return _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_upcomingError) ...[
        _retry(_text('โหลดคิวโพสต์ไม่สำเร็จ', 'Could not load scheduled posts'),
            'home-retry-upcoming', () => unawaited(_loadUpcoming())),
        const SizedBox(height: 8),
      ],
      Row(children: [
        Icon(Icons.calendar_today_outlined,
            color: AppTheme.accentCyanInk, size: 21),
        const SizedBox(width: 9),
        Expanded(
            child: Text(_text('โพสต์ถัดไป', 'Next scheduled post'),
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary))),
        PostDeePressFeedback(
            enabled: widget.onOpenCalendar != null,
            child: TextButton(
                key: const ValueKey('home-open-calendar'),
                onPressed: widget.onOpenCalendar,
                child: Text(_text('ดูปฏิทิน', 'Calendar')))),
      ]),
      Text(_scheduleLabel(post.scheduledAt!),
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.accentCyanInk)),
      const SizedBox(height: 6),
      Text(
          post.caption.trim().isEmpty
              ? _text('โพสต์ของคุณ', 'Your post')
              : post.caption.trim(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary)),
      const SizedBox(height: 5),
      Text(
          post.platforms
              .map((value) =>
                  SocialPlatform.values
                      .where((platform) => platform.apiValue == value)
                      .firstOrNull
                      ?.label ??
                  value)
              .join(' · '),
          style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    if (_ownerUserId == null) {
      return _card(
          child: Text(
              _text('กรุณาเข้าสู่ระบบเพื่อตรวจสอบงานของคุณ',
                  'Sign in to check your work'),
              style: TextStyle(color: AppTheme.textSecondary)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AnimatedSwitcher(
        key: ValueKey('home-hero-owner-$_ownerGeneration'),
        duration: widget.isActive &&
                TickerMode.valuesOf(context).enabled &&
                !MediaQuery.disableAnimationsOf(context)
            ? const Duration(milliseconds: 180)
            : Duration.zero,
        child: KeyedSubtree(
          key: ValueKey(_hasLoadedDrafts
              ? 'loaded-${_latestDraft?.id ?? 'new'}'
              : _draftError
                  ? 'error'
                  : 'loading'),
          child: _buildHero(),
        ),
      ),
      const SizedBox(height: 12),
      _buildConnections(),
      if ((!_hasLoadedUpcoming && _loadingUpcoming) ||
          _upcomingError ||
          _upcomingPost != null) ...[
        const SizedBox(height: 12),
        _buildUpcoming(),
      ],
    ]);
  }
}
