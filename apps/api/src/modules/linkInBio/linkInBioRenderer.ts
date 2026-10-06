import { linkInBioFonts, normalizeStoredLinkInBioAppearance, readLinkInBioColor, type LinkInBioFont, type LinkInBioIcon, type LinkInBioTextStyle } from './linkInBioAppearance.js';
import type { LinkInBioLink, LinkInBioProfile } from './linkInBioStore.js';
import { linkInBioPlatformLogoFiles } from './linkInBioPlatformLogos.js';

const escapeHtml = (value: string) => value.replace(/[&<>"']/g, (character) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
})[character]!);
const fontFamily = (font: LinkInBioFont) => font === 'system' ? 'system-ui,-apple-system,sans-serif' : `"${font === 'prompt' ? 'Prompt' : 'Anuphan'}",system-ui,sans-serif`;
const textStyle = (style: LinkInBioTextStyle) => `color:${style.color};font-family:${fontFamily(style.font)}`;
const resolveIcon = (link: LinkInBioLink): Exclude<LinkInBioIcon, 'auto'> => {
  if (link.icon === 'link') return 'link';
  if (link.icon && link.icon !== 'auto' && Object.hasOwn(linkInBioPlatformLogoFiles, link.icon)) return link.icon;
  let host: string;
  try { host = new URL(link.url).hostname.toLowerCase(); } catch { return 'link'; }
  const domains: [Exclude<LinkInBioIcon, 'auto'>, string[]][] = [
    ['shopee', ['shopee.co.th', 'shopee.com', 'shope.ee']], ['lazada', ['lazada.co.th', 'lazada.com', 's.lazada.co.th']],
    ['line', ['line.me', 'lin.ee']], ['tiktok', ['tiktok.com']], ['youtube', ['youtube.com', 'youtu.be']],
    ['instagram', ['instagram.com']], ['facebook', ['facebook.com', 'fb.com', 'fb.me']]
  ];
  return domains.find(([, values]) => values.some((domain) => host === domain || host.endsWith(`.${domain}`)))?.[0] ?? 'link';
};

