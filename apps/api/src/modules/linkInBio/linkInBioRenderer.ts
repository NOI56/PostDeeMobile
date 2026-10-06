import { linkInBioFonts, normalizeStoredLinkInBioAppearance, readLinkInBioColor, type LinkInBioFont, type LinkInBioTextStyle } from './linkInBioAppearance.js';
import type { LinkInBioProfile } from './linkInBioStore.js';
import { getLinkInBioPlatformLogoGeometry, linkInBioPlatformLogoFiles, type LinkInBioBrandIcon } from './linkInBioPlatformLogos.js';
import { readLinkInBioUrl, resolveLinkInBioIcon } from './linkInBioDestinations.js';

const escapeHtml = (value: string) => value.replace(/[&<>"']/g, (character) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
})[character]!);
const fontFamily = (font: LinkInBioFont) => font === 'system' ? 'system-ui,-apple-system,sans-serif' : `"${font === 'prompt' ? 'Prompt' : 'Anuphan'}",system-ui,sans-serif`;
const textStyle = (style: LinkInBioTextStyle) => `color:${style.color};font-family:${fontFamily(style.font)}`;
const cssNumber = (value: number) => Number(value.toFixed(6));
const platformLogoStyles = (Object.keys(linkInBioPlatformLogoFiles) as LinkInBioBrandIcon[]).map((icon) => {
  const geometry = getLinkInBioPlatformLogoGeometry(icon);
  return `.platform-icon[data-icon="${icon}"] img{width:${cssNumber(geometry.width)}px;height:${cssNumber(geometry.height)}px;left:${cssNumber(geometry.left)}px;top:${cssNumber(geometry.top)}px}`;
}).join('\n');
const contactVectors = {
  website: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a16 16 0 0 1 0 18 16 16 0 0 1 0-18Z"/>',
  email: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 6 9 7 9-7"/>',
  phone: '<path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.69 2.79a2 2 0 0 1-.45 2.11L8.09 9.89a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.9.33 1.84.56 2.8.69A2 2 0 0 1 22 16.92Z"/>'
} as const;
const contactVector = (icon: keyof typeof contactVectors) => `<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" focusable="false">${contactVectors[icon]}</svg>`;

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
    const icon = resolveLinkInBioIcon(link);
    // The transparent YouTube replacement must not reuse the old one-day image cache.
    const revision = icon === 'youtube' ? '?v=2' : '';
    const isBrand = Object.hasOwn(linkInBioPlatformLogoFiles, icon);
    const logo = isBrand ? `<img src="/profile-platforms/${linkInBioPlatformLogoFiles[icon as LinkInBioBrandIcon]}${revision}" width="40" height="40" alt="">`
      : icon === 'link' ? '↗' : contactVector(icon as keyof typeof contactVectors);
    const destination = readLinkInBioUrl(link.url);
    const target = destination?.startsWith('mailto:') || destination?.startsWith('tel:') ? '' : ' target="_blank" rel="noopener noreferrer"';
    return `${heading}<li><a class="link-${index}${featured ? ' featured' : ''}" href="${escapeHtml(destination ?? link.url)}"${target}><span class="platform-icon${isBrand ? ' brand-logo' : ''}" data-icon="${icon}" aria-hidden="true">${logo}</span><span class="link-copy">${featured && appearance.featuredLabel ? `<span class="featured-label">${escapeHtml(appearance.featuredLabel)}</span>` : ''}<span>${escapeHtml(link.title)}</span></span><span class="arrow" aria-hidden="true">↗</span></a></li>`;
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
a:hover .link-copy{text-decoration:underline}a:focus-visible{outline:3px solid #d5a22f;outline-offset:4px}.platform-icon{display:flex;align-items:center;justify-content:center;flex-shrink:0;width:40px;height:40px;border-radius:10px;background:rgba(255,255,255,.14);font-family:system-ui,sans-serif;font-size:18px}.platform-icon.brand-logo{background:transparent;position:relative;overflow:hidden;border-radius:0}.platform-icon img{position:absolute;display:block;max-width:none;object-fit:contain;pointer-events:none}.link-copy{display:flex;flex-direction:column;min-width:0;flex:1}.arrow{flex-shrink:0}.featured{box-shadow:inset 0 0 0 2px currentColor}.featured-label{font-size:11px;opacity:.86;font-weight:400}footer{${textStyle(appearance.brandStyle)};text-align:center;font-size:12px;margin-top:28px}
${platformLogoStyles}
${linkStyles}
@media(max-width:400px){main{margin:24px auto;padding:24px 18px}h1{font-size:24px}.cover{width:calc(100% + 36px);margin:-24px -18px 24px}a{padding:14px 16px}}
</style></head><body><main>${appearance.coverKey ? `<img class="cover" src="${imagePath('cover')}" alt="ภาพปกของ ${escapeHtml(profile.storeName)}">` : ''}<div class="brand">PostDee</div>${appearance.logoKey ? `<img class="logo" src="${imagePath('logo')}" alt="โลโก้ ${escapeHtml(profile.storeName)}">` : ''}<h1>${escapeHtml(profile.storeName)}</h1>
<p class="description">${escapeHtml(appearance.description || 'เลือกช่องทางที่ต้องการได้เลย')}</p><ul>${links}</ul>
<footer>สร้างหน้าเว็บร้านค้าด้วย PostDee</footer></main></body></html>`;
};
