import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';
import 'review_localizations.dart';

@immutable
class PublishPostPreviewChannel {
  const PublishPostPreviewChannel({
    required this.platform,
    required this.caption,
    required this.displayName,
    this.title,
    this.publishingNote,
  });

  final SocialPlatform platform;
  final String caption;
  final String displayName;
  final String? title;
  final String? publishingNote;
}

@immutable
class PublishPostPreviewData {
  PublishPostPreviewData({
    required List<PublishPostPreviewChannel> channels,
    required this.caption,
    this.coverImagePath,
    Uint8List? coverImageBytes,
    this.watermarkEnabled = false,
  })  : channels = List.unmodifiable(channels),
        coverImageBytes = coverImageBytes == null
            ? null
            : Uint8List.fromList(coverImageBytes).asUnmodifiableView();

  final List<PublishPostPreviewChannel> channels;
  final String caption;
  final String? coverImagePath;
  final Uint8List? coverImageBytes;
  final bool watermarkEnabled;
}

const _supportedPlatforms = {
  SocialPlatform.tiktok,
  SocialPlatform.youtubeShorts,
  SocialPlatform.instagramReels,
  SocialPlatform.facebookReels,
};

String _label(SocialPlatform platform) =>
    platform == SocialPlatform.facebookReels ? 'Facebook' : platform.label;

/// A local visual approximation. Playback and publishing remain caller-owned.
class PublishPostPreviewPane extends StatefulWidget {
  const PublishPostPreviewPane({
    super.key,
    required this.data,
    required this.video,
    this.hasStartedPlayback = false,
    this.isPlaying = false,
    this.onShowCover,
    this.onShowInformation,
    this.immersive = false,
  });

  final PublishPostPreviewData data;
  final Widget video;
  final bool hasStartedPlayback;
  final bool isPlaying;
  final VoidCallback? onShowCover;
  final VoidCallback? onShowInformation;
  final bool immersive;

  @override
  State<PublishPostPreviewPane> createState() => _PublishPostPreviewPaneState();
}

class _PublishPostPreviewPaneState extends State<PublishPostPreviewPane> {
  SocialPlatform? _selectedPlatform;
  bool _expanded = false;
  bool _showCover = false;
  bool _showInformation = false;

  List<PublishPostPreviewChannel> get _channels {
    final seen = <SocialPlatform>{};
    return [
      for (final channel in widget.data.channels)
        if (_supportedPlatforms.contains(channel.platform) &&
            seen.add(channel.platform))
          channel
    ];
  }

  PublishPostPreviewChannel? get _channel {
    final channels = _channels;
    for (final channel in channels) {
      if (channel.platform == _selectedPlatform) return channel;
    }
    return channels.isEmpty ? null : channels.first;
  }

  bool get _hasCover =>
      (widget.data.coverImageBytes?.isNotEmpty ?? false) ||
      (widget.data.coverImagePath?.trim().isNotEmpty ?? false);

