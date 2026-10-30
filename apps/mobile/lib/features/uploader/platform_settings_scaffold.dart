import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';
import 'channel_localizations.dart';

/// Shared sheet chrome. Short forms shrink; long forms scroll above the actions.
class PlatformSettingsScaffold extends StatelessWidget {
  const PlatformSettingsScaffold({
    super.key,
    required this.platform,
    required this.displayName,
    required this.child,
    this.onSave,
    this.validationMessage,
    this.memoryMessage,
  });

  final SocialPlatform platform;
  final String displayName;
  final Widget child;
  final VoidCallback? onSave;
  final String? validationMessage;
  final String? memoryMessage;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final height = math.max(
          0.0,
          math.min(media.size.height * .86,
              constraints.maxHeight - media.viewInsets.bottom));
      return Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: ConstrainedBox(
          key: const ValueKey('uploader-platform-settings-sheet'),
          constraints: BoxConstraints(maxHeight: height),
          child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
                    child: Row(children: [
                      SocialPlatformLogo(platform: platform, size: 34),
                      const SizedBox(width: 11),
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(platform.label,
                              style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                              displayName.trim().isEmpty
                                  ? localizeChannelMessage(context, 'ยังยืนยันบัญชีไม่ได้')
                                  : displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 12)),
                        ],
                      )),
                      IconButton(
                          tooltip: localizeChannelMessage(context, 'ปิด'),
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded)),
                    ]),
                  ),
                  Divider(height: 1, color: AppTheme.borderSoft),
                  Flexible(
                      fit: FlexFit.loose,
                      child: SingleChildScrollView(
                          key: const ValueKey('platform-settings-scroll'),
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (memoryMessage != null) ...[
                                ChannelText(memoryMessage!,
                                    key: const ValueKey(
                                        'platform-settings-memory'),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary)),
                                const SizedBox(height: 12),
                              ],
                              child,
                            ],
                          ))),
                  Divider(height: 1, color: AppTheme.borderSoft),
                  if (validationMessage != null)
                    Padding(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                        child: Semantics(
                            liveRegion: true,
                            child: ChannelText(validationMessage!,
                                style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        Theme.of(context).colorScheme.error)))),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                      child: Row(children: [
                        Expanded(
                            child: OutlinedButton(
                                key: const ValueKey(
                                    'uploader-platform-settings-cancel'),
                                onPressed: () => Navigator.of(context).pop(),
                                child: const ChannelText('ยกเลิก',
                                    textAlign: TextAlign.center))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: FilledButton(
                                key: const ValueKey(
                                    'uploader-platform-settings-save'),
                                onPressed: onSave,
                                child: const ChannelText('บันทึกการตั้งค่า',
                                    textAlign: TextAlign.center))),
                      ])),
                ],
              )),
        ),
      );
    });
  }
}

class PlatformSettingsSection extends StatelessWidget {
  const PlatformSettingsSection(
      {super.key, required this.title, required this.child, this.description});

  final String title;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        color: AppTheme.glass,
        shape: RoundedRectangleBorder(
            side: BorderSide(color: AppTheme.borderSoft),
            borderRadius: BorderRadius.circular(16)),
        child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ChannelText(title,
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  if (description != null) ...[
                    const SizedBox(height: 5),
                    ChannelText(description!,
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                  const SizedBox(height: 12),
                  child,
                ])),
      );
}
