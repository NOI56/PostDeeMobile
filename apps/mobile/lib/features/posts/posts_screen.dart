import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/localization/postdee_localizations.dart';
import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../platforms/social_platform.dart';
import '../shared/post_delivery_outcome.dart';
import '../shared/postdee_notice.dart';
import 'post_detail_screen.dart';

typedef PostsLoader = Future<List<PostSummaryResult>> Function();

enum _PostsLoadError { ownerChanged, loadFailed }

/// Searchable owned activity, including both immediate and scheduled posts.
class PostsScreen extends StatefulWidget {
  const PostsScreen({super.key, this.loadPosts, this.apiClient});
  final PostsLoader? loadPosts;
  final PostDeeApiClient? apiClient;

  @override
  State<PostsScreen> createState() => _PostsScreenState();
}

class _PostsScreenState extends State<PostsScreen> with WidgetsBindingObserver {
  late final _apiClient = widget.apiClient ?? PostDeeApiClient();
  final _sessions = PostDeeAuthSessionStore.instance;
  final _search = TextEditingController();
  List<PostSummaryResult> _posts = const [];
  bool _loading = true;
  _PostsLoadError? _error;
  late String? _owner;
  int _generation = 0;
  bool _ownerInvalidated = false;
  String _status = 'ALL';
  String _platform = 'ALL';
  String _dateRange = 'ALL';

  String get _languageCode =>
      Localizations.of<PostDeeLocalizations>(context, PostDeeLocalizations)
          ?.locale
          .languageCode ??
      'th';

  String _text(String thai, String english) =>
      _languageCode == 'th' ? thai : english;

  String? get _errorMessage => switch (_error) {
        _PostsLoadError.ownerChanged => _text(
            'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดรายการโพสต์ใหม่',
            'Your account has changed. Reopen All posts.'),
        _PostsLoadError.loadFailed => _text(
            'โหลดรายการโพสต์ไม่สำเร็จ กรุณาลองใหม่',
            'Could not load your posts. Please try again.'),
        null => null,
      };