export const renderLinkInBioPage = (profile: LinkInBioProfile, nonce: string) => {
  const appearance = normalizeStoredLinkInBioAppearance(profile.appearance, profile.links);
  const imagePath = (slot: 'logo' | 'cover' | 'background') => `/p/${encodeURIComponent(profile.slug)}/images/${slot}`;
  const radius = { rounded: '14px', pill: '999px', square: '4px' }[appearance.buttonRadius];
  let background = `background:${appearance.background.color}`;
  if (appearance.background.mode === 'gradient') {
    background = `background:linear-gradient(135deg,${appearance.background.color},${appearance.background.gradientColor});background-attachment:fixed`;
  } else if (appearance.background.mode === 'image' && appearance.background.imageKey) {
    const color = appearance.background.color;
    background = `background-color:${color};background-image:linear-gradient(rgba(0,0,0,${appearance.background.overlay / 100}),rgba(0,0,0,${appearance.background.overlay / 100})),url("${imagePath('background')}");background-size:cover;background-position:center;background-attachment:fixed`;
  }
  const linkStyles = profile.links.map((link, index) => {
    const color = readLinkInBioColor(link.textColor) ?? appearance.buttonStyle.color;
    const buttonColor = readLinkInBioColor(link.buttonColor) ?? appearance.buttonColor;
    const font = linkInBioFonts.includes(link.font as LinkInBioFont) ? link.font! : appearance.buttonStyle.font;
    return `.link-${index}{color:${color};background:${buttonColor};font-family:${fontFamily(font)}}`;
  }).join('\n');
  let currentCategory: string | undefined;
  const links = profile.links.map((link, index) => {
    const category = link.category?.trim() ?? '';
    const heading = category && category !== currentCategory ? `<li class="category">${escapeHtml(category)}</li>` : '';
    currentCategory = category;
    const featured = link.id === appearance.featuredLinkId;
    const icon = resolveIcon(link);
    // The transparent YouTube replacement must not reuse the old one-day image cache.
    const revision = icon === 'youtube' ? '?v=2' : '';
    const logo = icon === 'link' ? '↗' : `<img src="/profile-platforms/${linkInBioPlatformLogoFiles[icon]}${revision}" width="40" height="40" alt="">`;
    return `${heading}<li><a class="link-${index}${featured ? ' featured' : ''}" href="${escapeHtml(link.url)}" target="_blank" rel="noopener noreferrer"><span class="platform-icon${icon === 'link' ? '' : ' brand-logo'}" data-icon="${icon}" aria-hidden="true">${logo}</span><span class="link-copy">${featured && appearance.featuredLabel ? `<span class="featured-label">${escapeHtml(appearance.featuredLabel)}</span>` : ''}<span>${escapeHtml(link.title)}</span></span><span class="arrow" aria-hidden="true">↗</span></a></li>`;
  }).join('');
  return `<!doctype html>
<html lang="th"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer"><title>${escapeHtml(profile.storeName)} | PostDee</title>
<style nonce="${nonce}">
@font-face{font-family:Anuphan;font-style:normal;font-weight:400;font-display:swap;src:url('/profile-fonts/anuphan-regular.ttf') format('truetype')}
@font-face{font-family:Anuphan;font-style:normal;font-weight:600;font-display:swap;src:url('/profile-fonts/anuphan-semibold.ttf') format('truetype')}
@font-face{font-family:Prompt;font-style:normal;font-weight:400;font-display:swap;src:url('/profile-fonts/prompt-regular.ttf') format('truetype')}
@font-face{font-family:Prompt;font-style:normal;font-weight:600;font-display:swap;src:url('/profile-fonts/prompt-semibold.ttf') format('truetype')}
*{box-sizing:border-box}body{margin:0;${background};font-family:Anuphan,system-ui,sans-serif;line-height:1.6;min-height:100vh}
main{width:min(100% - 32px,520px);margin:48px auto;padding:32px 24px;border:1px solid rgba(128,128,128,.18);border-radius:24px;background:${appearance.surfaceColor};box-shadow:0 12px 32px rgba(0,0,0,.06);overflow:hidden}
.brand{${textStyle(appearance.brandStyle)};font-size:13px;font-weight:600;letter-spacing:1px}.cover{display:block;width:calc(100% + 48px);margin:-32px -24px 24px;max-height:220px;object-fit:cover}.logo{display:block;width:88px;height:88px;object-fit:cover;border-radius:24px;margin:0 0 18px}
h1{${textStyle(appearance.nameStyle)};font-size:28px;font-weight:600;line-height:1.4;overflow-wrap:anywhere;margin:16px 0 8px}.description{${textStyle(appearance.descriptionStyle)};white-space:pre-line;overflow-wrap:anywhere;margin:0 0 28px}
ul{list-style:none;padding:0;margin:0;display:grid;gap:12px}.category{${textStyle(appearance.categoryStyle)};font-size:14px;font-weight:600;overflow-wrap:anywhere;margin:12px 0 0}a{display:flex;align-items:center;gap:12px;border-radius:${radius};padding:16px 20px;text-decoration:none;font-weight:600;overflow-wrap:anywhere;min-width:0}
a:hover .link-copy{text-decoration:underline}a:focus-visible{outline:3px solid #d5a22f;outline-offset:4px}.platform-icon{display:flex;align-items:center;justify-content:center;flex-shrink:0;width:40px;height:40px;border-radius:10px;background:rgba(255,255,255,.14);font-family:system-ui,sans-serif;font-size:18px}.platform-icon.brand-logo{background:transparent}.platform-icon img{display:block;width:40px;height:40px;object-fit:contain}.link-copy{display:flex;flex-direction:column;min-width:0;flex:1}.arrow{flex-shrink:0}.featured{box-shadow:inset 0 0 0 2px currentColor}.featured-label{font-size:11px;opacity:.86;font-weight:400}footer{${textStyle(appearance.brandStyle)};text-align:center;font-size:12px;margin-top:28px}
${linkStyles}
@media(max-width:400px){main{margin:24px auto;padding:24px 18px}h1{font-size:24px}.cover{width:calc(100% + 36px);margin:-24px -18px 24px}a{padding:14px 16px}}
</style></head><body><main>${appearance.coverKey ? `<img class="cover" src="${imagePath('cover')}" alt="ภาพปกของ ${escapeHtml(profile.storeName)}">` : ''}<div class="brand">PostDee</div>${appearance.logoKey ? `<img class="logo" src="${imagePath('logo')}" alt="โลโก้ ${escapeHtml(profile.storeName)}">` : ''}<h1>${escapeHtml(profile.storeName)}</h1>
<p class="description">${escapeHtml(appearance.description || 'เลือกช่องทางที่ต้องการได้เลย')}</p><ul>${links}</ul>
<footer>สร้างหน้าเว็บร้านค้าด้วย PostDee</footer></main></body></html>`;
};
