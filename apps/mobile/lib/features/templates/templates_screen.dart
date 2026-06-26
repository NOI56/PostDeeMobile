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
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(AppTheme.spaceSm),
                      child: Icon(
                        Icons.text_snippet_outlined,
                        color: AppTheme.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'สร้างเทมเพลตใหม่',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
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
                    child: _GradientTemplateButton(
                      onPressed: _isSaving ? null : _saveTemplate,
                      icon: Icons.save_outlined,
                      label: _isSaving ? 'กำลังบันทึก...' : 'บันทึกเทมเพลต',
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

class _GradientTemplateButton extends StatelessWidget {
  const _GradientTemplateButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          colors: isEnabled
              ? const [
                  AppTheme.accentPink,
                  AppTheme.accent,
                  AppTheme.accentCyan,
                ]
              : const [
                  Color(0xFF2A2D36),
                  Color(0xFF20232B),
                ],
        ),
        boxShadow: isEnabled
            ? [
                BoxShadow(
                  color: AppTheme.accent.withValues(alpha: 0.16),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : const [],
      ),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 18),
        label: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}


class _EmptyTemplateCard extends StatelessWidget {
  const _EmptyTemplateCard();

  @override
  Widget build(BuildContext context) {
    return PostDeeCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppTheme.accentCyan.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: EdgeInsets.all(10),
              child: Icon(
                Icons.library_books_outlined,
                color: AppTheme.accentCyanInk,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ยังไม่มีเทมเพลตที่โหลด',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'กดโหลดเทมเพลต หรือสร้างรายการใหม่เพื่อใช้ซ้ำตอนอัปโหลด',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                ),
              ],
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
    return PostDeeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.notes_outlined,
                color: AppTheme.accentCyanInk,
                size: 20,
              ),
              const SizedBox(width: AppTheme.spaceSm),
              Expanded(
                child: Text(
                  template.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const _TemplateStatusPill(label: 'พร้อมใช้'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            template.body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _TemplateStatusPill extends StatelessWidget {
  const _TemplateStatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.success.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppTheme.successInk,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}
