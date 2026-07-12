import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class PostDeeStatusSheetData {
  const PostDeeStatusSheetData({
    required this.icon,
    required this.iconColor,
    required this.iconTint,
    required this.title,
    required this.body,
    required this.primaryLabel,
    this.secondaryLabel = 'ปิด',
  });

  final IconData icon;
  final Color iconColor;
  final Color iconTint;
  final String title;
  final String body;
  final String primaryLabel;
  final String? secondaryLabel;
}

Future<bool?> showPostDeeStatusSheet(
  BuildContext context, {
  required PostDeeStatusSheetData data,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xFF0A120E).withValues(alpha: 0.5),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        18,
        18,
        18 + MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: DecoratedBox(
        key: const ValueKey('postdee-system-status-sheet'),
        decoration: BoxDecoration(
          color: AppTheme.glass,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x550A120E),
              blurRadius: 50,
              spreadRadius: -16,
              offset: Offset(0, 24),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: data.iconTint,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(data.icon, size: 28, color: data.iconColor),
              ),
              const SizedBox(height: 14),
              Text(
                data.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                data.body,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (data.secondaryLabel != null) ...[
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton(
                          onPressed: () =>
                              Navigator.of(sheetContext).pop(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textPrimary,
                            side: BorderSide(color: AppTheme.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: Text(data.secondaryLabel!),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: Text(data.primaryLabel),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
