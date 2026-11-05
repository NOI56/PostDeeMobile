import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/auth/auth_session.dart';
import '../../core/theme/app_theme.dart';
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';
import '../shared/postdee_card.dart';
import '../shared/postdee_press_feedback.dart';
import 'clip_split_localizations.dart';
import 'clip_split_plan.dart';
import 'clip_split_timeline.dart';
import 'platform_publish_preflight.dart';

/// Chooses and reviews a local plan. Confirmation returns it to the uploader;
/// this route never encodes, uploads, creates posts or changes entitlements.
class ClipSplitScreen extends StatefulWidget {
  const ClipSplitScreen({
    super.key,
    required this.sourceDurationSeconds,
    required this.videoName,
    required this.initialPlatforms,
    this.videoFile,
    this.tikTokDirectPost = false,
    this.tikTokMaxDurationSeconds,
    this.availablePlatforms,
    this.previewSegment,
    this.ownerSession,
  });

  final double sourceDurationSeconds;
  final String videoName;
  final Set<SocialPlatform> initialPlatforms;
  final File? videoFile;
  final bool tikTokDirectPost;
  final int? tikTokMaxDurationSeconds;
  final Set<SocialPlatform>? availablePlatforms;
  final Future<void> Function(ClipSplitSegment segment)? previewSegment;
  final AuthSessionBinding? ownerSession;

  @override
  State<ClipSplitScreen> createState() => _ClipSplitScreenState();
}

class _ClipSplitScreenState extends State<ClipSplitScreen> {
  static const _platformOrder = [
    SocialPlatform.facebookReels,
    SocialPlatform.youtubeShorts,
    SocialPlatform.tiktok,
    SocialPlatform.instagramReels,
  ];
  final _selected = <SocialPlatform>{};
  final _segmentOverrides = <SocialPlatform, List<ClipSplitSegment>>{};
  final _scrollController = ScrollController();
  late final AuthSessionBinding _owner;
  ClipSplitMode _mode = ClipSplitMode.affectedChannels;
  SocialPlatform? _active;
  bool _reviewing = false;
  bool _previewing = false;
  bool _ownerChanged = false;
  String? _previewError;
  String? _rangeNotice;

  List<SocialPlatform> get _available => _platformOrder
      .where(
          (platform) => widget.availablePlatforms?.contains(platform) ?? true)
      .toList();

  bool get _unknownTikTokDirect =>
      widget.tikTokDirectPost &&
      (widget.tikTokMaxDurationSeconds == null ||
          widget.tikTokMaxDurationSeconds! <= 0);

  bool _canSelect(SocialPlatform platform) {
    if (platform == SocialPlatform.tiktok && _unknownTikTokDirect) return false;
    final rule = platformVideoDurationRule(platform);
    return rule != null &&
        widget.sourceDurationSeconds.isFinite &&
        widget.sourceDurationSeconds >= (rule.minimumSeconds ?? 0);
  }

  @override
  void initState() {
    super.initState();
    _owner = widget.ownerSession ??
        PostDeeAuthSessionStore.instance.captureSession();
    _ownerChanged = !_owner.isCurrent;
    PostDeeAuthSessionStore.instance.addListener(_sessionChanged);
    _selected.addAll(widget.initialPlatforms.where(
        (platform) => _available.contains(platform) && _canSelect(platform)));
    _active = _available.where(_selected.contains).firstOrNull;
  }

  void _sessionChanged() {
    if (!mounted || _owner.isCurrent || _ownerChanged) return;
    setState(() => _ownerChanged = true);
  }

  @override
  void dispose() {
    PostDeeAuthSessionStore.instance.removeListener(_sessionChanged);
    _scrollController.dispose();
    super.dispose();
  }

  ClipSplitPlan _createPlan({
    Map<SocialPlatform, List<ClipSplitSegment>>? overrides,
    Set<SocialPlatform>? platforms,
    ClipSplitMode? mode,
  }) =>
      ClipSplitPlan.create(
        sourceDurationSeconds: widget.sourceDurationSeconds,
        platforms: platforms ?? _selected,
        mode: mode ?? _mode,
        tikTokDirectPost: widget.tikTokDirectPost,
        tikTokMaxDurationSeconds: widget.tikTokMaxDurationSeconds,
        segmentOverrides: overrides ?? _segmentOverrides,
      );

  void _retainCompatibleRanges() {
    _rangeNotice = null;
    _segmentOverrides
        .removeWhere((platform, _) => !_selected.contains(platform));
    if (_segmentOverrides.isEmpty || _selected.isEmpty) return;
    final reset = <SocialPlatform>[];
    if (_mode == ClipSplitMode.sameParts) {
      try {
        final plan = _createPlan();
        for (final channel in plan.channelPlans) {
          _segmentOverrides[channel.platform] = channel.segments;
        }
      } on ClipSplitPlanException {
        reset.addAll(_selected);
        _segmentOverrides.clear();
      }
    } else {
      for (final platform in _segmentOverrides.keys.toList()) {
        try {
          _createPlan(platforms: {
            platform
          }, overrides: {
            platform: _segmentOverrides[platform]!,
          });
        } on ClipSplitPlanException {
          reset.add(platform);
          _segmentOverrides.remove(platform);
        }
      }
    }
    if (reset.isNotEmpty) {
      final names = reset.map((platform) => platform.label).join(' · ');
      _rangeNotice = clipSplitText(
          context,
          'คืนช่วงเวลา $names เป็นอัตโนมัติ เพราะวิธีแบ่งหรือข้อกำหนดเปลี่ยน กรุณาตรวจอีกครั้ง',
          '$names ranges were reset to automatic because the split mode or limits changed. Review them again.');
    }
  }

