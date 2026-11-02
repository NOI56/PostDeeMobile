import type { LinkInBioAppearance } from './linkInBioAppearance.js';
import { getProfileTemplate, type ProfileTemplateDefinition } from './profileTemplateCatalog.generated.js';

type CartoonGeometry = { heroHeight: number; avatarSize: number; linkGap: number; panelRadius: string };

// Hand-drawn corners: each corner gets its own elliptical radius, so a box
// reads as drawn by hand. The app uses the same values as Radius.elliptical.
const wobblyPanel = '30px 44px 34px 40px/40px 30px 44px 34px';
const wobblyLink = { rounded: '16px 26px 14px 24px/24px 14px 26px 16px', square: '6px 3px 7px 4px/4px 7px 3px 6px', pill: '999px' };

// The cartoon release. Geometry is fixed by a trusted catalog ID, never request
// CSS; palette, font and radius still come from the validated owner appearance.
// Keep in step with the app's link_in_bio_cartoon_scenes.dart.
export const linkInBioCartoonDesigns: Record<string, CartoonGeometry> = {
  'cartoon-doodle-shop': { heroHeight: 176, avatarSize: 84, linkGap: 16, panelRadius: wobblyPanel },
  'cartoon-comic-panels': { heroHeight: 150, avatarSize: 88, linkGap: 16, panelRadius: '8px' },
  'cartoon-tag-buddy': { heroHeight: 168, avatarSize: 72, linkGap: 14, panelRadius: '28px' },
  'cartoon-sticker-sheet': { heroHeight: 176, avatarSize: 84, linkGap: 16, panelRadius: '26px' },
  'cartoon-chalkboard': { heroHeight: 168, avatarSize: 80, linkGap: 14, panelRadius: '14px' },
  'cartoon-street-front': { heroHeight: 200, avatarSize: 64, linkGap: 14, panelRadius: '24px' },
  'cartoon-chat-bubbles': { heroHeight: 140, avatarSize: 64, linkGap: 18, panelRadius: '28px' },
  'cartoon-signposts': { heroHeight: 168, avatarSize: 72, linkGap: 14, panelRadius: '22px' },
  'cartoon-crayon-sky': { heroHeight: 176, avatarSize: 84, linkGap: 16, panelRadius: wobblyPanel },
  'cartoon-rocket-night': { heroHeight: 176, avatarSize: 84, linkGap: 14, panelRadius: '28px' }
};

// Rotating crayon outlines; the first follows the owner's heading color.
export const linkInBioCrayonColors = ['#2e86de', '#3fa34d', '#f08a00'];

const linkRadius = (appearance: LinkInBioAppearance, wobbly: boolean) => wobbly ? wobblyLink[appearance.buttonRadius]
  : appearance.buttonRadius === 'pill' ? '999px' : appearance.buttonRadius === 'square' ? '4px' : '16px';

// Each design's link edge: a border and a shadow drawn in its own style.
const linkMaterial = (id: string, ink: string, line: string, panel: string): { border: string; shadow: string } => {
  switch (id) {
    case 'cartoon-doodle-shop': return { border: `2px solid ${ink}`, shadow: `3px 4px 0 -1px ${panel},3px 4px 0 1px ${ink}` };
    case 'cartoon-comic-panels': return { border: `3px solid ${ink}`, shadow: `5px 5px 0 ${ink}` };
    case 'cartoon-tag-buddy': return { border: `1px solid ${line}24`, shadow: `inset 6px 0 0 ${line},0 4px 0 ${line}29,0 10px 18px #0000000f` };
    case 'cartoon-sticker-sheet': return { border: '4px solid #ffffff', shadow: `0 0 0 1px ${line}33,0 6px 12px #0000001f` };
    case 'cartoon-chalkboard': return { border: '2px dashed var(--pd-link-button)', shadow: 'none' };
    case 'cartoon-street-front': return { border: `2px solid ${line}`, shadow: `0 4px 0 ${line}40` };
    case 'cartoon-chat-bubbles': return { border: `2px solid ${ink}`, shadow: `0 3px 0 ${ink}1f` };
    case 'cartoon-signposts': return { border: '0', shadow: 'none' };
    case 'cartoon-crayon-sky': return { border: `3px solid ${line}`, shadow: '0 3px 0 #00000012' };
    default: return { border: `2px solid ${line}66`, shadow: `0 0 0 4px ${panel},0 0 0 5px ${line}33,0 8px 18px #00000040` };
  }
};

