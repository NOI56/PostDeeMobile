import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/localization/postdee_localizations.dart';
import '../../core/network/api_error_message.dart';
import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../home/home_service_status_banner.dart';
import '../shared/postdee_notice.dart';

typedef SupportChatLoader = Future<SupportChatResult> Function({String? after});
typedef SupportMessageSender = Future<SupportMessageResult> Function({
  required String id,
  required String body,
});

/// A random version-4 UUID, made once per message so the server recognizes
/// a retry after a lost response instead of storing the message twice.
String newSupportMessageId([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// The member's chat with the PostDee team. Known service problems show at
/// the top, and new replies are polled while the screen is open.
class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({
    super.key,
    this.loadChat,
    this.sendMessage,
    this.loadServiceStatus,
    this.pollInterval = const Duration(seconds: 5),
    this.newMessageId = newSupportMessageId,
    this.now,
  });

  final SupportChatLoader? loadChat;
  final SupportMessageSender? sendMessage;
  final HomeServiceStatusLoader? loadServiceStatus;
  final Duration pollInterval;
  final String Function() newMessageId;
  final DateTime Function()? now;

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _Outgoing {
  _Outgoing(this.id, this.body);

  final String id;
  final String body;
  bool failed = false;
}

class _SupportChatScreenState extends State<SupportChatScreen>
    with WidgetsBindingObserver {
  PostDeeApiClient? _client;
  final _messages = <SupportMessageResult>[];
  final _outgoing = <_Outgoing>[];
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  String? _cursor;
  var _loading = true;
  String? _loadError;
  String? _sendError;
  Timer? _timer;
  var _polling = false;
  var _appResumed = true;
  var _generation = 0;

  SupportChatLoader get _load =>
      widget.loadChat ?? (_client ??= PostDeeApiClient()).loadSupportChat;
  SupportMessageSender get _send =>
      widget.sendMessage ??
      (_client ??= PostDeeApiClient()).sendSupportMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _composer.addListener(() => setState(() {}));
    _initialLoad();
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    if (_appResumed) unawaited(_poll());
    _syncTimer();
  }

  // Polls only while the chat is loaded and the app is in the foreground.
  void _syncTimer() {
    final shouldRun =
        mounted && _appResumed && !_loading && _loadError == null;
    if (shouldRun && _timer == null) {
      _timer = Timer.periodic(widget.pollInterval, (_) => unawaited(_poll()));
    } else if (!shouldRun) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _initialLoad() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final result = await _load();
      if (!mounted || generation != _generation) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(result.messages);
        _cursor = result.cursor;
        _loading = false;
      });
      _scrollToEnd();
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _loadError = apiErrorMessage(error,
            fallbackMessage: 'โหลดแชทไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
      });
    }
    _syncTimer();
  }

  Future<void> _poll() async {
    if (_polling || _loading || _loadError != null || !mounted) return;
    _polling = true;
    final generation = _generation;
    try {
      final result = await _load(after: _cursor);
      if (!mounted || generation != _generation) return;
      _merge(result.messages, cursor: result.cursor);
    } catch (_) {
      // A missed poll is simply retried on the next tick.
    } finally {
      _polling = false;
    }
  }

  // Sent messages are merged without moving the cursor, so a team reply that
  // landed meanwhile is still fetched by the next poll.
  void _merge(List<SupportMessageResult> incoming, {String? cursor}) {
    final known = _messages.map((message) => message.id).toSet();
    final fresh =
        incoming.where((message) => !known.contains(message.id)).toList();
    setState(() {
      _messages
        ..addAll(fresh)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _outgoing.removeWhere(
          (pending) => _messages.any((message) => message.id == pending.id));
      if (cursor != null) _cursor = cursor;
    });
    if (fresh.isNotEmpty) _scrollToEnd();
  }

  Future<void> _submit() async {
    final body = _composer.text.trim();
    if (body.isEmpty) return;
    final outgoing = _Outgoing(widget.newMessageId(), body);
    _composer.clear();
    setState(() => _outgoing.add(outgoing));
    _scrollToEnd();
    await _deliver(outgoing);
  }

  Future<void> _deliver(_Outgoing outgoing) async {
    setState(() {
      outgoing.failed = false;
      _sendError = null;
    });
    try {
      final message = await _send(id: outgoing.id, body: outgoing.body);
      if (!mounted) return;
      _merge([message]);
    } catch (error) {
      if (!mounted) return;
      final isLimit =
          error is ApiException && error.code == 'SUPPORT_MESSAGE_LIMIT';
      setState(() {
        outgoing.failed = true;
        _sendError = isLimit
            ? 'วันนี้ส่งข้อความครบจำนวนแล้ว รอทีมงานตอบกลับก่อน'
            : apiErrorMessage(error,
                fallbackMessage:
                    'ส่งข้อความไม่สำเร็จ แตะข้อความเพื่อส่งอีกครั้ง');
      });
    }
  }

  void _discard(_Outgoing outgoing) => setState(() {
        _outgoing.remove(outgoing);
        if (!_outgoing.any((pending) => pending.failed)) _sendError = null;
      });

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  String _time(DateTime value, bool isThai) {
    final now = (widget.now ?? DateTime.now)();
    final time = '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
    final sameDay = value.year == now.year &&
        value.month == now.month &&
        value.day == now.day;
    final when = sameDay ? time : '${value.day}/${value.month} $time';
    return isThai ? '$when น.' : when;
  }

  @override
  Widget build(BuildContext context) {
    final isThai =
        PostDeeLocalizations.of(context).locale.languageCode == 'th';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isThai ? 'แชทกับทีมงาน' : 'Chat with the team',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: AppTheme.screenBackground,
          child: Column(
            children: [
              Expanded(child: _buildBody(isThai)),
              _buildComposer(isThai),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(bool isThai) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Align(
          alignment: Alignment.topCenter,
          child: PostDeeNotice(
            message: _loadError!,
            actionLabel: isThai ? 'ลองใหม่' : 'Retry',
            onAction: _initialLoad,
          ),
        ),
      );
    }
    return ListView(
      key: const ValueKey('support-chat-list'),
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        HomeServiceStatusBanner(
          isActive: true,
          loadStatus: widget.loadServiceStatus,
          now: widget.now,
        ),
        const SizedBox(height: 14),
        Text(
          isThai
              ? 'ทีมงาน PostDee จะตอบกลับในแชทนี้ และแจ้งเตือนเมื่อมีคำตอบ · '
                  'ห้ามส่งรหัสผ่าน รหัส OTP หรือข้อมูลบัตร'
              : 'The PostDee team replies here and notifies you. '
                  'Never send passwords, OTP codes or card details.',
          style: TextStyle(
            fontSize: 12,
            height: 1.45,
            color: AppTheme.textMuted,
          ),
        ),
        const SizedBox(height: 12),
        if (_messages.isEmpty && _outgoing.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Text(
              isThai
                  ? 'มีปัญหาหรือคำถาม พิมพ์บอกทีมงานได้เลย'
                  : 'Have a problem or question? Tell the team.',
              key: const ValueKey('support-chat-empty'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
          ),
        for (final message in _messages)
          _SupportBubble(
            key: ValueKey('support-message-${message.id}'),
            body: message.body,
            fromTeam: message.isFromTeam,
            teamLabel: isThai ? 'ทีมงาน PostDee' : 'PostDee team',
            meta: _time(message.createdAt, isThai),
          ),
        for (final pending in _outgoing)
          _SupportBubble(
            key: ValueKey('support-pending-${pending.id}'),
            body: pending.body,
            fromTeam: false,
            teamLabel: '',
            meta: pending.failed
                ? (isThai
                    ? 'ส่งไม่สำเร็จ · แตะเพื่อส่งอีกครั้ง'
                    : 'Not sent · tap to retry')
                : (isThai ? 'กำลังส่ง…' : 'Sending…'),
            failed: pending.failed,
            onRetry: pending.failed ? () => _deliver(pending) : null,
            onDiscard: pending.failed ? () => _discard(pending) : null,
            discardLabel: isThai ? 'ลบข้อความนี้' : 'Remove this message',
          ),
      ],
    );
  }

  Widget _buildComposer(bool isThai) {
    final canSend = !_loading &&
        _loadError == null &&
        _composer.text.trim().isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.midnight,
        border: Border(top: BorderSide(color: AppTheme.borderSoft)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_sendError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 4),
                child: Text(
                  _sendError!,
                  key: const ValueKey('support-chat-send-error'),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('support-chat-input'),
                    controller: _composer,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 1000,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: isThai
                          ? 'พิมพ์ข้อความถึงทีมงาน'
                          : 'Message the team',
                      counterText: '',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  key: const ValueKey('support-chat-send'),
                  tooltip: isThai ? 'ส่ง' : 'Send',
                  onPressed: canSend ? _submit : null,
                  icon: const Icon(Icons.send_rounded, size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportBubble extends StatelessWidget {
  const _SupportBubble({
    super.key,
    required this.body,
    required this.fromTeam,
    required this.teamLabel,
    required this.meta,
    this.failed = false,
    this.onRetry,
    this.onDiscard,
    this.discardLabel,
  });

  final String body;
  final bool fromTeam;
  final String teamLabel;
  final String meta;
  final bool failed;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;
  final String? discardLabel;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    final bubble = DecoratedBox(
      decoration: BoxDecoration(
        color: fromTeam ? AppTheme.glass : AppTheme.mint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: failed ? error.withValues(alpha: 0.6) : AppTheme.borderSoft,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
        child: Column(
          crossAxisAlignment:
              fromTeam ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            if (fromTeam)
              Text(
                teamLabel,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentCyanInk,
                ),
              ),
            Text(
              body,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              meta,
              style: TextStyle(
                fontSize: 11,
                color: failed ? error : AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            fromTeam ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (onDiscard != null)
            IconButton(
              tooltip: discardLabel,
              onPressed: onDiscard,
              icon: Icon(Icons.close_rounded, size: 18, color: error),
            ),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.78,
              ),
              child: onRetry == null
                  ? bubble
                  : InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: onRetry,
                      child: bubble,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
