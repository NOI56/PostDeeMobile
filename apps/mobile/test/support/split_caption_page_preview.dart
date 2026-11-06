import 'package:flutter/material.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/platforms/social_platform_logo.dart';
import 'package:postdee_mobile/features/shared/postdee_card.dart';
import 'package:postdee_mobile/features/uploader/clip_split_localizations.dart';
import 'package:postdee_mobile/features/uploader/clip_split_plan.dart';

/// Offline concept chrome around the real shared-caption editor supplied by
/// the preview fixture. It neither prepares media nor submits any posts.
class SplitCaptionPagePreview extends StatefulWidget {
  const SplitCaptionPagePreview({
    super.key,
    required this.captionEditor,
    required this.videoName,
    required this.sourceDurationSeconds,
    required this.segments,
    required this.platform,
    this.english = false,
    this.onContinue,
    this.onBack,
    this.onSave,
  });

  final Widget captionEditor;
  final String videoName;
  final double sourceDurationSeconds;
  final List<ClipSplitSegment> segments;
  final SocialPlatform platform;
  final bool english;
  final VoidCallback? onContinue;
  final VoidCallback? onBack;
  final VoidCallback? onSave;

  @override
  State<SplitCaptionPagePreview> createState() =>
      _SplitCaptionPagePreviewState();
}