// The avatar's own ring, drawn in the design's style.
const avatarRing = (id: string, ink: string, line: string, panel: string) => {
  switch (id) {
    case 'cartoon-doodle-shop': return `0 0 0 4px ${panel},0 0 0 6px ${ink},4px 5px 0 6px ${ink}33`;
    case 'cartoon-sticker-sheet': return `0 0 0 5px #ffffff,0 6px 14px #00000033`;
    case 'cartoon-chalkboard': return `0 0 0 4px ${panel},0 0 0 6px ${line}`;
    case 'cartoon-crayon-sky': return `0 0 0 4px ${panel},0 0 0 7px ${line}`;
    case 'cartoon-rocket-night': return `0 0 0 4px ${panel},0 0 0 6px ${line},0 0 18px ${line}59`;
    default: return '0 6px 14px #0000001f';
  }
};

const panelFrame = (template: ProfileTemplateDefinition, ink: string, line: string) => {
  switch (template.id) {
    case 'cartoon-doodle-shop': return `border:2px solid ${ink};box-shadow:5px 6px 0 ${ink}1f`;
    case 'cartoon-comic-panels': return `border:3px solid ${ink};box-shadow:6px 6px 0 ${ink}`;
    case 'cartoon-chalkboard': return 'border:10px solid #8b5e3c;box-shadow:0 16px 34px #00000038';
    case 'cartoon-crayon-sky': return `border:3px solid ${line}`;
    case 'cartoon-rocket-night': return `border:1px solid ${line}33;box-shadow:0 18px 40px #00000059`;
    default: return `border:1px solid ${line}24;box-shadow:0 14px 30px #0000000f`;
  }
};