  int _ticks(double seconds) => (seconds * 1000000).round();

  bool _isFullVideo(ClipSplitChannelPlan channel) =>
      channel.segments.length == 1 &&
      _ticks(channel.segments.single.startSeconds) == 0 &&
      _ticks(channel.segments.single.endSeconds) ==
          _ticks(widget.sourceDurationSeconds);

  bool _hasGaps(ClipSplitChannelPlan channel) {
    var end = 0;
    for (final segment in channel.segments) {
      if (_ticks(segment.startSeconds) > end) return true;
      end = _ticks(segment.endSeconds);
    }
    return _ticks(widget.sourceDurationSeconds) > end;
  }

  Future<void> _editRange(ClipSplitChannelPlan channel, int index) async {
    if (_previewing ||
        _ownerChanged ||
        !_owner.isCurrent ||
        channel.segments.length < 2) {
      return;
    }
    ClipSplitPlan validate(ClipSplitSegment segment) {
      final segments = List<ClipSplitSegment>.of(channel.segments)
        ..[index] = segment;
      return _createPlan(overrides: {
        ..._segmentOverrides,
        if (_mode == ClipSplitMode.sameParts)
          for (final platform in _selected) platform: segments
        else
          channel.platform: segments,
      });
    }

    final plan = await showDialog<ClipSplitPlan>(
        context: context,
        builder: (_) => _ClipSplitRangeDialog(
            segment: channel.segments[index],
            sourceDuration: _ticks(widget.sourceDurationSeconds) / 1000000,
            availableStart:
                index == 0 ? 0 : channel.segments[index - 1].endSeconds,
            availableEnd: index + 1 < channel.segments.length
                ? channel.segments[index + 1].startSeconds
                : _ticks(widget.sourceDurationSeconds) / 1000000,
            minimumDuration: channel.minimumDurationSeconds,
            maximumDuration: channel.maximumDurationSeconds,
            shared: _mode == ClipSplitMode.sameParts,
            owner: _owner,
            validate: validate,
            onPreview: widget.videoFile != null || widget.previewSegment != null
                ? _preview
                : null));
    if (plan == null || !mounted || _ownerChanged || !_owner.isCurrent) return;
    setState(() {
      if (_mode == ClipSplitMode.sameParts) {
        for (final selected in plan.channelPlans) {
          _segmentOverrides[selected.platform] = selected.segments;
        }
      } else {
        _segmentOverrides[channel.platform] =
            plan.channelPlanFor(channel.platform).segments;
      }
      _rangeNotice = null;
    });
  }

  void _showReview() {
    if (_ownerChanged || !_owner.isCurrent) return;
    setState(() => _reviewing = true);
    _scrollToTop();
  }

