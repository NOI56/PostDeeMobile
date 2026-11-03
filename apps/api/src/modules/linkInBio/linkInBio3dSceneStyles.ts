import type { LinkInBioAppearance } from './linkInBioAppearance.js';
import type { ProfileTemplateDefinition } from './profileTemplateCatalog.generated.js';

type SceneGeometry = { heroHeight: number; avatarSize: number; linkGap: number; panelRadius: number };

// Second 3D release. Geometry is fixed by a trusted catalog ID, never request
// CSS; palette, font and radius still come from the validated owner appearance.
// Keep in step with the app's link_in_bio_3d_scenes.dart.
export const linkInBio3dScenes: Record<string, SceneGeometry> = {
  'dimensional-chrome-night': { heroHeight: 184, avatarSize: 84, linkGap: 14, panelRadius: 24 },
  'dimensional-lowpoly-dawn': { heroHeight: 184, avatarSize: 84, linkGap: 14, panelRadius: 24 },
  'dimensional-zen-garden': { heroHeight: 176, avatarSize: 80, linkGap: 12, panelRadius: 20 },
  'dimensional-wood-blocks': { heroHeight: 160, avatarSize: 64, linkGap: 18, panelRadius: 26 },
  'dimensional-parcel-stack': { heroHeight: 160, avatarSize: 64, linkGap: 14, panelRadius: 18 },
  'dimensional-ceramic-tiles': { heroHeight: 150, avatarSize: 60, linkGap: 14, panelRadius: 24 },
  'dimensional-pop-shapes': { heroHeight: 150, avatarSize: 60, linkGap: 14, panelRadius: 28 },
  'dimensional-neon-sign': { heroHeight: 168, avatarSize: 76, linkGap: 16, panelRadius: 28 },
  'dimensional-concrete-slab': { heroHeight: 150, avatarSize: 64, linkGap: 18, panelRadius: 4 },
  'dimensional-terrazzo-steps': { heroHeight: 150, avatarSize: 64, linkGap: 18, panelRadius: 22 }
};

// Each scene's link material: a border and a shadow that reads as its surface.
const linkMaterial = (id: string, ink: string, line: string, button: string): { border: string; shadow: string } => {
  switch (id) {
    case 'dimensional-chrome-night': return { border: `1px solid ${line}38`, shadow: `0 10px 22px #00000052,0 1px 0 ${line}40` };
    case 'dimensional-lowpoly-dawn': return { border: `1px solid ${line}1f`, shadow: `0 8px 18px ${ink}1a,0 2px 4px ${ink}0f` };
    case 'dimensional-zen-garden': return { border: '1.5px solid var(--pd-link-button)', shadow: `0 2px 0 ${line}29` };
    case 'dimensional-wood-blocks': return { border: `2px solid ${ink}`, shadow: `0 5px 0 ${ink}` };
    case 'dimensional-parcel-stack': return { border: `1px solid ${line}47`, shadow: `0 3px 0 ${line}2e,0 10px 18px #0000000f` };
    case 'dimensional-ceramic-tiles': return { border: `1px solid ${ink}26`, shadow: `0 5px 0 ${ink}cc,0 12px 20px ${ink}26` };
    case 'dimensional-pop-shapes': return { border: `2px solid ${ink}`, shadow: `3px 4px 0 ${line}` };
    case 'dimensional-neon-sign': return { border: '1.5px solid var(--pd-link-button)', shadow: `0 0 14px ${button}73,0 0 2px ${button}` };
    case 'dimensional-concrete-slab': return { border: `2px solid ${ink}`, shadow: `0 6px 0 ${ink}` };
    default: return { border: `1.5px solid ${line}99`, shadow: `0 5px 0 ${line}59,0 10px 16px #0000000f` };
  }
};

