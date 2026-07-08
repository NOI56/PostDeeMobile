import 'package:flutter/material.dart';

import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../shared/postdee_card.dart';
import '../shared/postdee_notice.dart';

typedef TemplateLoader = Future<List<TextTemplateResult>> Function();
typedef TemplateCreator = Future<TextTemplateResult> Function({
  required String title,
  required String body,
});

class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({
    super.key,
    this.loadTemplates,
    this.createTemplate,
  });

  final TemplateLoader? loadTemplates;
  final TemplateCreator? createTemplate;

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  final _apiClient = PostDeeApiClient();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final List<TextTemplateResult> _templates = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final loader = widget.loadTemplates ?? _apiClient.listTemplates;
      final templates = await loader();

      if (!mounted) {
        return;
      }

      setState(() {
        _templates
          ..clear()
          ..addAll(templates);
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Unexpected error: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveTemplate() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (title.isEmpty || body.isEmpty) {
      setState(() {
        _errorMessage = 'กรอกชื่อและเนื้อหาเทมเพลตก่อนบันทึก';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final creator = widget.createTemplate ?? _apiClient.createTemplate;
      final template = await creator(title: title, body: body);

      if (!mounted) {
        return;
      }

      setState(() {
        _templates.insert(0, template);
        _titleController.clear();
        _bodyController.clear();
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Unexpected error: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                decoration: const InputDecoration(
                  labelText: 'ชื่อเทมเพลต',
                  hintText: 'เช่น โปรโมชันส่งฟรี',
                ),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              TextField(
                controller: _bodyController,
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
                        onPressed: _isSaving ? null : _saveTemplate,
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
                      onPressed: _isLoading ? null : _loadTemplates,
                      icon: const Icon(Icons.sync, size: 18),
                      label: Text(
                          _isLoading ? 'กำลังโหลดเทมเพลต...' : 'โหลดเทมเพลต'),
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
        if (_templates.isEmpty)
          const _EmptyTemplateCard()
        else
          ..._templates.map(
            (template) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SavedTemplateCard(template: template),
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
            'ยังไม่มีเทมเพลตที่โหลด',
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
  const _SavedTemplateCard({required this.template});

  final TextTemplateResult template;

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
