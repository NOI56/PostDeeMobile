import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../shared/post_schedule_policy.dart';
import '../shared/postdee_card.dart';
import '../shared/postdee_time_picker.dart';
import '../platforms/social_platform.dart';
import 'clip_group_draft.dart';
import 'clip_group_localizations.dart';
import 'clip_group_submission.dart';
import 'clip_split_localizations.dart';
import 'platform_publish_preflight.dart';
import 'post_video_preview_screen.dart';
import 'publish_draft.dart';
import 'publish_review_screen.dart';
import 'review_localizations.dart';

enum ClipGroupEditSection { caption, cover, channels }

typedef ClipGroupDatePicker = Future<DateTime?> Function(
    BuildContext context, DateTime initial, DateTime first, DateTime last);
typedef ClipGroupTimePicker = Future<TimeOfDay?> Function(
    BuildContext context, TimeOfDay initial, DateTime? date);

/// Reviews prepared local files together. Persistence, existing per-clip consent
/// and the actual posting pipeline remain caller-owned.
class ClipGroupReviewScreen extends StatefulWidget {
  const ClipGroupReviewScreen({
    super.key,
    required this.initialGroup,
    required this.draftsById,
    required this.ownerSession,
    required this.onSaveGroup,
    required this.onSaveCaption,
    required this.onEditClip,
    required this.onReloadGroup,
    required this.onSubmit,
    required this.loadSubscription,
    required this.loadPostQuota,
    this.now = DateTime.now,
    this.pickDate,
    this.pickTime,
    this.previewClip,
    this.connectionDisplayNames = const {},
  });
  final ClipGroupDraft initialGroup;
  final Map<String, PublishDraft> draftsById;
  final AuthSessionBinding ownerSession;
  final Future<ClipGroupDraft> Function(ClipGroupDraft) onSaveGroup;
  final Future<PublishDraft> Function(PublishDraft, String) onSaveCaption;
  final Future<PublishDraft?> Function(PublishDraft, ClipGroupEditSection)
      onEditClip;
  final Future<ClipGroupDraft> Function() onReloadGroup;
  final Future<ClipGroupSubmissionResult> Function(
      ClipGroupDraft, void Function(ClipGroupSubmissionProgress)) onSubmit;
  final Future<SubscriptionStatusResult> Function() loadSubscription;
  final Future<SubscriptionStatusResult> Function() loadPostQuota;
  final DateTime Function() now;
  final ClipGroupDatePicker? pickDate;
  final ClipGroupTimePicker? pickTime;
  final Future<void> Function(PublishDraft)? previewClip;
  final Map<SocialPlatform, String> connectionDisplayNames;
  @override
  State<ClipGroupReviewScreen> createState() => _ClipGroupReviewScreenState();
}

class _ClipGroupReviewScreenState extends State<ClipGroupReviewScreen> {
  late ClipGroupDraft _group;
  late final Map<String, PublishDraft> _drafts;
  late final TextEditingController _sharedCaption;
  final _scroll = ScrollController();
  final _dates = <String, DateTime>{};
  final _times = <String, TimeOfDay>{};
  SubscriptionStatusResult? _subscription;
  SubscriptionStatusResult? _quota;
  int _stage = 0;
  bool _busy = false;
  bool _navigating = false;
  bool _dirty = false;
  bool _checking = false;
  bool _quotaFailed = false;
  bool _result = false;
  bool _showSharedCaption = false;
  bool _ownerChanged = false;
  String? _error;
  String? _message;
  ClipGroupSubmissionProgress? _progress;

  String _text(String th, String en) => clipGroupText(context, th, en);
  List<ClipGroupItem> get _pending =>
      _group.items.where((item) => !item.isAccepted).toList();
  bool get _owned =>
      widget.ownerSession.isCurrent &&
      !_ownerChanged &&
      widget.ownerSession.userId == _group.ownerUserId;
  bool _hasReceipt(ClipGroupItem item) =>
      !item.isAccepted && _drafts[item.draftId]?.uploadedMedia != null;
  bool get _hasUnresolved => _pending.any(_hasReceipt);
  bool _editable(ClipGroupItem item) =>
      _owned &&
      !_busy &&
      !_navigating &&
      !item.isAccepted &&
      _drafts[item.draftId] != null &&
      !_hasReceipt(item);
  int get _pendingUnits =>
      _pending.fold(0, (sum, item) => sum + item.platformApiValues.length);
  int get _freshUnits => _pending
      .where((item) => !_hasReceipt(item))
      .fold(0, (sum, item) => sum + item.platformApiValues.length);
  bool get _missing => _pending.any((item) => _drafts[item.draftId] == null);

  @override
  void initState() {
    super.initState();
    _group = widget.initialGroup;
    _result = _group.isComplete;
    _drafts = Map.of(widget.draftsById);
    _sharedCaption = TextEditingController(text: _group.sharedCaption);
    _sharedCaption.addListener(() {
      _dirty = true;
    });
    _ownerChanged = !widget.ownerSession.isCurrent;
    PostDeeAuthSessionStore.instance.addListener(_sessionChanged);
    _syncDates();
    unawaited(_loadQuota());
  }

