import 'package:flutter/material.dart';

import '../../core/localization/postdee_localizations.dart';
import '../../core/theme/app_theme.dart';
import 'growth_tool_settings_store.dart';
import 'postdee_card.dart';

class GrowthToolSettingOption {
  const GrowthToolSettingOption({
    required this.id,
    required this.label,
    this.enabledByDefault = true,
  });

  final String id;
  final String label;
  final bool enabledByDefault;
}

class GrowthToolDetail {
  const GrowthToolDetail({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.icon,
    required this.color,
    required this.settings,
    this.prototypeOnly = false,
    this.note =
        'รอบนี้เป็นหน้าตั้งค่าเบื้องต้น ระบบจะจำค่าที่เลือกไว้ในเครื่องเพื่อใช้ต่อยอดกับระบบจริง',
  });

  final String id;
  final String title;
  final String description;
  final String status;
  final IconData icon;
  final Color color;
  final List<GrowthToolSettingOption> settings;
  final bool prototypeOnly;
  final String note;
}

Future<void> showGrowthToolDetailSheet(
  BuildContext context,
  GrowthToolDetail detail, {
  PostDeeGrowthToolSettingsStore settingsStore =
      const SharedPreferencesGrowthToolSettingsStore(),
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _GrowthToolDetailSheet(
      detail: detail,
      settingsStore: settingsStore,
    ),
  );
}

class _GrowthToolDetailSheet extends StatefulWidget {
  const _GrowthToolDetailSheet({
    required this.detail,
    required this.settingsStore,
  });

  final GrowthToolDetail detail;
  final PostDeeGrowthToolSettingsStore settingsStore;

  @override
  State<_GrowthToolDetailSheet> createState() => _GrowthToolDetailSheetState();
}

class _GrowthToolDetailSheetState extends State<_GrowthToolDetailSheet> {
  late GrowthToolSettings _draftSettings = _defaultSettings();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  GrowthToolSettings _defaultSettings() {
    return GrowthToolSettings(
      isEnabled: false,
      enabledOptionIds: widget.detail.settings
          .where((setting) => setting.enabledByDefault)
          .map((setting) => setting.id)
          .toSet(),
    );
  }

