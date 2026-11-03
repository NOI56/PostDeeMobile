import 'dart:convert';

import '../../core/models/link_in_bio_appearance.dart';
import '../../core/models/profile_template_catalog.generated.dart';
import '../../core/network/postdee_api_client.dart';

/// Membership follows the catalog category, even when a premium template uses
/// the same base theme as a free template. Unknown or inconsistent IDs fail closed.
bool bioRequiresThemeMembership(LinkInBioAppearance appearance) {
  final templateId = appearance.templateId;
  if (templateId == null) return appearance.themeId != 'minimal';
  final template = getProfileTemplate(templateId);
  return template == null ||
      template.themeId != appearance.themeId ||
      template.category != 'minimal';
}

/// The server flag is authoritative. Plan names, trial features and purchased
/// credits alone never unlock premium themes, including on older API responses.
bool bioHasThemeMembership(SubscriptionStatusResult? subscription) {
  if (subscription == null ||
      !subscription.canUsePremiumProfileThemes ||
      subscription.status != 'ACTIVE') {
    return false;
  }
  return const {'STARTER', 'PRO', 'BUSINESS'}
      .contains(subscription.purchasedPlan ?? subscription.plan);
}

/// Derive the rendered fallback without replacing or mutating the saved draft.
LinkInBioAppearance bioEffectiveThemeAppearance(LinkInBioAppearance appearance,
    {required bool hasMembership}) {
  if (hasMembership || !bioRequiresThemeMembership(appearance)) {
    return appearance;
  }
  const simple = LinkInBioAppearance();
  final keepImage = appearance.background.mode == 'image' &&
      appearance.background.imageKey != null;
  return simple.copyWith(
    description: appearance.description,
    logoKey: appearance.logoKey,
    coverKey: appearance.coverKey,
    background: simple.background.copyWith(
      imageKey: appearance.background.imageKey,
      mode: keepImage ? 'image' : simple.background.mode,
      overlay:
          keepImage ? appearance.background.overlay : simple.background.overlay,
    ),
    featuredLinkId: appearance.featuredLinkId,
    featuredLabel: appearance.featuredLabel,
  );
}

/// Content edits may retain a saved premium style after membership expires.
/// Every other serialized field remains styling, including background overlays.
bool bioSameThemeStyle(LinkInBioAppearance left, LinkInBioAppearance right) {
  final imageChanged = left.background.imageKey != right.background.imageKey &&
      (left.background.imageKey != null || right.background.imageKey != null) &&
      (left.background.mode == 'image' || right.background.mode == 'image');
  try {
    return jsonEncode(_themeStyle(left, omitImageMode: imageChanged)) ==
        jsonEncode(_themeStyle(right, omitImageMode: imageChanged));
  } on FormatException {
    return false;
  }
}

Map<String, Object?> _themeStyle(LinkInBioAppearance appearance,
    {required bool omitImageMode}) {
  final value = appearance.toJson();
  for (final field in [
    'description',
    'logoKey',
    'coverKey',
    'featuredLinkId',
    'featuredLabel'
  ]) {
    value.remove(field);
  }
  final background = Map<String, Object?>.from(value['background']! as Map);
  background.remove('imageKey');
  if (omitImageMode) background.remove('mode');
  value['background'] = background;
  return value;
}
