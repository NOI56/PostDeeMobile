import 'package:flutter/material.dart';

import 'uploader_localizations.dart';

String clipGroupText(BuildContext context, String thai, String english) =>
    uploaderText(context, thai, english);

String clipGroupDate(BuildContext context, DateTime value) {
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}

String clipGroupTime(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
