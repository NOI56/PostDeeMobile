import type { LinkInBioAppearance } from './linkInBioAppearance.js';
import { linkInBioColorContrast } from './linkInBioCompositionStyles.js';
import { getProfileTemplate } from './profileTemplateCatalog.generated.js';

// How a premium link is finished: a polished plate with a sheen, a gilded double
// rule, cut Art Deco corners, an open row over a fine rule, a stitched inner
// line, or a soft pearl glow.
export type PremiumLinkMaterial = 'plate' | 'gilded' | 'notched' | 'hairline' | 'stitched' | 'pearl';
type PremiumGeometry = {
  heroHeight: number; avatarSize: number; linkGap: number; panelRadius: number;
  material: PremiumLinkMaterial; frame: boolean;
  /** Full-width art fades into the page; a light page under dark art keeps a clean edge. */
  fade?: false;
};

// The premium release. Geometry is fixed by a trusted catalog ID, never request
// CSS; palette, font and radius still come from the validated owner appearance.
// Keep in step with the app's link_in_bio_premium_scenes.dart.
export const linkInBioPremiumDesigns: Record<string, PremiumGeometry> = {
  'premium-gold-leaf': { heroHeight: 188, avatarSize: 92, linkGap: 14, panelRadius: 6, material: 'plate', frame: true },
  'premium-white-marble': { heroHeight: 250, avatarSize: 84, linkGap: 14, panelRadius: 6, material: 'gilded', frame: true },
  'premium-thai-gold': { heroHeight: 188, avatarSize: 92, linkGap: 14, panelRadius: 6, material: 'gilded', frame: true },
  'premium-art-deco': { heroHeight: 210, avatarSize: 96, linkGap: 14, panelRadius: 4, material: 'notched', frame: true },
  'premium-emerald-facet': { heroHeight: 176, avatarSize: 72, linkGap: 14, panelRadius: 6, material: 'gilded', frame: false },
  'premium-pearl-strand': { heroHeight: 250, avatarSize: 84, linkGap: 14, panelRadius: 28, material: 'pearl', frame: false },
  'premium-velvet-wine': { heroHeight: 176, avatarSize: 80, linkGap: 14, panelRadius: 16, material: 'stitched', frame: false },
  'premium-champagne': { heroHeight: 210, avatarSize: 96, linkGap: 14, panelRadius: 28, material: 'plate', frame: false },
  'premium-guilloche': { heroHeight: 210, avatarSize: 96, linkGap: 14, panelRadius: 6, material: 'gilded', frame: true },
  'premium-rose-gold': { heroHeight: 176, avatarSize: 72, linkGap: 14, panelRadius: 24, material: 'plate', frame: false },
  'premium-midnight-stars': { heroHeight: 210, avatarSize: 96, linkGap: 0, panelRadius: 6, material: 'hairline', frame: true },
  'premium-black-onyx': { heroHeight: 176, avatarSize: 80, linkGap: 0, panelRadius: 4, material: 'hairline', frame: false },
  'premium-silk-ribbon': { heroHeight: 250, avatarSize: 84, linkGap: 14, panelRadius: 28, material: 'plate', frame: false },
  'premium-crystal': { heroHeight: 176, avatarSize: 72, linkGap: 14, panelRadius: 20, material: 'pearl', frame: false },
  'premium-damask': { heroHeight: 188, avatarSize: 92, linkGap: 14, panelRadius: 6, material: 'plate', frame: true },
  'premium-golden-palms': { heroHeight: 176, avatarSize: 80, linkGap: 14, panelRadius: 16, material: 'gilded', frame: false },
  'premium-spotlight': { heroHeight: 210, avatarSize: 96, linkGap: 14, panelRadius: 8, material: 'gilded', frame: false },
  'premium-colonnade': { heroHeight: 250, avatarSize: 84, linkGap: 0, panelRadius: 6, material: 'hairline', frame: true },
  'premium-leather-stitch': { heroHeight: 176, avatarSize: 80, linkGap: 14, panelRadius: 14, material: 'stitched', frame: false, fade: false },
  'premium-sapphire-wave': { heroHeight: 176, avatarSize: 72, linkGap: 14, panelRadius: 4, material: 'notched', frame: true }
};