export const linkInBioCartoonStyles = (appearance: LinkInBioAppearance): string => {
  const template = getProfileTemplate(appearance.templateId);
  const design = template?.category === 'cartoon' ? linkInBioCartoonDesigns[template.id] : undefined;
  if (!template || !design) return '';
  const s = 'body[data-template][data-template-category="cartoon"][data-composition]';
  const composition = template.layout.composition;
  const ink = appearance.nameStyle.color;
  const panel = appearance.surfaceColor;
  const line = appearance.categoryStyle.color;
  const wash = appearance.background.gradientColor;
  const avatar = design.avatarSize;
  const half = avatar / 2;
  const avatarRadius = template.layout.avatar === 'circle' ? '50%' : template.layout.avatar === 'rounded' ? `${Math.round(avatar * .22)}px` : '3px';
  const wobbly = template.id === 'cartoon-doodle-shop' || template.id === 'cartoon-crayon-sky';
  const material = linkMaterial(template.id, ink, line, panel);
  const top = composition === 'banner' || composition === 'signboard' ? 0 : composition === 'beside' ? 24 : 20;
  const image = 'display:block;max-height:none;margin:0;pointer-events:none;user-select:none';
  const rules: string[] = [
    `${s} main{--pd-cartoon-side:20px;background:${panel};border-radius:${design.panelRadius};overflow:hidden;padding:${top}px var(--pd-cartoon-side) 28px;${panelFrame(template, ink, line)}}`,
    `${s} .profile-header{margin:0 0 26px;isolation:isolate;text-align:left}`,
    `${s} .profile-copy{position:relative;min-width:0}`,
    `${s} .profile-header h1{font-size:28px;margin:0 0 8px;line-height:1.35;overflow-wrap:anywhere}`,
    `${s} .description{margin:0;overflow-wrap:anywhere}`,
    `${s} .profile-cartoon-hero .logo{flex-shrink:0;width:${avatar}px;height:${avatar}px;margin:0;border:0;border-radius:${avatarRadius};background:${panel};color:${ink};box-shadow:${avatarRing(template.id, ink, line, panel)}}`,
    `${s} img.logo{object-fit:contain;object-position:center}`,
    `${s} .logo.avatar-initial{display:grid;place-items:center;line-height:1;font-size:${Math.round(avatar * .4)}px}`,
    `${s} ul{display:grid;grid-template-columns:minmax(0,1fr);gap:${design.linkGap}px;padding:0 0 6px}`,
    `${s} .link-item{min-width:0;max-width:100%}`,
    `${s} a{min-height:72px;min-width:0;padding:15px 16px;gap:12px;border:${material.border};border-radius:${linkRadius(appearance, wobbly)};box-shadow:${material.shadow};background-clip:padding-box}`,
    `${s} .link-copy{min-width:0;overflow-wrap:anywhere}`,
    `${s} .platform-icon{flex-shrink:0;width:40px;height:40px}`,
    `${s} .arrow{position:static;flex-shrink:0}`,
    `${s} a:focus-visible{outline:3px solid currentColor;outline-offset:4px}`,
    `${s} footer{padding-top:36px;margin-top:auto}`
  ];
  // Overrides that must survive the small-screen padding below.
  const narrow: string[] = [];
  // A full-width drawing: cropped to the banner, the avatar overlaps its edge.
  if (composition === 'banner' || composition === 'signboard') {
    rules.push(`${s} .profile-cartoon-hero{position:relative;display:block;width:calc(100% + 2 * var(--pd-cartoon-side));height:${design.heroHeight}px;margin:0 calc(-1 * var(--pd-cartoon-side))}`);
    rules.push(`${s} .profile-cartoon-art{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;object-position:center;${image}}`);
    rules.push(`${s} .profile-cartoon-cover{position:absolute;inset:0;width:100%;height:100%;border-radius:0;object-fit:cover;object-position:center;${image}}`);
  }
  if (composition === 'banner') {
    const centered = template.layout.header === 'centered';
    rules.push(`${s} .profile-cartoon-hero .logo{position:absolute;bottom:-${half}px;left:${centered ? `calc(50% - ${half}px)` : 'var(--pd-cartoon-side)'}}`);
    rules.push(`${s} .profile-copy{padding-top:${half + 14}px;text-align:${centered ? 'center' : 'left'}}`);
  }
  // The owner's logo hangs on a painted board above the drawn shop awning.
  if (composition === 'signboard') {
    const sign = avatar + 18;
    rules.push(`${s} .profile-cartoon-hero::before{content:'';position:absolute;z-index:1;top:0;left:calc(50% - 26px);width:52px;height:20px;border-left:3px solid ${ink};border-right:3px solid ${ink};pointer-events:none}`);
    rules.push(`${s} .profile-cartoon-sign{position:absolute;z-index:2;top:18px;left:calc(50% - ${sign / 2}px);display:block;width:${sign}px;height:${sign}px;padding:6px;border:3px solid ${ink};border-radius:14px;background:${panel};box-shadow:0 4px 0 ${ink}}`);
    rules.push(`${s} .profile-cartoon-sign .logo{box-shadow:none}`);
    rules.push(`${s} .profile-copy{padding-top:18px;text-align:center}`);
  }
  // Transparent drawing beside the avatar, with the name across the card.
  if (composition === 'beside') {
    rules.push(`${s} .profile-header{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1.45fr);column-gap:12px;row-gap:14px;align-items:end}`);
    rules.push(`${s} .profile-cartoon-hero{display:contents}`, `${s} .profile-cartoon-hero .logo{grid-column:1;grid-row:1;align-self:end}`);
    rules.push(`${s} .profile-cartoon-cover{grid-column:2;grid-row:1;width:100%;height:${design.heroHeight}px;border-radius:16px;object-fit:cover;${image}}`);
    rules.push(`${s} .profile-cartoon-art{grid-column:2;grid-row:1;width:100%;height:${design.heroHeight}px;object-fit:contain;object-position:center bottom;${image}}`);
    rules.push(`${s} .profile-copy{grid-column:1/-1;grid-row:2}`);
  }
  // Comic page: a framed drawing panel, then an avatar panel and a caption box.
  if (composition === 'panels') {
    const frame = `border:3px solid ${ink};border-radius:6px`;
    rules.push(`${s} .profile-header{display:grid;grid-template-columns:${avatar}px minmax(0,1fr);column-gap:12px;row-gap:12px;align-items:start}`);
    rules.push(`${s} .profile-cartoon-hero{display:contents}`);
    rules.push(`${s} .profile-cartoon-art{grid-column:1/-1;grid-row:1;width:100%;height:${design.heroHeight}px;object-fit:cover;object-position:center;${frame};${image}}`);
    rules.push(`${s} .profile-cartoon-cover{grid-column:1/-1;grid-row:1;width:100%;height:${design.heroHeight}px;object-fit:cover;${frame};${image}}`);
    rules.push(`${s} .profile-cartoon-hero .logo{grid-column:1;grid-row:2;${frame};box-shadow:none}`);
    rules.push(`${s} .profile-copy{grid-column:2;grid-row:2;min-height:${avatar}px;padding:10px 12px;background:${wash};${frame}}`);
    // Small phones give the caption more room for long Thai names.
    const small = 64;
    narrow.push(`${s} .profile-header{grid-template-columns:${small}px minmax(0,1fr);column-gap:10px}`,
      `${s} .profile-cartoon-hero .logo{width:${small}px;height:${small}px}`, `${s} .logo.avatar-initial{font-size:${Math.round(small * .4)}px}`,
      `${s} .profile-copy{min-height:${small}px}`);
  }
  // Chat: a cluster of empty bubbles, then the name said in a bubble.
  if (composition === 'chat') {
    rules.push(`${s} .profile-header{display:grid;grid-template-columns:${avatar}px minmax(0,1fr);column-gap:16px;row-gap:16px;align-items:end}`);
    rules.push(`${s} .profile-cartoon-hero{display:contents}`, `${s} .profile-cartoon-hero .logo{grid-column:1;grid-row:2;align-self:end}`);
    rules.push(`${s} .profile-cartoon-art{grid-column:1/-1;grid-row:1;width:100%;height:${design.heroHeight}px;object-fit:contain;object-position:center;${image}}`);
    rules.push(`${s} .profile-cartoon-cover{grid-column:1/-1;grid-row:1;width:100%;height:${design.heroHeight}px;border-radius:16px;object-fit:cover;${image}}`);
    rules.push(`${s} .profile-copy{grid-column:2;grid-row:2;padding:12px 14px;background:${wash};border:2px solid ${ink};border-radius:20px}`);
    rules.push(`${s} .profile-copy::after{content:'';position:absolute;left:-9px;bottom:14px;width:14px;height:14px;background:inherit;border-left:2px solid ${ink};border-bottom:2px solid ${ink};transform:rotate(45deg)}`);
    rules.push(`${s} .link-item{width:88%;justify-self:start}`);
    rules.push(`${s} .link-item[data-rhythm="1"],${s} .link-item[data-rhythm="3"]{justify-self:end}`);
    rules.push(`${s} a::after{content:'';position:absolute;bottom:-9px;left:22px;width:14px;height:14px;background:inherit;border-right:2px solid ${ink};border-bottom:2px solid ${ink};transform:rotate(45deg)}`);
    rules.push(`${s} .link-item[data-rhythm="1"] a::after,${s} .link-item[data-rhythm="3"] a::after{left:auto;right:22px}`);
  }
  if (template.id === 'cartoon-tag-buddy') {
    rules.push(`${s} a{padding-left:22px}`);
    narrow.push(`${s} a{padding-left:18px}`);
  }
  // A still tilt, like stickers pressed on by hand; nothing moves.
  if (template.id === 'cartoon-sticker-sheet') {
    rules.push(`${s} .link-item[data-rhythm="0"] a,${s} .link-item[data-rhythm="2"] a{transform:rotate(-1deg)}`);
    rules.push(`${s} .link-item[data-rhythm="1"] a,${s} .link-item[data-rhythm="3"] a{transform:rotate(1deg)}`);
  }
  if (template.id === 'cartoon-street-front') {
    rules.push(`${s} a{padding-top:24px;background-image:repeating-linear-gradient(90deg,${line} 0 14px,#ffffff 14px 28px);background-size:100% 10px;background-repeat:no-repeat}`);
    narrow.push(`${s} a{padding-top:22px}`);
  }
  // Arrow signs: the clip hides borders and outlines, so the shadow sits on
  // the list item and keyboard focus is drawn around the whole item.
  if (template.id === 'cartoon-signposts') {
    const left = linkRadius(appearance, false);
    rules.push(`${s} a{padding-right:34px;border-radius:${left} 0 0 ${left};clip-path:polygon(0 0,calc(100% - 20px) 0,100% 50%,calc(100% - 20px) 100%,0 100%);background-image:repeating-linear-gradient(0deg,#0000000d 0 2px,transparent 2px 10px)}`);
    rules.push(`${s} .link-item{filter:drop-shadow(0 4px 0 ${ink}59)}`);
    rules.push(`${s} .link-item:focus-within{outline:3px solid ${ink};outline-offset:3px;border-radius:6px}`);
    narrow.push(`${s} a{padding-right:30px}`);
  }
  if (template.id === 'cartoon-crayon-sky') {
    [line, ...linkInBioCrayonColors].forEach((color, rhythm) => rules.push(`${s} .link-item[data-rhythm="${rhythm}"] a{border-color:${color}}`));
  }
  rules.push(`@media(max-width:400px){${s} main{--pd-cartoon-side:16px;width:calc(100% - 24px)}${s} .profile-header h1{font-size:26px}${s} a{padding:14px 12px;gap:10px}${narrow.join('')}}`);
  return rules.join('\n');
};