  @override
  void initState() {
    super.initState();
    _owner = _sessions.session.stableUserId;
    _sessions.addListener(_ownerChanged);
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      unawaited(_load());
    }
  }

  void _ownerChanged() {
    if (_owner == _sessions.session.stableUserId) return;
    _owner = _sessions.session.stableUserId;
    _generation++;
    _ownerInvalidated = true;
    _search.clear();
    setState(() {
      _posts = const [];
      _loading = false;
      _error = _PostsLoadError.ownerChanged;
    });
  }

  @override
  void dispose() {
    _sessions.removeListener(_ownerChanged);
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_ownerInvalidated || !mounted) return;
    final generation = ++_generation;
    final owner = _sessions.session.stableUserId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final posts = await (widget.loadPosts?.call() ??
          _apiClient.listRecentPosts(limit: 0));
      if (!mounted ||
          generation != _generation ||
          owner != _sessions.session.stableUserId) {
        return;
      }
      setState(() => _posts = [...posts]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
    } catch (_) {
      if (mounted && !_ownerInvalidated && generation == _generation) {
        setState(() => _error = _PostsLoadError.loadFailed);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(PostSummaryResult post) async {
    final owner = _sessions.session.stableUserId;
    await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => PostDetailScreen(
              post: post,
              apiClient: _apiClient,
              refreshOnOpen: widget.loadPosts == null,
              loadPost: widget.loadPosts == null
                  ? null
                  : (id) async => (await widget.loadPosts!())
                      .where((post) => post.id == id)
                      .firstOrNull,
            )));
    if (mounted &&
        !_ownerInvalidated &&
        owner == _sessions.session.stableUserId) {
      await _load();
    }
  }

  List<PostSummaryResult> get _filteredPosts {
    final query = _search.text.trim().toLowerCase();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = switch (_dateRange) {
      'TODAY' => today,
      '7D' => today.subtract(const Duration(days: 6)),
      '30D' => today.subtract(const Duration(days: 29)),
      _ => null,
    };
    return _posts.where((post) {
      if (query.isNotEmpty &&
          !post.caption.toLowerCase().contains(query) &&
          !post.id.toLowerCase().contains(query)) {
        return false;
      }
      if (_platform != 'ALL' && !post.platforms.contains(_platform)) {
        return false;
      }
      final state = post.status.toUpperCase();
      if (_status == 'PENDING' && state != 'QUEUED' && state != 'PUBLISHING') {
        return false;
      }
      if (_status == 'UNCONFIRMED' &&
          !hasUnconfirmedDeliveryOutcome(post.platformResults)) {
        return false;
      }
      if (_status != 'ALL' &&
          _status != 'PENDING' &&
          _status != 'UNCONFIRMED' &&
          state != _status) {
        return false;
      }
      final created = post.createdAt.toLocal();
      if (start != null &&
          (created.isBefore(start) ||
              !created.isBefore(today.add(const Duration(days: 1))))) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  Widget _filters() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
            key: const ValueKey('posts-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: _text(
                  'ค้นหาแคปชั่นหรือรหัสโพสต์', 'Search caption or post ID'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: _text('ล้างคำค้นหา', 'Clear search'),
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      }),
            )),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, constraints) {
          final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.4;
          final fullWidth = constraints.maxWidth < 330 || largeText;
          final width = fullWidth
              ? constraints.maxWidth
              : (constraints.maxWidth - 12) / 2;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(
                width: width,
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('posts-status-filter'),
                  initialValue: _status,
                  isDense: !largeText,
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: _text('สถานะ', 'Status')),
                  items: {
                    'ALL': _text('ทุกสถานะ', 'All statuses'),
                    'PENDING': _text('รอส่ง / กำลังส่ง', 'Queued / Sending'),
                    'PUBLISHED': _text('ส่งสำเร็จ', 'Delivered'),
                    'PARTIAL_PUBLISHED':
                        _text('สำเร็จบางช่องทาง', 'Partially delivered'),
                    'FAILED': _text('ส่งไม่สำเร็จ', 'Failed'),
                    'UNCONFIRMED':
                        _text('ผลยังไม่ยืนยัน', 'Delivery unconfirmed')
                  }
                      .entries
                      .map((entry) => DropdownMenuItem(
                          value: entry.key, child: Text(entry.value)))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _status = value ?? 'ALL'),
                )),
            SizedBox(
                width: width,
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('posts-platform-filter'),
                  initialValue: _platform,
                  isDense: !largeText,
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: _text('ช่องทาง', 'Channel')),
                  items: [
                    DropdownMenuItem(
                        value: 'ALL',
                        child: Text(_text('ทุกช่องทาง', 'All channels'))),
                    for (final platform in const [
                      SocialPlatform.tiktok,
                      SocialPlatform.youtubeShorts,
                      SocialPlatform.instagramReels,
                      SocialPlatform.facebookReels
                    ])
                      DropdownMenuItem(
                          value: platform.apiValue, child: Text(platform.label))
                  ],
                  onChanged: (value) =>
                      setState(() => _platform = value ?? 'ALL'),
                )),
            SizedBox(
                width: width,
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('posts-date-filter'),
                  initialValue: _dateRange,
                  isDense: !largeText,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: _text('วันที่สร้าง', 'Created date')),
                  items: {
                    'ALL': _text('ทุกวัน', 'All dates'),
                    'TODAY': _text('วันนี้', 'Today'),
                    '7D': _text('7 วันล่าสุด', 'Last 7 days'),
                    '30D': _text('30 วันล่าสุด', 'Last 30 days')
                  }
                      .entries
                      .map((entry) => DropdownMenuItem(
                          value: entry.key, child: Text(entry.value)))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _dateRange = value ?? 'ALL'),
                )),
          ]);
        }),
        const SizedBox(height: 12),
      ]);

  @override
  Widget build(BuildContext context) {
    final visible = _filteredPosts;
    return Scaffold(
      appBar: AppBar(title: Text(_text('โพสต์ทั้งหมด', 'All posts'))),
      body: RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: _ownerInvalidated ? 1 : visible.length + 1,
            itemBuilder: (context, index) {
              if (index > 0) {
                final post = visible[index - 1];
                final platforms = post.platforms
                    .map((id) =>
                        SocialPlatform.values
                            .where((platform) => platform.apiValue == id)
                            .firstOrNull
                            ?.label ??
                        id)
                    .join(' · ');
                return Card(
                    child: ListTile(
                  key: ValueKey('all-post-${post.id}'),
                  onTap: () => _open(post),
                  leading: Icon(post.status == 'FAILED'
                      ? Icons.error_outline
                      : Icons.video_library_outlined),
                  title: Text(
                      post.caption.isEmpty
                          ? _text('โพสต์วิดีโอ', 'Video post')
                          : post.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_statusLabel(post, languageCode: _languageCode)),
                        Text(_postDateLabel(post.createdAt,
                            languageCode: _languageCode)),
                        Text(platforms,
                            style: TextStyle(color: AppTheme.textMuted)),
                      ]),
                  trailing: const Icon(Icons.chevron_right),
                ));
              }
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_ownerInvalidated) _filters(),
                    if (_error != null)
                      PostDeeNotice(
                          icon: Icons.cloud_off,
                          message: _errorMessage!,
                          color: Theme.of(context).colorScheme.error,
                          actionLabel: _text('ลองใหม่', 'Try again'),
                          onAction: _ownerInvalidated ? null : _load),
                    if (_loading && _posts.isEmpty)
                      Center(
                          child: MediaQuery.disableAnimationsOf(context)
                              ? const Icon(Icons.hourglass_empty)
                              : const CircularProgressIndicator())
                    else if (visible.isEmpty && _error == null)
                      PostDeeNotice(
                          icon: Icons.video_library_outlined,
                          message: _posts.isEmpty
                              ? _text('ยังไม่มีโพสต์', 'No posts yet')
                              : _text('ไม่พบโพสต์ที่ตรงกับตัวกรอง',
                                  'No posts match your filters'),
                          color: AppTheme.accent)
                    else if (!_ownerInvalidated)
                      Text(
                          _text('${visible.length} โพสต์',
                              '${visible.length} post${visible.length == 1 ? '' : 's'}'),
                          style: TextStyle(color: AppTheme.textMuted)),
                    const SizedBox(height: 8),
                  ]);
            },
          )),
    );
  }
}

