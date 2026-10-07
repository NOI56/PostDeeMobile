import { readFile } from 'node:fs/promises';
import { describe, expect, it } from 'vitest';
import { profileTemplateCategories, profileTemplates, getProfileTemplate } from './profileTemplateCatalog.generated.js';
import { createDefaultLinkInBioAppearance, createDefaultLinkInBioTemplateAppearance, readLinkInBioAppearance } from './linkInBioAppearance.js';

describe('shared profile template catalog and appearance contract', () => {
  it('contains five agreed categories with twenty distinct layouts each', () => {
    expect(profileTemplateCategories.map((category) => category.id)).toEqual(['minimal', 'cute', 'nature', 'luxury', 'creative']);
    expect(profileTemplates).toHaveLength(100);
    expect(new Set(profileTemplates.map((template) => template.id)).size).toBe(100);
    for (const category of profileTemplateCategories) {
      const templates = profileTemplates.filter((template) => template.category === category.id);
      expect(templates).toHaveLength(20);
      expect(new Set(templates.map((template) => `${template.layout.header}/${template.layout.links}/${template.layout.button}`)).size).toBe(20);
      expect(new Set(templates.map((template) => template.name)).size).toBe(20);
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
