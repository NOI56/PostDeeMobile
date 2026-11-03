import { readFile } from 'node:fs/promises';
import { describe, expect, it } from 'vitest';
import { profileTemplateCatalogVersion, profileTemplateCategories, profileTemplates, getProfileTemplate } from './profileTemplateCatalog.generated.js';
import { createDefaultLinkInBioAppearance, createDefaultLinkInBioTemplateAppearance, readLinkInBioAppearance } from './linkInBioAppearance.js';

describe('shared profile template catalog and appearance contract', () => {
  it('keeps five original categories, twenty 3D and twenty cartoon templates', () => {
    expect(profileTemplateCatalogVersion).toBe(4);
    expect(profileTemplateCategories.map((category) => category.id)).toEqual(['minimal', 'cute', 'nature', 'luxury', 'creative', 'dimensional', 'cartoon']);
    expect(profileTemplates).toHaveLength(140);
    expect(new Set(profileTemplates.map((template) => template.id)).size).toBe(140);
    for (const category of profileTemplateCategories) {
      const templates = profileTemplates.filter((template) => template.category === category.id);
      const expected = { dimensional: { count: 20, layouts: 8 }, cartoon: { count: 20, layouts: 7 } }[category.id as string] ?? { count: 20, layouts: 20 };
      expect(templates).toHaveLength(expected.count);
      expect(new Set(templates.map((template) => template.layout.composition)).size).toBe(expected.layouts);
      expect(new Set(templates.map((template) => template.name)).size).toBe(expected.count);
    }
  });

  it('places the three agreed reference compositions first in each category', () => {
    const representatives = {
      minimal: ['editorial', 'bicolor', 'portrait'],
      cute: ['scallop', 'collage', 'window'],
      nature: ['botanical', 'glass', 'torn'],
      luxury: ['seal', 'tag', 'gallery'],
      creative: ['poster', 'window-grid', 'ticket'],
    };
    for (const [category, expected] of Object.entries(representatives)) {
      expect(profileTemplates.filter((template) => template.category === category).slice(0, 3)
        .map((template) => template.layout.composition)).toEqual(expected);
    }
  });

  it('matches the authored source and round trips every template with custom styling intact', async () => {
    const source = JSON.parse(await readFile(new URL('../../../../../shared/profile-templates.json', import.meta.url), 'utf8'));
    expect(source.categories).toEqual(profileTemplateCategories);
    expect(source.templates).toEqual(profileTemplates);
    for (const template of profileTemplates) {
      expect(getProfileTemplate(template.id)).toEqual(template);
      const defaults = createDefaultLinkInBioTemplateAppearance(template.id);
      expect(defaults).toMatchObject({ version: 1, themeId: template.themeId, templateId: template.id });
      expect(readLinkInBioAppearance(defaults, [])).toEqual(defaults);
      expect(readLinkInBioAppearance({ templateId: template.id }, [])).toEqual(defaults);
      expect(readLinkInBioAppearance({ ...defaults, buttonColor: '#abcdef', nameStyle: { color: '#123456', font: 'system' } }, []))
        .toMatchObject({ templateId: template.id, buttonColor: '#abcdef', nameStyle: { color: '#123456', font: 'system' } });
    }
  });

  it('keeps all seven legacy themes unchanged when templateId is omitted or null', () => {
    for (const themeId of ['minimal', 'shop', 'pastel', 'dark', 'pink', 'garden', 'cards'] as const) {
      const defaults = createDefaultLinkInBioAppearance(themeId);
      expect(defaults.templateId).toBeNull();
      expect(readLinkInBioAppearance({ themeId }, [])).toEqual(defaults);
      expect(readLinkInBioAppearance({ themeId, templateId: null }, [])).toEqual(defaults);
    }
  });

  it.each(['missing', '', 'cute-01;display:none', 1, {}, []])('rejects unknown or malformed template IDs %#', (templateId) => {
    expect(readLinkInBioAppearance({ templateId }, [])).toBeUndefined();
  });

  it('rejects mismatched template theme and returns independent mutable defaults', () => {
    const template = profileTemplates[0]!;
    expect(readLinkInBioAppearance({ templateId: template.id, themeId: 'dark' }, [])).toBeUndefined();
    expect(readLinkInBioAppearance({ templateId: template.id, themeId: null }, [])).toBeUndefined();
    expect(() => createDefaultLinkInBioTemplateAppearance('missing')).toThrow();
    expect(getProfileTemplate(undefined)).toBeUndefined();
    expect(getProfileTemplate(null)).toBeUndefined();
    const first = createDefaultLinkInBioTemplateAppearance(template.id);
    first.effects.entrance = !first.effects.entrance;
    first.background.color = '#000000';
    const second = createDefaultLinkInBioTemplateAppearance(template.id);
    expect(second.background.color).toBe(template.palette.background);
    expect(second.effects).toEqual(template.effects);
  });
});
