import type { LinkInBioAppearance } from './linkInBioAppearance.js';
import { getProfileTemplate } from './profileTemplateCatalog.generated.js';

type DimensionalGeometry = {
  heroHeight: number;
  avatarSize: number;
  linkGap: number;
  material: 'clay' | 'paper' | 'glass';
  shadow: string;
};

// Geometry and materials are fixed by a trusted catalog ID, never request CSS.
// Palette, font and radius still come from the validated owner appearance.
const geometry: Record<string, DimensionalGeometry> = {
  'dimensional-clay-mint': { heroHeight: 200, avatarSize: 96, linkGap: 16, material: 'clay', shadow: '0 7px 12px #00000014,0 2px 3px #00000012' },
  'dimensional-clay-peach': { heroHeight: 200, avatarSize: 96, linkGap: 14, material: 'clay', shadow: '0 5px 0 #0000000a,0 10px 16px #00000013' },
  'dimensional-clay-cloud': { heroHeight: 212, avatarSize: 88, linkGap: 18, material: 'clay', shadow: '0 10px 18px #00000012,0 3px 4px #0000000c' },
  'dimensional-clay-sand': { heroHeight: 192, avatarSize: 96, linkGap: 16, material: 'clay', shadow: '4px 5px 0 #00000012,0 9px 14px #0000000d' },
  'dimensional-paper-fold': { heroHeight: 200, avatarSize: 96, linkGap: 14, material: 'paper', shadow: '2px 3px 0 #00000014,4px 6px 8px #0000000c' },
  'dimensional-paper-stage': { heroHeight: 208, avatarSize: 96, linkGap: 18, material: 'paper', shadow: '0 4px 0 #00000017,0 8px 0 #00000008,0 11px 14px #0000000b' },
  'dimensional-paper-ribbon': { heroHeight: 192, avatarSize: 88, linkGap: 14, material: 'paper', shadow: '3px 3px 0 #00000012,0 7px 12px #0000000c' },
  'dimensional-glass-lavender': { heroHeight: 212, avatarSize: 96, linkGap: 16, material: 'glass', shadow: '0 8px 18px #00000010' },
  'dimensional-glass-mist': { heroHeight: 200, avatarSize: 88, linkGap: 18, material: 'glass', shadow: '0 6px 12px #00000012,0 2px 4px #00000008' },
  'dimensional-glass-sage': { heroHeight: 204, avatarSize: 96, linkGap: 14, material: 'glass', shadow: '0 10px 22px #00000012' }
};

