import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_session.dart';
import '../../core/network/postdee_api_client.dart';
import '../platforms/social_platform.dart';
import 'platform_publish_settings.dart';

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
      required this.loadOptions,
      required this.isCurrent});
  final PlatformPublishSettings initialSettings;
  final Future<TikTokPublishingOptionsResult> Function() loadOptions;
  final bool Function() isCurrent;

  @override
  State<TikTokPublishingSettingsSheet> createState() => _TikTokSettingsState();
}

class _TikTokSettingsState extends State<TikTokPublishingSettingsSheet> {
  late PlatformPublishSettings _settings;
  TikTokPublishingOptionsResult? _options;
  bool _loading = true;
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
    _load();
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

  void _change(PlatformPublishSettings settings) => setState(() {
        _settings = settings.copyWith(
            tiktokMusicUsageConfirmed: false,
            tiktokBrandedContentPolicyConfirmed: false);
      });

  Future<void> _policy(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
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
    return Padding(
        key: const ValueKey('uploader-platform-settings-sheet'),
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .86,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                      title: const Text('การตั้งค่า TikTok'),
                      subtitle:
                          info == null ? null : Text(info.creatorNickname),
                      trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context))),
                  Expanded(
                      child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Wrap(spacing: 8, children: [
                                  ChoiceChip(
                                      key: const ValueKey(
                                          'uploader-tiktok-mode-inbox'),
                                      label:
                                          const Text('ส่งเป็นร่างเข้า TikTok'),
                                      selected: !direct,
                                      onSelected: (_) => _change(
                                          _settings.copyWith(
                                              tiktokPublishMode:
                                                  TikTokPublishMode
                                                      .inboxDraft))),
                                  ChoiceChip(
                                      key: const ValueKey(
                                          'uploader-tiktok-mode-direct'),
                                      label: const Text('โพสต์ตรง'),
                                      selected: direct,
                                      onSelected: (_) => _change(
                                          _settings.copyWith(
                                              tiktokPublishMode:
                                                  TikTokPublishMode
                                                      .directPost))),
                                ]),
                                const SizedBox(height: 12),
                                if (!direct)
                                  const Text(
                                      'ส่งออกจริงและใช้โควตาโพสต์ · ต้องเปิด TikTok เพื่อตั้งค่าต่อ'),
                                if (_loading) const LinearProgressIndicator(),
                                if (_error != null) ...[
                                  Text(_error!,
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error)),
                                  TextButton(
                                      key: const ValueKey(
                                          'uploader-tiktok-options-retry'),
                                      onPressed:
                                          widget.isCurrent() ? _load : null,
                                      child: const Text('ลองใหม่')),
                                ],
                                if (direct && info != null) ...[
                                  DropdownButtonFormField<TikTokPrivacyLevel>(
                                      key: ValueKey('uploader-tiktok-privacy'),
                                      initialValue:
                                          _settings.tiktokPrivacyLevel,
                                      decoration: const InputDecoration(
                                          labelText: 'ใครดูวิดีโอนี้ได้',
                                          hintText: 'เลือกการมองเห็น'),
                                      items: info.privacyLevelOptions
                                          .map((value) => DropdownMenuItem(
                                              value: value,
                                              enabled: !(value ==
                                                      TikTokPrivacyLevel
                                                          .selfOnly &&
                                                  _settings
                                                      .tiktokBrandContentToggle),
                                              child: Text(
                                                  tikTokPrivacyLabel(value))))
                                          .toList(),
                                      onChanged: (value) => _change(
                                          _settings.copyWith(
                                              tiktokPrivacyLevel: value))),
                                  const SizedBox(height: 12),
                                  _interaction(
                                      'comment',
                                      'อนุญาตความคิดเห็น',
                                      _settings.tiktokAllowComment,
                                      info.commentDisabled,
                                      (value) => _settings.copyWith(
                                          tiktokAllowComment: value)),
                                  _interaction(
                                      'duet',
                                      'อนุญาต Duet',
                                      _settings.tiktokAllowDuet,
                                      info.duetDisabled,
                                      (value) => _settings.copyWith(
                                          tiktokAllowDuet: value)),
                                  _interaction(
                                      'stitch',
                                      'อนุญาต Stitch',
                                      _settings.tiktokAllowStitch,
                                      info.stitchDisabled,
                                      (value) => _settings.copyWith(
                                          tiktokAllowStitch: value)),
                                  SwitchListTile(
                                      key: const ValueKey(
                                          'uploader-tiktok-commercial'),
                                      title: const Text('เนื้อหาเชิงพาณิชย์'),
                                      value: _commercial,
                                      onChanged: (value) {
                                        _commercial = value;
                                        _change(_settings.copyWith(
                                            tiktokBrandContentToggle: false,
                                            tiktokBrandOrganicToggle: false));
                                      }),
                                  if (_commercial) ...[
                                    CheckboxListTile(
                                        key: const ValueKey(
                                            'uploader-tiktok-own-brand'),
                                        title: const Text('โปรโมตแบรนด์ของฉัน'),
                                        value:
                                            _settings.tiktokBrandOrganicToggle,
                                        onChanged: (value) => _change(
                                            _settings.copyWith(
                                                tiktokBrandOrganicToggle:
                                                    value ?? false))),
                                    CheckboxListTile(
                                        key: const ValueKey(
                                            'uploader-tiktok-third-party'),
                                        title: const Text(
                                            'โปรโมตแบรนด์ของบุคคลอื่น'),
                                        value: _settings
                                            .tiktokBrandContentToggle,
                                        onChanged: _settings
                                                    .tiktokPrivacyLevel ==
                                                TikTokPrivacyLevel.selfOnly
                                            ? null
                                            : (value) => _change(
                                                _settings.copyWith(
                                                    tiktokBrandContentToggle:
                                                        value ?? false))),
                                    if (_settings.tiktokPrivacyLevel ==
                                        TikTokPrivacyLevel.selfOnly)
                                      const Text(
                                          'เนื้อหาที่มีผู้สนับสนุนตั้งเป็นเฉพาะฉันไม่ได้ เลือกผู้ชมอื่นก่อน'),
                                    if (_settings.tiktokBrandContentToggle)
                                      const Text(
                                          'วิดีโอนี้จะแสดงป้าย Paid partnership / มีผู้สนับสนุน')
                                    else if (_settings.tiktokBrandOrganicToggle)
                                      const Text(
                                          'วิดีโอนี้จะแสดงป้ายเนื้อหาโปรโมต'),
                                  ],
                                  CheckboxListTile(
                                      key: const ValueKey(
                                          'uploader-tiktok-aigc'),
                                      title:
                                          const Text('มีเนื้อหาที่สร้างโดย AI'),
                                      value: _settings.tiktokIsAigc,
                                      onChanged: (value) => _change(
                                          _settings.copyWith(
                                              tiktokIsAigc: value ?? false))),
                                  CheckboxListTile(
                                      key: const ValueKey(
                                          'uploader-tiktok-music-consent'),
                                      title: const Text(
                                          'ฉันยืนยันสิทธิ์การใช้เพลงและยอมรับเงื่อนไขการใช้เพลงของ TikTok'),
                                      value:
                                          _settings.tiktokMusicUsageConfirmed,
                                      onChanged: (value) => setState(() =>
                                          _settings = _settings.copyWith(
                                              tiktokMusicUsageConfirmed:
                                                  value ?? false))),
                                  TextButton(
                                      onPressed: () => _policy(
                                          'https://www.tiktok.com/legal/page/global/music-usage-confirmation/en'),
                                      child:
                                          const Text('อ่านเงื่อนไขการใช้เพลง')),
                                  if (_settings.tiktokBrandContentToggle) ...[
                                    CheckboxListTile(
                                        key: const ValueKey(
                                            'uploader-tiktok-brand-consent'),
                                        title: const Text(
                                            'ฉันยอมรับนโยบาย Branded Content ของ TikTok'),
                                        value: _settings
                                            .tiktokBrandedContentPolicyConfirmed,
                                        onChanged: (value) => setState(() =>
                                            _settings = _settings.copyWith(
                                                tiktokBrandedContentPolicyConfirmed:
                                                    value ?? false))),
                                    TextButton(
                                        onPressed: () => _policy(
                                            'https://www.tiktok.com/legal/page/global/bc-policy/en'),
                                        child: const Text(
                                            'อ่านนโยบาย Branded Content')),
                                  ],
                                  const Text(
                                      'TikTok อาจใช้เวลาประมวลผลหลายนาที ผลเผยแพร่ขึ้นอยู่กับการมองเห็นที่เลือก'),
                                  if (validation != null)
                                    Text(validation,
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error)),
                                ],
                              ]))),
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: FilledButton(
                          key:
                              const ValueKey('uploader-platform-settings-save'),
                          onPressed: canSave
                              ? () => Navigator.pop(context,
                                  TikTokSettingsSelection(_settings, _options))
                              : null,
                          child: const Text('บันทึกการตั้งค่า'))),
                ])));
  }

  Widget _interaction(String key, String title, bool value, bool disabled,
          PlatformPublishSettings Function(bool) update) =>
      CheckboxListTile(
        key: ValueKey('uploader-tiktok-allow-$key'),
        title: Text(title),
        subtitle: disabled ? const Text('บัญชี TikTok นี้ไม่อนุญาต') : null,
        value: !disabled && value,
        onChanged: disabled ? null : (next) => _change(update(next ?? false)),
      );
}
