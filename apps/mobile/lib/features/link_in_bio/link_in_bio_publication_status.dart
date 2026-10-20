import 'package:flutter/material.dart';

import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';

/// Null means that publication has not been confirmed for the current owner.
bool? linkInBioPublicationStatus(LinkInBioProfileResult? profile,
    {required bool confirmed}) {
  if (!confirmed) return null;
  if (profile?.isPublished != true) return false;
  return profile?.publicUrl == null ? null : true;
}

/// Decorative only: the adjacent status text provides the accessible label.
class LinkInBioPublicationDot extends StatelessWidget {
  const LinkInBioPublicationDot({super.key, required this.published});

  final bool? published;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox.square(
          dimension: 8,
          child: DecoratedBox(
            key: const ValueKey('link-in-bio-publication-dot'),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: switch (published) {
                true => AppTheme.successInk,
                false => const Color(0xFFEF4444),
                null => AppTheme.textMuted,
              },
            ),
          ),
        ),
      );
}
