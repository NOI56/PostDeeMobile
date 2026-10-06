export type LinkInBioFont = 'anuphan' | 'prompt' | 'system';
export type LinkInBioIcon = 'auto' | 'link' | 'website' | 'email' | 'phone' | 'shopee' | 'lazada' | 'line' | 'tiktok' | 'youtube' | 'instagram' | 'facebook' | 'messenger' | 'whatsapp' | 'google_maps';
export type LinkInBioTheme = 'minimal' | 'shop' | 'pastel' | 'dark';
export type LinkInBioTextStyle = { color: string; font: LinkInBioFont };
export type LinkInBioAppearance = {
  version: 1;
  themeId: LinkInBioTheme;
  description: string;
  logoKey: string | null;
  coverKey: string | null;
  background: { mode: 'solid' | 'gradient' | 'image'; color: string; gradientColor: string; imageKey: string | null; overlay: number };
  surfaceColor: string;
  buttonColor: string;
  buttonRadius: 'rounded' | 'pill' | 'square';
  nameStyle: LinkInBioTextStyle;
  descriptionStyle: LinkInBioTextStyle;
  categoryStyle: LinkInBioTextStyle;
  buttonStyle: LinkInBioTextStyle;
  brandStyle: LinkInBioTextStyle;
  featuredLinkId: string | null;
  featuredLabel: string;
};

export const linkInBioFonts: readonly LinkInBioFont[] = ['anuphan', 'prompt', 'system'];
export const linkInBioIcons: readonly LinkInBioIcon[] = ['auto', 'link', 'website', 'email', 'phone', 'shopee', 'lazada', 'line', 'tiktok', 'youtube', 'instagram', 'facebook', 'messenger', 'whatsapp', 'google_maps'];
const themes: readonly LinkInBioTheme[] = ['minimal', 'shop', 'pastel', 'dark'];
const palettes = {
  minimal: ['#fff8ef', '#f4e3c7', '#ffffff', '#305d36', '#253529', '#687065', '#537844', '#ffffff', '#687065'],
  shop: ['#fff5e8', '#ffe0b2', '#ffffff', '#e85d24', '#3a2418', '#765a49', '#c44918', '#ffffff', '#765a49'],
  pastel: ['#f8f0fc', '#e6f1ff', '#ffffff', '#8b5fbf', '#473258', '#766185', '#8b5fbf', '#ffffff', '#766185'],
  dark: ['#111827', '#263449', '#1f2937', '#34d399', '#f9fafb', '#cbd5e1', '#a7f3d0', '#102a22', '#cbd5e1']
} as const;

export const createDefaultLinkInBioAppearance = (themeId: LinkInBioTheme = 'minimal'): LinkInBioAppearance => {
  const [color, gradientColor, surfaceColor, buttonColor, name, description, category, button, brand] = palettes[themeId];
  return {
    version: 1, themeId, description: '', logoKey: null, coverKey: null,
    background: { mode: 'solid', color, gradientColor, imageKey: null, overlay: 30 },
    surfaceColor, buttonColor, buttonRadius: themeId === 'pastel' ? 'pill' : 'rounded',
    nameStyle: { color: name, font: themeId === 'shop' || themeId === 'dark' ? 'prompt' : 'anuphan' },
    descriptionStyle: { color: description, font: 'anuphan' },
    categoryStyle: { color: category, font: 'anuphan' },
    buttonStyle: { color: button, font: 'anuphan' },
    brandStyle: { color: brand, font: 'anuphan' },
    featuredLinkId: null, featuredLabel: 'โปรวันนี้'
  };
};

export const defaultLinkInBioAppearance = createDefaultLinkInBioAppearance;

const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null && !Array.isArray(value);
export const readLinkInBioColor = (value: unknown) => typeof value === 'string' && /^#[a-f\d]{6}$/i.test(value) ? value.toLowerCase() : undefined;
const readImageKey = (value: unknown): string | null | undefined => {
  if (value === null) return null;
  if (typeof value !== 'string' || value.length < 1 || value.length > 512 || /[\s\u0000-\u001f\u007f\\]/.test(value) || value.startsWith('/') || value.includes(':')) return undefined;
  if (value.split('/').some((part) => !part || part === '.' || part === '..')) return undefined;
  return value;
};