String _postDateLabel(DateTime value, {String languageCode = 'th'}) {
  final local = value.toLocal();
  final months = languageCode == 'th'
      ? const [
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
          'ธ.ค.'
        ]
      : const [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec'
        ];
  return '${local.day} ${months[local.month - 1]} ${local.year} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String _statusLabel(PostSummaryResult post, {String languageCode = 'th'}) =>
    aggregatePostDeliveryOutcomeLabel(post.platformResults,
        compact: true, languageCode: languageCode) ??
    switch (post.status) {
      'PUBLISHED' => languageCode == 'th' ? 'ส่งสำเร็จ' : 'Delivered',
      'PARTIAL_PUBLISHED' =>
        languageCode == 'th' ? 'ส่งสำเร็จบางช่องทาง' : 'Partially delivered',
      'FAILED' => languageCode == 'th' ? 'ส่งไม่สำเร็จ' : 'Failed',
      'PUBLISHING' => languageCode == 'th' ? 'กำลังส่ง' : 'Sending',
      'QUEUED' when post.scheduledAt != null =>
        languageCode == 'th' ? 'รอส่งตามเวลา' : 'Scheduled',
      _ => languageCode == 'th' ? 'รอส่ง' : 'Queued',
    };

/// Resolves a notification directly through an authenticated owned-post read.
class PostDetailLoaderScreen extends StatefulWidget {
  const PostDetailLoaderScreen(
      {super.key,
      required this.postId,
      this.loadPosts,
      this.loadPost,
      this.apiClient});
  final String postId;
  final PostsLoader? loadPosts;
  final PostDetailReader? loadPost;
  final PostDeeApiClient? apiClient;

  @override
  State<PostDetailLoaderScreen> createState() => _PostDetailLoaderScreenState();
}

class _PostDetailLoaderScreenState extends State<PostDetailLoaderScreen> {
  final _sessions = PostDeeAuthSessionStore.instance;
  PostSummaryResult? _post;
  bool _loading = true;
  int _generation = 0;
  late String? _owner;
  bool _ownerInvalidated = false;
  bool _loadFailed = false;

  String get _languageCode =>
      Localizations.of<PostDeeLocalizations>(context, PostDeeLocalizations)
          ?.locale
          .languageCode ??
      'th';

  String _text(String thai, String english) =>
      _languageCode == 'th' ? thai : english;

  Future<PostSummaryResult?> _readPost(String id) async {
    if (widget.loadPost != null) return widget.loadPost!(id);
    if (widget.loadPosts != null) {
      return (await widget.loadPosts!())
          .where((post) => post.id == id)
          .firstOrNull;
    }
    return (widget.apiClient ?? PostDeeApiClient())
        .getPostById(id, includeMedia: true);
  }

  @override
  void initState() {
    super.initState();
    _owner = _sessions.session.stableUserId;
    _sessions.addListener(_ownerChanged);
    _load();
  }

  void _ownerChanged() {
    if (_owner == _sessions.session.stableUserId) return;
    _generation++;
    _ownerInvalidated = true;
    setState(() {
      _post = null;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _sessions.removeListener(_ownerChanged);
    super.dispose();
  }

  Future<void> _load() async {
    if (_ownerInvalidated) return;
    final generation = ++_generation;
    setState(() => _loading = true);
    try {
      final post = await _readPost(widget.postId);
      if (!mounted ||
          generation != _generation ||
          _owner != _sessions.session.stableUserId) {
        return;
      }
      if (post != null && post.id != widget.postId) {
        throw const ApiException('Post id mismatch');
      }
      setState(() {
        _post = post;
        _loadFailed = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _post = null;
          _loadFailed = true;
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    if (post != null) {
      return PostDetailScreen(
          post: post,
          apiClient: widget.apiClient,
          loadPost: widget.loadPost != null || widget.loadPosts != null
              ? _readPost
              : null,
          refreshOnOpen: false);
    }
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    final retry = !_ownerInvalidated && _owner == _sessions.session.stableUserId
        ? _load
        : null;
    return Scaffold(
        appBar: AppBar(title: Text(_text('รายละเอียดโพสต์', 'Post details'))),
        body: Center(
            child: _loading
                ? const CircularProgressIndicator()
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      PostDeeNotice(
                          key: const ValueKey('post-detail-unavailable'),
                          icon: Icons.info_outline,
                          message: _ownerInvalidated
                              ? _text(
                                  'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดรายละเอียดใหม่',
                                  'Your account has changed. Reopen Post details.')
                              : _loadFailed
                                  ? _text(
                                      'โหลดโพสต์ไม่สำเร็จ กรุณาลองใหม่เมื่อเชื่อมต่อได้',
                                      'Could not load this post. Please try again when connected.')
                                  : _text(
                                      'ไม่พบโพสต์นี้ในบัญชีที่ใช้งาน อาจถูกยกเลิกหรือถูกนำออก',
                                      'This post was not found in your account. It may have been canceled or removed.'),
                          color: AppTheme.accent,
                          actionLabel:
                              largeText ? null : _text('ลองใหม่', 'Try again'),
                          onAction: retry),
                      if (largeText && retry != null)
                        TextButton(
                            onPressed: retry,
                            child: Text(_text('ลองใหม่', 'Try again'))),
                    ]))));
  }
}
