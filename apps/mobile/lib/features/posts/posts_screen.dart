import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../shared/post_delivery_outcome.dart';
import '../shared/postdee_notice.dart';
import 'post_detail_screen.dart';

typedef PostsLoader = Future<List<PostSummaryResult>> Function();

/// Lists every owned server post, including post-now items absent from Calendar.
class PostsScreen extends StatefulWidget {
  const PostsScreen({super.key, this.loadPosts});
  final PostsLoader? loadPosts;

  @override
  State<PostsScreen> createState() => _PostsScreenState();
}

class _PostsScreenState extends State<PostsScreen> {
  final _apiClient = PostDeeApiClient();
  final _sessions = PostDeeAuthSessionStore.instance;
  List<PostSummaryResult> _posts = const [];
  bool _loading = true;
  String? _error;
  late String? _owner;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _owner = _sessions.session.stableUserId;
    _sessions.addListener(_ownerChanged);
    _load();
  }

  void _ownerChanged() {
    if (_owner == _sessions.session.stableUserId) return;
    _owner = _sessions.session.stableUserId;
    _generation++;
    setState(() {
      _posts = const [];
      _loading = false;
      _error = 'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดรายการโพสต์ใหม่';
    });
  }

  @override
  void dispose() {
    _sessions.removeListener(_ownerChanged);
    super.dispose();
  }

  Future<void> _load() async {
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
      if (mounted && generation == _generation) {
        setState(() => _error = 'โหลดรายการโพสต์ไม่สำเร็จ กรุณาลองใหม่');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(PostSummaryResult post) async {
    final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)));
    if (changed == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('โพสต์ทั้งหมด')),
        body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  PostDeeNotice(
                      icon: Icons.cloud_off,
                      message: _error!,
                      color: Theme.of(context).colorScheme.error,
                      actionLabel: 'ลองใหม่',
                      onAction: _load),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_posts.isEmpty && _error == null)
                  const PostDeeNotice(
                      icon: Icons.video_library_outlined,
                      message: 'ยังไม่มีโพสต์',
                      color: AppTheme.accent)
                else
                  for (final post in _posts)
                    Card(
                        child: ListTile(
                      key: ValueKey('all-post-${post.id}'),
                      onTap: () => _open(post),
                      leading: Icon(post.status == 'FAILED'
                          ? Icons.error_outline
                          : Icons.video_library_outlined),
                      title: Text(
                          post.caption.isEmpty ? 'โพสต์วิดีโอ' : post.caption,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(_statusLabel(post)),
                      trailing: const Icon(Icons.chevron_right),
                    )),
              ],
            )),
      );
}

String _statusLabel(PostSummaryResult post) =>
    aggregatePostDeliveryOutcomeLabel(post.platformResults, compact: true) ??
    switch (post.status) {
      'PUBLISHED' => 'ส่งสำเร็จ',
      'PARTIAL_PUBLISHED' => 'ส่งสำเร็จบางช่องทาง',
      'FAILED' => 'ส่งไม่สำเร็จ',
      'PUBLISHING' => 'กำลังส่ง',
      'QUEUED' when post.scheduledAt != null => 'รอส่งตามเวลา',
      _ => 'รอส่ง',
    };

/// Resolves notification IDs through the authenticated user's post list.
class PostDetailLoaderScreen extends StatefulWidget {
  const PostDetailLoaderScreen(
      {super.key, required this.postId, this.loadPosts, this.apiClient});
  final String postId;
  final PostsLoader? loadPosts;
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
    final generation = ++_generation;
    setState(() => _loading = true);
    try {
      final posts = await (widget.loadPosts?.call() ??
          (widget.apiClient ?? PostDeeApiClient()).listRecentPosts(limit: 0));
      if (!mounted ||
          generation != _generation ||
          _owner != _sessions.session.stableUserId) {
        return;
      }
      setState(() =>
          _post = posts.where((post) => post.id == widget.postId).firstOrNull);
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _post = null);
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
      return PostDetailScreen(post: post, apiClient: widget.apiClient);
    }
    return Scaffold(
        appBar: AppBar(title: const Text('รายละเอียดโพสต์')),
        body: Center(
            child: _loading
                ? const CircularProgressIndicator()
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: PostDeeNotice(
                        key: const ValueKey('post-detail-unavailable'),
                        icon: Icons.info_outline,
                        message:
                            'ไม่พบโพสต์นี้ในบัญชีที่ใช้งาน หรือโหลดไม่สำเร็จ',
                        color: AppTheme.accent,
                        actionLabel: 'ลองใหม่',
                        onAction: _owner == _sessions.session.stableUserId
                            ? _load
                            : null))));
  }
}
