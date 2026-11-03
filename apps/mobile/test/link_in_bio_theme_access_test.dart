import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/models/profile_template_catalog.generated.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_theme_access.dart';

const _logo =
    'uploads/owner/12345678-1234-1234-1234-123456789abc/profile-logo.png';
const _cover =
    'uploads/owner/12345678-1234-1234-1234-123456789abc/profile-cover.png';
const _background =
    'uploads/owner/12345678-1234-1234-1234-123456789abc/profile-background.png';
const _otherBackground =
    'uploads/owner/87654321-4321-4321-4321-cba987654321/profile-background.png';

SubscriptionStatusResult _subscription({
  String plan = 'PRO',
  String? purchasedPlan,
  String status = 'ACTIVE',
  bool access = true,
  int posts = 0,
  int captions = 0,
}) =>
    SubscriptionStatusResult(
        userId: 'theme-owner',
        plan: plan,
        purchasedPlan: purchasedPlan,
        status: status,
        canUsePremiumProfileThemes: access,
        addonPostUnits: posts,
        addonAiCaptions: captions,
        canSchedule: false,
        canUseAiCaptions: false,
        canUseAnalytics: false);

LinkInBioAppearance _premium() =>
    LinkInBioAppearance.forTemplate(profileTemplates
        .firstWhere((template) => template.category == 'cartoon')
        .id);