  void _syncDates() {
    for (final item in _group.items) {
      final at = item.scheduledAt?.toLocal();
      if (at != null) {
        _dates[item.draftId] = DateTime(at.year, at.month, at.day);
        _times[item.draftId] = TimeOfDay(hour: at.hour, minute: at.minute);
      }
    }
  }

  void _sessionChanged() {
    if (!mounted || widget.ownerSession.isCurrent) return;
    setState(() => _ownerChanged = true);
  }

  @override
  void dispose() {
    PostDeeAuthSessionStore.instance.removeListener(_sessionChanged);
    _sharedCaption.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadQuota() async {
    if (!_owned || _checking) return;
    setState(() {
      _checking = true;
      _quotaFailed = false;
    });
    try {
      final value = await widget.loadPostQuota();
      if (!mounted || !_owned) return;
      final available = _available(value);
      if (value.userId != _group.ownerUserId || available == null) {
        throw const FormatException('Quota unavailable');
      }
      setState(() => _quota = value);
    } catch (_) {
      if (mounted && _owned) {
        setState(() {
          _quota = null;
          _quotaFailed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  int? _available(SubscriptionStatusResult value) {
    final direct = value.availablePostUnits;
    if (direct != null) return direct >= 0 ? direct : null;
    final left = value.remainingPostsThisMonth;
    if (left == null || left < 0 || value.addonPostUnits < 0) return null;
    return left + (value.isPaid ? value.addonPostUnits : 0);
  }

  ClipGroupDraft _proposal() => _group.copyWith(
        sharedCaption: _sharedCaption.text,
        updatedAt: widget.now().toUtc().isBefore(_group.createdAt)
            ? _group.createdAt
            : widget.now().toUtc(),
      );
  void _checkReturnedGroup(ClipGroupDraft group) {
    if (!_owned ||
        group.id != _group.id ||
        group.ownerUserId != _group.ownerUserId) {
      throw const AuthSessionChangedException();
    }
  }

  void _syncDrafts() {
    _drafts
      ..clear()
      ..addAll(Map.fromEntries(widget.draftsById.entries
          .where((entry) => entry.value.ownerUserId == _group.ownerUserId)));
  }

  Future<void> _refreshAfterFailure() async {
    if (!mounted || !_owned) return;
    try {
      final current = await widget.onReloadGroup();
      if (!mounted || !_owned) return;
      _checkReturnedGroup(current);
      setState(() {
        _group = current;
        _syncDrafts();
      });
    } catch (_) {
      // Keep the local input if the saved state cannot be read yet.
    }
  }

  Future<bool> _save({bool feedback = false}) async {
    if (!_owned || _busy) return false;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final saved = await widget.onSaveGroup(_proposal());
      if (!mounted || !_owned) return false;
      _checkReturnedGroup(saved);
      setState(() {
        _group = saved;
        _syncDrafts();
        if (_sharedCaption.text != saved.sharedCaption) {
          _sharedCaption.text = saved.sharedCaption;
        }
        _dirty = false;
        if (feedback) {
          _message = _text('บันทึกทั้งชุดเป็นฉบับร่างแล้ว · ยังไม่ใช้โควตา',
              'The entire set is saved as a draft · No post units used');
        }
      });
      return true;
    } catch (_) {
      await _refreshAfterFailure();
      if (mounted && _owned) {
        setState(() {
          _dirty = true;
          _error = _text('บันทึกชุดคลิปไม่สำเร็จ กรุณาลองอีกครั้ง',
              'Could not save this set. Please try again.');
        });
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editCaption(ClipGroupItem item) async {
    if (!_editable(item) || !await _save()) return;
    if (!mounted || !_owned) return;
    final draft = _drafts[item.draftId]!;
    final next = await showDialog<String>(
        context: context,
        builder: (context) => _ClipGroupCaptionDialog(
            initialCaption: _caption(item), ownerSession: widget.ownerSession));
    if (next == null || !mounted || !_owned) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await widget.onSaveCaption(draft, next);
      final group = await widget.onReloadGroup();
      if (!mounted || !_owned) return;
      _checkReturnedGroup(group);
      if (updated.id != draft.id || updated.ownerUserId != _group.ownerUserId) {
        throw const AuthSessionChangedException();
      }
      setState(() {
        _syncDrafts();
        _drafts[draft.id] = updated;
        _group = group;
        if (_sharedCaption.text != group.sharedCaption) {
          _sharedCaption.text = group.sharedCaption;
        }
        _dirty = false;
      });
    } catch (_) {
      await _refreshAfterFailure();
      if (mounted && _owned) {
        setState(() => _error = _text('บันทึกแคปชั่นไม่สำเร็จ กรุณาลองใหม่',
            'Could not save the caption. Please try again.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(ClipGroupItem item, ClipGroupEditSection section) async {
    if (!_editable(item) || !await _save()) return;
    if (!mounted || !_owned) return;
    final draft = _drafts[item.draftId]!;
    setState(() => _busy = true);
    try {
      final updated = await widget.onEditClip(draft, section);
      final group = await widget.onReloadGroup();
      if (!mounted || !_owned) return;
      _checkReturnedGroup(group);
      if (updated != null &&
          (updated.id != draft.id ||
              updated.ownerUserId != _group.ownerUserId)) {
        throw const AuthSessionChangedException();
      }
      setState(() {
        _syncDrafts();
        if (updated != null) _drafts[draft.id] = updated;
        _group = group;
        if (_sharedCaption.text != group.sharedCaption) {
          _sharedCaption.text = group.sharedCaption;
        }
        _dirty = false;
      });
    } catch (_) {
      await _refreshAfterFailure();
      if (mounted && _owned) {
        setState(() => _error = _text('เปิดแก้ไขคลิปไม่สำเร็จ กรุณาลองใหม่',
            'Could not edit this clip. Please try again.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview(ClipGroupItem item) async {
    final draft = _drafts[item.draftId];
    if (draft == null || !_owned || _busy) return;
    setState(() => _busy = true);
    try {
      if (widget.previewClip != null) {
        await widget.previewClip!(draft);
      } else {
        await Navigator.push<void>(
            context,
            MaterialPageRoute(
                builder: (_) => PostVideoPreviewScreen(
                    videoFile: File(draft.videoPath),
                    videoName: draft.videoName,
                    ownerSession: widget.ownerSession)));
      }
    } catch (_) {
      if (mounted && _owned) {
        setState(() => _error = _text('เปิดตัวอย่างคลิปไม่ได้ กรุณาลองใหม่',
            'Could not open the preview. Please try again.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _loadSchedulePolicy() async {
    if (!_owned || _busy) return false;
    setState(() => _busy = true);
    try {
      final subscription = await widget.loadSubscription();
      if (!mounted || !_owned) return false;
      if (subscription.userId != _group.ownerUserId ||
          !subscription.canSchedule ||
          postScheduleLimitForPlan(subscription.plan) == null) {
        setState(() => _error = _text(
            'แพ็กเกจนี้ยังตั้งเวลาไม่ได้ เลือกส่งทันทีหรือดูแพ็กเกจ',
            'Scheduling is unavailable on this plan. Send now or review your plan.'));
        return false;
      }
      setState(() {
        _subscription = subscription;
        _error = null;
      });
      return true;
    } catch (_) {
      if (mounted && _owned) {
        setState(() => _error = _text(
            'ตรวจสอบแพ็กเกจไม่สำเร็จ กรุณาลองใหม่ก่อนตั้งเวลา',
            'Could not verify your plan. Try again before scheduling.'));
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setItemSchedule(String id) {
    final date = _dates[id];
    final time = _times[id];
    final at = date == null || time == null
        ? null
        : DateTime(date.year, date.month, date.day, time.hour, time.minute)
            .toUtc();
    _group = _group.copyWith(items: [
      for (final item in _group.items)
        if (item.draftId == id) item.copyWith(scheduledAt: at) else item
    ]);
    _dirty = true;
  }

  Future<void> _pickDate(ClipGroupItem item) async {
    if (!_editable(item) ||
        !await _loadSchedulePolicy() ||
        !mounted ||
        !_owned) {
      return;
    }
    final now = widget.now().toLocal();
    final first = DateTime(now.year, now.month, now.day);
    final last = first.add(postScheduleLimitForPlan(_subscription!.plan)!);
    final selected = _dates[item.draftId] ?? first.add(const Duration(days: 1));
    final initial = selected.isBefore(first)
        ? first
        : selected.isAfter(last)
            ? last
            : selected;
    final picked = widget.pickDate == null
        ? await showDatePicker(
            context: context,
            initialDate: initial,
            firstDate: first,
            lastDate: last)
        : await widget.pickDate!(context, initial, first, last);
    if (picked == null || !mounted || !_owned) return;
    setState(() {
      _dates[item.draftId] = picked;
      _setItemSchedule(item.draftId);
      _error = null;
    });
  }

  Future<void> _pickTime(ClipGroupItem item) async {
    if (!_editable(item) ||
        _dates[item.draftId] == null ||
        !await _loadSchedulePolicy() ||
        !mounted ||
        !_owned) {
      return;
    }
    final initial = _times[item.draftId] ?? const TimeOfDay(hour: 9, minute: 0);
    final picked = widget.pickTime == null
        ? await showPostDeeTimePicker(
            context: context,
            initialTime: initial,
            date: _dates[item.draftId],
            languageCode: reviewUsesThai(context) ? 'th' : 'en')
        : await widget.pickTime!(context, initial, _dates[item.draftId]);
    if (picked == null || !mounted || !_owned) return;
    setState(() {
      _times[item.draftId] = picked;
      _setItemSchedule(item.draftId);
      _error = null;
    });
  }

  String? _scheduleError() {
    if (_group.deliveryMode != ClipGroupDeliveryMode.scheduled) return null;
    if (!_pending.any((item) => !_hasReceipt(item))) return null;
    if (_subscription == null) {
      return _text('ตรวจสอบแพ็กเกจก่อนยืนยันตั้งเวลา',
          'Verify your plan before confirming schedules.');
    }
    for (final item in _pending.where((item) => !_hasReceipt(item))) {
      final at = item.scheduledAt;
      if (at == null) {
        return _text('เลือกวันและเวลาของทุกคลิปให้ครบ',
            'Choose a date and time for every clip.');
      }
      if (!isPostScheduleWithinLimit(
          scheduledAt: at, now: widget.now(), plan: _subscription!.plan)) {
        return postScheduleLimitMessage(_subscription!.plan,
            languageCode: reviewUsesThai(context) ? 'th' : 'en');
      }
    }
    return null;
  }

  Future<void> _next() async {
    if (!_owned || _busy || _navigating) return;
    setState(() => _navigating = true);
    try {
      if (_stage == 1 &&
          _group.deliveryMode == ClipGroupDeliveryMode.scheduled &&
          _pending.any((item) => !_hasReceipt(item))) {
        if (!await _loadSchedulePolicy()) return;
        final problem = _scheduleError();
        if (problem != null) {
          setState(() => _error = problem);
          return;
        }
      }
      if (!await _save() || !mounted || !_owned) return;
      if (_stage == 1) await _loadQuota();
      if (!mounted || !_owned) return;
      setState(() {
        _stage++;
        _error = null;
        _message = null;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } finally {
      if (mounted) setState(() => _navigating = false);
    }
  }

  String _caption(ClipGroupItem item) =>
      item.usesSharedCaption && !item.isAccepted && !_hasReceipt(item)
          ? _sharedCaption.text
          : _drafts[item.draftId]?.caption ?? '';
  List<SocialPlatform> _platforms(ClipGroupItem item) => SocialPlatform.values
      .where((platform) => item.platformApiValues.contains(platform.apiValue))
      .toList();
  String? _captionProblem() {
    for (final item in _pending.where((item) => !_hasReceipt(item))) {
      final caption = _caption(item);
      final draft = _drafts[item.draftId];
      if (draft == null) continue;
      if (_platforms(item).any((platform) => draft.platformSettings
          .effectiveCaption(platform, caption)
          .trim()
          .isEmpty)) {
        return _text('เพิ่มแคปชั่นให้ทุกคลิปก่อนยืนยัน',
            'Add a caption to every clip before confirming.');
      }
      final issue = validatePlatformPublishPreflight(
          selectedPlatforms: _platforms(item).toSet(),
          caption: caption,
          platformCaptions: draft.platformSettings.usePlatformCaptions
              ? draft.platformSettings.platformCaptions
              : const {});
      if (issue != null) return localizeReviewMessage(context, issue.message);
    }
    return null;
  }

  String? _confirmationError() {
    if (!_owned) {
      return _text('บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดชุดคลิปใหม่',
          'Your account changed. Reopen this set.');
    }
    if (_missing) {
      return _text('ไม่พบคลิปร่างบางรายการ กรุณาตรวจร่างก่อนส่ง',
          'Some member drafts are missing. Check Drafts before submitting.');
    }
    final caption = _captionProblem();
    if (caption != null) return caption;
    final schedule = _scheduleError();
    if (schedule != null) return schedule;
    if (_freshUnits > 0) {
      if (_quota == null) {
        return _text('ตรวจโควตาไม่สำเร็จ กรุณาลองใหม่ก่อนส่ง',
            'Could not verify post units. Retry before submitting.');
      }
      if (_quota!.requiresPhoneVerification) {
        return _text('ยืนยันเบอร์โทรก่อนใช้โควตาโพสต์ฟรี',
            'Verify your phone before using free post units.');
      }
      if (_available(_quota!)! < _freshUnits) {
        return _text('หน่วยโพสต์ไม่พอสำหรับรายการที่เหลือ',
            'Not enough post units for the remaining items.');
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (_navigating || !_owned || _busy) return;
    setState(() => _navigating = true);
    try {
      await _runSubmission();
    } finally {
      if (mounted) setState(() => _navigating = false);
    }
  }

  String _failureMessage(String summary, Object? error) {
    if (error == null) return summary;
    final reason = clipGroupErrorText(context, error);
    return reason == summary ? summary : '$summary\n$reason';
  }

  Future<void> _runSubmission() async {
    if (_busy || !_owned || _pending.isEmpty || _confirmationError() != null) {
      return;
    }
    if (!await _save() || !mounted || !_owned) return;
    await _loadQuota();
    if (!mounted || !_owned) return;
    final issue = _confirmationError();
    if (issue != null) {
      setState(() => _error = issue);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await widget.onSubmit(_group, (progress) {
        if (mounted && _owned) setState(() => _progress = progress);
      });
      if (!mounted || !_owned) return;
      _checkReturnedGroup(result.group);
      setState(() {
        _group = result.group;
        _syncDrafts();
        _result = true;
        _error = result.remaining > 0
            ? _failureMessage(
                _text(
                    'ยังมีรายการที่ไม่สำเร็จ ตรวจรายการเดิมก่อนลองส่งส่วนที่เหลือ',
                    'Some items remain. Check existing submissions before retrying the remaining items.'),
                result.error)
            : null;
      });
    } catch (error) {
      if (mounted && _owned) {
        await _refreshAfterFailure();
        if (mounted && _owned) {
          setState(() {
            _result = true;
            _error = _failureMessage(
                _text('ส่งชุดคลิปไม่ครบ กรุณาตรวจผลก่อนลองใหม่',
                    'The set did not finish. Check the results before retrying.'),
                error);
          });
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _back() async {
    if (_busy || _navigating) return;
    if (_stage > 0 && !_result) {
      setState(() => _stage--);
      if (_scroll.hasClients) _scroll.jumpTo(0);
      return;
    }
    if (_dirty && _owned && !await _save()) return;
    if (mounted) Navigator.pop(context, _group);
  }

  @override
  Widget build(BuildContext context) {
    final titles = [
      _text('ตรวจคลิปในชุดนี้', 'Review this set'),
      _text('เลือกเวลาส่งแต่ละคลิป', 'Schedule each clip'),
      _text('ตรวจและยืนยันทั้งชุด', 'Confirm the entire set')
    ];
    final confirmation = _stage == 2 ? _confirmationError() : null;
    return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_back());
        },
        child: Scaffold(
          key: const ValueKey('clip-group-review'),
          appBar: AppBar(
              title: Text(_result
                  ? _text('ผลการส่งทั้งชุด', 'Set submission results')
                  : titles[_stage]),
              leading:
                  BackButton(onPressed: _busy || _navigating ? null : _back)),
          body: SafeArea(
              bottom: false,
              child: ListView(
                  key: const ValueKey('clip-group-scroll'),
                  controller: _scroll,
                  padding: AppTheme.screenPadding,
                  children: [
                    Text(_group.title,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppTheme.spaceXs),
                    Text(
                        _text('${_group.items.length} คลิปอยู่ในชุดเดียว',
                            '${_group.items.length} clips in one set'),
                        style: TextStyle(color: AppTheme.textSecondary)),
                    const SizedBox(height: AppTheme.spaceLg),
                    if (!_owned)
                      _notice(_text(
                          'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดชุดคลิปใหม่',
                          'Your account changed. Reopen this set.')),
                    if (_result)
                      ..._resultWidgets()
                    else if (_stage == 0) ...[
                      _sharedEditor(),
                      const SizedBox(height: AppTheme.spaceLg),
                      for (final item in _group.items) ...[
                        _clipCard(item),
                        const SizedBox(height: AppTheme.spaceMd)
                      ],
                    ] else if (_stage == 1) ...[
                      _deliveryChoices(),
                      const SizedBox(height: AppTheme.spaceLg),
                      for (final item in _group.items) ...[
                        _scheduleCard(item),
                        const SizedBox(height: AppTheme.spaceMd)
                      ],
                      Text(
                          _text(
                              'เวลาในเครื่อง · แต่ละคลิปเปลี่ยนวันและเวลาได้แยกกัน',
                              'Device local time · Each clip has its own date and time'),
                          style: TextStyle(color: AppTheme.textSecondary)),
                    ] else ...[
                      for (final item in _group.items) ...[
                        _confirmCard(item),
                        const SizedBox(height: AppTheme.spaceMd)
                      ],
                      Text(_text(
                          'การยืนยันนี้ครอบคลุมแคปชั่นทุกคลิปที่แสดง และยังต้องผ่านการตรวจปลายทางและสิทธิ์ของแต่ละคลิป',
                          'This confirms the captions shown for every clip. Each item still passes its destination and permission checks.')),
                      if (confirmation != null) ...[
                        const SizedBox(height: AppTheme.spaceMd),
                        _notice(confirmation)
                      ],
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: AppTheme.spaceMd),
                      _notice(_error!)
                    ],
                    if (_message != null) ...[
                      const SizedBox(height: AppTheme.spaceMd),
                      Text(_message!,
                          style: TextStyle(color: AppTheme.successInk))
                    ],
                    if (_progress != null && _busy) ...[
                      const SizedBox(height: AppTheme.spaceLg),
                      const LinearProgressIndicator(),
                      Text(_text(
                          'รับรายการแล้ว ${_progress!.completed}/${_progress!.total}',
                          '${_progress!.completed}/${_progress!.total} items accepted'))
                    ],
                  ])),
          bottomNavigationBar: _footer(confirmation),
        ));
  }

  Widget _sharedEditor() => PostDeeCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
              child: Text(_text('แคปชั่นหลักของชุดนี้', 'Shared caption'),
                  style: Theme.of(context).textTheme.titleSmall)),
          TextButton(
              key: const ValueKey('clip-group-shared-caption-toggle'),
              onPressed: _owned && !_busy && !_hasUnresolved
                  ? () =>
                      setState(() => _showSharedCaption = !_showSharedCaption)
                  : null,
              child: Text(_showSharedCaption
                  ? _text('ย่อ', 'Collapse')
                  : _text('แก้ไข', 'Edit')))
        ]),
        if (_showSharedCaption)
          TextField(
              key: const ValueKey('clip-group-shared-caption'),
              controller: _sharedCaption,
              minLines: 3,
              maxLines: 8,
              enabled: _owned && !_busy && !_hasUnresolved,
              decoration: InputDecoration(
                  labelText: _text('ใช้กับคลิปที่ไม่ได้แก้แยก',
                      'Applies to clips without a custom caption')))
        else
          Text(
              _sharedCaption.text.isEmpty
                  ? _text('ยังไม่มีแคปชั่นหลัก', 'No shared caption yet')
                  : _sharedCaption.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        if (_hasUnresolved)
          Text(_text(
              'มีรายการที่เคยเริ่มส่งแล้ว ตรวจผลเดิมก่อนเปลี่ยนแคปชั่นหลัก',
              'Some items already started submitting. Check their results before changing the shared caption.')),
      ]));
  String _label(ClipGroupItem item) =>
      _text('คลิป ${item.index + 1}', 'Clip ${item.index + 1}');
  Widget _clipCard(ClipGroupItem item) {
    final draft = _drafts[item.draftId];
    final editable = _editable(item);
    return PostDeeCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
            child: Text(_label(item),
                style: Theme.of(context).textTheme.titleSmall)),
        PopupMenuButton<ClipGroupEditSection>(
            key: ValueKey('clip-group-edit-${item.draftId}'),
            enabled: editable,
            onSelected: (section) => _edit(item, section),
            itemBuilder: (_) => [
                  PopupMenuItem(
                      value: ClipGroupEditSection.cover,
                      child: Text(_text('หน้าปก', 'Cover'))),
                  PopupMenuItem(
                      value: ClipGroupEditSection.channels,
                      child: Text(_text('ตั้งค่าช่องทาง', 'Channel settings'))),
                ])
      ]),
      Text(_platforms(item).map((p) => p.label).join(' · ')),
      Text(
          '${formatClipSplitTime(item.sourceStartSeconds)}–${formatClipSplitTime(item.sourceEndSeconds)}',
          style: TextStyle(color: AppTheme.textSecondary)),
      const SizedBox(height: AppTheme.spaceSm),
      if (item.isAccepted)
        Text(_text('รับรายการแล้ว · ${item.acceptedPostStatus ?? ''}',
            'Accepted · ${item.acceptedPostStatus ?? ''}'))
      else if (draft == null)
        _notice(_text('ไม่พบคลิปในเครื่อง', 'Local clip unavailable'))
      else if (_hasReceipt(item))
        _notice(_text('เคยเริ่มส่งแล้ว · จะตรวจรายการเดิมก่อน เพื่อไม่ส่งซ้ำ',
            'Submission started · Existing request will be checked to avoid duplicates'))
      else
        Text(
            item.usesSharedCaption
                ? _text('ใช้แคปชั่นหลัก', 'Uses the shared caption')
                : _caption(item),
            maxLines: 3,
            overflow: TextOverflow.ellipsis),
      if (draft?.captionNeedsReview == true && !item.isAccepted)
        Text(
            _text('ตรวจแคปชั่นของตอนนี้อีกครั้งก่อนยืนยันทั้งชุด',
                'Review this part’s caption before confirming the set.'),
            style: TextStyle(color: AppTheme.textSecondary)),
      Wrap(spacing: AppTheme.spaceSm, children: [
        TextButton.icon(
            onPressed:
                draft != null && _owned && !_busy ? () => _preview(item) : null,
            icon: const Icon(Icons.play_circle_outline),
            label: Text(_text('ดูคลิป', 'Preview'))),
        TextButton(
            key: ValueKey('clip-group-caption-${item.draftId}'),
            onPressed: editable ? () => _editCaption(item) : null,
            child: Text(_text('แก้แคปชั่น', 'Edit caption'))),
      ]),
    ]));
  }

  Widget _deliveryChoices() => RadioGroup<ClipGroupDeliveryMode>(
      groupValue: _group.deliveryMode,
      onChanged: (mode) async {
        if (mode == null || _busy || !_owned || _hasUnresolved) return;
        if (mode == ClipGroupDeliveryMode.scheduled &&
            !await _loadSchedulePolicy()) {
          return;
        }
        if (!mounted || !_owned) return;
        setState(() => _group = _group.copyWith(deliveryMode: mode));
        _dirty = true;
      },
      child: PostDeeCard(
          child: Column(children: [
        RadioListTile<ClipGroupDeliveryMode>(
            key: const ValueKey('clip-group-mode-scheduled'),
            enabled: !_hasUnresolved && _owned && !_busy,
            value: ClipGroupDeliveryMode.scheduled,
            title: Text(
                _text('ตั้งเวลาแยกแต่ละคลิป', 'Schedule each clip separately')),
            subtitle: Text(_text('แต่ละคลิปเลือกวันและเวลาต่างกันได้',
                'Choose a different date and time for each clip.'))),
        RadioListTile<ClipGroupDeliveryMode>(
            key: const ValueKey('clip-group-mode-immediate'),
            enabled: !_hasUnresolved && _owned && !_busy,
            value: ClipGroupDeliveryMode.immediate,
            title: Text(_text('ส่งทั้งหมดทันที', 'Send all now'))),
      ])));
  Widget _scheduleCard(ClipGroupItem item) {
    final date = _dates[item.draftId];
    final time = _times[item.draftId];
    return PostDeeCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
          '${_label(item)} · ${_platforms(item).map((p) => p.label).join(' · ')}',
          style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: AppTheme.spaceSm),
      if (item.isAccepted)
        Text(_acceptedTime(item))
      else if (_group.deliveryMode == ClipGroupDeliveryMode.immediate)
        Text(_text('ส่งทันทีหลังยืนยัน', 'Send after confirmation')),
      Wrap(spacing: AppTheme.spaceSm, runSpacing: AppTheme.spaceSm, children: [
        OutlinedButton(
            key: ValueKey('clip-group-date-${item.draftId}'),
            onPressed: _editable(item) &&
                    _group.deliveryMode == ClipGroupDeliveryMode.scheduled
                ? () => _pickDate(item)
                : null,
            child: Text(date == null
                ? _text('เลือกวันส่ง', 'Choose date')
                : clipGroupDate(context, date))),
        OutlinedButton(
            key: ValueKey('clip-group-time-${item.draftId}'),
            onPressed: _editable(item) &&
                    date != null &&
                    _group.deliveryMode == ClipGroupDeliveryMode.scheduled
                ? () => _pickTime(item)
                : null,
            child: Text(time == null
                ? _text('เลือกเวลาส่ง', 'Choose time')
                : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}')),
      ]),
    ]));
  }

  String _acceptedTime(ClipGroupItem item) => item.acceptedScheduledAt == null
      ? _text('รับรายการส่งทันทีแล้ว', 'Immediate submission accepted')
      : '${clipGroupDate(context, item.acceptedScheduledAt!)} ${clipGroupTime(item.acceptedScheduledAt!)}';
  Widget _confirmCard(ClipGroupItem item) {
    final draft = _drafts[item.draftId];
    final at = _group.deliveryMode == ClipGroupDeliveryMode.scheduled
        ? item.scheduledAt
        : null;
    return PostDeeCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(_label(item), style: Theme.of(context).textTheme.titleSmall),
      Text(item.isAccepted
          ? _acceptedTime(item)
          : at == null
              ? _text('ส่งทันที', 'Send now')
              : '${clipGroupDate(context, at)} ${clipGroupTime(at)}'),
      const SizedBox(height: AppTheme.spaceSm),
      for (final platform in _platforms(item)) ...[
        Text(platform.label, style: Theme.of(context).textTheme.titleSmall),
        Text(
            widget.connectionDisplayNames[platform]?.trim().isNotEmpty == true
                ? widget.connectionDisplayNames[platform]!
                : _text('ยังยืนยันบัญชีไม่ได้', 'Account not verified yet'),
            style: TextStyle(color: AppTheme.textSecondary)),
        if (draft != null) ...[
          Text(draft.platformSettings
              .effectiveCaption(platform, _caption(item))),
          Text(localizeReviewMessage(
              context,
              publishReviewOutcomeFor(platform,
                      settings: draft.platformSettings
                          .resolvedForCaption(_caption(item)),
                      scheduledAt: at) ??
                  '')),
        ],
        const SizedBox(height: AppTheme.spaceSm),
      ],
      if (item.isAccepted)
        Text(_text(
            'รับรายการแล้ว · จะไม่ส่งซ้ำ', 'Accepted · Will not submit again')),
      if (_hasReceipt(item))
        Text(_text('จะตรวจรายการเดิมก่อนส่งอีกครั้ง',
            'The existing request will be checked before retrying.')),
    ]));
  }

  List<Widget> _resultWidgets() => [
        Text(
            _group.isComplete
                ? _text('รับรายการครบทั้งชุดแล้ว',
                    'All items in this set were accepted')
                : _text('ผลแยกแต่ละรายการ', 'Results for each item'),
            key: const ValueKey('clip-group-result'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppTheme.spaceMd),
        for (final item in _group.items) ...[
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(item.isAccepted
                  ? Icons.check_circle_outline
                  : Icons.pending_outlined),
              title: Text(
                  '${_label(item)} · ${_platforms(item).map((p) => p.label).join(' · ')}'),
              subtitle: Text(item.isAccepted
                  ? _text('รับรายการแล้ว · ${item.acceptedPostStatus ?? ''}',
                      'Accepted · ${item.acceptedPostStatus ?? ''}')
                  : _text('ยังไม่รับรายการ · ตรวจผลเดิมก่อนลองใหม่',
                      'Not accepted yet · Check existing submissions before retrying'))),
        ],
      ];
  Widget _footer(String? confirmation) => DecoratedBox(
      decoration: BoxDecoration(
          color: AppTheme.glass,
          border: Border(top: BorderSide(color: AppTheme.borderSoft))),
      child: SafeArea(
          top: false,
          child: Padding(
              padding: const EdgeInsets.all(AppTheme.spaceLg),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                        _text('ใช้ $_pendingUnits หน่วยโพสต์',
                            '$_pendingUnits post units'),
                        style: Theme.of(context).textTheme.titleMedium),
                    if (_checking)
                      Text(_text('กำลังตรวจโควตา...', 'Checking post units...'))
                    else if (_quota != null)
                      Text(
                          _text('คงเหลือ ${_available(_quota!)} หน่วย',
                              '${_available(_quota!)} units available'),
                          style: TextStyle(color: AppTheme.textSecondary))
                    else if (_quotaFailed)
                      TextButton(
                          onPressed: _busy ? null : _loadQuota,
                          child: Text(
                              _text('ตรวจโควตาใหม่', 'Retry post unit check'))),
                    const SizedBox(height: AppTheme.spaceSm),
                    if (_result)
                      FilledButton(
                          onPressed: _busy || !_owned || _pending.isEmpty
                              ? null
                              : () {
                                  setState(() => _result = false);
                                },
                          child: Text(_text(
                              'ตรวจรายการที่เหลือ', 'Review remaining items')))
                    else if (_stage < 2)
                      FilledButton(
                          key: const ValueKey('clip-group-next'),
                          onPressed:
                              _busy || _navigating || !_owned ? null : _next,
                          child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppTheme.spaceSm),
                              child: Text(
                                  _stage == 0
                                      ? _text('ถัดไป: เลือกเวลาส่ง',
                                          'Next: Choose posting times')
                                      : _text('ถัดไป: ตรวจและยืนยัน',
                                          'Next: Review and confirm'),
                                  textAlign: TextAlign.center)))
                    else
                      FilledButton(
                          key: const ValueKey('clip-group-confirm'),
                          onPressed: _busy ||
                                  _navigating ||
                                  _checking ||
                                  confirmation != null ||
                                  _pending.isEmpty
                              ? null
                              : _submit,
                          child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppTheme.spaceSm),
                              child: Text(
                                  _hasUnresolved
                                      ? _text(
                                          'ตรวจรายการเดิมและส่งส่วนที่เหลือ',
                                          'Check existing requests and send remaining items')
                                      : _group.deliveryMode ==
                                              ClipGroupDeliveryMode.scheduled
                                          ? _text(
                                              'ยืนยันตั้งเวลา ${_pending.length} รายการ',
                                              'Confirm ${_pending.length} scheduled items')
                                          : _text(
                                              'ยืนยันส่ง ${_pending.length} รายการ',
                                              'Confirm ${_pending.length} submissions'),
                                  textAlign: TextAlign.center))),
                    if (!_result)
                      TextButton(
                          key: const ValueKey('clip-group-save'),
                          onPressed: _busy || _navigating || !_owned
                              ? null
                              : () => _save(feedback: true),
                          child: Text(
                              _text('บันทึกทั้งชุดเป็นฉบับร่าง',
                                  'Save entire set as a draft'),
                              textAlign: TextAlign.center)),
                  ]))));
  Widget _notice(String message) => Text(message,
      style: TextStyle(color: Theme.of(context).colorScheme.error));
}

class _ClipGroupCaptionDialog extends StatefulWidget {
  const _ClipGroupCaptionDialog(
      {required this.initialCaption, required this.ownerSession});
  final String initialCaption;
  final AuthSessionBinding ownerSession;
  @override
  State<_ClipGroupCaptionDialog> createState() =>
      _ClipGroupCaptionDialogState();
}

class _ClipGroupCaptionDialogState extends State<_ClipGroupCaptionDialog> {
  late final _controller = TextEditingController(text: widget.initialCaption);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: PostDeeAuthSessionStore.instance,
        builder: (context, _) => AlertDialog(
          scrollable: true,
          title: Text(clipGroupText(
              context, 'แคปชั่นเฉพาะคลิปนี้', 'Caption for this clip')),
          content: widget.ownerSession.isCurrent
              ? TextField(
                  key: const ValueKey('clip-group-caption-input'),
                  controller: _controller,
                  minLines: 3,
                  maxLines: 8,
                  decoration: InputDecoration(
                      labelText: clipGroupText(context, 'แคปชั่น', 'Caption')))
              : Text(clipGroupText(
                  context,
                  'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดชุดคลิปใหม่',
                  'Your account changed. Reopen this set.')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(clipGroupText(context, 'ยกเลิก', 'Cancel'))),
            FilledButton(
                key: const ValueKey('clip-group-caption-apply'),
                onPressed: widget.ownerSession.isCurrent
                    ? () => Navigator.pop(context, _controller.text)
                    : null,
                child: Text(clipGroupText(
                    context, 'ใช้แคปชั่นนี้', 'Use this caption')))
          ],
        ),
      );
}