  void _showEditor() {
    setState(() => _reviewing = false);
    _scrollToTop();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  Future<void> _preview(ClipSplitSegment segment) async {
    if (_previewing || _ownerChanged || !_owner.isCurrent) return;
    setState(() {
      _previewing = true;
      _previewError = null;
    });
    try {
      if (widget.previewSegment != null) {
        await widget.previewSegment!(segment);
      } else if (widget.videoFile != null) {
        await Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => _ClipRangePreviewScreen(
              file: widget.videoFile!, segment: segment, owner: _owner),
        ));
      }
    } catch (_) {
      if (mounted && _owner.isCurrent) {
        setState(() => _previewError = clipSplitText(
            context,
            'ยังเปิดตัวอย่างคลิปไม่ได้ ลองอีกครั้ง',
            'Could not open the video preview. Try again.'));
      }
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ClipSplitPlan? plan;
    ClipSplitPlanProblem? problem;
    try {
      plan = _createPlan();
    } on ClipSplitPlanException catch (error) {
      problem = error.problem;
    }
    final active = plan?.channelPlans
            .where((channel) => channel.platform == _active)
            .firstOrNull ??
        plan?.channelPlans.firstOrNull;
    return PopScope(
      canPop: !_reviewing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _reviewing) _showEditor();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(clipSplitText(
              context,
              _reviewing ? 'ตรวจแผนแบ่งคลิป' : 'แบ่งคลิปเป็นตอน',
              _reviewing ? 'Review split plan' : 'Split into parts')),
          leading: BackButton(
              onPressed:
                  _reviewing ? _showEditor : () => Navigator.of(context).pop()),
        ),
        body: SafeArea(
          bottom: false,
          child: ListView(
            key: const ValueKey('clip-split-scroll'),
            controller: _scrollController,
            padding: AppTheme.screenPadding,
            children: [
              _sourceSummary(),
              if (_ownerChanged) ...[
                _notice(clipSplitText(
                    context,
                    'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดคลิปใหม่',
                    'Your account has changed. Reopen the video.')),
                const SizedBox(height: AppTheme.spaceLg),
              ],
              if (_reviewing && plan != null)
                ..._review(plan)
              else ...[
                _channelChoices(),
                const SizedBox(height: AppTheme.spaceLg),
                _modeChoices(),
                const SizedBox(height: AppTheme.spaceLg),
                if (_rangeNotice != null) ...[
                  KeyedSubtree(
                      key: const ValueKey('clip-split-ranges-reset-notice'),
                      child: _notice(_rangeNotice!)),
                  const SizedBox(height: AppTheme.spaceLg),
                ],
                if (plan != null && active != null) ...[
                  _channelTabs(plan),
                  const SizedBox(height: AppTheme.spaceLg),
                  _segments(active),
                  if (_segmentOverrides.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.spaceLg),
                    TextButton.icon(
                      key: const ValueKey('clip-split-reset-ranges'),
                      onPressed: _previewing || _ownerChanged
                          ? null
                          : () => setState(() {
                                _segmentOverrides.clear();
                                _rangeNotice = null;
                              }),
                      icon: const Icon(Icons.restart_alt),
                      label: Text(clipSplitText(
                          context,
                          'คืนทุกช่วงเวลาเป็นอัตโนมัติ',
                          'Reset all ranges to automatic')),
                    ),
                  ],
                ],
              ],
              if (problem != null) ...[
                const SizedBox(height: AppTheme.spaceLg),
                _notice(clipSplitProblemText(context, problem)),
              ],
              if (_previewError != null) ...[
                const SizedBox(height: AppTheme.spaceLg),
                _notice(_previewError!),
              ],
            ],
          ),
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.glass,
            border: Border(top: BorderSide(color: AppTheme.borderSoft)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spaceLg),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (plan != null) ...[
                  _quotaSummary(plan),
                  const SizedBox(height: AppTheme.spaceMd),
                ],
                SizedBox(
                    width: double.infinity,
                    child: PostDeePressFeedback(
                        enabled: plan != null && !_ownerChanged && !_previewing,
                        child: FilledButton(
                          key: ValueKey(_reviewing
                              ? 'clip-split-confirm'
                              : 'clip-split-review'),
                          onPressed:
                              plan == null || _ownerChanged || _previewing
                                  ? null
                                  : _reviewing
                                      ? () {
                                          if (_owner.isCurrent) {
                                            Navigator.of(context).pop(plan);
                                          }
                                        }
                                      : _showReview,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: AppTheme.spaceMd),
                            child: Text(
                                clipSplitText(
                                    context,
                                    _reviewing
                                        ? 'ยืนยันแบ่งคลิป · เตรียมทั้งชุด'
                                        : 'ใช้แผนนี้ · ตรวจรายการ',
                                    _reviewing
                                        ? 'Confirm split · Prepare set'
                                        : 'Use this plan · Review'),
                                textAlign: TextAlign.center),
                          ),
                        ))),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sourceSummary() => Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.spaceXl),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DecoratedBox(
            decoration: BoxDecoration(
                color: AppTheme.mint,
                borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
            child: Padding(
                padding: const EdgeInsets.all(AppTheme.spaceLg),
                child: Icon(Icons.content_cut_rounded,
                    color: AppTheme.accentCyanInk)),
          ),
          const SizedBox(width: AppTheme.spaceMd),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(widget.videoName,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: AppTheme.spaceXs),
                Text(
                    widget.sourceDurationSeconds.isFinite &&
                            widget.sourceDurationSeconds > 0
                        ? clipSplitText(
                            context,
                            'ต้นฉบับ ${formatClipSplitTime(widget.sourceDurationSeconds)} นาที',
                            'Original ${formatClipSplitTime(widget.sourceDurationSeconds)} min')
                        : clipSplitText(
                            context, 'ยังไม่ทราบความยาว', 'Length unavailable'),
                    style: TextStyle(color: AppTheme.textSecondary)),
                Text(
                    clipSplitText(
                        context, 'เก็บต้นฉบับไว้เสมอ', 'Your original is kept'),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppTheme.textSecondary)),
              ])),
        ]),
      );

  Widget _channelChoices() => PostDeeCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(clipSplitText(context, 'ต้องการลงที่ไหนบ้าง', 'Choose channels'),
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppTheme.spaceSm),
          for (final platform in _available) ...[
            if (platform != _available.first)
              const SizedBox(height: AppTheme.spaceXs),
            _selectionSurface(
                selected: _selected.contains(platform),
                child: CheckboxListTile(
                  key: ValueKey('clip-split-channel-${platform.apiValue}'),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: AppTheme.spaceSm),
                  controlAffinity: ListTileControlAffinity.leading,
                  checkboxShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.spaceXs)),
                  secondary: ExcludeSemantics(
                      child: SocialPlatformLogo(platform: platform, size: 24)),
                  value: _selected.contains(platform),
                  title: Text(platform.label),
                  subtitle: Text(_channelLimit(platform)),
                  onChanged:
                      !_canSelect(platform) || _ownerChanged || _previewing
                          ? null
                          : (checked) {
                              setState(() {
                                checked == true
                                    ? _selected.add(platform)
                                    : _selected.remove(platform);
                                _retainCompatibleRanges();
                                if (!_selected.contains(_active)) {
                                  _active = _available
                                      .where(_selected.contains)
                                      .firstOrNull;
                                }
                              });
                            },
                )),
          ],
        ]),
      );

  Widget _selectionSurface({required bool selected, required Widget child}) =>
      Material(
        animationDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        animateColor: true,
        color: selected ? AppTheme.mint : AppTheme.glass.withValues(alpha: 0),
        borderRadius: BorderRadius.circular(AppTheme.tileRadius),
        clipBehavior: Clip.antiAlias,
        child: child,
      );

  String _channelLimit(SocialPlatform platform) {
    if (platform == SocialPlatform.tiktok && _unknownTikTokDirect) {
      return clipSplitProblemText(
          context, ClipSplitPlanProblem.tikTokAccountRequired);
    }
    final rule = platformVideoDurationRule(platform,
        tikTokMaxDurationSeconds:
            widget.tikTokDirectPost ? widget.tikTokMaxDurationSeconds : null)!;
    if (widget.sourceDurationSeconds < (rule.minimumSeconds ?? 0)) {
      return clipSplitText(
          context,
          'ต้องยาวอย่างน้อย ${rule.minimumSeconds} วินาที',
          'At least ${rule.minimumSeconds} seconds required');
    }
    final maximum = formatClipSplitTime(rule.maximumSeconds.toDouble());
    if (platform == SocialPlatform.tiktok) {
      return widget.tikTokDirectPost
          ? clipSplitText(context, 'โพสต์ตรง · สูงสุด $maximum นาที',
              'Direct post · Up to $maximum min')
          : clipSplitText(context, 'ส่งไปร่างใน TikTok · สูงสุด $maximum นาที',
              'Send to TikTok drafts · Up to $maximum min');
    }
    return clipSplitText(context, 'สูงสุด $maximum นาที', 'Up to $maximum min');
  }

  Widget _modeChoices() => PostDeeCard(
        child: RadioGroup<ClipSplitMode>(
          groupValue: _mode,
          onChanged: (mode) {
            if (mode == null || _ownerChanged || _previewing) return;
            setState(() {
              _mode = mode;
              _retainCompatibleRanges();
            });
          },
          child: Column(children: [
            _selectionSurface(
                selected: _mode == ClipSplitMode.affectedChannels,
                child: RadioListTile<ClipSplitMode>(
                  key: const ValueKey('clip-split-mode-affected'),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: AppTheme.spaceSm),
                  value: ClipSplitMode.affectedChannels,
                  title: Text(clipSplitText(context,
                      'แบ่งเฉพาะช่องทางที่ยาวเกิน', 'Split only where needed')),
                  subtitle: Text(clipSplitText(
                      context,
                      'แนะนำ · ช่องทางที่ลงเต็มได้ ใช้คลิปเดิม',
                      'Recommended · Keep the full video where it fits')),
                )),
            const SizedBox(height: AppTheme.spaceSm),
            _selectionSurface(
                selected: _mode == ClipSplitMode.sameParts,
                child: RadioListTile<ClipSplitMode>(
                  key: const ValueKey('clip-split-mode-all'),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: AppTheme.spaceSm),
                  value: ClipSplitMode.sameParts,
                  title: Text(clipSplitText(context, 'ใช้ตอนเดียวกันทุกช่องทาง',
                      'Use the same parts everywhere')),
                  subtitle: Text(clipSplitText(
                      context,
                      'จุดตัดและจำนวนตอนตรงกันทุกช่องทาง',
                      'Keep the cuts and part counts the same')),
                )),
          ]),
        ),
      );

  Widget _channelTabs(ClipSplitPlan plan) => LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns = constraints.maxWidth >= 380 &&
              MediaQuery.textScalerOf(context).scale(14) <= 18;
          final width = twoColumns
              ? (constraints.maxWidth - AppTheme.spaceSm) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: AppTheme.spaceSm,
            runSpacing: AppTheme.spaceSm,
            children: [
              for (final platform in _available.where(_selected.contains))
                SizedBox(
                  width: width,
                  child: Semantics(
                    selected: _active == platform,
                    child: PostDeePressFeedback(
                        enabled: !_ownerChanged && !_previewing,
                        child: OutlinedButton(
                          key: ValueKey('clip-split-tab-${platform.apiValue}'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.all(AppTheme.spaceMd),
                            backgroundColor: _active == platform
                                ? AppTheme.mint
                                : AppTheme.glass,
                            foregroundColor: _active == platform
                                ? AppTheme.accentCyanInk
                                : AppTheme.textPrimary,
                            side: BorderSide(
                                color: _active == platform
                                    ? AppTheme.accentCyanInk
                                    : AppTheme.border),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppTheme.tileRadius)),
                          ),
                          onPressed: _ownerChanged || _previewing
                              ? null
                              : () => setState(() => _active = platform),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(platform.label, textAlign: TextAlign.center),
                              const SizedBox(height: AppTheme.spaceXs),
                              Text(
                                _isFullVideo(plan.channelPlanFor(platform))
                                    ? clipSplitText(
                                        context, 'คลิปเต็ม', 'Full video')
                                    : clipSplitPartsText(
                                        context,
                                        plan
                                            .channelPlanFor(platform)
                                            .segments
                                            .length),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )),
                  ),
                ),
            ],
          );
        },
      );

  Widget _segments(ClipSplitChannelPlan channel) => PostDeeCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SocialPlatformLogo(platform: channel.platform),
            const SizedBox(width: AppTheme.spaceSm),
            Expanded(
                child: Text(channel.platform.label,
                    style: Theme.of(context).textTheme.titleSmall)),
          ]),
          const SizedBox(height: AppTheme.spaceMd),
          ClipSplitTimeline(
            key: const ValueKey('clip-split-timeline'),
            sourceDurationSeconds: widget.sourceDurationSeconds,
            segments: channel.segments,
          ),
          const SizedBox(height: AppTheme.spaceSm),
          for (var index = 0; index < channel.segments.length; index++) ...[
            if (index > 0) Divider(height: 1, color: AppTheme.borderSoft),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceMd),
              child: Column(children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ExcludeSemantics(
                    child: Container(
                      width: AppTheme.spaceXl + AppTheme.spaceLg,
                      height: AppTheme.spaceXl + AppTheme.spaceLg,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.mint,
                        borderRadius:
                            BorderRadius.circular(AppTheme.tileRadius),
                      ),
                      child: _isFullVideo(channel)
                          ? Icon(Icons.movie_outlined,
                              color: AppTheme.accentCyanInk, size: 20)
                          : Text('${index + 1}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(color: AppTheme.accentCyanInk)),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spaceMd),
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          _isFullVideo(channel)
                              ? clipSplitText(context, 'คลิปเต็ม', 'Full video')
                              : clipSplitText(context, 'ตอน ${index + 1}',
                                  'Part ${index + 1}'),
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: AppTheme.spaceXs),
                      Text(
                          '${formatClipSplitTime(channel.segments[index].startSeconds)}–${formatClipSplitTime(channel.segments[index].endSeconds)}',
                          style: TextStyle(color: AppTheme.textSecondary)),
                      Text(
                          clipSplitText(
                              context,
                              'ยาว ${formatClipSplitTime(channel.segments[index].durationSeconds)} นาที',
                              'Length ${formatClipSplitTime(channel.segments[index].durationSeconds)} min'),
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  )),
                ]),
                const SizedBox(height: AppTheme.spaceXs),
                Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppTheme.spaceSm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (channel.segments.length > 1)
                        PostDeePressFeedback(
                            enabled: !_previewing && !_ownerChanged,
                            child: TextButton.icon(
                              key: ValueKey('clip-split-range-$index'),
                              onPressed: _previewing || _ownerChanged
                                  ? null
                                  : () => _editRange(channel, index),
                              icon: const Icon(Icons.tune, size: 18),
                              label: Text(clipSplitText(
                                  context, 'ปรับช่วงเวลา', 'Edit time range')),
                            )),
                      PostDeePressFeedback(
                          enabled: !_previewing &&
                              !_ownerChanged &&
                              (widget.videoFile != null ||
                                  widget.previewSegment != null),
                          child: IconButton(
                            key: ValueKey('clip-split-preview-$index'),
                            tooltip: clipSplitText(context, 'ดูตัวอย่างตอนนี้',
                                'Preview this part'),
                            onPressed: _previewing ||
                                    _ownerChanged ||
                                    (widget.videoFile == null &&
                                        widget.previewSegment == null)
                                ? null
                                : () => _preview(channel.segments[index]),
                            style: IconButton.styleFrom(
                              backgroundColor: AppTheme.glassDeep,
                              foregroundColor: AppTheme.accentCyanInk,
                            ),
                            icon: const Icon(Icons.play_arrow_rounded),
                          )),
                    ]),
              ]),
            ),
          ],
          if (_hasGaps(channel)) ...[
            const SizedBox(height: AppTheme.spaceSm),
            _notice(clipSplitText(
                context,
                'ช่วงที่เว้นไว้จะไม่รวมอยู่ในคลิปที่เตรียม',
                'Skipped ranges will not be included in the prepared clips.')),
          ],
        ]),
      );

  List<Widget> _review(ClipSplitPlan plan) => [
        Text(
            clipSplitText(
                context, 'เตรียมคลิปตามแผนนี้', 'Prepare these clips'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppTheme.spaceMd),
        PostDeeCard(
            child: Column(children: [
          for (final platform in _available.where(_selected.contains)) ...[
            if (platform != _available.where(_selected.contains).first)
              Divider(height: 1, color: AppTheme.borderSoft),
            Padding(
                padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceMd),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: Text(platform.label)),
                            const SizedBox(width: AppTheme.spaceSm),
                            Text(_isFullVideo(plan.channelPlanFor(platform))
                                ? clipSplitText(
                                    context, 'คลิปเต็ม', 'Full video')
                                : clipSplitPartsText(
                                    context,
                                    plan
                                        .channelPlanFor(platform)
                                        .segments
                                        .length)),
                          ]),
                      for (var index = 0;
                          index < plan.channelPlanFor(platform).segments.length;
                          index++)
                        Text(
                            clipSplitText(
                                context,
                                'ตอน ${index + 1} · ${formatClipSplitTime(plan.channelPlanFor(platform).segments[index].startSeconds)}–${formatClipSplitTime(plan.channelPlanFor(platform).segments[index].endSeconds)}',
                                'Part ${index + 1} · ${formatClipSplitTime(plan.channelPlanFor(platform).segments[index].startSeconds)}–${formatClipSplitTime(plan.channelPlanFor(platform).segments[index].endSeconds)}'),
                            style: TextStyle(color: AppTheme.textSecondary)),
                      if (_hasGaps(plan.channelPlanFor(platform)))
                        Text(
                            clipSplitText(
                                context,
                                'ช่วงที่เว้นไว้จะไม่รวมอยู่ในคลิปที่เตรียม',
                                'Skipped ranges will not be included in the prepared clips.'),
                            style: Theme.of(context).textTheme.bodySmall),
                    ])),
          ],
        ])),
        const SizedBox(height: AppTheme.spaceLg),
        Text(clipSplitText(
            context,
            'เตรียม ${plan.groupedParts.length} คลิปเป็นชุดเดียวและเก็บไว้ในเครื่อง',
            'Prepare ${plan.groupedParts.length} ${plan.groupedParts.length == 1 ? 'clip' : 'clips'} as one set and save them on this device.')),
        const SizedBox(height: AppTheme.spaceSm),
        Text(
            clipSplitText(
                context,
                'ตรวจแคปชั่น หน้าปก และเวลาส่งแยกแต่ละคลิป แล้วค่อยยืนยันส่งทั้งชุด ไม่มีการโพสต์อัตโนมัติ',
                'Review each clip’s caption, cover and posting time, then confirm the entire set before posting. Nothing is posted automatically.'),
            style: TextStyle(color: AppTheme.textSecondary)),
      ];

  Widget _quotaSummary(ClipSplitPlan plan) => Semantics(
        liveRegion: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(clipSplitUnitsText(context, plan.totalPostUnits),
              key: const ValueKey('clip-split-total-units'),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: AppTheme.accentCyanInk)),
          const SizedBox(height: AppTheme.spaceXs),
          Text(
              clipSplitText(
                  context,
                  'หากสร้างโพสต์ครบทุกตอน · 1 ตอน × 1 ช่องทาง = 1 หน่วย',
                  'If every part is submitted · 1 part × 1 channel = 1 unit'),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.textSecondary)),
          const SizedBox(height: AppTheme.spaceXs),
          Text(
              clipSplitText(context, 'การแบ่งคลิปและเก็บร่างยังไม่ใช้โควตา',
                  'Splitting and saving drafts do not use post units.'),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.textSecondary)),
        ]),
      );

  Widget _notice(String message) => Text(message,
      style: TextStyle(color: Theme.of(context).colorScheme.error));
}