  Future<void> _loadSavedSettings() async {
    GrowthToolSettings? savedSettings;

    try {
      savedSettings = await widget.settingsStore.loadSettings(widget.detail.id);
    } catch (_) {
      savedSettings = null;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _draftSettings = widget.detail.prototypeOnly
          ? (savedSettings ?? _defaultSettings()).copyWith(isEnabled: false)
          : savedSettings ?? _defaultSettings();
    });
  }

  void _setEnabled(bool value) {
    setState(() {
      _draftSettings = _draftSettings.copyWith(isEnabled: value);
    });
  }

  void _setOptionEnabled(String optionId, bool value) {
    final enabledOptionIds = {..._draftSettings.enabledOptionIds};

    if (value) {
      enabledOptionIds.add(optionId);
    } else {
      enabledOptionIds.remove(optionId);
    }

    setState(() {
      _draftSettings = _draftSettings.copyWith(
        enabledOptionIds: enabledOptionIds,
      );
    });
  }

  Future<void> _saveSettings() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() {
      _isSaving = true;
    });

    try {
      final settingsToSave = widget.detail.prototypeOnly
          ? _draftSettings.copyWith(isEnabled: false)
          : _draftSettings;
      await widget.settingsStore.saveSettings(
        widget.detail.id,
        settingsToSave,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
      });
      messenger.showSnackBar(
        const SnackBar(content: _GrowthToolText('บันทึกการตั้งค่าไม่สำเร็จ')),
      );
      return;
    }

    if (!mounted) {
      return;
    }

    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: _GrowthToolText(
          widget.detail.prototypeOnly
              ? 'บันทึกแบบร่างไว้ในเครื่องแล้ว ยังไม่ได้เปิดใช้งานฟีเจอร์'
              : 'บันทึกการตั้งค่าแล้ว',
        ),
      ),
    );
  }

  Widget _statusPill(String message) {
    final label = localizeGrowthToolMessage(context, message);
    final color = widget.detail.color;
    if (MediaQuery.textScalerOf(context).scale(12) <= 18) {
      return PostDeeSoftPill(label: label, color: color);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        color: AppTheme.isLightMode
            ? color.withValues(alpha: 0.12)
            : AppTheme.glassDeep.withValues(alpha: 0.82),
        border: Border.all(color: color.withValues(
            alpha: AppTheme.isLightMode ? 0.55 : 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Text(label, softWrap: true,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _actions() {
    final close = OutlinedButton(
      onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
      child: const _GrowthToolText('ปิด'),
    );
    final save = FilledButton.icon(
      onPressed: _isSaving ? null : _saveSettings,
      icon: const Icon(Icons.save_outlined, size: 18),
      label: _GrowthToolText(_isSaving
          ? 'กำลังบันทึก...'
          : widget.detail.prototypeOnly ? 'บันทึกแบบร่าง' : 'บันทึกการตั้งค่า'),
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppTheme.accent.withValues(alpha: 0.55),
        disabledForegroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
    );
    if (MediaQuery.textScalerOf(context).scale(14) > 18) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        close,
        const SizedBox(height: 10),
        ConstrainedBox(constraints: const BoxConstraints(minHeight: 48), child: save),
      ]);
    }
    return Row(children: [
      Expanded(child: close),
      const SizedBox(width: 10),
      Expanded(child: SizedBox(height: 48, child: save)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final textTheme = Theme.of(context).textTheme;
    final statusLabel = detail.prototypeOnly
        ? 'แบบร่างในเครื่อง'
        : _draftSettings.isEnabled
            ? 'เปิดใช้งานแล้ว'
            : 'ยังไม่เปิดใช้งาน';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.glass,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A120E).withValues(alpha: 0.3),
            blurRadius: 22,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          10,
          16,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.border.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(AppTheme.pillRadius),
                ),
                child: const SizedBox(width: 42, height: 4),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    color: detail.color.withValues(alpha: 0.14),
                  ),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(detail.icon,
                        color: AppTheme.inkFor(detail.color), size: 25),
                  ),
                ),
                const SizedBox(width: AppTheme.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _GrowthToolText(
                        'รายละเอียดและตั้งค่า',
                        style: textTheme.labelLarge?.copyWith(
                          color: detail.color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _growthToolUsesThai(context)
                            ? 'ตั้งค่า: ${detail.title}'
                            : 'Settings: ${localizeGrowthToolMessage(context, detail.title)}',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed:
                      _isSaving ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: localizeGrowthToolMessage(context, 'ปิด'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              localizeGrowthToolMessage(context, detail.description),
              style: textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppTheme.spaceMd),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statusPill(detail.prototypeOnly ? 'เร็ว ๆ นี้' : detail.status),
                _statusPill(statusLabel),
                if (!detail.prototypeOnly)
                  _statusPill('ตั้งค่าในเครื่องนี้'),
              ],
            ),
            const SizedBox(height: 14),
            if (!detail.prototypeOnly) ...[
              _ToolEnabledCard(
                color: detail.color,
                isEnabled: _draftSettings.isEnabled,
                onChanged: _isSaving ? null : _setEnabled,
              ),
              const SizedBox(height: 10),
            ],
            PostDeeCard(
              padding: const EdgeInsets.all(AppTheme.spaceMd),
              glowColor: detail.color,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GrowthToolText(
                    'ตั้งค่าที่ต้องการใช้',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spaceSm),
                  for (final setting in detail.settings) ...[
                    _SettingToggleRow(
                      key: ValueKey(
                        'growth-tool-row-${detail.id}-${setting.id}',
                      ),
                      checkboxKey: ValueKey(
                        'growth-tool-option-${detail.id}-${setting.id}',
                      ),
                      label: setting.label,
                      color: detail.color,
                      value: _draftSettings.isOptionEnabled(setting.id),
                      onChanged: _isSaving
                          ? null
                          : (value) =>
                              _setOptionEnabled(setting.id, value ?? false),
                    ),
                    if (setting != detail.settings.last)
                      const SizedBox(height: 7),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            DecoratedBox(
              key: const ValueKey('growth-tool-real-status-note'),
              decoration: BoxDecoration(
                color: AppTheme.mint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(13),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      color: AppTheme.accentCyanInk,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _GrowthToolText(
                        detail.prototypeOnly
                            ? 'ฟีเจอร์นี้ยังไม่เชื่อมระบบจริง ค่าที่เลือกจะบันทึกเป็นแบบร่างในเครื่องนี้เท่านั้น'
                            : detail.note,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spaceMd),
            _actions(),
          ],
        ),
      ),
    );
  }
}

class _ToolEnabledCard extends StatelessWidget {
  const _ToolEnabledCard({
    required this.color,
    required this.isEnabled,
    required this.onChanged,
  });