  @override
  void didUpdateWidget(covariant PublishPostPreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying ||
        (widget.hasStartedPlayback && !oldWidget.hasStartedPlayback)) {
      _showCover = false;
    }
    if (!_hasCover) _showCover = false;
    if (_selectedPlatform != null &&
        !_channels.any((channel) => channel.platform == _selectedPlatform)) {
      _selectedPlatform = null;
      _expanded = false;
    }
  }

  void _toggleCover() {
    if (!_showCover) widget.onShowCover?.call();
    setState(() => _showCover = !_showCover);
  }

  String _coverNote(SocialPlatform? platform) => switch (platform) {
        SocialPlatform.tiktok =>
          'TikTok ใช้เฟรมจากคลิปเป็นปก ไม่ใช้ภาพปกแต่งนี้',
        SocialPlatform.youtubeShorts => 'ภาพปกนี้ไม่ได้ส่งเป็นภาพย่อ YouTube',
        SocialPlatform.facebookReels => 'Facebook อาจใช้เฟรมอื่นเป็นภาพปก',
        _ => 'ภาพปกที่เลือกไว้ รูปแบบจริงอาจต่างตามแพลตฟอร์ม',
      };

  Widget _header(PublishPostPreviewChannel? channel) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_channels.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final candidate in _channels)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: ValueKey(
                        'preview-platform-${candidate.platform.apiValue}'),
                    avatar: SocialPlatformLogo(
                        platform: candidate.platform, size: 18),
                    label: Text(_label(candidate.platform)),
                    selected: candidate.platform == channel?.platform,
                    showCheckmark: false,
                    onSelected: (_) => setState(() {
                      _selectedPlatform = candidate.platform;
                      _expanded = false;
                    }),
                  ),
                ),
            ]),
          ),
        if (channel?.publishingNote?.trim().isNotEmpty ?? false)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: ReviewText(channel!.publishingNote!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant)),
          ),
        if (_hasCover)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('preview-cover-toggle'),
              onPressed: _toggleCover,
              icon: Icon(
                  _showCover ? Icons.play_circle_outline : Icons.image_outlined,
                  size: 18),
              label: ReviewText(_showCover ? 'ดูคลิป' : 'ดูปก'),
            ),
          ),
        if (_showCover) ...[
          const ReviewText('ปกที่เลือกใน PostDee',
              style: TextStyle(fontWeight: FontWeight.w600)),
          ReviewText(_coverNote(channel?.platform),
              style: Theme.of(context).textTheme.bodySmall),
        ],
        if (widget.data.watermarkEnabled)
          ReviewText('ลายน้ำจริงจะถูกใส่ตอนส่งโพสต์',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ReviewText('ภาพตัวอย่างก่อนส่ง · หน้าตาจริงอาจต่างตามแพลตฟอร์ม',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontSize: 11, color: colors.onSurfaceVariant)),
        ),
      ],
    );
  }

  Widget _details(PublishPostPreviewChannel? channel,
      {required bool overlay, bool compact = false, bool watchStyle = false}) {
    final colors = Theme.of(context).colorScheme;
    final caption = channel?.caption ?? widget.data.caption;
    final ink = overlay ? AppTheme.onDarkPrimary : colors.onSurface;
    final secondary =
        overlay ? AppTheme.onDarkSecondary : colors.onSurfaceVariant;
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
        color: ink,
        fontSize: 14,
        height: 1.4,
        shadows: watchStyle
            ? const [Shadow(color: Colors.black54, blurRadius: 3)]
            : null);
    return DecoratedBox(
      decoration: watchStyle
          ? const BoxDecoration()
          : BoxDecoration(
              color: overlay
                  ? Colors.black.withValues(alpha: .78)
                  : colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
      child: SingleChildScrollView(
        padding: watchStyle
            ? const EdgeInsets.fromLTRB(16, 20, 0, 12)
            : const EdgeInsets.all(12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (channel != null) ...[
            if (watchStyle)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(channel.displayName,
                    key: const ValueKey('preview-identity'),
                    style: style.copyWith(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              )
            else
              Row(children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor:
                      overlay ? Colors.white24 : colors.surfaceContainerHighest,
                  child: channel.displayName.trim().isEmpty
                      ? Icon(Icons.person_outline, color: ink, size: 18)
                      : Text(channel.displayName.trim().characters.first,
                          style: TextStyle(color: ink, fontSize: 14)),
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(channel.displayName,
                        key: const ValueKey('preview-identity'),
                        style: style.copyWith(fontWeight: FontWeight.w600))),
              ]),
            if (!compact && !watchStyle)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(_label(channel.platform),
                    style: style.copyWith(color: secondary, fontSize: 11)),
              ),
            if (channel.platform == SocialPlatform.youtubeShorts &&
                (channel.title?.isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(channel.title!,
                    key: const ValueKey('preview-title'),
                    style: style.copyWith(fontWeight: FontWeight.w700)),
              ),
          ],
          LayoutBuilder(builder: (context, constraints) {
            final painter = TextPainter(
              text: TextSpan(text: caption, style: style),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 3,
            )..layout(maxWidth: constraints.maxWidth);
            final canExpand = painter.didExceedMaxLines;
            painter.dispose();
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(caption,
                      key: const ValueKey('preview-caption'),
                      style: style,
                      maxLines: _expanded ? null : 3,
                      softWrap: true,
                      overflow: _expanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis),
                  if (canExpand)
                    Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const ValueKey('preview-caption-expand'),
                          onPressed: () =>
                              setState(() => _expanded = !_expanded),
                          style: TextButton.styleFrom(foregroundColor: ink),
                          child: ReviewText(
                              _expanded ? 'ย่อแคปชั่น' : 'ดูแคปชั่นทั้งหมด'),
                        )),
                ]);
          }),
          if (watchStyle)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                key: const ValueKey('preview-clip-audio'),
                children: [
                  const Icon(Icons.music_note,
                      color: AppTheme.onDarkPrimary, size: 16),
                  const SizedBox(width: 5),
                  Flexible(
                      child: ReviewText('เสียงจากคลิป',
                          style: style.copyWith(fontSize: 12))),
                ],
              ),
            ),
        ]),
      ),
    );
  }

  Widget _poster() {
    Widget unavailable(BuildContext context, Object error, StackTrace? stack) =>
        const Center(
            child: ReviewText('ยังแสดงปกไม่ได้',
                style: TextStyle(color: AppTheme.onDarkPrimary)));
    final bytes = widget.data.coverImageBytes;
    return ColoredBox(
      color: Colors.black,
      child: bytes != null && bytes.isNotEmpty
          ? Image.memory(bytes,
              key: const ValueKey('preview-cover-image'),
              fit: BoxFit.contain,
              errorBuilder: unavailable)
          : Image.file(File(widget.data.coverImagePath!),
              key: const ValueKey('preview-cover-image'),
              fit: BoxFit.contain,
              errorBuilder: unavailable),
    );
  }

  Widget _immersiveHeader(PublishPostPreviewChannel? channel) => Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final candidate in _channels)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey(
                          'preview-platform-${candidate.platform.apiValue}'),
                      avatar: SocialPlatformLogo(
                          platform: candidate.platform, size: 16),
                      label: Text(_label(candidate.platform)),
                      selected: candidate.platform == channel?.platform,
                      showCheckmark: false,
                      color: WidgetStateProperty.resolveWith((states) =>
                          states.contains(WidgetState.selected)
                              ? const Color(0xFF161B18)
                              : const Color(0xFF272C29)),
                      surfaceTintColor: Colors.transparent,
                      side: BorderSide(
                          color: candidate.platform == channel?.platform
                              ? Colors.white
                              : Colors.white38),
                      labelStyle:
                          const TextStyle(color: Colors.white, fontSize: 12),
                      onSelected: (_) => setState(() {
                        _selectedPlatform = candidate.platform;
                        _expanded = false;
                      }),
                    ),
                  ),
              ]),
            ),
          ),
          if (_hasCover)
            IconButton(
              key: const ValueKey('preview-cover-toggle'),
              onPressed: _toggleCover,
              tooltip: localizeReviewMessage(context, _showCover ? 'ดูคลิป' : 'ดูปก'),
              icon: Icon(
                  _showCover ? Icons.play_circle_outline : Icons.image_outlined,
                  color: Colors.white,
                  size: 22),
            ),
          IconButton(
            key: const ValueKey('preview-info-toggle'),
            tooltip: localizeReviewMessage(context, 'ข้อมูลพรีวิว'),
            onPressed: () {
              widget.onShowInformation?.call();
              setState(() => _showInformation = true);
            },
            icon: const Icon(Icons.info_outline, color: Colors.white, size: 22),
          ),
        ],
      );

  // Keep this panel in the same widget subtree as the sensitive preview.
  // A session revocation removes it together with the video and metadata.
  Widget _information(PublishPostPreviewChannel? channel) => BlockSemantics(
        key: const ValueKey('preview-info-panel'),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: Stack(children: [
            ModalBarrier(
              color: Colors.black54,
              dismissible: true,
              onDismiss: () => setState(() => _showInformation = false),
            ),
            Center(
              child: AlertDialog(
                title: const ReviewText('ข้อมูลพรีวิว'),
                scrollable: true,
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ReviewText(
                        'ภาพตัวอย่างก่อนส่ง · หน้าตาจริงอาจต่างตามแพลตฟอร์ม'),
                    if (channel?.publishingNote?.trim().isNotEmpty ??
                        false) ...[
                      const SizedBox(height: 12),
                      ReviewText(channel!.publishingNote!),
                    ],
                    if (_hasCover) ...[
                      const SizedBox(height: 12),
                      ReviewText(_coverNote(channel?.platform)),
                    ],
                    if (widget.data.watermarkEnabled) ...[
                      const SizedBox(height: 12),
                      const ReviewText('ลายน้ำจริงจะถูกใส่ตอนส่งโพสต์'),
                    ],
                    const SizedBox(height: 12),
                    const ReviewText('หัวใจและความคิดเห็นเป็นภาพตัวอย่าง'),
                  ],
                ),
                actions: [
                  TextButton(
                    key: const ValueKey('preview-info-close'),
                    onPressed: () => setState(() => _showInformation = false),
                    child: const ReviewText('ปิด'),
                  ),
                ],
              ),
            ),
          ]),
        ),
      );

  Widget _immersiveSocialRail(PublishPostPreviewChannel? channel) =>
      IgnorePointer(
        key: const ValueKey('preview-tiktok-social-rail'),
        child: ExcludeSemantics(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: Colors.white24,
              child: channel == null || channel.displayName.trim().isEmpty
                  ? const Icon(Icons.person_outline,
                      color: Colors.white, size: 28)
                  : Text(channel.displayName.trim().characters.first,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 20)),
            ),
            const SizedBox(height: 24),
            const Icon(Icons.favorite, color: Colors.white, size: 34),
            const SizedBox(height: 24),
            const Icon(Icons.chat_bubble, color: Colors.white, size: 32),
            const SizedBox(height: 24),
            const Icon(Icons.bookmark, color: Colors.white, size: 32),
            const SizedBox(height: 24),
            const Icon(Icons.share, color: Colors.white, size: 34),
            const SizedBox(height: 24),
            const CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white24,
              child: Icon(Icons.music_note, color: Colors.white, size: 24),
            ),
          ]),
        ),
      );

  Widget _immersive(
      BoxConstraints constraints, PublishPostPreviewChannel? channel) {
    final safe = MediaQuery.paddingOf(context);
    final availableHeight =
        math.max(0.0, constraints.maxHeight - safe.top - safe.bottom - 140);
    final detailsHeight = math.min(280.0, availableHeight * .58);
    return ColoredBox(
      color: Colors.black,
      child: Stack(fit: StackFit.expand, children: [
        widget.video,
        if (_showCover) Positioned.fill(child: _poster()),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              key: const ValueKey('preview-tiktok-gradient'),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: .48),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: .72),
                  ],
                  stops: const [0, .25, .52, 1],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 66,
          bottom: 0,
          child: SafeArea(
            top: false,
            right: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: detailsHeight),
              child: _details(channel, overlay: true, watchStyle: true),
            ),
          ),
        ),
        Positioned(
          right: 12 + safe.right,
          bottom: 16 + safe.bottom,
          child: SizedBox(
            width: 44,
            height: math.min(360.0, availableHeight),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomCenter,
              child: _immersiveSocialRail(channel),
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 4,
          top: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 64),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _immersiveHeader(channel),
                  if (_showCover)
                    const Padding(
                      padding: EdgeInsets.only(left: 4, top: 4),
                      child: ReviewText('ปกที่เลือกใน PostDee',
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_showInformation) Positioned.fill(child: _information(channel)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        key: const ValueKey('publish-post-preview'),
        builder: (context, constraints) {
          final channel = _channel;
          if (widget.immersive) return _immersive(constraints, channel);
          final shortWide =
              constraints.maxWidth > constraints.maxHeight * 1.5 &&
                  constraints.maxHeight < 300;
          final tiktokWatch = channel?.platform == SocialPlatform.tiktok &&
              !shortWide &&
              constraints.maxWidth < constraints.maxHeight &&
              constraints.maxHeight >= 380 &&
              MediaQuery.textScalerOf(context).scale(14) <= 20;
          final overlay = channel != null &&
              channel.platform != SocialPlatform.facebookReels &&
              constraints.maxHeight >= 280 &&
              !shortWide &&
              (channel.platform != SocialPlatform.tiktok || tiktokWatch);
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: math.min(165, constraints.maxHeight * .36)),
                  child: SingleChildScrollView(child: _header(channel)),
                ),
                const SizedBox(height: 6),
                Expanded(child: LayoutBuilder(builder: (context, body) {
                  final detailsHeight = math.min(
                      tiktokWatch ? 240.0 : 220.0, body.maxHeight * .50);
                  return Flex(
                      direction: shortWide ? Axis.horizontal : Axis.vertical,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                            flex: shortWide ? 2 : 1,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Stack(fit: StackFit.expand, children: [
                                widget.video,
                                if (_showCover)
                                  Positioned.fill(child: _poster()),
                                if (tiktokWatch)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: DecoratedBox(
                                        key: const ValueKey(
                                            'preview-tiktok-gradient'),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.transparent,
                                              Colors.black
                                                  .withValues(alpha: .60),
                                              Colors.black
                                                  .withValues(alpha: .85)
                                            ],
                                            stops: const [.25, .68, 1],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (tiktokWatch)
                                  const Positioned(
                                    right: 12,
                                    bottom: 34,
                                    child: IgnorePointer(
                                      key: ValueKey(
                                          'preview-tiktok-social-rail'),
                                      child: ExcludeSemantics(
                                        child: Column(children: [
                                          Icon(Icons.favorite,
                                              color: Colors.white, size: 30),
                                          SizedBox(height: 24),
                                          Icon(Icons.chat_bubble,
                                              color: Colors.white, size: 29),
                                          SizedBox(height: 24),
                                          Icon(Icons.bookmark,
                                              color: Colors.white, size: 29),
                                          SizedBox(height: 24),
                                          Icon(Icons.share,
                                              color: Colors.white, size: 30),
                                        ]),
                                      ),
                                    ),
                                  ),
                                if (overlay &&
                                    !tiktokWatch &&
                                    body.maxHeight >= 220)
                                  const Positioned(
                                      right: 12,
                                      top: 14,
                                      child: IgnorePointer(
                                          child: ExcludeSemantics(
                                              child: Column(children: [
                                        Icon(Icons.favorite_border,
                                            color: Colors.white, size: 26),
                                        SizedBox(height: 16),
                                        Icon(Icons.chat_bubble_outline,
                                            color: Colors.white, size: 25),
                                        SizedBox(height: 16),
                                        Icon(Icons.share_outlined,
                                            color: Colors.white, size: 25),
                                      ])))),
                                if (overlay)
                                  Positioned(
                                      left: tiktokWatch ? 0 : 8,
                                      right: tiktokWatch ? 62 : 48,
                                      bottom: tiktokWatch ? 0 : 8,
                                      child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                              maxHeight: detailsHeight),
                                          child: _details(channel,
                                              overlay: true,
                                              watchStyle: tiktokWatch))),
                              ]),
                            )),
                        if (!overlay) ...[
                          SizedBox(
                              width: shortWide ? 8 : 0,
                              height: shortWide ? 0 : 6),
                          if (shortWide)
                            Expanded(
                                flex: 3,
                                child: _details(channel,
                                    overlay: false, compact: true))
                          else
                            ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxHeight: detailsHeight),
                                child: _details(channel, overlay: false)),
                        ],
                      ]);
                })),
              ]);
        },
      );
}
