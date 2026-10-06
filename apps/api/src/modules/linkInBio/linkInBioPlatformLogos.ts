import type { LinkInBioIcon } from './linkInBioAppearance.js';

// Keep artwork paths fixed and bundled; destination URLs never become image URLs.
export const linkInBioPlatformLogoFiles: Record<Exclude<LinkInBioIcon, 'auto' | 'link'>, string> = {
  shopee: 'shopee.png', lazada: 'lazada.png', line: 'line.png', tiktok: 'tiktok.png',
  youtube: 'youtube.png', instagram: 'instagram.png', facebook: 'facebook.png'
};
