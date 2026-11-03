import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../platforms/social_platform.dart';
import '../shared/postdee_card.dart';
import '../shared/postdee_notice.dart';
import '../shared/postdee_skeleton.dart';
import '../uploader/platform_caption_fields.dart';
import '../uploader/platform_publish_preflight.dart';
import '../uploader/platform_publish_settings.dart';
import 'post_caption_localizations.dart';

/// Only text is editable. The server owns the final schedule/status/version check.
class PostCaptionEditScreen extends StatefulWidget {
  const PostCaptionEditScreen(
      {super.key, required this.post, this.apiClient, this.now});

  final PostSummaryResult post;
  final PostDeeApiClient? apiClient;
  final DateTime Function()? now;

  @override
  State<PostCaptionEditScreen> createState() => _PostCaptionEditScreenState();
}

class _PostCaptionEditScreenState extends State<PostCaptionEditScreen> {
  late final _api = widget.apiClient ?? PostDeeApiClient();
  final _sessions = PostDeeAuthSessionStore.instance;
  late final String? _owner;
  late PostSummaryResult _post;
  final _shared = TextEditingController();
  final _title = TextEditingController();
  Map<SocialPlatform, String> _captions = {};
  bool _customTitle = false;
  bool _initialCustomTitle = false;
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;
  bool _ownerChanged = false;
  bool _allowPop = false;
  bool _confirmingDiscard = false;
  bool _validated = false;
  Object? _error;
  String? _lockedCode;
  Timer? _windowTimer;

  DateTime get _now => widget.now?.call() ?? DateTime.now();
  bool get _owned =>
      mounted && !_ownerChanged && _sessions.session.stableUserId == _owner;
  Set<SocialPlatform> get _platforms => captionPlatforms
      .where((p) => _post.platforms.contains(p.apiValue))
      .toSet();
  bool get _separate => _post.hasPlatformCaptions;
  bool get _youtube => _platforms.contains(SocialPlatform.youtubeShorts);
  String _text(String thai) => postCaptionText(context, thai);
  String _effective(SocialPlatform platform) =>
      (_separate ? _captions[platform] ?? _post.caption : _shared.text).trim();
  String get _youtubeTitle => _customTitle && _title.text.trim().isNotEmpty
      ? _title.text.trim()
      : safeYouTubeTitleSuggestion(_effective(SocialPlatform.youtubeShorts));
  bool get _dirty =>
      !_loading &&
      !_loadFailed &&
      (_shared.text != _post.caption ||
          _customTitle != _initialCustomTitle ||
          (_customTitle && _title.text != _savedTitle) ||
          (_separate &&
              _platforms.any(
                  (p) => _captions[p] != _post.effectiveCaption(p.apiValue))));
  String get _savedTitle {
    final settings = _post.platformSettings['YOUTUBE_SHORTS'];
    return settings is Map && settings['title'] is String
        ? settings['title'] as String
        : '';
  }