void main() {
  test('raw catalog category alone determines template membership', () {
    expect(profileTemplateCategories.keys, contains('minimal'));
    for (final template in profileTemplates) {
      final appearance = LinkInBioAppearance.forTemplate(template.id);
      expect(bioRequiresThemeMembership(appearance),
          template.category != 'minimal',
          reason: template.id);
    }
    for (final category in profileTemplateCategories.keys) {
      expect(profileTemplates.any((template) => template.category == category),
          isTrue,
          reason: category);
    }
  });

  test('only the absent-template minimal legacy theme is free', () {
    for (final theme in linkInBioThemeNames.keys) {
      expect(bioRequiresThemeMembership(LinkInBioAppearance.forTheme(theme)),
          theme != 'minimal',
          reason: theme);
    }
    expect(
        bioRequiresThemeMembership(
            const LinkInBioAppearance(themeId: 'unknown')),
        isTrue);
    expect(bioRequiresThemeMembership(const LinkInBioAppearance(themeId: '')),
        isTrue);
  });

  test('unknown and mismatched templates fail closed as premium', () {
    for (final id in ['', 'missing-template', ' minimal-white-editorial ']) {
      expect(bioRequiresThemeMembership(LinkInBioAppearance(templateId: id)),
          isTrue,
          reason: id);
    }
    for (final template in profileTemplates) {
      final mismatch = LinkInBioAppearance.forTemplate(template.id).copyWith(
          themeId: template.themeId == 'minimal' ? 'dark' : 'minimal');
      expect(bioRequiresThemeMembership(mismatch), isTrue, reason: template.id);
    }
  });

  test('only active purchased paid plans with authoritative access qualify',
      () {
    for (final plan in ['STARTER', 'PRO', 'BUSINESS']) {
      expect(bioHasThemeMembership(_subscription(plan: plan)), isTrue,
          reason: plan);
      expect(
          bioHasThemeMembership(
              _subscription(plan: 'BASIC', purchasedPlan: plan)),
          isTrue,
          reason: 'explicit purchased $plan');
      for (final status in [
        'EXPIRED',
        'INACTIVE',
        'PAST_DUE',
        'TRIALING',
        'CANCELED',
        'UNKNOWN',
        '',
        'active'
      ]) {
        expect(bioHasThemeMembership(_subscription(plan: plan, status: status)),
            isFalse,
            reason: '$plan/$status');
      }
      expect(bioHasThemeMembership(_subscription(plan: plan, access: false)),
          isFalse,
          reason: 'authoritative denial for $plan');
    }
  });

  test(
      'missing access, trials, credits and unknown plans never grant membership',
      () {
    expect(bioHasThemeMembership(null), isFalse);
    expect(
        bioHasThemeMembership(const SubscriptionStatusResult(
            userId: 'theme-owner',
            plan: 'PRO',
            status: 'ACTIVE',
            canSchedule: true,
            canUseAiCaptions: true,
            canUseAnalytics: false)),
        isFalse,
        reason: 'old API without authoritative flag');
    for (final plan in ['BASIC', 'FREE', 'UNKNOWN', 'pro', '']) {
      expect(
          bioHasThemeMembership(
              _subscription(plan: plan, posts: 999, captions: 999)),
          isFalse,
          reason: plan);
    }
    expect(
        bioHasThemeMembership(
            _subscription(plan: 'PRO', purchasedPlan: 'BASIC')),
        isFalse,
        reason: 'trial effective plan is not a paid purchase');
    expect(
        bioHasThemeMembership(
            _subscription(plan: 'PRO', purchasedPlan: 'UNKNOWN')),
        isFalse);
  });

  test('allowed appearance keeps the original instance for every template', () {
    for (final template in profileTemplates) {
      final appearance = LinkInBioAppearance.forTemplate(template.id);
      expect(bioEffectiveThemeAppearance(appearance, hasMembership: true),
          same(appearance),
          reason: template.id);
      if (template.category == 'minimal') {
        expect(bioEffectiveThemeAppearance(appearance, hasMembership: false),
            same(appearance),
            reason: template.id);
      }
    }
    final minimal = const LinkInBioAppearance().copyWith(
        buttonColor: '#123456',
        effects: const LinkInBioEffects(entrance: true));
    expect(bioEffectiveThemeAppearance(minimal, hasMembership: false),
        same(minimal));
  });

  test('denied premium fallback resets styling while preserving owned content',
      () {
    final original = _premium().copyWith(
        description: 'ข้อมูลร้านเดิม',
        logoKey: _logo,
        coverKey: _cover,
        background: const LinkInBioBackground(
            mode: 'image',
            imageKey: _background,
            color: '#123456',
            gradientColor: '#654321',
            overlay: 61),
        featuredLinkId: 'shop',
        featuredLabel: 'โปรของร้าน',
        surfaceColor: '#112233',
        buttonColor: '#445566',
        buttonRadius: 'square',
        effects: const LinkInBioEffects(
            background: true,
            entrance: true,
            featured: true,
            stickers: 'sparkles'));
    final saved = original.toJson();
    final fallback =
        bioEffectiveThemeAppearance(original, hasMembership: false);
    const defaults = LinkInBioAppearance();
    expect(fallback, isNot(same(original)));
    expect(fallback.themeId, 'minimal');
    expect(fallback.templateId, isNull);
    expect(fallback.description, original.description);
    expect(fallback.logoKey, _logo);
    expect(fallback.coverKey, _cover);
    expect(fallback.background.imageKey, _background);
    expect(fallback.background.mode, 'image');
    expect(fallback.background.overlay, 61);
    expect(fallback.background.color, defaults.background.color);
    expect(
        fallback.background.gradientColor, defaults.background.gradientColor);
    expect(fallback.featuredLinkId, 'shop');
    expect(fallback.featuredLabel, 'โปรของร้าน');
    expect(fallback.surfaceColor, defaults.surfaceColor);
    expect(fallback.buttonColor, defaults.buttonColor);
    expect(fallback.buttonRadius, defaults.buttonRadius);
    expect(fallback.nameStyle.toJson(), defaults.nameStyle.toJson());
    expect(
        fallback.descriptionStyle.toJson(), defaults.descriptionStyle.toJson());
    expect(fallback.categoryStyle.toJson(), defaults.categoryStyle.toJson());
    expect(fallback.buttonStyle.toJson(), defaults.buttonStyle.toJson());
    expect(fallback.brandStyle.toJson(), defaults.brandStyle.toJson());
    expect(fallback.effects.toJson(), defaults.effects.toJson());
    expect(original.toJson(), saved,
        reason: 'saved premium draft is never mutated');
    expect(bioEffectiveThemeAppearance(original, hasMembership: true),
        same(original));
  });

  test(
      'fallback retains inactive image content but activates only actual image mode',
      () {
    for (final background in [
      const LinkInBioBackground(
          mode: 'gradient', imageKey: _background, overlay: 77),
      const LinkInBioBackground(mode: 'image', overlay: 77),
    ]) {
      final fallback = bioEffectiveThemeAppearance(
          _premium().copyWith(background: background),
          hasMembership: false);
      expect(fallback.background.imageKey, background.imageKey);
      expect(fallback.background.mode, 'solid');
      expect(fallback.background.overlay, const LinkInBioBackground().overlay);
    }
  });

  test('theme style ignores only content and preserves source objects', () {
    final original = _premium();
    final before = original.toJson();
    final content = original.copyWith(
        description: 'รายละเอียดใหม่',
        logoKey: _logo,
        coverKey: _cover,
        featuredLinkId: 'new-link',
        featuredLabel: 'ป้ายใหม่',
        background: original.background.copyWith(imageKey: _background));
    expect(bioSameThemeStyle(original, content), isTrue);
    expect(bioSameThemeStyle(content, original), isTrue);
    expect(original.toJson(), before);
    expect(bioSameThemeStyle(original, original), isTrue);
  });

  test('every serialized styling component participates in style comparison',
      () {
    final original = _premium();
    final changes = <String, LinkInBioAppearance>{
      'theme': original.copyWith(themeId: 'dark', templateId: null),
      'template': LinkInBioAppearance.forTemplate(profileTemplates
          .firstWhere((template) =>
              template.id != original.templateId &&
              template.category == 'cartoon')
          .id),
      'surface': original.copyWith(surfaceColor: '#123456'),
      'button': original.copyWith(buttonColor: '#123456'),
      'radius': original.copyWith(
          buttonRadius: original.buttonRadius == 'square' ? 'pill' : 'square'),
      'name': original.copyWith(
          nameStyle: original.nameStyle.copyWith(color: '#123456')),
      'description': original.copyWith(
          descriptionStyle:
              original.descriptionStyle.copyWith(color: '#123456')),
      'category': original.copyWith(
          categoryStyle: original.categoryStyle.copyWith(color: '#123456')),
      'button text': original.copyWith(
          buttonStyle: original.buttonStyle.copyWith(color: '#123456')),
      'brand': original.copyWith(
          brandStyle: original.brandStyle.copyWith(color: '#123456')),
      'background color': original.copyWith(
          background: original.background.copyWith(color: '#123456')),
      'background gradient': original.copyWith(
          background: original.background.copyWith(gradientColor: '#123456')),
      'background overlay': original.copyWith(
          background: original.background
              .copyWith(overlay: original.background.overlay == 31 ? 32 : 31)),
      'background mode': original.copyWith(
          background: original.background.copyWith(
              mode:
                  original.background.mode == 'solid' ? 'gradient' : 'solid')),
      'effects': original.copyWith(
          effects:
              original.effects.copyWith(entrance: !original.effects.entrance)),
    };
    for (final entry in changes.entries) {
      expect(bioSameThemeStyle(original, entry.value), isFalse,
          reason: entry.key);
      expect(bioSameThemeStyle(entry.value, original), isFalse,
          reason: entry.key);
    }
  });

  test('latent image key changes do not excuse non-image background mode edits',
      () {
    final original = _premium().copyWith(
        background: _premium()
            .background
            .copyWith(mode: 'solid', imageKey: _background));
    final contentOnly = original.copyWith(
        background: original.background.copyWith(imageKey: _otherBackground));
    final changedMode = original.copyWith(
        background: original.background
            .copyWith(mode: 'gradient', imageKey: _otherBackground));
    expect(bioSameThemeStyle(original, contentOnly), isTrue);
    expect(bioSameThemeStyle(contentOnly, original), isTrue);
    expect(bioSameThemeStyle(original, changedMode), isFalse);
    expect(bioSameThemeStyle(changedMode, original), isFalse);
  });

  test(
      'image content may add remove or replace an image with its mode transition',
      () {
    final original = _premium();
    final image = original.copyWith(
        background:
            original.background.copyWith(mode: 'image', imageKey: _background));
    final removed = image.copyWith(
        background: image.background.copyWith(mode: 'solid', imageKey: null));
    final replaced = image.copyWith(
        background: image.background.copyWith(imageKey: _otherBackground));
    expect(bioSameThemeStyle(original, image), isTrue);
    expect(bioSameThemeStyle(image, original), isTrue);
    expect(bioSameThemeStyle(image, removed), isTrue);
    expect(bioSameThemeStyle(removed, image), isTrue);
    expect(bioSameThemeStyle(image, replaced), isTrue);
    final modeOnly =
        image.copyWith(background: image.background.copyWith(mode: 'solid'));
    expect(bioSameThemeStyle(image, modeOnly), isFalse,
        reason: 'unchanged image key cannot excuse a style mode change');
    final overlayEdit = image.copyWith(
        background: image.background
            .copyWith(overlay: original.background.overlay == 31 ? 32 : 31));
    expect(bioSameThemeStyle(original, overlayEdit), isFalse,
        reason: 'image edits never excuse changed overlay styling');
  });
}
