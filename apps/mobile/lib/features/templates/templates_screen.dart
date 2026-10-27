import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/network/postdee_api_client.dart';
import '../../core/network/api_error_message.dart';
import '../../core/theme/app_theme.dart';
import '../shared/postdee_card.dart';
import '../shared/postdee_notice.dart';

typedef TemplateLoader = Future<List<TextTemplateResult>> Function();
typedef TemplateCreator = Future<TextTemplateResult> Function({
  required String title,
  required String body,
});

typedef TemplateDeleter = Future<void> Function(String templateId);

enum _TemplateExitAction { discard, save }

class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({
    super.key,
    this.loadTemplates,
    this.createTemplate,
    this.deleteTemplate,
  });

  final TemplateLoader? loadTemplates;
  final TemplateCreator? createTemplate;
  final TemplateDeleter? deleteTemplate;

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  final _sessions = PostDeeAuthSessionStore.instance;
  late final AuthSessionBinding _screenSession;
  late final PostDeeApiClient _apiClient;
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final List<TextTemplateResult> _templates = [];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _hasLoaded = false;
  bool _allowPop = false;
  bool _isConfirmingExit = false;
  DialogRoute<_TemplateExitAction>? _exitDialogRoute;
  String? _errorMessage;

  bool get _canUseScreen => mounted && _screenSession.isCurrent;
  bool get _hasUnsavedChanges =>
      _titleController.text.isNotEmpty || _bodyController.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _screenSession = _sessions.captureSession();
    _apiClient = PostDeeApiClient(sessionBinding: _screenSession);
    _sessions.addListener(_handleSessionChanged);
    unawaited(_loadTemplates());
  }

  @override
  void dispose() {
    _sessions.removeListener(_handleSessionChanged);
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _handleSessionChanged() {
    if (!mounted || _screenSession.isCurrent) return;
    final dialog = _exitDialogRoute;
    _exitDialogRoute = null;
    if (dialog != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (dialog.isActive) dialog.navigator?.removeRoute(dialog);
      });
    }
    setState(() {
      _templates.clear();
      _titleController.clear();
      _bodyController.clear();
      _isLoading = false;
      _isSaving = false;
      _hasLoaded = false;
      _errorMessage = 'บัญชีเปลี่ยนแล้ว กรุณาเปิดหน้าเทมเพลตใหม่';
    });
  }

  Future<void> _confirmExit() async {
    if (!_canUseScreen || _isConfirmingExit || _isSaving) return;
    _isConfirmingExit = true;
    final route = DialogRoute<_TemplateExitAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ยังไม่ได้บันทึกเทมเพลต'),
        content: const Text('ต้องการบันทึกข้อความก่อนออกจากหน้านี้ไหม?'),
        scrollable: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('แก้ต่อ'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_TemplateExitAction.discard),
            child: const Text('ออกโดยไม่บันทึก'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_TemplateExitAction.save),
            child: const Text('บันทึกแล้วออก'),
          ),
        ],
      ),
    );
    _exitDialogRoute = route;
    try {
      final action =
          await Navigator.of(context, rootNavigator: true).push(route);
      if (!_canUseScreen) return;
      if (action == _TemplateExitAction.discard) {
        _leave();
      } else if (action == _TemplateExitAction.save) {
        final saved = await _saveTemplate();
        if (_canUseScreen && saved && !_hasUnsavedChanges) _leave();
      }
    } finally {
      if (identical(_exitDialogRoute, route)) _exitDialogRoute = null;
      _isConfirmingExit = false;
    }
  }

  void _leave() {
    if (!_canUseScreen) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_canUseScreen) return;
      if (ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      } else {
        setState(() => _allowPop = false);
      }
    });
  }

  Future<void> _loadTemplates() async {
    if (!_canUseScreen || _isLoading || _isSaving) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final loader = widget.loadTemplates ?? _apiClient.listTemplates;
      final templates = await loader();

      if (!_canUseScreen) {
        return;
      }

      setState(() {
        _templates
          ..clear()
          ..addAll(templates);
        _hasLoaded = true;
      });
    } on ApiException catch (error) {
      if (!_canUseScreen) {
        return;
      }

      setState(() {
        _errorMessage = apiErrorMessage(error,
            fallbackMessage: 'โหลดเทมเพลตไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
      });
    } catch (error) {
      if (!_canUseScreen) {
        return;
      }

      setState(() {
        _errorMessage = apiErrorMessage(error,
            fallbackMessage: 'โหลดเทมเพลตไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
      });
    } finally {
      if (_canUseScreen) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<bool> _saveTemplate() async {
    if (!_canUseScreen || _isSaving) return false;
    if (_isLoading) {
      setState(
          () => _errorMessage = 'กำลังโหลดรายการ กรุณารอสักครู่ก่อนบันทึก');
      return false;
    }
    final originalTitle = _titleController.text;
    final originalBody = _bodyController.text;
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (title.isEmpty || body.isEmpty) {
      setState(() {
        _errorMessage = 'กรอกชื่อและเนื้อหาเทมเพลตก่อนบันทึก';
      });
      return false;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final creator = widget.createTemplate ?? _apiClient.createTemplate;
      final template = await creator(title: title, body: body);

      if (!_canUseScreen) {
        return false;
      }

      setState(() {
        _templates.insert(0, template);
        _hasLoaded = true;
        if (_titleController.text == originalTitle &&
            _bodyController.text == originalBody) {
          _titleController.clear();
          _bodyController.clear();
        }
      });
      return true;
    } on ApiException catch (error) {
      if (!_canUseScreen) {
        return false;
      }

      setState(() {
        _errorMessage = apiErrorMessage(error,
            fallbackMessage: 'บันทึกเทมเพลตไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
      });
    } catch (error) {
      if (!_canUseScreen) {
        return false;
      }

      setState(() {
        _errorMessage = apiErrorMessage(error,
            fallbackMessage: 'บันทึกเทมเพลตไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
      });
    } finally {
      if (_canUseScreen) {
        setState(() {
          _isSaving = false;
        });
      }
    }
    return false;
  }

  Future<void> _confirmAndDeleteTemplate(TextTemplateResult template) async {
    if (!_canUseScreen) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ลบเทมเพลตนี้?'),
        content: Text(template.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );

    if (confirmed != true || !_canUseScreen) return;

    try {
      final deleter = widget.deleteTemplate ?? _apiClient.deleteTemplate;
      await deleter(template.id);
      if (!_canUseScreen) return;
      setState(() {
        _templates.removeWhere((saved) => saved.id == template.id);
        _errorMessage = null;
      });
    } catch (error) {
      if (!_canUseScreen) return;
      setState(() {
        _errorMessage = apiErrorMessage(error,
            fallbackMessage: 'ลบเทมเพลตไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop ||
          !_screenSession.isCurrent ||
          (!_hasUnsavedChanges && !_isSaving),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_confirmExit());
      },
      child: _buildTemplates(),
    );
  }

  Widget _buildTemplates() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        Text(
          'เทมเพลต',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'จัดการแคปชั่นที่ใช้บ่อย',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
              ),
        ),
        const SizedBox(height: 14),
        PostDeeCard(
          glowColor: AppTheme.accentPink,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppTheme.mint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.text_snippet_outlined,
                      size: 19,
                      color: AppTheme.accentCyanInk,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'สร้างเทมเพลตใหม่',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _titleController,
                enabled: _canUseScreen,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'ชื่อเทมเพลต',
                  hintText: 'เช่น โปรโมชันส่งฟรี',
                ),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              TextField(
                controller: _bodyController,
                enabled: _canUseScreen,
                onChanged: (_) => setState(() {}),
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'เนื้อหาเทมเพลต',
                  hintText: 'ข้อความที่อยากใช้ซ้ำในแคปชั่น',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: FilledButton.icon(
                        onPressed: !_canUseScreen || _isSaving || _isLoading
                            ? null
                            : _saveTemplate,
                        icon: const Icon(Icons.save_outlined, size: 19),
                        label: Text(
                            _isSaving ? 'กำลังบันทึก...' : 'บันทึกเทมเพลต'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              AppTheme.accent.withValues(alpha: 0.55),
                          disabledForegroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spaceMd),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: !_canUseScreen || _isLoading || _isSaving
                          ? null
                          : _loadTemplates,
                      icon: const Icon(Icons.sync, size: 18),
                      label: Text(
                          _isLoading ? 'กำลังโหลดเทมเพลต...' : 'รีเฟรชเทมเพลต'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.spaceLg),
        if (_errorMessage != null) ...[
          PostDeeNotice(
            message: _errorMessage!,
            color: Theme.of(context).colorScheme.error,
            icon: Icons.error_outline,
          ),
          const SizedBox(height: AppTheme.spaceMd),
        ],
        Text(
          'เทมเพลตที่บันทึกไว้',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: AppTheme.spaceMd),
        if (_templates.isEmpty && _hasLoaded && !_isLoading)
          const _EmptyTemplateCard()
        else
          ..._templates.map(
            (template) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SavedTemplateCard(
                template: template,
                onDelete: () => _confirmAndDeleteTemplate(template),
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptyTemplateCard extends StatelessWidget {
  const _EmptyTemplateCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
      decoration: BoxDecoration(
        color: AppTheme.glass,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.glassDeep,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              Icons.text_snippet_outlined,
              size: 27,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'ยังไม่มีเทมเพลตที่บันทึกไว้',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'บันทึกแคปชั่นที่ใช้บ่อยไว้ด้านบน\nแล้วหยิบมาใช้ตอนสร้างโพสต์ได้ทันที',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedTemplateCard extends StatelessWidget {
  const _SavedTemplateCard({required this.template, required this.onDelete});

  final TextTemplateResult template;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.glass,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF122018).withValues(alpha: 0.04),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.notes,
                size: 18,
                color: AppTheme.accentCyanInk,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  template.title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('template-delete-${template.id}'),
                onPressed: onDelete,
                tooltip: 'ลบเทมเพลต',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            template.body,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
