import 'dart:async';

import 'package:flutter/material.dart';

void showPostDeeUndoToast(
  BuildContext context, {
  required String message,
  FutureOr<void> Function()? onUndo,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: const ValueKey('postdee-undo-toast'),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        padding: const EdgeInsets.fromLTRB(16, 11, 8, 11),
        duration: const Duration(milliseconds: 4500),
        backgroundColor: const Color(0xFF1F2A24),
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              size: 20,
              color: Color(0xFF5FE3A1),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        action: onUndo == null
            ? null
            : SnackBarAction(
                label: 'เลิกทำ',
                textColor: const Color(0xFF5FE3A1),
                onPressed: () => unawaited(Future.sync(onUndo)),
              ),
      ),
    );
}
