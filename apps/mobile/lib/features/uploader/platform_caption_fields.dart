import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';
import '../shared/postdee_card.dart';

const captionPlatforms = [
  SocialPlatform.tiktok,
  SocialPlatform.youtubeShorts,
  SocialPlatform.instagramReels,
  SocialPlatform.facebookReels,
];

class PlatformCaptionAiTargets extends StatelessWidget {
  const PlatformCaptionAiTargets({
    super.key,
    required this.selectedPlatforms,
    required this.onChanged,
    this.enabled = true,
  });

  final Set<SocialPlatform> selectedPlatforms;
  final ValueChanged<Set<SocialPlatform>> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final selected = captionPlatforms.where(selectedPlatforms.contains).toSet();
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Reserve both selected borders as well as padding, logo and label gap
        // so the chip measures wrapped text at its final available width.
        final labelWidth = ((constraints.maxWidth - 8) / 2 - 46)
            .clamp(0, double.infinity)
            .toDouble();
        Widget target(SocialPlatform platform) {
          final isSelected = selected.contains(platform);
          return FilterChip(
            key: ValueKey('ai-caption-target-${platform.apiValue}'),
            avatar: SocialPlatformLogo(platform: platform, size: 20),
            avatarBoxConstraints:
                const BoxConstraints.tightFor(width: 20, height: 20),
            label: SizedBox(
              width: labelWidth,
              child: Builder(builder: (context) {
                // FilterChip supplies a one-line default. Reset it so full
                // platform names remain readable at larger text sizes.
                return DefaultTextStyle(
                  style: DefaultTextStyle.of(context).style,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                  child: Text(
                    platform.label,
                    softWrap: true,
                    overflow: TextOverflow.visible,
                  ),
                );
              }),
            ),
            labelStyle: TextStyle(
              color: enabled ? colors.onSurface : colors.onSurfaceVariant,
              fontSize: 12,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
            labelPadding: const EdgeInsets.only(left: 7),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            side: BorderSide(
              color: isSelected ? colors.primary : colors.outlineVariant,
              width: isSelected ? 1.5 : 1,
            ),
            backgroundColor: colors.surface,
            selectedColor: colors.surface,
            showCheckmark: false,
            selected: isSelected,
            onSelected: enabled
                ? (value) {
                    final updated = {...selected};
                    if (value) {
                      updated.add(platform);
                    } else {
                      updated.remove(platform);
                    }
                    onChanged(updated);
                  }
                : null,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < captionPlatforms.length; index += 2)
              Padding(
                padding: EdgeInsets.only(bottom: index == 0 ? 8 : 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: target(captionPlatforms[index])),
                    const SizedBox(width: 8),
                    Expanded(child: target(captionPlatforms[index + 1])),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class PlatformCaptionFields extends StatefulWidget {
  const PlatformCaptionFields({
    super.key,
    required this.captions,
    required this.onChanged,
    required this.validationMessage,
    this.readOnly = false,
  });

  final Map<SocialPlatform, String> captions;
  final void Function(SocialPlatform, String) onChanged;
  final String? Function(SocialPlatform) validationMessage;
  final bool readOnly;

  @override
  State<PlatformCaptionFields> createState() => _PlatformCaptionFieldsState();
}

class _PlatformCaptionFieldsState extends State<PlatformCaptionFields> {
  late final _controllers = {
    for (final platform in captionPlatforms)
      platform: TextEditingController(text: widget.captions[platform] ?? ''),
  };

  @override
  void didUpdateWidget(covariant PlatformCaptionFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final platform in captionPlatforms) {
      final text = widget.captions[platform] ?? '';
      if (_controllers[platform]!.text != text) {
        _controllers[platform]!.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length));
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final platform in captionPlatforms)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PostDeeCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      SocialPlatformLogo(platform: platform, size: 26),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          platform.label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    TextField(
                      key: ValueKey('uploader-caption-${platform.apiValue}'),
                      controller: _controllers[platform],
                      readOnly: widget.readOnly,
                      minLines: 3,
                      maxLines: 7,
                      onChanged: (text) => widget.onChanged(platform, text),
                      decoration: InputDecoration(
                        labelText: platform == SocialPlatform.youtubeShorts
                            ? 'คำอธิบาย YouTube'
                            : 'แคปชั่น ${platform.shortLabel}',
                        hintText: 'เขียนแคปชั่นสำหรับช่องทางนี้...',
                        errorText: widget.validationMessage(platform),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      platform == SocialPlatform.youtubeShorts
                          ? '${utf8.encode((_controllers[platform]!.text).trim()).length} / 5,000 ไบต์ · ชื่อคลิปตั้งในช่องทาง'
                          : '${_controllers[platform]!.text.trim().length} ตัวอักษร',
                      style: TextStyle(
                          fontSize: 11.5, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
}

class PlatformCaptionPreviewSheet extends StatelessWidget {
  const PlatformCaptionPreviewSheet({
    super.key,
    required this.captions,
    required this.isFallback,
    required this.charged,
  });

  final Map<SocialPlatform, String> captions;
  final bool isFallback;
  final bool charged;

  @override
  Widget build(BuildContext context) {
    final platforms = captionPlatforms.where(captions.containsKey).toList();
    final count = platforms.length;
    final countLabel = count == 4 ? 'ทั้ง 4 ช่องทาง' : '$count ช่องทาง';
    return SizedBox(
      key: const ValueKey('uploader-platform-ai-preview'),
      height: MediaQuery.sizeOf(context).height * .85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
            child: Row(children: [
              Expanded(
                child: Text(
                    isFallback
                        ? 'ตรวจข้อความสำรอง${count == 4 ? countLabel : ' $countLabel'}'
                        : 'แคปชั่นจาก AI $countLabel',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(
                  tooltip: 'กลับไปเขียนเอง',
                  onPressed: () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
                isFallback
                    ? 'AI วิเคราะห์คลิปไม่สำเร็จ กรุณาตรวจข้อความ $count ช่องทางก่อนใช้'
                        '${charged ? '' : ' · ไม่หักโควตา AI'}'
                    : 'เลือกใช้แล้วแก้ต่อได้ ข้อความเดิมจะยังอยู่จนกดใช้',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(children: [
                for (final platform in platforms)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: PostDeeCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            SocialPlatformLogo(platform: platform, size: 24),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(platform.label),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          Text(captions[platform]!),
                        ],
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: FilledButton.icon(
                key: const ValueKey('uploader-platform-ai-apply'),
                onPressed:
                    count > 0 ? () => Navigator.pop(context, true) : null,
                icon: const Icon(Icons.check),
                label: Text(
                    count == 4 ? 'ใช้ทั้ง 4 แคปชั่น' : 'ใช้ $count แคปชั่น'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
