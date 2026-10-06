import { profilePlatformFiles, profilePlatformMetrics, type ProfilePlatformId } from './profilePlatformCatalog.generated.js';

export type LinkInBioBrandIcon = ProfilePlatformId;

// Keep artwork paths fixed and bundled; destination URLs never become image URLs.
export const linkInBioPlatformLogoFiles = profilePlatformFiles;

// Audited original canvas and nontransparent bounds. Keep source pixels unchanged.
export const linkInBioPlatformLogoMetrics = profilePlatformMetrics;

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
