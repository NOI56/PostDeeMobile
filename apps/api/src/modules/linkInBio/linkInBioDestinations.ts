import { linkInBioIcons, type LinkInBioIcon } from './linkInBioAppearance.js';
import type { LinkInBioLink } from './linkInBioStore.js';
import { profilePlatformCatalog } from './profilePlatformCatalog.generated.js';

// Contact links intentionally support one recipient and no headers or dial extensions.
// Keep validation shared by publication and automatic artwork selection.
export const readLinkInBioUrl = (value: unknown): string | undefined => {
  if (typeof value !== 'string' || /[\u0000-\u001f\u007f]/.test(value)) return undefined;
  const url = value.trim();
  if (url.length > 2048 || /\s/.test(url)) return undefined;
  if (/^mailto:/i.test(url)) {
    const address = url.slice(7);
    if (address.length > 254) return undefined;
    const parts = address.split('@');
    if (parts.length !== 2) return undefined;
    const [local, domain] = parts as [string, string];
    if (!/^[a-z\d._+-]{1,64}$/i.test(local) || local.startsWith('.') || local.endsWith('.') || local.includes('..')) return undefined;
    const labels = domain.split('.');
    if (labels.length < 2 || !labels.every((label) => /^[a-z\d](?:[a-z\d-]{0,61}[a-z\d])?$/i.test(label))) return undefined;
    if (!/^[a-z]{2,63}$/i.test(labels.at(-1)!)) return undefined;
    return `mailto:${address}`;
  }
  if (/^tel:/i.test(url)) {
    const number = url.slice(4);
    return /^\+?\d{7,15}$/.test(number) ? `tel:${number}` : undefined;
  }
  if (!/^https?:\/\//i.test(url)) return undefined;
  try {
    const parsed = new URL(url);
    if (!parsed.hostname || parsed.username || parsed.password || !['https:', 'http:'].includes(parsed.protocol)) return undefined;
    return parsed.href.length <= 2048 ? parsed.href : undefined;
  } catch {
    return undefined;
  }
};

const matchesHost = (host: string, domain: string) => host === domain || host.endsWith(`.${domain}`);

export const resolveLinkInBioIcon = (link: LinkInBioLink): Exclude<LinkInBioIcon, 'auto'> => {
  if (link.icon && link.icon !== 'auto' && linkInBioIcons.includes(link.icon)) return link.icon;
  const destination = readLinkInBioUrl(link.url);
  if (!destination) return 'link';
  if (destination.startsWith('mailto:')) return 'email';
  if (destination.startsWith('tel:')) return 'phone';
  const parsed = new URL(destination);
  const host = parsed.hostname.toLowerCase();
  const path = parsed.pathname;
  // Specific paths are checked before broad platform domains. A path prefix
  // must end at a segment boundary, so /maps cannot accidentally brand /mapshop.
  for (const platform of profilePlatformCatalog) {
    for (const match of platform.matches) {
      const hostMatches = match.subdomains ? matchesHost(host, match.host) : host === match.host;
      if (hostMatches && (path === match.pathPrefix || path.startsWith(`${match.pathPrefix}/`))) return platform.id;
    }
  }
  return profilePlatformCatalog.find((platform) => platform.domains.some((domain) => matchesHost(host, domain)))?.id ?? 'website';
};