class _ClipSplitRangeDialog extends StatefulWidget {
  const _ClipSplitRangeDialog(
      {required this.segment,
      required this.sourceDuration,
      required this.availableStart,
      required this.availableEnd,
      required this.minimumDuration,
      required this.maximumDuration,
      required this.shared,
      required this.owner,
      required this.validate,
      this.onPreview});

  final ClipSplitSegment segment;
  final double sourceDuration;
  final double availableStart;
  final double availableEnd;
  final double minimumDuration;
  final double maximumDuration;
  final bool shared;
  final AuthSessionBinding owner;
  final ClipSplitPlan Function(ClipSplitSegment) validate;
  final Future<void> Function(ClipSplitSegment)? onPreview;

  @override
  State<_ClipSplitRangeDialog> createState() => _ClipSplitRangeDialogState();
}

class _ClipSplitRangeDialogState extends State<_ClipSplitRangeDialog> {
  static const _ticksPerSecond = 1000000;
  static int _ticks(double seconds) => (seconds * _ticksPerSecond).round();

  // Displaying whole seconds must not rewrite an untouched measured boundary.
  late double? _startSeconds =
      _ticks(widget.segment.startSeconds) / _ticksPerSecond;
  late double? _endSeconds =
      _ticks(widget.segment.endSeconds) / _ticksPerSecond;
  late final _start = TextEditingController(
      text: formatClipSplitTime(widget.segment.startSeconds));
  late final _end = TextEditingController(
      text: formatClipSplitTime(widget.segment.endSeconds));
  bool _previewing = false;
  ClipSplitPlanProblem? _problem;
  bool _invalidFormat = false;
  String? _previewError;

