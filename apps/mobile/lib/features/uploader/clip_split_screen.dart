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
import 'clip_split_localizations.dart';
import 'clip_split_plan.dart';
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
  final _boundaries = <SocialPlatform, double>{};
  final _scrollController = ScrollController();
  late final AuthSessionBinding _owner;
  ClipSplitMode _mode = ClipSplitMode.affectedChannels;
  SocialPlatform? _active;
  bool _reviewing = false;
  bool _previewing = false;
  bool _ownerChanged = false;
  String? _previewError;

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

  ClipSplitPlan _createPlan() => ClipSplitPlan.create(
        sourceDurationSeconds: widget.sourceDurationSeconds,
        platforms: _selected,
        mode: _mode,
        tikTokDirectPost: widget.tikTokDirectPost,
        tikTokMaxDurationSeconds: widget.tikTokMaxDurationSeconds,
        firstBoundaries: _boundaries,
      );

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
                if (plan != null && active != null) ...[
                  _channelTabs(plan),
                  const SizedBox(height: AppTheme.spaceLg),
                  _segments(active),
                  if (active.canAdjustFirstBoundary) ...[
                    const SizedBox(height: AppTheme.spaceLg),
                    _adjustBoundary(active),
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
                    child: FilledButton(
                      key: ValueKey(_reviewing
                          ? 'clip-split-confirm'
                          : 'clip-split-review'),
                      onPressed: plan == null || _ownerChanged || _previewing
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
                                    ? 'ยืนยันแบ่งคลิป · เตรียมร่าง'
                                    : 'ใช้แผนนี้ · ตรวจรายการ',
                                _reviewing
                                    ? 'Confirm split · Prepare drafts'
                                    : 'Use this plan · Review'),
                            textAlign: TextAlign.center),
                      ),
                    )),
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
                color: AppTheme.glassDeep,
                borderRadius: BorderRadius.circular(AppTheme.tileRadius)),
            child: Padding(
                padding: const EdgeInsets.all(AppTheme.spaceLg),
                child:
                    Icon(Icons.movie_outlined, color: AppTheme.accentCyanInk)),
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
              Divider(height: 1, color: AppTheme.borderSoft),
            CheckboxListTile(
              key: ValueKey('clip-split-channel-${platform.apiValue}'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _selected.contains(platform),
              title: Text(platform.label),
              subtitle: Text(_channelLimit(platform)),
              onChanged: !_canSelect(platform) || _ownerChanged
                  ? null
                  : (checked) {
                      setState(() {
                        checked == true
                            ? _selected.add(platform)
                            : _selected.remove(platform);
                        _boundaries.clear();
                        if (!_selected.contains(_active)) {
                          _active =
                              _available.where(_selected.contains).firstOrNull;
                        }
                      });
                    },
            ),
          ],
        ]),
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
          : clipSplitText(context, 'ส่งเป็นร่าง · สูงสุด $maximum นาที',
              'Send to drafts · Up to $maximum min');
    }
    return clipSplitText(context, 'สูงสุด $maximum นาที', 'Up to $maximum min');
  }

  Widget _modeChoices() => PostDeeCard(
        child: RadioGroup<ClipSplitMode>(
          groupValue: _mode,
          onChanged: (mode) {
            if (mode == null || _ownerChanged) return;
            setState(() {
              _mode = mode;
              _boundaries.clear();
            });
          },
          child: Column(children: [
            RadioListTile<ClipSplitMode>(
              key: const ValueKey('clip-split-mode-affected'),
              contentPadding: EdgeInsets.zero,
              value: ClipSplitMode.affectedChannels,
              title: Text(clipSplitText(context, 'แบ่งเฉพาะช่องทางที่ยาวเกิน',
                  'Split only where needed')),
              subtitle: Text(clipSplitText(
                  context,
                  'แนะนำ · ช่องทางที่ลงเต็มได้ ใช้คลิปเดิม',
                  'Recommended · Keep the full video where it fits')),
            ),
            Divider(height: 1, color: AppTheme.borderSoft),
            RadioListTile<ClipSplitMode>(
              key: const ValueKey('clip-split-mode-all'),
              contentPadding: EdgeInsets.zero,
              value: ClipSplitMode.sameParts,
              title: Text(clipSplitText(context, 'ใช้ตอนเดียวกันทุกช่องทาง',
                  'Use the same parts everywhere')),
              subtitle: Text(clipSplitText(
                  context,
                  'จุดตัดและจำนวนตอนตรงกันทุกช่องทาง',
                  'Keep the cuts and part counts the same')),
            ),
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
                      onPressed: _ownerChanged
                          ? null
                          : () => setState(() => _active = platform),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(platform.label, textAlign: TextAlign.center),
                          const SizedBox(height: AppTheme.spaceXs),
                          Text(
                            plan.channelPlanFor(platform).segments.length == 1
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
                    ),
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
          for (var index = 0; index < channel.segments.length; index++) ...[
            if (index > 0) Divider(height: 1, color: AppTheme.borderSoft),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceSm),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppTheme.spaceSm,
                runSpacing: AppTheme.spaceXs,
                children: [
                  Text(channel.segments.length == 1
                      ? clipSplitText(context, 'คลิปเต็ม', 'Full video')
                      : clipSplitText(
                          context, 'ตอน ${index + 1}', 'Part ${index + 1}')),
                  Text(
                      '${formatClipSplitTime(channel.segments[index].startSeconds)}–${formatClipSplitTime(channel.segments[index].endSeconds)}',
                      style: TextStyle(color: AppTheme.textSecondary)),
                  IconButton(
                    key: ValueKey('clip-split-preview-$index'),
                    tooltip: clipSplitText(
                        context, 'ดูตัวอย่างตอนนี้', 'Preview this part'),
                    onPressed: _previewing ||
                            _ownerChanged ||
                            (widget.videoFile == null &&
                                widget.previewSegment == null)
                        ? null
                        : () => _preview(channel.segments[index]),
                    icon: const Icon(Icons.play_circle_outline),
                  ),
                ],
              ),
            ),
          ],
        ]),
      );

  Widget _adjustBoundary(ClipSplitChannelPlan channel) {
    final lower = channel.minimumFirstBoundarySeconds!;
    final upper = channel.maximumFirstBoundarySeconds!;
    final boundary = channel.segments.first.endSeconds;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(clipSplitText(
          context,
          'ปรับจุดจบตอนแรก · ${formatClipSplitTime(boundary)}',
          'First cut · ${formatClipSplitTime(boundary)}')),
      Slider(
        key: const ValueKey('clip-split-first-boundary'),
        min: lower,
        max: upper,
        value: boundary.clamp(lower, upper),
        divisions:
            math.min(1000, ((upper - lower) * 10).round()).clamp(1, 1000),
        label: formatClipSplitTime(boundary),
        onChanged: _ownerChanged
            ? null
            : (value) => setState(() {
                  if (_mode == ClipSplitMode.sameParts) {
                    for (final platform in _selected) {
                      _boundaries[platform] = value;
                    }
                  } else {
                    _boundaries[channel.platform] = value;
                  }
                }),
      ),
      Text(
          clipSplitText(context, 'ตอนถัดไปจะปรับตาม โดยเก็บเนื้อหาครบ',
              'Later parts adjust to keep all your content.'),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppTheme.textSecondary)),
    ]);
  }

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
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(platform.label)),
                      const SizedBox(width: AppTheme.spaceSm),
                      Text(plan.channelPlanFor(platform).segments.length == 1
                          ? clipSplitText(context, 'คลิปเต็ม', 'Full video')
                          : clipSplitPartsText(context,
                              plan.channelPlanFor(platform).segments.length)),
                    ])),
          ],
        ])),
        const SizedBox(height: AppTheme.spaceLg),
        Text(clipSplitText(
            context,
            'เตรียม ${plan.groupedParts.length} ร่างในเครื่อง แต่ละร่างมีแคปชั่น หน้าปก และเวลาส่งของตัวเอง',
            'Prepare ${plan.groupedParts.length} drafts on this device. Each draft has its own caption, cover and posting time.')),
        const SizedBox(height: AppTheme.spaceSm),
        Text(
            clipSplitText(
                context,
                'ตรวจทานและส่งแต่ละร่างจากขั้นตอนโพสต์เดิม ไม่มีการส่งโพสต์อัตโนมัติ',
                'Review and submit each draft using the existing posting flow. Nothing is posted automatically.'),
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
