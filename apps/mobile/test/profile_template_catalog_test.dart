import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/models/profile_template_catalog.generated.dart';

void main() {
  test('five categories contain twenty structurally distinct templates each',
      () {
    expect(profileTemplateCategories.keys,
        ['minimal', 'cute', 'nature', 'luxury', 'creative']);
    expect(profileTemplates, hasLength(100));
    expect(profileTemplates.map((template) => template.id).toSet(),
        hasLength(100));
    for (final category in profileTemplateCategories.keys) {
      final templates = profileTemplates
          .where((template) => template.category == category)
          .toList();
      expect(templates, hasLength(20));
      expect(templates.map((template) => template.layout.composition).toSet(),
          hasLength(20));
      expect(templates.map((template) => template.name).toSet(), hasLength(20));
    }
  });

  test('the three agreed reference compositions appear first in each category',
      () {
    const representatives = {
      'minimal': ['editorial', 'bicolor', 'portrait'],
      'cute': ['scallop', 'collage', 'window'],
      'nature': ['botanical', 'glass', 'torn'],
      'luxury': ['seal', 'tag', 'gallery'],
      'creative': ['poster', 'window-grid', 'ticket'],
    };
    for (final category in profileTemplateCategories.keys) {
      expect(
          profileTemplates
              .where((template) => template.category == category)
              .take(3)
              .map((template) => template.layout.composition),
          representatives[category]);
    }
  });

  test('all generated templates match authored data and appearance round trips',
      () {
    final source = jsonDecode(
            File('../../shared/profile-templates.json').readAsStringSync())
        as Map<String, dynamic>;
    final templates = source['templates'] as List<dynamic>;
    for (final template in profileTemplates) {
      final raw = templates.singleWhere((value) => value['id'] == template.id)
          as Map<String, dynamic>;
      expect(template.name, raw['name']);
      expect(template.category, raw['category']);
      expect(template.layout.composition, raw['layout']['composition']);
      expect(template.layout.header, raw['layout']['header']);
      expect(template.layout.links, raw['layout']['links']);
      expect(template.layout.button, raw['layout']['button']);
      expect(template.layout.decoration, raw['layout']['decoration']);
      expect(template.layout.avatar, raw['layout']['avatar']);
      expect({
        'background': template.palette.background,
        'gradient': template.palette.gradient,
        'surface': template.palette.surface,
        'button': template.palette.button,
        'name': template.palette.name,
        'description': template.palette.description,
        'category': template.palette.category,
        'buttonText': template.palette.buttonText,
        'brand': template.palette.brand,
      }, raw['palette']);
      final appearance = LinkInBioAppearance.forTemplate(template.id);
      expect(appearance.templateId, template.id);
      expect(appearance.themeId, template.themeId);
      expect(appearance.background.color, raw['palette']['background']);
      expect(appearance.nameStyle.font, raw['font']);
      expect(appearance.toJson()['effects'], raw['effects']);
      expect(LinkInBioAppearance.fromJson(appearance.toJson()).toJson(),
          appearance.toJson());
      final custom = appearance.copyWith(
          buttonColor: '#abcdef',
          description: 'ชื่อเดิม',
          nameStyle:
              const LinkInBioTextStyle(color: '#123456', font: 'system'));
      expect(LinkInBioAppearance.fromJson(custom.toJson()).toJson(),
          custom.toJson());
    }
  });

  test('legacy themes retain null template and clearing templateId is explicit',
      () {
    for (final theme in linkInBioThemeNames.keys) {
      final original = LinkInBioAppearance.forTheme(theme).toJson();
      expect(original['templateId'], isNull);
      final legacy = Map<String, Object?>.of(original)..remove('templateId');
      expect(LinkInBioAppearance.fromJson(legacy).toJson(), original);
    }
    final appearance =
        LinkInBioAppearance.forTemplate(profileTemplates.first.id);
    expect(appearance.copyWith(description: 'เดิม').templateId,
        appearance.templateId);
    expect(appearance.copyWith(templateId: null).templateId, isNull);
    expect(getProfileTemplate(null), isNull);
    expect(getProfileTemplate('missing'), isNull);
    expect(() => LinkInBioAppearance.forTemplate('missing'),
        throwsFormatException);
  });

  test('unknown template and mismatched theme cannot be encoded or decoded',
      () {
    final appearance =
        LinkInBioAppearance.forTemplate(profileTemplates.first.id);
    for (final invalid in ['unknown', '', 12, <String, Object?>{}]) {
      final json = Map<String, Object?>.of(appearance.toJson())
        ..['templateId'] = invalid;
      expect(() => LinkInBioAppearance.fromJson(json), throwsFormatException);
    }
    expect(() => appearance.copyWith(themeId: 'dark').toJson(),
        throwsFormatException);
    expect(() => const LinkInBioAppearance(templateId: 'unknown').toJson(),
        throwsFormatException);
  });
}
