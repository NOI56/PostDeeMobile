import { linkInBioIcons, type LinkInBioIcon } from './linkInBioAppearance.js';
import type { LinkInBioLink } from './linkInBioStore.js';

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
  if (matchesHost(host, 'facebook.com') && /^\/messages(?:\/|$)/.test(path)) return 'messenger';
  const mapHost = ['maps.app.goo.gl', 'maps.google.com', 'maps.google.co.th'].some((domain) => matchesHost(host, domain));
  const googleMapPath = ['google.com', 'www.google.com', 'google.co.th', 'www.google.co.th'].includes(host) && /^\/maps(?:\/|$)/.test(path);
  if (mapHost || googleMapPath || (host === 'goo.gl' && /^\/maps(?:\/|$)/.test(path))) return 'google_maps';
  const domains: [Exclude<LinkInBioIcon, 'auto'>, string[]][] = [
    ['messenger', ['m.me', 'messenger.com']], ['whatsapp', ['wa.me', 'whatsapp.com']],
    ['shopee', ['shopee.co.th', 'shopee.com', 'shope.ee']], ['lazada', ['lazada.co.th', 'lazada.com', 's.lazada.co.th']],
    ['line', ['line.me', 'lin.ee']], ['tiktok', ['tiktok.com']], ['youtube', ['youtube.com', 'youtu.be']],
    ['instagram', ['instagram.com']], ['facebook', ['facebook.com', 'fb.com', 'fb.me']]
  ];
  return domains.find(([, values]) => values.some((domain) => matchesHost(host, domain)))?.[0] ?? 'website';
};