// Every value interpolated into CSS comes from these enums or an exact hex
// color. Image keys are storage identifiers, never browser URLs.
export const readLinkInBioAppearance = (value: unknown, links: readonly { id: string }[]): LinkInBioAppearance | undefined => {
  if (!isRecord(value)) return undefined;
  if (value.version !== undefined && value.version !== 1) return undefined;
  const themeId = value.themeId ?? 'minimal';
  if (!themes.includes(themeId as LinkInBioTheme)) return undefined;
  const result = createDefaultLinkInBioAppearance(themeId as LinkInBioTheme);
  for (const field of ['description', 'featuredLabel'] as const) {
    if (value[field] !== undefined) {
      if (typeof value[field] !== 'string' || value[field].length > (field === 'description' ? 280 : 40)) return undefined;
      result[field] = value[field].trim();
    }
  }
  for (const field of ['logoKey', 'coverKey'] as const) {
    if (value[field] !== undefined) {
      const key = readImageKey(value[field]);
      if (key === undefined) return undefined;
      result[field] = key;
    }
  }
  for (const field of ['surfaceColor', 'buttonColor'] as const) {
    if (value[field] !== undefined) {
      const color = readLinkInBioColor(value[field]);
      if (!color) return undefined;
      result[field] = color;
    }
  }
  if (value.buttonRadius !== undefined) {
    if (!['rounded', 'pill', 'square'].includes(value.buttonRadius as string)) return undefined;
    result.buttonRadius = value.buttonRadius as LinkInBioAppearance['buttonRadius'];
  }
  for (const field of ['nameStyle', 'descriptionStyle', 'categoryStyle', 'buttonStyle', 'brandStyle'] as const) {
    if (value[field] !== undefined) {
      const style = value[field];
      if (!isRecord(style)) return undefined;
      if (style.color !== undefined) {
        const color = readLinkInBioColor(style.color);
        if (!color) return undefined;
        result[field].color = color;
      }
      if (style.font !== undefined) {
        if (!linkInBioFonts.includes(style.font as LinkInBioFont)) return undefined;
        result[field].font = style.font as LinkInBioFont;
      }
    }
  }
  if (value.background !== undefined) {
    const background = value.background;
    if (!isRecord(background)) return undefined;
    if (background.mode !== undefined) {
      if (!['solid', 'gradient', 'image'].includes(background.mode as string)) return undefined;
      result.background.mode = background.mode as LinkInBioAppearance['background']['mode'];
    }
    for (const field of ['color', 'gradientColor'] as const) {
      if (background[field] !== undefined) {
        const color = readLinkInBioColor(background[field]);
        if (!color) return undefined;
        result.background[field] = color;
      }
    }
    if (background.imageKey !== undefined) {
      const key = readImageKey(background.imageKey);
      if (key === undefined) return undefined;
      result.background.imageKey = key;
    }
    if (background.overlay !== undefined) {
      if (typeof background.overlay !== 'number' || !Number.isInteger(background.overlay) || background.overlay < 0 || background.overlay > 80) return undefined;
      result.background.overlay = background.overlay;
    }
  }
  if (value.featuredLinkId !== undefined && value.featuredLinkId !== null) {
    if (typeof value.featuredLinkId !== 'string' || !links.some(({ id }) => id === value.featuredLinkId)) return undefined;
    result.featuredLinkId = value.featuredLinkId;
  }
  return result;
};

export const normalizeStoredLinkInBioAppearance = (value: unknown, links: readonly { id: string }[]): LinkInBioAppearance => {
  // A legacy publish can remove its previously featured link. Preserve the
  // remaining appearance, while no longer featuring a missing destination.
  if (isRecord(value)) {
    const featuredLinkId = value.featuredLinkId;
    if (typeof featuredLinkId === 'string' && !links.some(({ id }) => id === featuredLinkId)) {
      value = { ...value, featuredLinkId: null };
    }
  }
  return readLinkInBioAppearance(value, links) ?? createDefaultLinkInBioAppearance();
};
