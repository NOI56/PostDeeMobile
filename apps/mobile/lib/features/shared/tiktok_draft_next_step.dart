import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import 'postdee_card.dart';

typedef TikTokDraftUrlLauncher = Future<bool> Function(Uri uri);

/// A draft receipt is actionable only after TikTok confirms its delivery.
bool hasConfirmedTikTokDraft(Iterable<PostPlatformResult> results) =>
    results.any((result) =>
        result.platform.trim().toUpperCase() == 'TIKTOK' &&
        result.status.trim().toUpperCase() == 'PUBLISHED' &&
        result.deliveryOutcome?.trim().toUpperCase() == 'DRAFT');

/// TikTok's upload flow requires the creator to continue from an inbox
/// notification: https://developers.tiktok.com/docs/en/content-posting-api-get-started-upload-content
/// This opens the public homepage, never a provider-supplied URL or publish API.
class TikTokDraftNextStepCard extends StatefulWidget {
  const TikTokDraftNextStepCard(
      {super.key, this.launchTikTokUrl, this.languageCode = 'th'});

  final TikTokDraftUrlLauncher? launchTikTokUrl;
  final String languageCode;

  @override
  State<TikTokDraftNextStepCard> createState() =>
      _TikTokDraftNextStepCardState();
}

class _TikTokDraftNextStepCardState extends State<TikTokDraftNextStepCard> {
  bool _opening = false;
  bool _openFailed = false;

  String _text(String thai, String english) =>
      widget.languageCode == 'th' ? thai : english;

  Future<void> _openTikTok() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _openFailed = false;
    });
    var opened = false;
    try {
      final uri = Uri.parse('https://www.tiktok.com/');
      opened = await (widget.launchTikTokUrl ??
          (uri) => launchUrl(uri, mode: LaunchMode.externalApplication))(uri);
    } on Object {
      // Keep the next step available even when no external opener is installed.
    }
    if (!mounted) return;
    setState(() {
      _opening = false;
      _openFailed = !opened;
    });
  }

  @override
  Widget build(BuildContext context) => PostDeeCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_text('เผยแพร่ต่อใน TikTok', 'Continue in TikTok'),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            Text(
              _text(
                  'การส่งเป็นร่างยังไม่ใช่การเผยแพร่ให้ผู้ชม '
                      'เปิดแอป TikTok ด้วยบัญชีที่เชื่อมต่อ ไปที่ Inbox แล้วแตะการแจ้งเตือน '
                      'เพื่อตรวจ แก้ไข และยืนยันเผยแพร่ด้วยตนเอง',
                  'A draft is not published to viewers. Open the TikTok app '
                      'with your connected account, go to Inbox, and tap the notification '
                      'to review, edit, and publish it yourself.'),
              style: TextStyle(
                  fontSize: 13, height: 1.5, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const ValueKey('tiktok-draft-open'),
              onPressed: _opening ? null : _openTikTok,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(_opening
                  ? _text('กำลังเปิด TikTok...', 'Opening TikTok...')
                  : _text('เปิด TikTok', 'Open TikTok')),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
            ),
            const SizedBox(height: 6),
            Text(
              _text(
                  'ปุ่มนี้อาจเปิดเป็นเว็บไซต์ หากเป็นเช่นนั้นให้เปิดแอป TikTok เอง '
                      'ปุ่มนี้ไม่ส่งคลิปซ้ำ',
                  'This button may open a website. If it does, open the TikTok '
                      'app yourself. This does not send your video again.'),
              style: TextStyle(
                  fontSize: 12, height: 1.4, color: AppTheme.textMuted),
            ),
            if (_openFailed) ...[
              const SizedBox(height: 8),
              Text(
                _text(
                    'เปิด TikTok ไม่สำเร็จ กรุณาเปิดแอป TikTok ด้วยตนเอง แล้วตรวจ Inbox',
                    'Could not open TikTok. Open the TikTok app yourself '
                        'and check Inbox.'),
                key: const ValueKey('tiktok-draft-open-error'),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error, height: 1.4),
              ),
            ],
          ],
        ),
      );
}
