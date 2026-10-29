import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_session.dart';
import '../../core/network/postdee_api_client.dart';
import '../platforms/social_platform.dart';
import 'channel_localizations.dart';
import 'platform_publish_settings.dart';
import 'platform_settings_scaffold.dart';

String tikTokPrivacyLabel(TikTokPrivacyLevel value) => switch (value) {
      TikTokPrivacyLevel.publicToEveryone => 'ทุกคน',
      TikTokPrivacyLevel.mutualFollowFriends => 'เพื่อนที่ติดตามกัน',
      TikTokPrivacyLevel.followerOfCreator => 'ผู้ติดตาม',
      TikTokPrivacyLevel.selfOnly => 'เฉพาะฉัน',
    };

class TikTokSettingsSelection {
  const TikTokSettingsSelection(this.settings, this.options);
  final PlatformPublishSettings settings;
  final TikTokPublishingOptionsResult? options;
}

/// The capabilities belong to this opening/account, never to a saved draft.
class TikTokPublishingSettingsSheet extends StatefulWidget {
  const TikTokPublishingSettingsSheet(
      {super.key,
      required this.initialSettings,
      this.connectionDisplayName,
      this.memoryMessage,
      required this.loadOptions,
      required this.isCurrent});
  final PlatformPublishSettings initialSettings;
  final String? connectionDisplayName;
  final String? memoryMessage;
  final Future<TikTokPublishingOptionsResult> Function() loadOptions;
  final bool Function() isCurrent;

  @override
  State<TikTokPublishingSettingsSheet> createState() => _TikTokSettingsState();
}