class _SplitCaptionPagePreviewState extends State<SplitCaptionPagePreview> {
  String _text(String thai, String english) => widget.english ? english : thai;
  int get _count => widget.segments.length;
  String get _parts =>
      _text('$_count ตอน', '$_count ${_count == 1 ? 'part' : 'parts'}');
  String get _scope =>
      _text('แคปชันเดียวกันทั้ง $_parts', 'One shared caption for all $_parts');

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: AppTheme.screenBackground,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              key: const ValueKey('split-caption-preview-scroll'),
              padding: AppTheme.screenPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  const SizedBox(height: AppTheme.spaceLg),
                  _progress(),
                  const SizedBox(height: AppTheme.spaceXl),
                  _splitContext(),
                  const SizedBox(height: AppTheme.spaceXl),
                  Text(
                    _text('เขียนแคปชัน', 'Write a caption'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppTheme.spaceXs),
                  Text(
                    _text(
                      'เขียนครั้งเดียว ใช้กับทุกตอน แล้วตรวจแต่ละตอนก่อนส่ง',
                      'Write once for the set, then review each part before sending.',
                    ),
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: AppTheme.spaceLg),
                  widget.captionEditor,
                  const SizedBox(height: AppTheme.spaceLg),
                ],
              ),
            ),
          ),
          bottomNavigationBar: _footer(),
        ),
      );

  Widget _header() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_text('สร้างโพสต์', 'Create post'),
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: AppTheme.spaceXs),
                Text(
                  _text('เตรียมคลิป แล้วตรวจทานก่อนส่ง',
                      'Prepare your clips, then review before sending.'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          if (widget.onSave != null) ...[
            const SizedBox(width: AppTheme.spaceSm),
            IconButton(
              key: const ValueKey('split-caption-preview-save'),
              onPressed: widget.onSave,
              tooltip: _text('เก็บร่างทั้งชุด', 'Save the set as a draft'),
              icon: const Icon(Icons.save_outlined),
            ),
          ],
        ],
      );

  Widget _progress() {
    final labels = widget.english
        ? const ['Channels', 'Video', 'Caption', 'Review']
        : const ['ช่องทาง', 'คลิป', 'แคปชัน', 'ตรวจทาน'];
    return LayoutBuilder(builder: (context, constraints) {
      final stepWidth = constraints.maxWidth / labels.length;
      return Stack(children: [
        for (var index = 0; index < labels.length - 1; index++)
          Positioned(
            left: stepWidth * (index + .5) + 13,
            top: 12,
            width: stepWidth - 26,
            height: 2,
            child: ExcludeSemantics(child: ColoredBox(color: AppTheme.border)),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < labels.length; index++)
              Expanded(
                child: Semantics(
                  label: _text('ขั้นตอน ${index + 1} จาก 4 · ${labels[index]}',
                      'Step ${index + 1} of 4 · ${labels[index]}'),
                  selected: index == 2,
                  child: ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spaceXs),
                      child: Column(children: [
                        Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: index == 2
                                ? AppTheme.accent
                                : index < 2
                                    ? AppTheme.accent.withValues(alpha: .12)
                                    : AppTheme.glassDeep,
                            border: index > 2
                                ? Border.all(color: AppTheme.border)
                                : null,
                          ),
                          child: index < 2
                              ? Icon(Icons.check_rounded,
                                  size: 17, color: AppTheme.accent)
                              : Text('${index + 1}',
                                  textScaler: TextScaler.noScaling,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: index == 2
                                          ? Colors.white
                                          : AppTheme.textMuted)),
                        ),
                        const SizedBox(height: AppTheme.spaceXs),
                        Text(labels[index],
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: index == 2
                                      ? AppTheme.accentCyanInk
                                      : AppTheme.textSecondary,
                                  fontWeight: index == 2
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                )),
                      ]),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ]);
    });
  }

  Widget _splitContext() => PostDeeCard(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.content_cut_rounded,
                  size: 20, color: AppTheme.accentCyanInk),
              const SizedBox(width: AppTheme.spaceSm),
              Expanded(
                child: Text(_text('แบ่งคลิปแล้ว $_parts', 'Split into $_parts'),
                    style: Theme.of(context).textTheme.titleSmall),
              ),
            ]),
            const SizedBox(height: AppTheme.spaceSm),
            Text(widget.videoName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppTheme.spaceXs),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ExcludeSemantics(
                  child:
                      SocialPlatformLogo(platform: widget.platform, size: 20)),
              const SizedBox(width: AppTheme.spaceSm),
              Expanded(
                child: Text(
                  '${widget.platform.label} · ${_text('ต้นฉบับ', 'Original')} ${formatClipSplitTime(widget.sourceDurationSeconds)}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppTheme.textSecondary),
                ),
              ),
            ]),
            const SizedBox(height: AppTheme.spaceXs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('split-caption-preview-parts'),
                onPressed: _showParts,
                icon: const Icon(Icons.view_list_outlined, size: 18),
                label: Text(_text('ดูตอนที่แบ่ง', 'View the parts')),
              ),
            ),
          ],
        ),
      );

  Widget _footer() => DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.glass,
          border: Border(top: BorderSide(color: AppTheme.borderSoft)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_scope,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppTheme.textSecondary)),
              if (widget.onContinue != null) ...[
                const SizedBox(height: AppTheme.spaceSm),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('split-caption-preview-continue'),
                    onPressed: widget.onContinue,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: AppTheme.spaceSm),
                      child: Text(
                          _text(
                              'ถัดไป: ตรวจทาน $_parts', 'Next: Review $_parts'),
                          textAlign: TextAlign.center),
                    ),
                  ),
                ),
              ],
              if (widget.onBack != null)
                TextButton.icon(
                  key: const ValueKey('split-caption-preview-back'),
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: Text(_text('กลับไปที่คลิป', 'Back to the video')),
                ),
            ]),
          ),
        ),
      );

  Future<void> _showParts() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => FractionallySizedBox(
          heightFactor: .52,
          child: Padding(
            key: const ValueKey('split-caption-preview-parts-sheet'),
            padding: AppTheme.screenPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(_text('ตอนที่แบ่งไว้', 'Your split parts'),
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  IconButton(
                    key: const ValueKey('split-caption-preview-parts-close'),
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    tooltip: _text('ปิด', 'Close'),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]),
                Text(widget.videoName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppTheme.textSecondary)),
                const SizedBox(height: AppTheme.spaceMd),
                Text(_scope, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: AppTheme.spaceMd),
                Expanded(
                  child: ListView.separated(
                    itemCount: widget.segments.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: AppTheme.borderSoft),
                    itemBuilder: (_, index) {
                      final segment = widget.segments[index];
                      return Padding(
                        key: ValueKey('split-caption-preview-part-$index'),
                        padding: const EdgeInsets.symmetric(
                            vertical: AppTheme.spaceLg),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ExcludeSemantics(
                              child: Icon(Icons.movie_outlined,
                                  color: AppTheme.accentCyanInk),
                            ),
                            const SizedBox(width: AppTheme.spaceMd),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      _text('ตอน ${index + 1}',
                                          'Part ${index + 1}'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                                  const SizedBox(height: AppTheme.spaceXs),
                                  Text(
                                      '${formatClipSplitTime(segment.startSeconds)}–${formatClipSplitTime(segment.endSeconds)}'),
                                  Text(
                                    _text(
                                      'ยาว ${formatClipSplitTime(segment.durationSeconds)} นาที',
                                      'Length ${formatClipSplitTime(segment.durationSeconds)} min',
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            color: AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