  String? get _blockedCode {
    if (_lockedCode != null) return _lockedCode;
    if (_post.status != 'QUEUED' || _post.scheduledAt == null) {
      return 'POST_NOT_EDITABLE';
    }
    if (_post.scheduledAt!.difference(_now) <= const Duration(seconds: 60)) {
      return 'POST_CAPTION_EDIT_WINDOW_CLOSED';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _owner = _sessions.session.stableUserId;
    _sessions.addListener(_sessionChanged);
    unawaited(_load());
  }

  void _sessionChanged() {
    if (!_ownerChanged && _sessions.session.stableUserId != _owner) {
      _windowTimer?.cancel();
      setState(() {
        _ownerChanged = true;
        _saving = false;
        _allowPop = true;
      });
    }
  }

  Future<void> _load() async {
    if (!_owned) return;
    setState(() {
      _loading = true;
      _loadFailed = false;
      _error = null;
    });
    try {
      final latest = await _api.getPostById(_post.id);
      if (!_owned) return;
      if (latest == null) {
        throw const ApiException('Post not found', code: 'POST_NOT_FOUND');
      }
      if (latest.id != widget.post.id) {
        throw const ApiException('Post mismatch');
      }
      setState(() {
        _post = latest;
        _shared.text = latest.caption;
        _captions = {
          for (final p in _platforms) p: latest.effectiveCaption(p.apiValue)
        };
        _title.text = _savedTitle;
        final savedTitle = _savedTitle.trim();
        // Persisted titles have no mode flag. Match the composer's suggestion.
        final automaticTitle = safeYouTubeTitleSuggestion(
            latest.effectiveCaption(SocialPlatform.youtubeShorts.apiValue));
        _customTitle = savedTitle.isNotEmpty && savedTitle != automaticTitle;
        _initialCustomTitle = _customTitle;
        _loading = false;
        _validated = false;
        _lockedCode = null;
      });
      _syncWindowTimer();
    } catch (error) {
      if (!_owned) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
        _error = error;
      });
    }
  }

  void _syncWindowTimer() {
    _windowTimer?.cancel();
    final schedule = _post.scheduledAt;
    if (schedule == null || _blockedCode != null || !_owned) return;
    final delay = schedule.difference(_now) - const Duration(seconds: 60);
    _windowTimer = Timer(delay, () {
      if (_owned) setState(() {});
    });
  }

  String? _captionError(SocialPlatform platform) {
    final caption = _effective(platform);
    if (caption.isEmpty &&
        !(platform == SocialPlatform.youtubeShorts &&
            _youtubeTitle.isNotEmpty)) {
      return _separate
          ? 'เพิ่มแคปชั่นสำหรับช่องทางนี้'
          : 'เพิ่มแคปชั่นก่อนโพสต์';
    }
    final settings = _post.platformSettings['TIKTOK'];
    if (platform == SocialPlatform.tiktok &&
        (settings is! Map || settings['publishMode'] != 'INBOX_DRAFT') &&
        caption.length > 2200) {
      return 'แคปชั่น TikTok ต้องไม่เกิน 2,200 ตัวอักษร';
    }
    return validatePlatformPublishPreflight(
            selectedPlatforms: {platform}, caption: caption)
        ?.message;
  }

  String? get _titleError {
    if (!_youtube) return null;
    final title = _youtubeTitle;
    if (title.isEmpty) return 'เพิ่มแคปชันหรือชื่อคลิป YouTube ก่อนโพสต์';
    if (title.runes.length > 100 ||
        title.contains('<') ||
        title.contains('>')) {
      return 'ชื่อ YouTube ต้องไม่เกิน 100 ตัวอักษร และห้ามมี < หรือ >';
    }
    return null;
  }

  String? get _validationError {
    for (final platform in _platforms) {
      final error = _captionError(platform);
      if (error != null) return error;
    }
    return _titleError;
  }

  Future<void> _save() async {
    if (!_owned || _saving || _loading || _loadFailed || _blockedCode != null) {
      return;
    }
    setState(() => _validated = true);
    if (_validationError != null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await _api.updatePostCaption(_post.id,
          caption: _separate ? _post.caption : _shared.text.trim(),
          platformCaptions: _separate
              ? {for (final p in _platforms) p.apiValue: _effective(p)}
              : null,
          youtubeTitle: _youtube ? _youtubeTitle : null,
          expectedUpdatedAt: _post.updatedAt);
      if (!_owned) return;
      setState(() {
        _allowPop = true;
        _saving = false;
      });
      // PopScope must receive canPop before returning the saved post.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_owned) Navigator.of(context).pop(updated);
      });
    } catch (error) {
      if (!_owned) return;
      setState(() {
        _saving = false;
        _error = error;
        if (error is ApiException &&
            const {
              'POST_NOT_EDITABLE',
              'POST_CAPTION_EDIT_WINDOW_CLOSED',
              'POST_CAPTION_CONFLICT',
              'POST_NOT_FOUND',
              'POST_CAPTION_EDIT_UNAVAILABLE'
            }.contains(error.code)) {
          _lockedCode = error.code;
        }
      });
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty || !_owned) return true;
    if (_confirmingDiscard) return false;
    _confirmingDiscard = true;
    try {
      return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                    title: Text(_text('ทิ้งการแก้ไข?')),
                    content: Text(_text('แคปชั่นที่แก้ไขยังไม่ได้บันทึก')),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(_text('แก้ไขต่อ'))),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(_text('ทิ้งการแก้ไข')))
                    ],
                  )) ??
          false;
    } finally {
      _confirmingDiscard = false;
    }
  }

  Future<void> _back() async {
    if (_saving) return;
    if (!await _confirmDiscard() || !mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _reload() async {
    if (await _confirmDiscard() && _owned) await _load();
  }

  @override
  void dispose() {
    _sessions.removeListener(_sessionChanged);
    _windowTimer?.cancel();
    _shared.dispose();
    _title.dispose();
    super.dispose();
  }

  Widget _notice(String message,
          {Key? key, String? action, VoidCallback? onAction}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PostDeeNotice(key: key, message: message),
        if (action != null)
          Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(onPressed: onAction, child: Text(action))),
      ]);

  @override
  Widget build(BuildContext context) {
    final blocked = _blockedCode;
    final readOnly = _saving || blocked != null;
    return PopScope<PostSummaryResult>(
        canPop: _allowPop || (!_dirty && !_saving),
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(_back());
        },
        child: Scaffold(
          appBar: AppBar(
              leading: BackButton(onPressed: _saving ? null : _back),
              title: Text(_text('แก้ไขแคปชั่น'))),
          body: DecoratedBox(
              decoration: AppTheme.screenBackground,
              child: SafeArea(
                  child: ListView(padding: AppTheme.screenPadding, children: [
                if (_ownerChanged)
                  _notice(_text(
                      'บัญชีเปลี่ยนแล้ว กรุณากลับไปเปิดโพสต์จากบัญชีปัจจุบัน'))
                else if (_loading) ...[
                  const PostDeeSkeleton(height: 24),
                  const SizedBox(height: AppTheme.spaceLg),
                  const PostDeeSkeleton(height: 180),
                ] else if (_loadFailed)
                  _notice(
                      _error is ApiException &&
                              (_error as ApiException).code == 'POST_NOT_FOUND'
                          ? postCaptionErrorText(context, _error!)
                          : _text('โหลดโพสต์ไม่สำเร็จ กรุณาลองใหม่'),
                      action: _text('ลองใหม่'),
                      onAction: () => unawaited(_load()))
                else ...[
                  Text(
                      _text(
                          'แก้แคปชั่นได้ก่อนเวลาโพสต์มากกว่า 1 นาที โดยไม่ใช้เครดิต AI หรือโควต้าโพสต์เพิ่ม'),
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: AppTheme.spaceLg),
                  if (blocked != null && _error == null) ...[
                    _notice(postCaptionErrorText(
                        context, ApiException('', code: blocked))),
                    const SizedBox(height: AppTheme.spaceLg),
                  ],
                  if (_error != null) ...[
                    _notice(postCaptionErrorText(context, _error!),
                        key: const ValueKey('post-caption-error'),
                        action: _text(_lockedCode == null
                            ? 'ลองใหม่'
                            : 'โหลดข้อมูลล่าสุด'),
                        onAction: () => unawaited(
                            _lockedCode == null ? _save() : _reload())),
                    const SizedBox(height: AppTheme.spaceLg),
                  ],
                  if (_separate)
                    PlatformCaptionFields(
                        captions: _captions,
                        visiblePlatforms: _platforms,
                        readOnly: readOnly,
                        onChanged: (p, value) => setState(() {
                              _captions = {..._captions, p: value};
                            }),
                        validationMessage: (p) {
                          final error = _validated ? _captionError(p) : null;
                          return error == null
                              ? null
                              : postCaptionValidationText(context, error);
                        })
                  else
                    PostDeeCard(
                        child: TextField(
                            key: const ValueKey('post-caption-shared'),
                            controller: _shared,
                            readOnly: readOnly,
                            minLines: 4,
                            maxLines: 10,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                                labelText: _text('แคปชั่น'),
                                error: _validated && _validationError != null
                                    ? Text(postCaptionValidationText(
                                        context, _validationError!))
                                    : null))),
                  if (_youtube) ...[
                    const SizedBox(height: AppTheme.spaceLg),
                    PostDeeCard(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                          if (_customTitle)
                            TextField(
                                key: const ValueKey(
                                    'post-caption-youtube-title'),
                                controller: _title,
                                readOnly: readOnly,
                                minLines: 1,
                                maxLines: 3,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                    labelText: _text('ชื่อคลิป YouTube'),
                                    error: _validated && _titleError != null
                                        ? Text(postCaptionValidationText(
                                            context, _titleError!))
                                        : null))
                          else ...[
                            Text(_text('ชื่อจากแคปชัน'),
                                style: Theme.of(context).textTheme.labelLarge),
                            const SizedBox(height: AppTheme.spaceSm),
                            Text(_youtubeTitle),
                          ],
                          Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: TextButton(
                                  onPressed: readOnly
                                      ? null
                                      : () => setState(() {
                                            if (!_customTitle) {
                                              _title.text = _youtubeTitle;
                                            }
                                            _customTitle = !_customTitle;
                                          }),
                                  child: Text(_text(_customTitle
                                      ? 'ใช้ชื่อจากแคปชัน'
                                      : 'ปรับชื่อเฉพาะ YouTube')))),
                        ])),
                  ],
                ],
              ]))),
          bottomNavigationBar: _ownerChanged
              ? null
              : SafeArea(
                  top: false,
                  child: Padding(
                      padding: const EdgeInsets.all(AppTheme.spaceLg),
                      child: FilledButton.icon(
                          key: const ValueKey('post-caption-save'),
                          onPressed: _loading || _loadFailed || readOnly
                              ? null
                              : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.check),
                          label: Text(_text(
                              _saving ? 'กำลังบันทึก...' : 'บันทึกแคปชั่น'))))),
        ));
  }
}