// A fine rule, a small diamond and a fine rule under centred names.
export const linkInBioPremiumOrnament = 'polygon(0 4px,56px 4px,66px 0,76px 4px,132px 4px,132px 5px,76px 5px,66px 9px,56px 5px,0 5px)';
// Cut corners for Art Deco plates.
export const linkInBioPremiumNotch = 10;

const linkRadius = (appearance: LinkInBioAppearance) => appearance.buttonRadius === 'pill' ? 999 : appearance.buttonRadius === 'square' ? 4 : 16;
const isDark = (color: string) => linkInBioColorContrast(color, '#ffffff') > linkInBioColorContrast(color, '#000000');

export const linkInBioPremiumStyles = (appearance: LinkInBioAppearance): string => {
  const template = getProfileTemplate(appearance.templateId);
  const design = template?.category === 'premium' ? linkInBioPremiumDesigns[template.id] : undefined;
  if (!template || !design) return '';
  const s = 'body[data-template][data-template-category="premium"][data-composition]';
  const composition = template.layout.composition;
  const ink = appearance.nameStyle.color;
  const panel = appearance.surfaceColor;
  const line = appearance.categoryStyle.color;
  const dark = isDark(panel);
  const avatar = design.avatarSize;
  const half = avatar / 2;
  const avatarRadius = template.layout.avatar === 'circle' ? '50%' : template.layout.avatar === 'rounded' ? `${Math.round(avatar * .22)}px` : '3px';
  const radius = linkRadius(appearance);
  const inner = Math.max(0, radius - 4);
  const fullBleed = ['crest', 'cameo', 'atelier'].includes(composition);
  const top = fullBleed ? 0 : composition === 'portal' ? 34 : 24;
  const image = 'position:absolute;inset:0;display:block;width:100%;height:100%;max-height:none;margin:0;border-radius:0;object-fit:cover;object-position:center;pointer-events:none;user-select:none';
  const ring = composition === 'vitrine'
    ? `0 0 0 3px ${panel},0 0 0 4px ${line},0 8px 18px #00000033`
    : `0 0 0 3px ${panel},0 0 0 4px ${line},0 0 0 7px ${panel},0 0 0 8px ${line}80,0 12px 28px #0000004d`;
  const rules: string[] = [
    `${s} main{--pd-premium-side:24px;background:${panel};border-radius:${design.panelRadius}px;padding:${top}px var(--pd-premium-side) 32px;border:1px solid ${line}33;box-shadow:${dark ? '0 24px 60px #00000059' : '0 18px 44px #0000001a'}}`,
    `${s} .profile-header{margin:0 0 30px;text-align:center}`,
    `${s} .profile-copy{position:relative;min-width:0}`,
    `${s} .profile-header h1{font-size:30px;margin:0 0 8px;line-height:1.3;overflow-wrap:anywhere}`,
    `${s} .description{margin:0;font-size:15px;line-height:1.7;overflow-wrap:anywhere}`,
    `${s} .profile-premium-hero .logo{position:absolute;z-index:2;flex-shrink:0;width:${avatar}px;height:${avatar}px;margin:0;border:0;border-radius:${avatarRadius};background:${panel};color:${ink};box-shadow:${ring}}`,
    `${s} img.logo{object-fit:contain;object-position:center}`,
    `${s} .logo.avatar-initial{display:grid;place-items:center;line-height:1;font-size:${Math.round(avatar * .4)}px}`,
    `${s} ul{display:grid;grid-template-columns:minmax(0,1fr);gap:${design.linkGap}px;padding:0}`,
    `${s} .link-item{min-width:0;max-width:100%}`,
    `${s} a{min-height:64px;min-width:0;padding:14px 18px;gap:14px;border-radius:${radius}px;background-clip:padding-box}`,
    `${s} .link-copy{min-width:0;overflow-wrap:anywhere}`,
    `${s} .platform-icon{flex-shrink:0;width:40px;height:40px}`,
    `${s} .arrow{position:static;flex-shrink:0}`,
    `${s} a:focus-visible{outline:3px solid currentColor;outline-offset:4px}`,
    `${s} footer{padding-top:40px;margin-top:auto}`
  ];
  // A fine inner frame around the whole page.
  if (design.frame) {
    rules.push(`${s} main::after{display:block;content:'';position:absolute;z-index:3;inset:10px;border:1px solid ${line}59;border-radius:${Math.max(0, design.panelRadius - 6)}px;pointer-events:none}`);
  }
  const narrow: string[] = [];
  // Full-width artwork fades into the page so the avatar can sit on its edge.
  if (fullBleed) {
    const fade = composition === 'cameo' ? 30 : 42;
    rules.push(`${s} .profile-premium-hero{position:relative;display:block;width:calc(100% + 2 * var(--pd-premium-side));height:${design.heroHeight}px;margin:0 calc(-1 * var(--pd-premium-side))}`);
    rules.push(`${s} .profile-premium-art,${s} .profile-premium-cover{${image}}`);
    if (design.fade !== false) rules.push(`${s} .profile-premium-hero::after{content:'';position:absolute;z-index:1;left:0;right:0;bottom:0;height:${fade}%;background:linear-gradient(180deg,${panel}00,${panel});pointer-events:none}`);
  }
  if (composition === 'crest') {
    rules.push(`${s} .profile-premium-hero .logo{bottom:-${half}px;left:calc(50% - ${half}px)}`);
    rules.push(`${s} .profile-copy{padding-top:${half + 18}px}`);
  }
  if (composition === 'cameo') {
    rules.push(`${s} .profile-premium-hero .logo{top:calc(50% - ${half}px);left:calc(50% - ${half}px)}`);
    rules.push(`${s} .profile-copy{padding-top:20px}`);
  }
  if (composition === 'atelier') {
    rules.push(`${s} .profile-header{text-align:left}`);
    rules.push(`${s} .profile-premium-hero .logo{bottom:-${half}px;left:var(--pd-premium-side)}`);
    rules.push(`${s} .profile-copy{padding-top:${half + 16}px}`);
    rules.push(`${s} .profile-copy::after{content:'';display:block;width:48px;height:1px;margin:16px 0 0;background:${line}}`);
  }
  // The picture is seen through an arched window; the avatar sits on its sill.
  if (composition === 'portal') {
    rules.push(`${s} .profile-premium-hero{position:relative;display:block;width:min(70%,300px);height:${design.heroHeight}px;margin:0 auto}`);
    rules.push(`${s} .profile-premium-arch{position:absolute;inset:0;display:block;overflow:hidden;border-radius:999px 999px 6px 6px;background:${appearance.background.gradientColor};box-shadow:0 0 0 6px ${panel},0 0 0 7px ${line},0 18px 40px #0000002e}`);
    rules.push(`${s} .profile-premium-art,${s} .profile-premium-cover{${image}}`);
    rules.push(`${s} .profile-premium-hero .logo{bottom:-${half}px;left:calc(50% - ${half}px)}`);
    rules.push(`${s} .profile-copy{padding-top:${half + 18}px}`);
  }
  if (['crest', 'cameo', 'portal'].includes(composition)) {
    rules.push(`${s} .profile-copy::after{content:'';display:block;width:132px;height:9px;margin:18px auto 0;background:${line};clip-path:${linkInBioPremiumOrnament}}`);
  }
  // A framed picture above, then the avatar beside the name like a label.
  if (composition === 'vitrine') {
    rules.push(`${s} .profile-header{display:grid;grid-template-columns:${avatar}px minmax(0,1fr);column-gap:16px;row-gap:26px;align-items:center;text-align:left}`);
    rules.push(`${s} .profile-premium-hero{display:contents}`);
    rules.push(`${s} .profile-premium-frame{grid-column:1/-1;grid-row:1;position:relative;display:block;height:${design.heroHeight}px;margin:6px 6px 0;overflow:hidden;border-radius:3px;background:${appearance.background.gradientColor};box-shadow:0 0 0 5px ${panel},0 0 0 6px ${line}99,0 16px 34px #00000040}`);
    rules.push(`${s} .profile-premium-art,${s} .profile-premium-cover{${image}}`);
    rules.push(`${s} .profile-premium-hero .logo{position:relative;grid-column:1;grid-row:2;align-self:center}`);
    rules.push(`${s} .profile-copy{grid-column:2;grid-row:2}`);
    rules.push(`${s} .profile-header h1{font-size:26px}`);
  }
  switch (design.material) {
    case 'plate':
      rules.push(`${s} a{border:1px solid ${line}66;background-image:linear-gradient(180deg,#ffffff38,#ffffff00 52%,#00000014);box-shadow:inset 0 1px 0 #ffffff59,0 8px 18px #00000026}`);
      break;
    case 'gilded':
      rules.push(`${s} a{border:1px solid ${line};box-shadow:0 10px 24px #00000026}`);
      rules.push(`${s} a::before{content:'';position:absolute;inset:4px;border:1px solid ${line}73;border-radius:${inner}px;pointer-events:none}`);
      break;
    case 'notched': {
      const cut = linkInBioPremiumNotch;
      rules.push(`${s} a{border:0;border-radius:0;background-image:linear-gradient(180deg,#ffffff33,#ffffff00 55%,#00000014);clip-path:polygon(${cut}px 0,calc(100% - ${cut}px) 0,100% ${cut}px,100% calc(100% - ${cut}px),calc(100% - ${cut}px) 100%,${cut}px 100%,0 calc(100% - ${cut}px),0 ${cut}px)}`);
      rules.push(`${s} .link-item{filter:drop-shadow(0 8px 12px #00000040)}`);
      rules.push(`${s} a.featured{outline:0;box-shadow:inset 0 0 0 2px var(--pd-link-text)}`);
      rules.push(`${s} .link-item:focus-within{outline:3px solid ${ink};outline-offset:4px}`);
      break;
    }
    case 'hairline':
      rules.push(`${s} ul{border-top:1px solid ${line}80}`);
      rules.push(`${s} a{min-height:68px;padding:16px 4px;border:0;border-bottom:1px solid ${line}80;border-radius:0}`);
      rules.push(`${s} a.custom-button{padding-left:14px;padding-right:14px}`);
      break;
    case 'stitched':
      rules.push(`${s} a{border:1px solid #00000033;box-shadow:0 8px 18px #00000033}`);
      // The thread takes the link's own text colour, so it shows on any fill.
      rules.push(`${s} a::before{content:'';position:absolute;inset:5px;border:1.5px dashed currentColor;border-radius:${Math.max(0, radius - 5)}px;opacity:.65;pointer-events:none}`);
      break;
    case 'pearl':
      rules.push(`${s} a{border:1px solid ${line}40;box-shadow:inset 0 1px 0 #ffffff,0 10px 24px ${line}26,0 2px 6px #0000000f}`);
      break;
  }
  narrow.push(`${s} main{--pd-premium-side:18px;width:calc(100% - 24px)}`, `${s} .profile-header h1{font-size:26px}`, `${s} a{padding:13px 14px;gap:12px}`);
  if (design.material === 'hairline') narrow.push(`${s} a{padding:14px 2px}`);
  if (composition === 'vitrine') narrow.push(`${s} .profile-header h1{font-size:24px}`);
  rules.push(`@media(max-width:400px){${narrow.join('')}}`);
  return rules.join('\n');
};