export const linkInBio3dSceneStyles = (appearance: LinkInBioAppearance, template: ProfileTemplateDefinition): string => {
  const scene = linkInBio3dScenes[template.id];
  if (!scene) return '';
  const s = 'body[data-template][data-template-category="dimensional"][data-composition]';
  const composition = template.layout.composition;
  const radius = appearance.buttonRadius === 'pill' ? '999px' : appearance.buttonRadius === 'square' ? '4px' : '18px';
  const ink = appearance.nameStyle.color;
  const panel = appearance.surfaceColor;
  const line = appearance.categoryStyle.color;
  const button = appearance.buttonColor;
  const avatar = scene.avatarSize;
  const half = avatar / 2;
  const avatarRadius = template.layout.avatar === 'circle' ? '50%' : template.layout.avatar === 'rounded' ? `${Math.round(avatar * .22)}px` : '6px';
  const material = linkMaterial(template.id, ink, line, button);
  const concrete = template.id === 'dimensional-concrete-slab';
  const panelFrame: Record<string, string> = {
    showcase: `padding:0 var(--pd-3d-side) 28px;border:1px solid ${line}1f;box-shadow:0 16px 36px #0000000f`,
    neon: `padding:16px var(--pd-3d-side) 28px;border:1px solid ${line}59;box-shadow:0 0 0 1px ${line}1f,0 0 36px ${line}2e`,
    'split-art': `padding:24px var(--pd-3d-side) 28px;border:1px solid ${line}24;box-shadow:0 14px 32px #0000000d`,
    'tile-grid': `padding:20px var(--pd-3d-side) 28px;border:1px solid ${line}1f;box-shadow:0 14px 30px #0000000d`,
    slab: concrete ? `padding:28px var(--pd-3d-side) 32px;border:2px solid ${ink};box-shadow:8px 8px 0 ${ink}`
      : `padding:28px var(--pd-3d-side) 28px;border:1px solid ${line}33;box-shadow:0 16px 34px #0000001f`
  };
  const rules: string[] = [
    `${s} main{--pd-3d-side:20px;background:${panel};border-radius:${scene.panelRadius}px;overflow:hidden;${panelFrame[composition]}}`,
    `${s} .profile-header{margin:0 0 26px;isolation:isolate;text-align:left}`,
    `${s} .profile-copy{position:relative;min-width:0}`,
    `${s} .profile-header h1{font-size:28px;margin:0 0 8px;line-height:1.35;overflow-wrap:anywhere}`,
    `${s} .description{margin:0;overflow-wrap:anywhere}`,
    `${s} .profile-3d-hero .logo{flex-shrink:0;width:${avatar}px;height:${avatar}px;margin:0;border:1px solid ${line}24;border-radius:${avatarRadius};background:${panel};color:${ink};box-shadow:0 6px 14px #0000001f}`,
    `${s} img.logo{object-fit:contain;object-position:center}`,
    `${s} .logo.avatar-initial{display:grid;place-items:center;line-height:1;font-size:${Math.round(avatar * .4)}px}`,
    `${s} ul{display:grid;grid-template-columns:minmax(0,1fr);gap:${scene.linkGap}px;padding:0 0 6px}`,
    `${s} .link-item{min-width:0;max-width:100%}`,
    `${s} a{min-height:72px;min-width:0;padding:15px 16px;gap:12px;border:${material.border};border-radius:${radius};box-shadow:${material.shadow};background-clip:padding-box}`,
    `${s} .link-copy{min-width:0;overflow-wrap:anywhere}`,
    `${s} .platform-icon{flex-shrink:0;width:40px;height:40px}`,
    `${s} .arrow{position:static;flex-shrink:0}`,
    `${s} a:focus-visible{outline:3px solid currentColor;outline-offset:4px}`,
    `${s} footer{padding-top:36px;margin-top:auto}`
  ];
  // A full-bleed or inset banner: artwork is cropped, the avatar overlaps it.
  if (composition === 'showcase' || composition === 'neon') {
    const neon = composition === 'neon';
    const centered = neon || template.layout.header === 'centered';
    const image = `position:absolute;inset:0;display:block;width:100%;height:100%;max-height:none;margin:0;border-radius:${neon ? 18 : 0}px;object-fit:cover;object-position:center;pointer-events:none;user-select:none`;
    rules.push(neon
      ? `${s} .profile-3d-hero{position:relative;display:block;height:${scene.heroHeight}px;margin:0;border-radius:18px;box-shadow:0 0 26px ${button}40}`
      : `${s} .profile-3d-hero{position:relative;display:block;width:calc(100% + 2 * var(--pd-3d-side));height:${scene.heroHeight}px;margin:0 calc(-1 * var(--pd-3d-side))}`);
    rules.push(`${s} .profile-3d-cover{${image}}`, `${s} .profile-3d-art{${image}}`);
    rules.push(`${s} .profile-3d-hero .logo{position:absolute;bottom:-${half}px;left:${centered ? `calc(50% - ${half}px)` : 'var(--pd-3d-side)'};box-shadow:${neon ? `0 0 0 3px ${panel},0 0 0 5px ${button},0 0 18px ${button}73` : `0 0 0 4px ${panel},0 8px 18px #00000029`}}`);
    rules.push(`${s} .profile-copy{padding-top:${half + (neon ? 16 : 14)}px;text-align:${centered ? 'center' : 'left'}}`);
  }
  // Transparent object art beside the avatar, with the name across the card.
  if (composition === 'split-art') {
    rules.push(`${s} .profile-header{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1.45fr);column-gap:12px;row-gap:14px;align-items:end}`);
    rules.push(`${s} .profile-3d-hero{display:contents}`, `${s} .profile-3d-hero .logo{grid-column:1;grid-row:1;align-self:end}`);
    rules.push(`${s} .profile-3d-cover{grid-column:2;grid-row:1;display:block;width:100%;height:${scene.heroHeight}px;max-height:none;margin:0;border-radius:16px;object-fit:cover}`);
    rules.push(`${s} .profile-3d-art{grid-column:2;grid-row:1;display:block;width:100%;height:${scene.heroHeight}px;object-fit:contain;object-position:center bottom;pointer-events:none;user-select:none}`);
    rules.push(`${s} .profile-copy{grid-column:1/-1;grid-row:2}`);
  }
  // Art above a side-by-side avatar and name; links pair up as tiles.
  if (composition === 'tile-grid') {
    rules.push(`${s} .profile-header{display:grid;grid-template-columns:${avatar}px minmax(0,1fr);column-gap:14px;row-gap:16px;align-items:center}`);
    rules.push(`${s} .profile-3d-hero{display:contents}`, `${s} .profile-3d-hero .logo{grid-column:1;grid-row:2}`);
    rules.push(`${s} .profile-3d-cover{grid-column:1/-1;grid-row:1;display:block;width:100%;height:${scene.heroHeight}px;max-height:none;margin:0;border-radius:16px;object-fit:cover}`);
    rules.push(`${s} .profile-3d-art{grid-column:1/-1;grid-row:1;display:block;width:100%;height:${scene.heroHeight}px;object-fit:contain;object-position:center;pointer-events:none;user-select:none}`);
    rules.push(`${s} .profile-copy{grid-column:2;grid-row:2}`);
    rules.push(`${s} ul{grid-template-columns:repeat(2,minmax(0,1fr))}`, `${s} .category{grid-column:1/-1}`, `${s} .fill-row{grid-column:1/-1}`);
    rules.push(`${s} a{position:relative;height:100%;min-height:116px;flex-direction:column;align-items:flex-start;padding:14px;gap:10px}`);
    rules.push(`${s} .link-copy{width:100%;padding-right:14px}`, `${s} .arrow{position:absolute;right:12px;bottom:12px}`);
  }
  // Owner text first, then the art as a display shelf above the links.
  if (composition === 'slab') {
    rules.push(`${s} .profile-header{display:flex;flex-direction:column;align-items:flex-start}`);
    rules.push(`${s} .profile-3d-hero{display:contents}`, `${s} .profile-3d-hero .logo{order:0}`);
    rules.push(`${s} .profile-copy{order:1;width:100%;margin-top:16px}`);
    rules.push(`${s} .profile-3d-cover{order:2;display:block;width:100%;height:${scene.heroHeight}px;max-height:none;margin:18px 0 0;border-radius:${concrete ? 4 : 16}px;object-fit:cover}`);
    rules.push(`${s} .profile-3d-art{order:2;display:block;width:calc(100% + 2 * var(--pd-3d-side));height:${scene.heroHeight}px;margin:18px calc(-1 * var(--pd-3d-side)) 0;object-fit:contain;object-position:center;pointer-events:none;user-select:none}`);
  }
  if (template.id === 'dimensional-ceramic-tiles') rules.push(`${s} a{background-image:linear-gradient(180deg,#ffffff33,#ffffff00 60%)}`);
  if (template.id === 'dimensional-wood-blocks') {
    rules.push(`${s} .link-item[data-rhythm="1"],${s} .link-item[data-rhythm="3"]{margin-left:14px}`);
    rules.push(`${s} .link-item[data-rhythm="0"],${s} .link-item[data-rhythm="2"]{margin-right:14px}`);
  }
  rules.push(`@media(max-width:400px){${s} main{--pd-3d-side:16px;width:calc(100% - 24px)}${s} .profile-header h1{font-size:26px}${s} a{padding:14px 12px;gap:10px}}`);
  return rules.join('\n');
};