export const linkInBio3dStyles = (appearance: LinkInBioAppearance): string => {
  const template = getProfileTemplate(appearance.templateId);
  if (template?.category !== 'dimensional') return '';
  const style = geometry[template.id];
  if (!style) return '';
  const s = 'body[data-template][data-template-category="dimensional"][data-composition]';
  const radius = appearance.buttonRadius === 'pill' ? '999px' : appearance.buttonRadius === 'square' ? '4px' : '18px';
  const ink = appearance.nameStyle.color;
  const panel = appearance.surfaceColor;
  const panelBackground = panel === template.palette.surface ? 'transparent' : panel;
  const line = appearance.categoryStyle.color;
  const rules: string[] = [
    `${s} main{padding:32px 20px 28px;border:1px solid ${line}14;border-radius:24px;background:${panelBackground};box-shadow:0 16px 36px #00000008;overflow:hidden}`,
    `${s} .profile-header{margin:0 0 28px;isolation:isolate}`,
    `${s} .profile-3d-hero{position:relative;display:flex;align-items:flex-end;justify-content:center;width:calc(100% + 40px);height:${style.heroHeight}px;margin:-32px -20px 0;padding:0 16px 16px;isolation:isolate}`,
    `${s} .profile-3d-art{position:absolute;inset:0;z-index:-1;display:block;width:100%;height:100%;object-fit:contain;object-position:center;pointer-events:none;user-select:none}`,
    `${s} .profile-3d-cover{position:absolute;inset:0;z-index:-1;display:block;width:100%;height:100%;max-height:none;object-fit:cover;object-position:center;margin:0;border-radius:0;pointer-events:none}`,
    `${s} .profile-3d-hero .logo{position:relative;flex-shrink:0;width:${style.avatarSize}px;height:${style.avatarSize}px;margin:0;border:1px solid ${line}1a;border-radius:50%;background:${panel};color:${ink};box-shadow:0 5px 12px #00000016,inset 2px 2px 3px #ffffffc9}`,
    `${s} img.logo{object-fit:contain;object-position:center}`,
    `${s} .logo.avatar-initial{font-size:${style.avatarSize === 88 ? 34 : 38}px;display:grid;place-items:center;line-height:1}`,
    `${s} .profile-copy{position:relative;min-width:0;padding-top:4px}`,
    `${s} .profile-header h1{font-size:30px;margin:16px 0 10px;line-height:1.35;overflow-wrap:anywhere}`,
    `${s} .description{margin:0;overflow-wrap:anywhere}`,
    `${s} ul{display:grid;grid-template-columns:minmax(0,1fr);gap:${style.linkGap}px;padding:0 4px 6px}`,
    `${s} .link-item{min-width:0;max-width:100%}`,
    `${s} a{min-height:76px;min-width:0;padding:16px;gap:12px;border:1px solid ${line}24;border-radius:${radius};box-shadow:inset 1px 2px 2px #ffffffa3,${style.shadow};background-clip:padding-box}`,
    `${s} .link-copy{min-width:0;overflow-wrap:anywhere}`,
    `${s} .platform-icon{flex-shrink:0;width:40px;height:40px}`,
    `${s} .arrow{position:static;flex-shrink:0}`,
    `${s} a:focus-visible{outline:3px solid currentColor;outline-offset:4px}`,
    `${s} footer{padding-top:36px;margin-top:auto}`
  ];
  if (style.material === 'paper') {
    rules.push(`${s} main{border-radius:18px;border-color:${line}2b;box-shadow:3px 4px 0 ${panel},4px 5px 0 ${line}24,7px 8px 0 ${panel},8px 9px 0 ${line}12}`);
    rules.push(`${s} a{border-color:${line}5c;box-shadow:inset 0 1px 0 #ffffffa3,${style.shadow}}`);
  }
  if (style.material === 'glass') {
    rules.push(`${s} .profile-3d-hero .logo{border-color:#ffffffa3;box-shadow:inset 2px 2px 3px #ffffffe6,0 6px 16px #00000015}`);
    rules.push(`${s} a{border-color:${line}30;box-shadow:inset 1px 1px 0 #ffffffcc,inset -1px -1px 0 #ffffff5c,${style.shadow};backdrop-filter:blur(14px);-webkit-backdrop-filter:blur(14px)}`);
  }
  if (template.id === 'dimensional-paper-stage') {
    rules.push(`${s} .link-item[data-rhythm="1"],${s} .link-item[data-rhythm="3"]{margin-left:6px}`);
    rules.push(`${s} .link-item[data-rhythm="0"],${s} .link-item[data-rhythm="2"]{margin-right:6px}`);
  }
  if (template.id === 'dimensional-paper-ribbon') {
    rules.push(`${s} .category{padding:6px 10px;border-left:3px solid ${line};background:${line}0d}`);
  }
  if (template.id === 'dimensional-glass-mist') {
    rules.push(`${s} .profile-copy{padding:0 10px}`);
  }
  rules.push(`@media(max-width:400px){${s} main{padding:32px 16px 24px;width:calc(100% - 24px)}${s} .profile-3d-hero{width:calc(100% + 32px);margin-left:-16px;margin-right:-16px}${s} .profile-header h1{font-size:28px}${s} a{padding:14px 12px;gap:10px}}`);
  return rules.join('\n');
};
