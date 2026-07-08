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
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppTheme.mint,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      child: Text(
                        '199 / 299',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accentCyanInk,
                        ),
                      ),
                    ),
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
              Text(
                'ข้อมูลหน้าร้าน',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
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
              Text(
                'ลิงก์สินค้าและแคมเปญ',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: AppTheme.spaceSm),
              _BioLinkTile(
                id: _recommendedProductLinkId,
                icon: Icons.shopping_bag_outlined,
                title: 'สินค้าแนะนำ',
                subtitle: 'ลิงก์ Shopee, Lazada หรือ affiliate หลัก',
                color: const Color(0xFFEC4899),
                enabled: _isLinkEnabled(_recommendedProductLinkId),
                onChanged: _setLinkEnabled,
              ),
              const SizedBox(height: AppTheme.spaceMd),
              _BioLinkTile(
                id: _dailyCampaignLinkId,
                icon: Icons.local_fire_department_outlined,
                title: 'แคมเปญวันนี้',
                subtitle: 'โปรโมชันที่อยากดันจากโพสต์ล่าสุด',
                color: const Color(0xFFF59E0B),
                enabled: _isLinkEnabled(_dailyCampaignLinkId),
                onChanged: _setLinkEnabled,
              ),
              const SizedBox(height: AppTheme.spaceMd),
              _BioLinkTile(
                id: _scheduledClipLinkId,
                icon: Icons.video_library_outlined,
                title: 'คลิปที่ตั้งเวลาไว้',
                subtitle: 'ให้หน้าโปรไฟล์อัปเดตลิงก์อัตโนมัติ',
                color: const Color(0xFF0EA5B7),
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
                  color: AppTheme.accentCyanInk,
                  enabled: _isLinkEnabled(customLink.id),
                  onChanged: _setLinkEnabled,
                  onEdit: () => _showEditLinkSheet(customLink),
                  onDelete: () => _deleteCustomLink(customLink.id),
                ),
              ],
              const SizedBox(height: 11),
              _AddLinkButton(onTap: _showAddLinkSheet),
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
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton(
                        onPressed: () => _showDraftMessage(
                          'พรีวิวหน้า Link in Bio จะเชื่อมเว็บจริงในขั้นต่อไป',
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppTheme.border),
                          foregroundColor: AppTheme.textPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text('ดูตัวอย่างหน้า'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _saveDraft,
                        icon: const Icon(Icons.save_outlined, size: 19),
                        label: Text(
                            _isSaving ? 'กำลังบันทึก...' : 'บันทึกแบบร่าง'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              AppTheme.accent.withValues(alpha: 0.55),
                          disabledForegroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
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
    final displayName = storeName.trim().isEmpty ? 'ร้านของคุณ' : storeName;
    final displaySlug = slug.trim().isEmpty ? 'ร้านของคุณ' : slug;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E9F6E), Color(0xFF0A7A55)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B7A55).withValues(alpha: 0.55),
            blurRadius: 30,
            spreadRadius: -16,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                child: const Icon(
                  Icons.storefront_outlined,
                  color: Colors.white,
                  size: 25,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'postdee.link/$displaySlug',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  child: Text(
                    'Preview',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          if (enabledLinkIds.contains('recommended_product'))
            const _PreviewLinkButton(
              label: 'สินค้าแนะนำ',
              icon: Icons.shopping_bag_outlined,
            ),
          if (enabledLinkIds.contains('daily_campaign'))
            const _PreviewLinkButton(
              label: 'แคมเปญวันนี้',
              icon: Icons.local_fire_department_outlined,
            ),
          if (enabledLinkIds.contains('scheduled_clip'))
            const _PreviewLinkButton(
              label: 'คลิปที่ตั้งเวลาไว้',
              icon: Icons.video_library_outlined,
            ),
          for (final customLink in customLinks)
            if (enabledLinkIds.contains(customLink.id))
              _PreviewLinkButton(label: customLink.title, icon: Icons.link),
        ],
      ),
    );
  }
}

class _PreviewLinkButton extends StatelessWidget {
  const _PreviewLinkButton({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          color: Colors.white.withValues(alpha: 0.16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              Icon(
                Icons.open_in_new,
                color: Colors.white.withValues(alpha: 0.7),
                size: 15,
              ),
            ],
          ),
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
    return Semantics(
      label: title,
      toggled: enabled,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => onChanged(id, !enabled),
        child: Container(
          padding: const EdgeInsets.all(13),
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
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  color: color.withValues(alpha: 0.14),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
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
                  color: AppTheme.textSecondary,
                  onPressed: onEdit!,
                ),
                const SizedBox(width: AppTheme.spaceXs),
              ],
              if (onDelete != null) ...[
                _LinkActionButton(
                  tooltip: 'ลบลิงก์',
                  icon: Icons.delete_outline,
                  color: const Color(0xFFEF4444),
                  onPressed: onDelete!,
                ),
                const SizedBox(width: AppTheme.spaceXs),
              ],
              ExcludeSemantics(child: _BioSwitch(isOn: enabled)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 46x27 pill switch with a 21px white knob, per the design handoff.
class _BioSwitch extends StatelessWidget {
  const _BioSwitch({required this.isOn});

  final bool isOn;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 46,
      height: 27,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isOn ? AppTheme.accent : AppTheme.track,
        borderRadius: BorderRadius.circular(999),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: isOn ? Alignment.centerRight : Alignment.centerLeft,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x33122018),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: SizedBox.square(dimension: 21),
        ),
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
    return Semantics(
      label: 'อัปเดตจากโพสต์ที่ตั้งเวลา',
      toggled: value,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => onChanged(!value),
        child: Container(
          padding: const EdgeInsets.all(13),
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
          child: Row(
            children: [
              Icon(
                Icons.event_repeat_outlined,
                size: 21,
                color: AppTheme.accentCyanInk,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'อัปเดตจากโพสต์ที่ตั้งเวลา',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'เตรียมลิงก์สินค้าให้หน้าโปรไฟล์อัตโนมัติ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.spaceSm),
              ExcludeSemantics(child: _BioSwitch(isOn: value)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddLinkButton extends StatelessWidget {
  const _AddLinkButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'เพิ่มลิงก์',
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: CustomPaint(
          foregroundPainter: _DashedRRectBorderPainter(
            color: AppTheme.border,
            radius: 13,
          ),
          child: SizedBox(
            height: 46,
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_link, size: 19, color: AppTheme.accentCyanInk),
                const SizedBox(width: 7),
                Text(
                  'เพิ่มลิงก์',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.accentCyanInk,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRRectBorderPainter extends CustomPainter {
  const _DashedRRectBorderPainter({
    required this.color,
    required this.radius,
  })  : dash = 7,
        gap = 6,
        strokeWidth = 1;

  final Color color;
  final double radius;
  final double dash;
  final double gap;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dash;
        canvas.drawPath(
          metric.extractPath(
            distance,
            next > metric.length ? metric.length : next,
          ),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
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