class _TikTokSettingsState extends State<TikTokPublishingSettingsSheet> {
  late PlatformPublishSettings _settings;
  TikTokPublishingOptionsResult? _options;
  bool _loading = false;
  bool _commercial = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings.copyWith(
      tiktokMusicUsageConfirmed: false,
      tiktokBrandedContentPolicyConfirmed: false,
      tiktokCreatorInfoRevision: null,
      tiktokVideoDurationSeconds: null,
    );
    _commercial = _settings.tiktokBrandContentToggle ||
        _settings.tiktokBrandOrganicToggle;
    PostDeeAuthSessionStore.instance.addListener(_ownerChanged);
    if (_settings.tiktokPublishMode == TikTokPublishMode.directPost) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _generation++;
    PostDeeAuthSessionStore.instance.removeListener(_ownerChanged);
    super.dispose();
  }

  void _ownerChanged() {
    if (!widget.isCurrent() && mounted) {
      _generation++;
      setState(() {
        _options = null;
        _loading = false;
        _settings = _settings.copyWith(
            tiktokMusicUsageConfirmed: false,
            tiktokBrandedContentPolicyConfirmed: false,
            tiktokCreatorInfoRevision: null);
        _error = 'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดการตั้งค่า TikTok ใหม่';
      });
    }
  }

  Future<void> _load() async {
    if (!widget.isCurrent() ||
        _settings.tiktokPublishMode != TikTokPublishMode.directPost) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _options = null;
    });
    try {
      final options = await widget.loadOptions();
      if (!mounted || generation != _generation || !widget.isCurrent()) return;
      final info = options.creatorInfo;
      setState(() {
        _options = options;
        _settings = _settings.copyWith(
          tiktokCreatorInfoRevision: options.creatorInfoRevision,
          tiktokPrivacyLevel:
              info.privacyLevelOptions.contains(_settings.tiktokPrivacyLevel)
                  ? _settings.tiktokPrivacyLevel
                  : null,
          tiktokAllowComment:
              !info.commentDisabled && _settings.tiktokAllowComment,
          tiktokAllowDuet: !info.duetDisabled && _settings.tiktokAllowDuet,
          tiktokAllowStitch:
              !info.stitchDisabled && _settings.tiktokAllowStitch,
          tiktokMusicUsageConfirmed: false,
          tiktokBrandedContentPolicyConfirmed: false,
        );
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
            () => _error = 'โหลดตัวเลือก TikTok ล่าสุดไม่สำเร็จ กรุณาลองใหม่');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _change(PlatformPublishSettings settings, {bool resetConsents = false}) =>
      setState(() {
        // Viewer/interaction choices do not change the music or policy text.
        // Disclosure changes must be acknowledged in their new context.
        _settings = resetConsents
            ? settings.copyWith(
                tiktokMusicUsageConfirmed: false,
                tiktokBrandedContentPolicyConfirmed: false)
            : settings;
      });

  void _selectMode(TikTokPublishMode mode) {
    if (_settings.tiktokPublishMode == mode || !widget.isCurrent()) return;
    // A late result from a previous Direct opening cannot restore its consent.
    _generation++;
    setState(() {
      _options = null;
      _loading = false;
      _error = null;
      _settings = _settings.copyWith(
          tiktokPublishMode: mode,
          tiktokCreatorInfoRevision: null,
          tiktokVideoDurationSeconds: null,
          tiktokMusicUsageConfirmed: false,
          tiktokBrandedContentPolicyConfirmed: false);
    });
    if (mode == TikTokPublishMode.directPost) unawaited(_load());
  }

  Future<void> _policy(String url) async {
    var opened = false;
    try {
      opened = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      // Reading a policy must never accept it or interrupt the current choices.
    }
    if (!opened && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: ChannelText('เปิดเงื่อนไข TikTok ไม่สำเร็จ '
              'ลองใหม่หรือเปิดลิงก์นี้ในเบราว์เซอร์: $url')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    final direct = _settings.tiktokPublishMode == TikTokPublishMode.directPost;
    final info = _options?.creatorInfo;
    final commercialIncomplete = _commercial &&
        !_settings.tiktokBrandContentToggle &&
        !_settings.tiktokBrandOrganicToggle;
    final validation = direct
        ? info == null
            ? 'รอข้อมูลบัญชี TikTok ล่าสุดก่อนตั้งค่าโพสต์ตรง'
            : commercialIncomplete
                ? 'เลือกชนิดเนื้อหาเชิงพาณิชย์ก่อน'
                : _settings.validateTikTokCreatorInfo(info,
                    validateDuration: false)
        : null;
    final canSave = widget.isCurrent() &&
        _settings.canSubmit(SocialPlatform.tiktok) &&
        (!direct || (!_loading && validation == null));
    return PlatformSettingsScaffold(
      platform: SocialPlatform.tiktok,
      displayName: info?.creatorNickname ?? widget.connectionDisplayName ?? '',
      memoryMessage: widget.memoryMessage,
      onSave: canSave
          ? () => Navigator.pop(context,
              TikTokSettingsSelection(_settings, direct ? _options : null))
          : null,
      validationMessage: !widget.isCurrent()
          ? 'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดการตั้งค่า TikTok ใหม่'
          : direct
              ? _error ?? validation
              : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const ChannelText('วิธีส่งวิดีโอ',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          ChoiceChip(
              key: const ValueKey('uploader-tiktok-mode-inbox'),
              label: const ChannelText('ส่งเป็นร่างเข้า TikTok'),
              selected: !direct,
              onSelected: (_) => _selectMode(TikTokPublishMode.inboxDraft)),
          ChoiceChip(
              key: const ValueKey('uploader-tiktok-mode-direct'),
              label: const ChannelText('โพสต์ตรง'),
              selected: direct,
              onSelected: (_) => _selectMode(TikTokPublishMode.directPost)),
        ]),
        const SizedBox(height: 12),
        if (!direct)
          const PlatformSettingsSection(
              title: 'ตั้งค่าต่อใน TikTok',
              description: 'ส่งออกจริงและใช้โควตาโพสต์',
              child: ChannelText('วิดีโอจะถูกส่งเข้า TikTok Inbox '
                  'ให้คุณเปิด TikTok เพื่อตรวจ แก้ไข และยืนยันเผยแพร่ต่อ')),
        if (direct && _loading) const LinearProgressIndicator(),
        if (direct && _error != null) ...[
          TextButton(
              key: const ValueKey('uploader-tiktok-options-retry'),
              onPressed: widget.isCurrent() ? _load : null,
              child: const ChannelText('ลองใหม่')),
        ],
        if (direct && info != null) ...[
          PlatformSettingsSection(
              title: 'ผู้ชมและการโต้ตอบ',
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (largeText) ...[
                      ExcludeSemantics(child: ChannelText('ใครดูวิดีโอนี้ได้',
                          style: Theme.of(context).textTheme.bodyLarge)),
                      const SizedBox(height: 8),
                    ],
                    Semantics(
                      label: largeText ? localizeChannelMessage(context, 'ใครดูวิดีโอนี้ได้') : null,
                      child: DropdownButtonFormField<TikTokPrivacyLevel>(
                        isExpanded: true,
                        isDense: !largeText,
                        itemHeight: largeText ? null : kMinInteractiveDimension,
                        key: ValueKey('uploader-tiktok-privacy'),
                        initialValue: _settings.tiktokPrivacyLevel,
                        decoration: InputDecoration(
                            labelText: largeText ? null : localizeChannelMessage(context, 'ใครดูวิดีโอนี้ได้'),
                            hintText: localizeChannelMessage(context, 'เลือกการมองเห็น')),
                        items: info.privacyLevelOptions
                            .map((value) => DropdownMenuItem(
                                value: value,
                                enabled:
                                    !(value == TikTokPrivacyLevel.selfOnly &&
                                        _settings.tiktokBrandContentToggle),
                                child: ChannelText(tikTokPrivacyLabel(value))))
                            .toList(),
                        onChanged: (value) => _change(
                            _settings.copyWith(tiktokPrivacyLevel: value)))),
                    const SizedBox(height: 12),
                    _interaction(
                        'comment',
                        'อนุญาตความคิดเห็น',
                        _settings.tiktokAllowComment,
                        info.commentDisabled,
                        (value) =>
                            _settings.copyWith(tiktokAllowComment: value)),
                    _interaction(
                        'duet',
                        'อนุญาต Duet',
                        _settings.tiktokAllowDuet,
                        info.duetDisabled,
                        (value) => _settings.copyWith(tiktokAllowDuet: value)),
                    _interaction(
                        'stitch',
                        'อนุญาต Stitch',
                        _settings.tiktokAllowStitch,
                        info.stitchDisabled,
                        (value) =>
                            _settings.copyWith(tiktokAllowStitch: value)),
                  ])),
          const SizedBox(height: 12),
          PlatformSettingsSection(
              title: 'เนื้อหาโปรโมตและผู้สนับสนุน',
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                        key: const ValueKey('uploader-tiktok-commercial'),
                        title: const ChannelText('เนื้อหาเชิงพาณิชย์'),
                        value: _commercial,
                        onChanged: (value) {
                          _commercial = value;
                          _change(
                              _settings.copyWith(
                                  tiktokBrandContentToggle: false,
                                  tiktokBrandOrganicToggle: false),
                              resetConsents: true);
                        }),
                    if (_commercial) ...[
                      CheckboxListTile(
                          key: const ValueKey('uploader-tiktok-own-brand'),
                          title: const ChannelText('โปรโมตแบรนด์ของฉัน'),
                          value: _settings.tiktokBrandOrganicToggle,
                          onChanged: (value) => _change(
                              _settings.copyWith(
                                  tiktokBrandOrganicToggle: value ?? false),
                              resetConsents: true)),
                      CheckboxListTile(
                          key: const ValueKey('uploader-tiktok-third-party'),
                          title: const ChannelText('โปรโมตแบรนด์ของบุคคลอื่น'),
                          value: _settings.tiktokBrandContentToggle,
                          onChanged: _settings.tiktokPrivacyLevel ==
                                  TikTokPrivacyLevel.selfOnly
                              ? null
                              : (value) => _change(
                                  _settings.copyWith(
                                      tiktokBrandContentToggle: value ?? false),
                                  resetConsents: true)),
                      if (_settings.tiktokPrivacyLevel ==
                          TikTokPrivacyLevel.selfOnly)
                        const ChannelText(
                            'เนื้อหาที่มีผู้สนับสนุนตั้งเป็นเฉพาะฉันไม่ได้ เลือกผู้ชมอื่นก่อน'),
                      if (_settings.tiktokBrandContentToggle)
                        const ChannelText(
                            'วิดีโอนี้จะแสดงป้าย Paid partnership / มีผู้สนับสนุน')
                      else if (_settings.tiktokBrandOrganicToggle)
                        const ChannelText('วิดีโอนี้จะแสดงป้ายเนื้อหาโปรโมต'),
                    ],
                  ])),
          const SizedBox(height: 12),
          PlatformSettingsSection(
              title: 'เนื้อหา AI และสิทธิ์ใช้งาน',
              description: 'เปิดเผย AI เมื่อภาพหรือเสียงในวิดีโอสร้างด้วย AI '
                  'การช่วยคิดแคปชั่นอย่างเดียวไม่รวมอยู่ในข้อนี้',
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CheckboxListTile(
                        key: const ValueKey('uploader-tiktok-aigc'),
                        title: const ChannelText('มีเนื้อหาที่สร้างโดย AI'),
                        value: _settings.tiktokIsAigc,
                        onChanged: (value) => _change(
                            _settings.copyWith(tiktokIsAigc: value ?? false))),
                    CheckboxListTile(
                        key: const ValueKey('uploader-tiktok-music-consent'),
                        title: const ChannelText(
                            'ฉันยืนยันสิทธิ์การใช้เพลงและยอมรับเงื่อนไขการใช้เพลงของ TikTok'),
                        value: _settings.tiktokMusicUsageConfirmed,
                        onChanged: (value) => setState(() => _settings =
                            _settings.copyWith(
                                tiktokMusicUsageConfirmed: value ?? false))),
                    TextButton(
                        onPressed: () => _policy(
                            'https://www.tiktok.com/legal/page/global/music-usage-confirmation/en'),
                        child: const ChannelText('อ่านเงื่อนไขการใช้เพลง')),
                    if (_settings.tiktokBrandContentToggle) ...[
                      CheckboxListTile(
                          key: const ValueKey('uploader-tiktok-brand-consent'),
                          title: const ChannelText(
                              'ฉันยอมรับนโยบาย Branded Content ของ TikTok'),
                          value: _settings.tiktokBrandedContentPolicyConfirmed,
                          onChanged: (value) => setState(() => _settings =
                              _settings.copyWith(
                                  tiktokBrandedContentPolicyConfirmed:
                                      value ?? false))),
                      TextButton(
                          onPressed: () => _policy(
                              'https://www.tiktok.com/legal/page/global/bc-policy/en'),
                          child: const ChannelText('อ่านนโยบาย Branded Content')),
                    ],
                    const ChannelText(
                        'TikTok อาจใช้เวลาประมวลผลหลายนาที ผลเผยแพร่ขึ้นอยู่กับการมองเห็นที่เลือก'),
                  ])),
        ],
      ]),
    );
  }

  Widget _interaction(String key, String title, bool value, bool disabled,
          PlatformPublishSettings Function(bool) update) =>
      CheckboxListTile(
        key: ValueKey('uploader-tiktok-allow-$key'),
        contentPadding: EdgeInsets.zero,
        title: ChannelText(title),
        subtitle: disabled ? const ChannelText('บัญชี TikTok นี้ไม่อนุญาต') : null,
        value: !disabled && value,
        onChanged: disabled ? null : (next) => _change(update(next ?? false)),
      );
}
