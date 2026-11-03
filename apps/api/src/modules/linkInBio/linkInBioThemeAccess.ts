import type { SubscriptionStore } from '../subscriptions/subscriptionStore.js';
import { createDefaultLinkInBioAppearance, type LinkInBioAppearance } from './linkInBioAppearance.js';
import { getProfileTemplate } from './profileTemplateCatalog.generated.js';

export { hasPaidProfileThemeMembership,
  readPurchasedSubscriptionPlan as readPurchasedProfileThemePlan } from '../subscriptions/subscriptionEntitlements.js';

export type ProfileThemeSubscriptionStore = Pick<SubscriptionStore, 'getPlan'> &
  Partial<Pick<SubscriptionStore, 'getPurchasedPlan'>>;

export const profileThemeRequiresMembership = (appearance: unknown): boolean => {
  if (!appearance || typeof appearance !== 'object' || Array.isArray(appearance)) return false;
  const { templateId, themeId } = appearance as Record<string, unknown>;
  if (templateId !== null && templateId !== undefined) {
    const template = typeof templateId === 'string' ? getProfileTemplate(templateId) : undefined;
    // Future/unknown categories and IDs never acquire free access by accident.
    return template?.category !== 'minimal';
  }
  return themeId !== undefined && themeId !== 'minimal';
};

const contentFields = new Set(['description', 'logoKey', 'coverKey', 'featuredLinkId', 'featuredLabel']);
export const samePremiumProfileStyling = (left: LinkInBioAppearance, right: LinkInBioAppearance) => {
  const imageContentChanged = left.background.imageKey !== right.background.imageKey &&
    Boolean(left.background.imageKey || right.background.imageKey) &&
    (left.background.mode === 'image' || right.background.mode === 'image');
  const style = (appearance: LinkInBioAppearance) => ({
    ...Object.fromEntries(Object.entries(appearance).filter(([key]) => !contentFields.has(key))),
    background: { ...appearance.background, imageKey: undefined,
      ...(imageContentChanged ? { mode: 'content-image' } : {}) }
  });
  return JSON.stringify(style(left)) === JSON.stringify(style(right));
};

// Only the rendering copy changes. Authored styling and image references remain
// saved, so an expired member can edit content and restore the design later.
export const createFreeProfileThemeAppearance = (saved: LinkInBioAppearance): LinkInBioAppearance => {
  const simple = createDefaultLinkInBioAppearance();
  return { ...simple, description: saved.description, logoKey: saved.logoKey, coverKey: saved.coverKey,
    featuredLinkId: saved.featuredLinkId, featuredLabel: saved.featuredLabel,
    background: { ...simple.background, imageKey: saved.background.imageKey,
      ...(saved.background.mode === 'image' && saved.background.imageKey ? {
        mode: 'image', overlay: saved.background.overlay
      } : {}) }
  };
};