  @override
  void initState() {
    super.initState();
    PostDeeAuthSessionStore.instance.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (mounted && !widget.owner.isCurrent) setState(() {});
  }

  @override
  void dispose() {
    PostDeeAuthSessionStore.instance.removeListener(_sessionChanged);
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  double? _parse(String input) {
    final match =
        RegExp(r'^(\d+):([0-5]\d)(?:\.(\d{1,6}))?$').firstMatch(input.trim());
    if (match == null) return null;
    final minutes = double.tryParse(match[1]!);
    if (minutes == null || !minutes.isFinite) return null;
    return minutes * 60 +
        int.parse(match[2]!) +
        (match[3] == null
            ? 0
            : int.parse(match[3]!.padRight(6, '0')) / 1000000);
  }

  ClipSplitSegment? get _segment {
    final start = _startSeconds;
    final end = _endSeconds;
    return start == null || end == null
        ? null
        : ClipSplitSegment(startSeconds: start, endSeconds: end);
  }

  ClipSplitPlan? _validated() {
    final segment = _segment;
    if (segment == null) {
      setState(() {
        _invalidFormat = true;
        _problem = null;
      });
      return null;
    }
    try {
      return widget.validate(segment);
    } on ClipSplitPlanException catch (error) {
      setState(() {
        _problem = error.problem;
        _invalidFormat = false;
      });
      return null;
    }
  }

  void _changed(String input, {required bool start}) => setState(() {
        if (start) {
          _startSeconds = _parse(input);
        } else {
          _endSeconds = _parse(input);
        }
        _problem = null;
        _invalidFormat = false;
        _previewError = null;
      });

  double _snapSecond(double candidate,
      {required int lower, required int upper, required double fallback}) {
    final firstSecond = (lower / _ticksPerSecond).ceil();
    final lastSecond = upper ~/ _ticksPerSecond;
    // A narrow legal range can contain only a fractional boundary. Keep it.
    if (lower > upper || firstSecond > lastSecond) return fallback;
    return candidate.round().clamp(firstSecond, lastSecond).toDouble();
  }

  void _sliderChanged(RangeValues values, RangeValues previous) {
    var start = previous.start;
    var end = previous.end;
    final minimum = math.max(1, _ticks(widget.minimumDuration));
    final maximum = _ticks(widget.maximumDuration);
    final availableStart = math.max(0, _ticks(widget.availableStart));
    final availableEnd =
        math.min(_ticks(widget.sourceDuration), _ticks(widget.availableEnd));
    if (_ticks(values.start) != _ticks(previous.start)) {
      start = _snapSecond(values.start,
          lower: math.max(availableStart, _ticks(end) - maximum),
          upper: math.min(availableEnd, _ticks(end) - minimum),
          fallback: start);
    } else if (_ticks(values.end) != _ticks(previous.end)) {
      end = _snapSecond(values.end,
          lower: math.max(availableStart, _ticks(start) + minimum),
          upper: math.min(availableEnd, _ticks(start) + maximum),
          fallback: end);
    }
    setState(() {
      _startSeconds = start;
      _endSeconds = end;
      _start.text = formatClipSplitTime(start);
      _end.text = formatClipSplitTime(end);
      _problem = null;
      _invalidFormat = false;
      _previewError = null;
    });
  }

  Future<void> _preview() async {
    if (!widget.owner.isCurrent || _previewing || _validated() == null) return;
    final segment = _segment!;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _previewing = true;
      _previewError = null;
    });
    try {
      await widget.onPreview!(segment);
    } catch (_) {
      if (mounted && widget.owner.isCurrent) {
        setState(() => _previewError = clipSplitText(
            context,
            'ยังเปิดตัวอย่างคลิปไม่ได้ ลองอีกครั้ง',
            'Could not open the video preview. Try again.'));
      }
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.owner.isCurrent && !_previewing;
    final segment = _segment;
    final sliderValid = segment != null &&
        segment.startSeconds >= 0 &&
        segment.endSeconds > segment.startSeconds &&
        segment.endSeconds <= widget.sourceDuration;
    final sliderValues = sliderValid
        ? RangeValues(segment.startSeconds, segment.endSeconds)
        : RangeValues(widget.segment.startSeconds, widget.segment.endSeconds);
    return PopScope(
      canPop: !_previewing,
      child: AlertDialog(
        key: const ValueKey('clip-split-range-dialog'),
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spaceLg, vertical: AppTheme.spaceMd),
        title: Text(clipSplitText(context, 'ปรับช่วงเวลา', 'Edit time range')),
        content: SizedBox(
            width: 440,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(clipSplitText(
                      context,
                      'ต้นฉบับ 0:00–${formatClipSplitTime(widget.sourceDuration)}',
                      'Original 0:00–${formatClipSplitTime(widget.sourceDuration)}')),
                  const SizedBox(height: AppTheme.spaceSm),
                  Text(clipSplitText(
                      context,
                      'ช่วงที่เลือกได้ตอนนี้ ${formatClipSplitTime(widget.availableStart)}–${formatClipSplitTime(widget.availableEnd)}',
                      'Available source range ${formatClipSplitTime(widget.availableStart)}–${formatClipSplitTime(widget.availableEnd)}')),
                  const SizedBox(height: AppTheme.spaceSm),
                  Text(
                      clipSplitText(
                          context,
                          widget.minimumDuration > 0
                              ? 'ความยาวตอน ${formatClipSplitTime(widget.minimumDuration)}–${formatClipSplitTime(widget.maximumDuration)} นาที'
                              : 'ความยาวตอนต้องมากกว่า 0 และไม่เกิน ${formatClipSplitTime(widget.maximumDuration)} นาที',
                          widget.minimumDuration > 0
                              ? 'Part length ${formatClipSplitTime(widget.minimumDuration)}–${formatClipSplitTime(widget.maximumDuration)} min'
                              : 'Part length must be above 0 and up to ${formatClipSplitTime(widget.maximumDuration)} min'),
                      style: Theme.of(context).textTheme.bodySmall),
                  if (widget.shared) ...[
                    const SizedBox(height: AppTheme.spaceSm),
                    Text(
                        clipSplitText(
                            context,
                            'ใช้ช่วงเวลานี้กับทุกช่องทางที่เลือก',
                            'Apply this range to every selected channel.'),
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const SizedBox(height: AppTheme.spaceLg),
                  TextField(
                      key: const ValueKey('clip-split-range-start'),
                      controller: _start,
                      enabled: enabled,
                      onChanged: (value) => _changed(value, start: true),
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                          labelText: clipSplitText(context,
                              'เวลาเริ่ม (นาที:วินาที)', 'Start (M:SS)'),
                          hintText: '0:00',
                          border: const OutlineInputBorder())),
                  const SizedBox(height: AppTheme.spaceMd),
                  TextField(
                      key: const ValueKey('clip-split-range-end'),
                      controller: _end,
                      enabled: enabled,
                      onChanged: (value) => _changed(value, start: false),
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                          labelText: clipSplitText(
                              context, 'เวลาจบ (นาที:วินาที)', 'End (M:SS)'),
                          hintText: '0:00',
                          border: const OutlineInputBorder())),
                  RangeSlider(
                      key: const ValueKey('clip-split-range-slider'),
                      min: 0,
                      max: widget.sourceDuration,
                      values: sliderValues,
                      labels: RangeLabels(
                          formatClipSplitTime(sliderValid
                              ? segment.startSeconds
                              : widget.segment.startSeconds),
                          formatClipSplitTime(sliderValid
                              ? segment.endSeconds
                              : widget.segment.endSeconds)),
                      onChanged: !enabled
                          ? null
                          : (values) => _sliderChanged(values, sliderValues)),
                  if (segment != null && segment.durationSeconds > 0)
                    Text(clipSplitText(
                        context,
                        'ยาว ${formatClipSplitTime(segment.durationSeconds)} นาที',
                        'Length ${formatClipSplitTime(segment.durationSeconds)} min')),
                  if (_problem != null ||
                      _invalidFormat ||
                      !widget.owner.isCurrent)
                    Padding(
                        padding: const EdgeInsets.only(top: AppTheme.spaceSm),
                        child: Text(
                            !widget.owner.isCurrent
                                ? clipSplitText(
                                    context,
                                    'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดคลิปใหม่',
                                    'Your account has changed. Reopen the video.')
                                : _invalidFormat
                                    ? clipSplitText(
                                        context,
                                        'ใส่เวลาเป็น นาที:วินาที เช่น 1:30',
                                        'Enter M:SS, for example 1:30.')
                                    : clipSplitProblemText(context, _problem!),
                            key: const ValueKey('clip-split-range-error'),
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  if (_previewError != null) Text(_previewError!),
                  if (widget.onPreview != null)
                    TextButton.icon(
                        key: const ValueKey('clip-split-range-preview'),
                        onPressed: enabled ? _preview : null,
                        icon: const Icon(Icons.play_circle_outline),
                        label: Text(clipSplitText(context, 'ดูตัวอย่างช่วงนี้',
                            'Preview this range'))),
                ])),
        actions: [
          TextButton(
              key: const ValueKey('clip-split-range-cancel'),
              onPressed: _previewing ? null : () => Navigator.pop(context),
              child: Text(clipSplitText(context, 'ยกเลิก', 'Cancel'))),
          FilledButton(
              key: const ValueKey('clip-split-range-save'),
              onPressed: !enabled
                  ? null
                  : () {
                      final plan = _validated();
                      if (plan != null && widget.owner.isCurrent) {
                        Navigator.pop(context, plan);
                      }
                    },
              child:
                  Text(clipSplitText(context, 'บันทึกช่วงเวลา', 'Save range'))),
        ],
      ),
    );
  }
}

