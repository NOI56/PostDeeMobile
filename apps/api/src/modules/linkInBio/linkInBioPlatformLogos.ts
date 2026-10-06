import type { LinkInBioIcon } from './linkInBioAppearance.js';

export type LinkInBioBrandIcon = Exclude<LinkInBioIcon, 'auto' | 'link' | 'website' | 'email' | 'phone'>;

// Keep artwork paths fixed and bundled; destination URLs never become image URLs.
export const linkInBioPlatformLogoFiles: Record<LinkInBioBrandIcon, string> = {
  shopee: 'shopee.png', lazada: 'lazada.png', line: 'line.png', tiktok: 'tiktok.png',
  youtube: 'youtube.png', instagram: 'instagram.png', facebook: 'facebook.png',
  messenger: 'messenger.png', whatsapp: 'whatsapp.png', google_maps: 'google_maps.png'
};

// Audited original canvas and nontransparent bounds. Keep source pixels unchanged.
export const linkInBioPlatformLogoMetrics: Record<LinkInBioBrandIcon, {
  sourceWidth: number; sourceHeight: number;
  left: number; top: number; width: number; height: number;
}> = {
  youtube: { sourceWidth: 1255, sourceHeight: 1075, left: 214, top: 248, width: 827, height: 579 },
  shopee: { sourceWidth: 96, sourceHeight: 96, left: 5, top: 0, width: 86, height: 96 },
  lazada: { sourceWidth: 128, sourceHeight: 128, left: 0, top: 0, width: 128, height: 128 },
  line: { sourceWidth: 1001, sourceHeight: 1000, left: 0, top: 0, width: 1001, height: 1000 },
  tiktok: { sourceWidth: 240, sourceHeight: 240, left: 0, top: 0, width: 240, height: 240 },
  instagram: { sourceWidth: 240, sourceHeight: 240, left: 0, top: 0, width: 240, height: 240 },
  facebook: { sourceWidth: 240, sourceHeight: 240, left: 0, top: 0, width: 240, height: 240 },
  messenger: { sourceWidth: 128, sourceHeight: 128, left: 5, top: 7, width: 117, height: 116 },
  whatsapp: { sourceWidth: 240, sourceHeight: 240, left: 0, top: 0, width: 240, height: 240 },
  google_maps: { sourceWidth: 192, sourceHeight: 192, left: 27, top: 8, width: 138, height: 176 }
};

export const getLinkInBioPlatformLogoGeometry = (icon: LinkInBioBrandIcon, size = 40) => {
  const content = linkInBioPlatformLogoMetrics[icon];
  const scale = size / Math.max(content.width, content.height);
  return {
    width: content.sourceWidth * scale,
    height: content.sourceHeight * scale,
    left: (size - content.width * scale) / 2 - content.left * scale,
    top: (size - content.height * scale) / 2 - content.top * scale
  };
};
