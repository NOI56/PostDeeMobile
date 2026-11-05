export type AppLanguage = 'th' | 'en';

/** Missing language preserves old clients; unsupported languages use English. */
export const normalizeAppLanguage = (value: unknown): AppLanguage | null => {
  if (value === undefined || value === null) return null;
  const language = typeof value === 'string' ? value.trim().toLowerCase().split(/[-_]/)[0] : '';
  return language === 'th' ? 'th' : 'en';
};