class _ClipRangePreviewScreen extends StatefulWidget {
  const _ClipRangePreviewScreen(
      {required this.file, required this.segment, required this.owner});
  final File file;
  final ClipSplitSegment segment;
  final AuthSessionBinding owner;
  @override
  State<_ClipRangePreviewScreen> createState() =>
      _ClipRangePreviewScreenState();
}

class _ClipRangePreviewScreenState extends State<_ClipRangePreviewScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _failed = false;
  bool _ended = false;
  bool _commandPending = false;
  bool _foreground = true;

  Duration get _start =>
      Duration(milliseconds: (widget.segment.startSeconds * 1000).round());
  Duration get _end =>
      Duration(milliseconds: (widget.segment.endSeconds * 1000).round());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PostDeeAuthSessionStore.instance.addListener(_sessionChanged);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (widget.owner.isCurrent) {
      unawaited(_initialize());
    } else {
      _loading = false;
      _failed = true;
    }
  }

  Future<void> _initialize() async {
    final controller = VideoPlayerController.file(widget.file);
    _controller = controller;
    try {
      await controller.initialize().timeout(const Duration(seconds: 15));
      if (!mounted ||
          !widget.owner.isCurrent ||
          !identical(_controller, controller)) {
        return;
      }
      await controller.seekTo(_start).timeout(const Duration(seconds: 5));
      if (!mounted || !widget.owner.isCurrent) return;
      controller.addListener(_checkEnd);
      setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _sessionChanged() {
    if (widget.owner.isCurrent) return;
    final controller = _controller;
    if (controller != null) unawaited(controller.pause().catchError((_) {}));
    if (mounted) {
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _checkEnd() {
    final controller = _controller;
    if (controller == null || !mounted || _ended) return;
    if (controller.value.position >= _end) {
      _ended = true;
      unawaited(controller.pause().catchError((_) {}));
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    final controller = _controller;
    if (!_foreground && controller != null) {
      unawaited(controller.pause().catchError((_) {}));
    }
    if (mounted) setState(() {});
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null ||
        _commandPending ||
        !_foreground ||
        !widget.owner.isCurrent) {
      return;
    }
    setState(() => _commandPending = true);
    try {
      if (controller.value.isPlaying) {
        await controller.pause().timeout(const Duration(seconds: 5));
      } else {
        if (_ended || controller.value.position >= _end) {
          await controller.seekTo(_start).timeout(const Duration(seconds: 5));
        }
        if (!mounted || !_foreground || !widget.owner.isCurrent) return;
        _ended = false;
        await controller.play().timeout(const Duration(seconds: 5));
        if (!mounted ||
            !_foreground ||
            !widget.owner.isCurrent ||
            _ended ||
            controller.value.position >= _end) {
          await controller.pause().timeout(const Duration(seconds: 5));
        }
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _commandPending = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PostDeeAuthSessionStore.instance.removeListener(_sessionChanged);
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_checkEnd);
    if (controller != null) unawaited(controller.dispose().catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
          title: Text(
              clipSplitText(context, 'ดูตัวอย่างตอนนี้', 'Preview this part'))),
      body: SafeArea(
          child: Center(
              child: Padding(
        padding: AppTheme.screenPadding,
        child: Column(children: [
          Text(
              '${formatClipSplitTime(widget.segment.startSeconds)}–${formatClipSplitTime(widget.segment.endSeconds)}'),
          const SizedBox(height: AppTheme.spaceLg),
          Expanded(
              child: Center(
                  child: _loading
                      ? const CircularProgressIndicator()
                      : _failed || controller == null
                          ? Text(clipSplitText(
                              context,
                              'ยังเปิดตัวอย่างคลิปไม่ได้ กรุณากลับไปลองใหม่',
                              'Could not open this preview. Go back and try again.'))
                          : AspectRatio(
                              aspectRatio: controller.value.aspectRatio,
                              child: VideoPlayer(controller)))),
          const SizedBox(height: AppTheme.spaceLg),
          if (!_loading && !_failed && controller != null)
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: controller,
              builder: (context, value, _) => FilledButton.icon(
                onPressed:
                    _commandPending || !_foreground || !widget.owner.isCurrent
                        ? null
                        : _togglePlayback,
                icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                label: Text(clipSplitText(
                    context,
                    value.isPlaying ? 'หยุดตัวอย่าง' : 'เล่นตอนนี้',
                    value.isPlaying ? 'Pause preview' : 'Play this part')),
              ),
            ),
          const SizedBox(height: AppTheme.spaceLg),
        ]),
      ))),
    );
  }
}