  final Color color;
  final bool isEnabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return PostDeeCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      glowColor: color,
      child: Row(
        children: [
          Icon(Icons.power_settings_new, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: _GrowthToolText(
              'เปิดใช้งานเครื่องมือนี้',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          Switch.adaptive(
            key: const ValueKey('growth-tool-enabled-switch'),
            value: isEnabled,
            activeThumbColor: color,
            activeTrackColor: color.withValues(alpha: 0.32),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SettingToggleRow extends StatelessWidget {
  const _SettingToggleRow({
    required super.key,
    required this.checkboxKey,
    required this.label,
    required this.color,
    required this.value,
    required this.onChanged,
  });

  final Key checkboxKey;
  final String label;
  final Color color;
  final bool value;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.tileRadius),
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              key: checkboxKey,
              value: value,
              activeColor: color,
              side: BorderSide(color: color.withValues(alpha: 0.62)),
              visualDensity: VisualDensity.compact,
              onChanged: onChanged,
            ),
            const SizedBox(width: AppTheme.spaceXs),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  localizeGrowthToolMessage(context, label),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _growthToolUsesThai(BuildContext context) =>
    (Localizations.of<PostDeeLocalizations>(context, PostDeeLocalizations)
                ?.locale.languageCode ??
            'th') ==
        'th';

/// Translate only known app-owned tool copy at render time. Unknown metadata
/// remains intact; local setting IDs and saved values are never translated.
String localizeGrowthToolMessage(BuildContext context, String message) =>
    _growthToolUsesThai(context)
        ? message
        : _englishGrowthToolMessages[message] ?? message;

class _GrowthToolText extends StatelessWidget {
  const _GrowthToolText(this.message, {this.style});

  final String message;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(
        localizeGrowthToolMessage(context, message),
        style: style,
      );
}

const _englishGrowthToolMessages = <String, String>{
  'รายละเอียดและตั้งค่า': 'Details and settings',
  'เร็ว ๆ นี้': 'Coming soon',
  'แบบร่างในเครื่อง': 'Local draft',
  'เปิดใช้งานแล้ว': 'Enabled',
  'ยังไม่เปิดใช้งาน': 'Not enabled',
  'ตั้งค่าในเครื่องนี้': 'Settings on this device',
  'ตั้งค่าที่ต้องการใช้': 'Options',
  'เปิดใช้งานเครื่องมือนี้': 'Enable this tool',
  'ปิด': 'Close',
  'กำลังบันทึก...': 'Saving...',
  'บันทึกแบบร่าง': 'Save draft',
  'บันทึกการตั้งค่า': 'Save settings',
  'บันทึกการตั้งค่าไม่สำเร็จ': 'Could not save settings.',
  'บันทึกแบบร่างไว้ในเครื่องแล้ว ยังไม่ได้เปิดใช้งานฟีเจอร์':
      'Draft saved on this device. This feature is still disabled.',
  'บันทึกการตั้งค่าแล้ว': 'Settings saved',
  'ฟีเจอร์นี้ยังไม่เชื่อมระบบจริง ค่าที่เลือกจะบันทึกเป็นแบบร่างในเครื่องนี้เท่านั้น':
      'This feature is not connected to a live service yet. Your choices are saved only as a draft on this device.',
  'รอบนี้เป็นหน้าตั้งค่าเบื้องต้น ระบบจะจำค่าที่เลือกไว้ในเครื่องเพื่อใช้ต่อยอดกับระบบจริง':
      'These are initial settings. Your choices are saved on this device for future integration with the live service.',
  'เรดาร์แฮชแท็กฮิต': 'Trending hashtag radar',
  'ดูแฮชแท็ก/คีย์เวิร์ดที่กำลังขึ้น เพื่อใช้กับคลิปต่อไป':
      'Find trending hashtags and keywords for your next video.',
  'เลือกหมวดสินค้าหรือกลุ่มคอนเทนต์':
      'Choose a product or content category',
  'ดูแฮชแท็กที่น่าลองใช้กับคลิปถัดไป':
      'Find hashtags to try in your next video',
  'ศูนย์คอมเมนต์ AI': 'AI comment center',
  'สรุปคอมเมนต์และเตรียมร่างคำตอบให้ตรวจภายหลัง':
      'Summarize comments and prepare reply drafts for review.',
  'ดูสรุปคอมเมนต์บวก ลบ และคำถามที่พบบ่อย':
      'See positive and negative comments and common questions',
  'ให้ AI ร่างคำตอบไว้รอตรวจ': 'Prepare AI reply drafts for review',
};
