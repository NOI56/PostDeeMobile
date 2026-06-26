import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../shared/postdee_card.dart';
import 'link_in_bio_draft_store.dart';

class LinkInBioScreen extends StatefulWidget {
  const LinkInBioScreen({
    super.key,
    this.draftStore = const SharedPreferencesLinkInBioDraftStore(),
  });

  final LinkInBioDraftStore draftStore;

  @override
  State<LinkInBioScreen> createState() => _LinkInBioScreenState();
}

class _LinkInBioScreenState extends State<LinkInBioScreen> {
  static const _recommendedProductLinkId = 'recommended_product';
  static const _dailyCampaignLinkId = 'daily_campaign';
  static const _scheduledClipLinkId = 'scheduled_clip';

  late final TextEditingController _storeNameController;
  late final TextEditingController _slugController;
  Set<String> _enabledLinkIds = LinkInBioDraft.defaults().enabledLinkIds;
  List<LinkInBioCustomLink> _customLinks = LinkInBioDraft.defaults().customLinks;
  bool _autoUpdateFromScheduledPosts = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final defaults = LinkInBioDraft.defaults();
    _storeNameController = TextEditingController(text: defaults.storeName);
    _slugController = TextEditingController(text: defaults.slug);
    _autoUpdateFromScheduledPosts = defaults.autoUpdateFromScheduledPosts;
    _loadDraft();
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _slugController.dispose();
    super.dispose();
  }

  void _showDraftMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _loadDraft() async {
    final draft = await widget.draftStore.loadDraft();

    if (!mounted || draft == null) {
      return;
    }

    setState(() {
      _storeNameController.text = draft.storeName;
      _slugController.text = draft.slug;
      _autoUpdateFromScheduledPosts = draft.autoUpdateFromScheduledPosts;
      _enabledLinkIds = draft.enabledLinkIds;
      _customLinks = draft.customLinks;
    });
  }

  bool _isLinkEnabled(String linkId) {
    return _enabledLinkIds.contains(linkId);
  }

  void _setLinkEnabled(String linkId, bool value) {
    final enabledLinkIds = {..._enabledLinkIds};

    if (value) {
      enabledLinkIds.add(linkId);
    } else {
      enabledLinkIds.remove(linkId);
    }

    setState(() {
      _enabledLinkIds = enabledLinkIds;
    });
  }

  Future<void> _saveDraft() async {
    final messenger = ScaffoldMessenger.of(context);
    final draft = LinkInBioDraft(
      storeName: _storeNameController.text.trim().isEmpty
          ? LinkInBioDraft.defaults().storeName
          : _storeNameController.text.trim(),
      slug: _slugController.text.trim().isEmpty
          ? LinkInBioDraft.defaults().slug
          : _slugController.text.trim(),
      autoUpdateFromScheduledPosts: _autoUpdateFromScheduledPosts,
      enabledLinkIds: _enabledLinkIds,
      customLinks: _customLinks,
    );

    setState(() {
      _isSaving = true;
    });

    try {
      await widget.draftStore.saveDraft(draft);
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('บันทึกแบบร่างไม่สำเร็จ')),
      );
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isSaving = false;
    });
    messenger.showSnackBar(
      const SnackBar(content: Text('บันทึกแบบร่างในเครื่องแล้ว')),
    );
  }

  Future<void> _showAddLinkSheet() async {
    final link = await showModalBottomSheet<LinkInBioCustomLink>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _AddLinkSheet(),
    );

    if (!mounted || link == null) {
      return;
    }

    setState(() {
      _customLinks = [..._customLinks, link];
      _enabledLinkIds = {..._enabledLinkIds, link.id};
    });
  }

  Future<void> _showEditLinkSheet(LinkInBioCustomLink existingLink) async {
    final updatedLink = await showModalBottomSheet<LinkInBioCustomLink>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddLinkSheet(initialLink: existingLink),
    );

    if (!mounted || updatedLink == null) {
      return;
    }

    setState(() {
      _customLinks = [
        for (final link in _customLinks)
          if (link.id == updatedLink.id) updatedLink else link,
      ];
    });
  }

  void _deleteCustomLink(String linkId) {
    setState(() {
      _customLinks = [
        for (final link in _customLinks)
          if (link.id != linkId) link,
      ];
      _enabledLinkIds = {
        for (final enabledLinkId in _enabledLinkIds)
          if (enabledLinkId != linkId) enabledLinkId,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: AppTheme.screenBackground,
        child: SafeArea(
          child: ListView(
            padding: AppTheme.screenPadding,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'กลับ',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Text(
                      'สร้างหน้า Link in Bio',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  PostDeeSoftPill(
                    label: '199 / 299',
                    icon: Icons.workspace_premium_outlined,
                    color: AppTheme.accentCyanInk,
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spaceMd),
              _BioPreviewCard(
                storeName: _storeNameController.text,
                slug: _slugController.text,
                customLinks: _customLinks,
                enabledLinkIds: _enabledLinkIds,
              ),
              const SizedBox(height: AppTheme.spaceLg),
              const PostDeeSectionHeader(title: 'ข้อมูลหน้าร้าน'),
              const SizedBox(height: AppTheme.spaceSm),
              PostDeeCard(
                padding: const EdgeInsets.all(AppTheme.spaceMd),
                glowColor: AppTheme.accentCyan,
                child: Column(
                  children: [
                    TextField(
                      controller: _storeNameController,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'ชื่อร้าน',
                        hintText: 'เช่น ร้านมินาขายดี',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _slugController,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'URL สั้น',
                        prefixText: 'postdee.link/',
                        hintText: 'store-name',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spaceLg),
              PostDeeSectionHeader(
                title: 'ลิงก์สินค้าและแคมเปญ',
                trailing: PostDeeSoftPill(
                  label: 'ร่าง',
                  icon: Icons.edit_note_outlined,
                  color: AppTheme.accentPinkInk,
                ),
              ),
              const SizedBox(height: AppTheme.spaceSm),
              _BioLinkTile(
                id: _recommendedProductLinkId,
                icon: Icons.shopping_bag_outlined,
                title: 'สินค้าแนะนำ',
                subtitle: 'ลิงก์ Shopee, Lazada หรือ affiliate หลัก',
                color: AppTheme.accentPinkInk,
                enabled: _isLinkEnabled(_recommendedProductLinkId),
                onChanged: _setLinkEnabled,
              ),
              const SizedBox(height: AppTheme.spaceMd),
              _BioLinkTile(
                id: _dailyCampaignLinkId,
                icon: Icons.local_fire_department_outlined,
                title: 'แคมเปญวันนี้',
                subtitle: 'ลิงก์โปรโมชันที่อยากดันจากโพสต์ล่าสุด',
                color: const Color(0xFFFFD166),
                enabled: _isLinkEnabled(_dailyCampaignLinkId),
                onChanged: _setLinkEnabled,
              ),
              const SizedBox(height: AppTheme.spaceMd),
              _BioLinkTile(
                id: _scheduledClipLinkId,
                icon: Icons.video_library_outlined,
                title: 'คลิปที่ตั้งเวลาไว้',
                subtitle: 'ให้หน้าโปรไฟล์อัปเดตลิงก์เมื่อคลิปถูกตั้งเวลา',
                color: AppTheme.accentCyanInk,
                enabled: _isLinkEnabled(_scheduledClipLinkId),
                onChanged: _setLinkEnabled,
              ),
              for (final customLink in _customLinks) ...[
                const SizedBox(height: AppTheme.spaceMd),
                _BioLinkTile(
                  id: customLink.id,
                  icon: Icons.link,
                  title: customLink.title,
                  subtitle: customLink.url,
                  color: AppTheme.successInk,
                  enabled: _isLinkEnabled(customLink.id),
                  onChanged: _setLinkEnabled,
                  onEdit: () => _showEditLinkSheet(customLink),
                  onDelete: () => _deleteCustomLink(customLink.id),
                ),
              ],
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _showAddLinkSheet,
                icon: const Icon(Icons.add_link_outlined),
                label: const Text('เพิ่มลิงก์'),
              ),
              const SizedBox(height: 14),
              _AutoUpdateCard(
                value: _autoUpdateFromScheduledPosts,
                onChanged: (value) => setState(() {
                  _autoUpdateFromScheduledPosts = value;
                }),
              ),
              const SizedBox(height: AppTheme.spaceLg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showDraftMessage(
                        'พรีวิวหน้า Link in Bio จะเชื่อมเว็บจริงในขั้นต่อไป',
                      ),
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('ดูตัวอย่างหน้า'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PostDeeGradientButton(
                      label: _isSaving ? 'กำลังบันทึก...' : 'บันทึกแบบร่าง',
                      icon: Icons.save_outlined,
                      onPressed: _isSaving ? null : _saveDraft,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BioPreviewCard extends StatelessWidget {
  const _BioPreviewCard({
    required this.storeName,
    required this.slug,
    required this.customLinks,
    required this.enabledLinkIds,
  });

  final String storeName;
  final String slug;
  final List<LinkInBioCustomLink> customLinks;
  final Set<String> enabledLinkIds;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final displayName = storeName.trim().isEmpty ? 'ร้านของคุณ' : storeName;
    final displaySlug = slug.trim().isEmpty ? 'ร้านของคุณ' : slug;

    return PostDeeCard(
      padding: const EdgeInsets.all(14),
      glowColor: AppTheme.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTheme.brandGradient,
                ),
                child: const SizedBox(
                  width: 46,
                  height: 46,
                  child: Icon(
                    Icons.storefront_outlined,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'postdee.link/$displaySlug',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppTheme.accentCyanInk,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const PostDeeSoftPill(
                label: 'Preview',
                icon: Icons.phone_iphone,
                color: AppTheme.accent,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PreviewLinkButton(
            label: 'ดูสินค้าจากคลิปล่าสุด',
            icon: Icons.play_circle_outline,
            color: AppTheme.accentPinkInk,
          ),
          const SizedBox(height: AppTheme.spaceSm),
          _PreviewLinkButton(
            label: 'โปรโมชันและคูปอง',
            icon: Icons.sell_outlined,
            color: AppTheme.accentCyanInk,
          ),
          const SizedBox(height: AppTheme.spaceSm),
          _PreviewLinkButton(
            label: 'ช่องทางติดต่อร้าน',
            icon: Icons.chat_bubble_outline,
            color: AppTheme.successInk,
          ),
          for (final customLink in customLinks)
            if (enabledLinkIds.contains(customLink.id)) ...[
              const SizedBox(height: AppTheme.spaceSm),
              _PreviewLinkButton(
                label: customLink.title,
                icon: Icons.link,
                color: AppTheme.successInk,
              ),
            ],
        ],
      ),
    );
  }
}

class _PreviewLinkButton extends StatelessWidget {
  const _PreviewLinkButton({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.tileRadius),
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: AppTheme.spaceSm),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            Icon(
              Icons.open_in_new,
              color: AppTheme.textSecondary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _BioLinkTile extends StatelessWidget {
  const _BioLinkTile({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.enabled,
    required this.onChanged,
    this.onEdit,
    this.onDelete,
  });

  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool enabled;
  final void Function(String id, bool value) onChanged;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return PostDeeCard(
      padding: const EdgeInsets.all(AppTheme.spaceMd),
      glowColor: color,
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.tileRadius),
              color: color.withValues(alpha: 0.14),
              border: Border.all(color: color.withValues(alpha: 0.32)),
            ),
            child: SizedBox(
              width: 38,
              height: 38,
              child: Icon(icon, color: color, size: 20),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                        height: 1.25,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spaceSm),
          if (onEdit != null) ...[
            _LinkActionButton(
              tooltip: 'แก้ไขลิงก์',
              icon: Icons.edit_outlined,
              color: color,
              onPressed: onEdit!,
            ),
            const SizedBox(width: AppTheme.spaceXs),
          ],
          if (onDelete != null) ...[
            _LinkActionButton(
              tooltip: 'ลบลิงก์',
              icon: Icons.delete_outline,
              color: AppTheme.accentPinkInk,
              onPressed: onDelete!,
            ),
            const SizedBox(width: AppTheme.spaceXs),
          ],
          Switch(
            value: enabled,
            onChanged: (value) => onChanged(id, value),
          ),
        ],
      ),
    );
  }
}

class _LinkActionButton extends StatelessWidget {
  const _LinkActionButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

class _AutoUpdateCard extends StatelessWidget {
  const _AutoUpdateCard({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return PostDeeCard(
      padding: const EdgeInsets.all(AppTheme.spaceMd),
      glowColor: AppTheme.accentCyan,
      child: Row(
        children: [
          Icon(
            Icons.event_repeat_outlined,
            color: AppTheme.accentCyanInk,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'อัปเดตจากโพสต์ที่ตั้งเวลา',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                Text(
                  'เมื่อมีคลิปตั้งเวลาไว้ ระบบจะเตรียมลิงก์สินค้าให้หน้าโปรไฟล์',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                        height: 1.25,
                      ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _AddLinkSheet extends StatefulWidget {
  const _AddLinkSheet({
    this.initialLink,
  });

  final LinkInBioCustomLink? initialLink;

  @override
  State<_AddLinkSheet> createState() => _AddLinkSheetState();
}

class _AddLinkSheetState extends State<_AddLinkSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _urlController;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialLink?.title);
    _urlController = TextEditingController(text: widget.initialLink?.url);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    final url = _urlController.text.trim();

    if (title.isEmpty || url.isEmpty) {
      setState(() {
        _errorMessage = 'กรอกชื่อปุ่มและ URL ก่อนบันทึก';
      });
      return;
    }

    Navigator.of(context).pop(
      LinkInBioCustomLink(
        id: widget.initialLink?.id ??
            'custom_${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        url: url,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final isEditing = widget.initialLink != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.pitchBlack,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(
          top: BorderSide(color: AppTheme.accentCyan.withValues(alpha: 0.42)),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottomInset),
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
              children: [
                Icon(
                  Icons.add_link_outlined,
                  color: AppTheme.accentCyanInk,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isEditing ? 'แก้ไขลิงก์' : 'เพิ่มลิงก์ใหม่',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'ปิด',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _titleController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'ชื่อปุ่ม',
                hintText: 'เช่น คูปอง Shopee',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'URL ปลายทาง',
                hintText: 'https://...',
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: AppTheme.spaceSm),
              Text(
                _errorMessage!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
            const SizedBox(height: 14),
            PostDeeGradientButton(
              label: 'บันทึกลิงก์',
              icon: Icons.check,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
