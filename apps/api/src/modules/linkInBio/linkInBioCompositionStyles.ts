import type { LinkInBioAppearance } from './linkInBioAppearance.js';
import { getProfileTemplate } from './profileTemplateCatalog.generated.js';

// The catalog chooses a composition; the owner still controls every color,
// font, image and destination. All artwork here is a fixed same-origin asset.
export const linkInBioColorContrast = (foreground: string, background: string) => {
  const luminance = (color: string) => {
    const [red, green, blue] = [1, 3, 5].map((offset) => {
      const value = Number.parseInt(color.slice(offset, offset + 2), 16) / 255;
      return value <= .04045 ? value / 12.92 : ((value + .055) / 1.055) ** 2.4;
    });
    return red! * .2126 + green! * .7152 + blue! * .0722;
  };
  const first = luminance(foreground);
  const second = luminance(background);
  return (Math.max(first, second) + .05) / (Math.min(first, second) + .05);
};

export const hasCustomProfileTemplateBackground = (appearance: LinkInBioAppearance) => {
  const template = getProfileTemplate(appearance.templateId);
  return Boolean(template && (appearance.background.imageKey || appearance.background.mode !== (template.effects.background ? 'gradient' : 'solid') || appearance.background.color !== template.palette.background || appearance.background.gradientColor !== template.palette.gradient));
};

export const isDefaultPortraitSecondaryLink = (appearance: LinkInBioAppearance, customButton: string | undefined, customText: boolean, position: number) => {
  const template = getProfileTemplate(appearance.templateId);
  return Boolean(template?.layout.composition === 'portrait' && position > 0 && !customButton && !customText && appearance.buttonColor === template.palette.button && appearance.buttonStyle.color === template.palette.buttonText);
};

export const profileTemplateLinkFill = (appearance: LinkInBioAppearance, text: string, customButton: string | undefined, customText: boolean, rhythm: number, position = 0) => {
  if (customButton) return customButton;
  const template = getProfileTemplate(appearance.templateId);
  if (!template) return appearance.buttonColor;
  if (isDefaultPortraitSecondaryLink(appearance, customButton, customText, position)) return appearance.surfaceColor;
  // Existing published snapshots can have white text from an earlier filled
  // preset. Keep their fill rather than turning their text invisible.
  if (template.layout.button === 'outline') {
    const openPage = ['editorial', 'botanical', 'gallery', 'rail'].includes(template.layout.composition);
    const legible = linkInBioColorContrast(text, appearance.surfaceColor) >= 4.5 && (!openPage || linkInBioColorContrast(text, appearance.background.color) >= 4.5);
    return legible ? 'transparent' : appearance.buttonColor;
  }
  if (template.layout.composition === 'glass' && !customText && appearance.buttonColor === template.palette.button && appearance.buttonStyle.color === template.palette.buttonText) return `${appearance.buttonColor}eb`;
  if (!customText && ['poster', 'window', 'collage', 'window-grid'].includes(template.layout.composition) && appearance.buttonColor === template.palette.button && appearance.buttonStyle.color === template.palette.buttonText) {
    const colors = template.layout.composition === 'window' ? [appearance.buttonColor, '#fff9e6', '#d2bfff', '#bcf0bd'] : template.layout.composition === 'window-grid' ? [appearance.buttonColor, appearance.background.color, appearance.surfaceColor, '#f8d4e1'] : [appearance.buttonColor, '#bcf0bd', '#d2bfff', '#fff9e6'];
    const color = colors[rhythm]!;
    return linkInBioColorContrast(text, color) >= 4.5 ? color : appearance.buttonColor;
  }
  return appearance.buttonColor;
};

export const linkInBioCompositionStyles = (appearance: LinkInBioAppearance) => {
  const template = getProfileTemplate(appearance.templateId);
  if (!template) return '';
  const composition = template.layout.composition;
  const s = `body[data-template][data-composition="${composition}"]`;
  const customBackground = hasCustomProfileTemplateBackground(appearance);
  const rules = (entries: [string, string][]) => entries.map(([selector, declaration]) => `${s}${selector}{${declaration}}`).join('\n');
  const panel = appearance.surfaceColor;
  const ink = appearance.nameStyle.color;
  const accent = appearance.buttonColor;
  const line = appearance.categoryStyle.color;
  const wash = appearance.background.gradientColor;
  const base = appearance.background.color;
  const openPanel = appearance.surfaceColor === template.palette.surface && appearance.background.mode !== 'image' ? 'transparent' : panel;
  const openGlassPanel = !customBackground && openPanel === 'transparent';
  const openGlassCopy = openGlassPanel && [appearance.nameStyle.color, appearance.descriptionStyle.color, appearance.brandStyle.color].every((color) => linkInBioColorContrast(color, '#182a16') >= 4.5);
  const radius = appearance.buttonRadius === 'pill' ? '999px' : appearance.buttonRadius === 'square' ? '4px' : '16px';
  const avatarRadius = (size: number) => template.layout.avatar === 'circle' ? '50%' : template.layout.avatar === 'rounded' ? `${Number((size * .22).toFixed(2))}px` : '3px';
  const sideHeader: [string, string][] = [
    [' .profile-header', 'display:grid;grid-template-columns:78px minmax(0,1fr);gap:18px;align-items:center;text-align:left'],
    [' .profile-copy', 'grid-column:2;min-width:0'],
    [' .logo', `grid-column:1;grid-row:1;width:78px;height:130px;margin:0;border-radius:44px 44px 4px 4px;background:${accent};color:${appearance.buttonStyle.color}`],
    [' .profile-header h1', 'margin:0 0 8px;font-size:28px']
  ];
  const grid: [string, string][] = [
    [' ul', 'grid-template-columns:repeat(2,minmax(0,1fr));gap:14px'],
    [' .category', 'grid-column:1/-1'],
    [' a', 'height:100%;min-height:112px;flex-direction:column;align-items:flex-start;gap:12px;padding:16px 14px 38px'],
    [' .link-copy', 'width:100%;padding-right:0'],
    [' .arrow', 'position:absolute;right:12px;bottom:14px']
  ];
  const mixed: [string, string][] = [
    ...grid,
    [' .link-item[data-rhythm="0"], ' + s + ' .link-item[data-rhythm="3"]', 'grid-column:1/-1'],
    [' .link-item[data-rhythm="0"] a, ' + s + ' .link-item[data-rhythm="3"] a', 'min-height:72px;flex-direction:row;align-items:center;padding-bottom:14px'],
    [' .link-item[data-rhythm="0"] .arrow, ' + s + ' .link-item[data-rhythm="3"] .arrow', 'position:static'],
    [' .link-item[data-rhythm="0"] .link-copy, ' + s + ' .link-item[data-rhythm="3"] .link-copy', 'padding-right:0']
  ];
  let styles: [string, string][] = [];
  switch (composition) {
    case 'editorial': styles = [
      [' main', `border-radius:0;padding-top:44px;background:${openPanel}`],
      [' .profile-header', 'display:block;text-align:left;border:0;padding-bottom:0'],
      [' .logo', 'width:48px;height:48px;margin:0 0 20px;border-radius:0'],
      [' .logo.avatar-initial', 'display:none'],
      [' .profile-header h1', `font-size:clamp(48px,14vw,56px);line-height:1.15;letter-spacing:-1px;margin:0 0 14px;padding-bottom:20px;border-bottom:1px solid ${line}55`],
      [' ul', 'gap:0'], [' a', `border-radius:0;border:0;border-bottom:1px solid ${line}55;min-height:84px;padding:16px 0;gap:12px`],
      [' .link-number', `display:block;min-width:28px;font-size:13px;padding-right:10px;border-right:1px solid ${line}55`],
      [' footer', `border-top:1px solid ${line}55;margin-top:32px;padding-top:24px`]
    ]; break;
    case 'bicolor': styles = [
      [' main', 'border-radius:0;padding-top:0'],
      [' .profile-header', `margin:-0px -20px 28px;padding:40px 20px 28px;background:${wash}`],
      [' .logo', `border:1px solid ${line};outline:1px solid ${line};outline-offset:6px;margin-bottom:26px`],
      [' .profile-header h1', `border:3px double ${line};padding:12px 6px;font-size:24px;letter-spacing:4px`],
      ...grid, [' a', `border:1px solid ${line};border-radius:${radius};min-height:136px`],
      [' footer', `border-top:1px solid ${line}55;margin-top:32px;padding-top:24px`]
    ]; break;
    case 'portrait': styles = [
      [' main', 'border-radius:0;padding-top:44px'], ...sideHeader,
      [' .profile-header', `display:grid;grid-template-columns:78px minmax(0,1fr);gap:18px;align-items:center;text-align:left;padding-bottom:28px;border-bottom:1px solid ${line}55`],
      [' ul', 'gap:12px'], [' a', 'min-height:76px'],
      [' .link-item[data-position="1"] a', `border-left:6px solid ${line}`],
      [' .link-item:not([data-position="1"]) a:not(.custom-button)', `box-shadow:inset 4px 0 ${wash}`]
    ]; break;
    case 'scallop': styles = [
      [' main', `border:1px dashed ${line}88;border-radius:20px;padding:48px 24px 28px;outline:8px solid ${panel};outline-offset:3px`],
      [' main::before', 'display:block;content:"";position:absolute;inset:0;background:url("/profile-decorations/letter-frame.png") center/100% 100% no-repeat;opacity:.8;pointer-events:none'],
      [' .profile-header', 'display:block;text-align:center;padding:12px 0 24px'],
      [' .logo', `width:84px;height:84px;border:3px double ${line};outline:5px solid ${wash};outline-offset:3px`],
      [' .profile-header h1', 'font-size:28px'], [' ul', 'gap:0'],
      [' a', `min-height:80px;border:0;border-radius:0;border-bottom:1px solid ${line}66;padding-left:8px;padding-right:8px`]
    ]; break;
    case 'collage': styles = [
      [' main', `border-radius:0;padding-top:56px;background:${openPanel}`],
      [' .profile-header', 'display:grid;grid-template-columns:76px minmax(0,1fr);gap:20px;align-items:center;text-align:left;margin-bottom:36px'],
      [' .profile-copy', 'grid-column:2;min-width:0'],
      [' .logo', `grid-column:1;grid-row:1;width:76px;height:92px;margin:0;background:${wash};border:6px solid ${panel};border-bottom-width:18px;border-radius:0;transform:rotate(-6deg);box-shadow:2px 3px 8px #00000018`],
      [' .profile-header::before', 'content:"";position:absolute;z-index:3;left:8px;top:-22px;width:82px;height:40px;background:url("/profile-decorations/collage-tape.png") center/contain no-repeat;pointer-events:none'],
      [' .profile-header h1', `font-size:32px;margin:0 0 10px;border-bottom:6px solid ${wash}`],
      ...mixed, [' a', `border:1px solid ${line}66;border-radius:${radius};box-shadow:3px 4px 0 ${line}35`],
      [' .link-item[data-rhythm="1"]', 'transform:rotate(-2deg)'], [' .link-item[data-rhythm="2"]', 'transform:rotate(2deg)']
    ]; break;
    case 'window': styles = [
      ...(!customBackground ? [['', `background-color:${base};background-image:linear-gradient(90deg,#ffffff77 50%,transparent 50%),linear-gradient(#ffffff77 50%,transparent 50%);background-size:24px 24px;background-attachment:fixed`], [' .background-motion', 'display:none']] as [string, string][] : []),
      [' main', `padding-top:64px;border:1px solid ${line};border-radius:14px;box-shadow:4px 5px 0 ${line}33;background:${panel}`],
      [' main::before', `content:"";display:block;position:absolute;inset:0 0 auto;height:36px;background:${wash};border-bottom:1px solid ${line};pointer-events:none`],
      [' main::after', 'content:"";display:block;position:absolute;left:14px;top:12px;width:12px;height:12px;border:0;background:#f997ac;border-radius:50%;box-shadow:19px 0 0 #f8d779,38px 0 0 #96c6a0;pointer-events:none'],
      ...sideHeader, [' .logo', `width:48px;height:48px;border-radius:${avatarRadius(48)};margin:0;background:${wash};color:${ink}`],
      [' .profile-header', 'display:grid;grid-template-columns:48px minmax(0,1fr);gap:16px;align-items:center;text-align:left'],
      [' .profile-header h1', 'font-size:30px'],
      [' a', `min-height:78px;border:1px solid ${line}55;box-shadow:none`],
      [' .platform-icon', `border:1px solid ${line}55;border-radius:50%`]
    ]; break;
    case 'botanical': styles = [
      [' main', `border-radius:0;background:${openPanel};padding:60px 28px 40px`],
      [' main::before', 'content:"";display:block;position:absolute;inset:0;background:url("/profile-decorations/botanical-frame.png") center/100% 100% no-repeat;pointer-events:none;opacity:.9'],
      [' .profile-header', 'display:block;text-align:center;padding:0 0 28px'],
      [' .logo', `width:88px;height:88px;border:1px solid ${line};outline:5px solid ${wash};outline-offset:4px`],
      [' .profile-header h1', 'font-size:28px'],
      [' ul', 'gap:0'], [' a', `border:0;border-radius:0;border-bottom:1px solid ${line}77;min-height:80px;padding-left:4px;padding-right:4px`],
      [' .arrow', `border-radius:50%;background:${wash};padding:4px`]
    ]; break;
    case 'glass': styles = [
      ...(customBackground ? [] : [['', 'background-image:url("/profile-decorations/forest.png");background-position:center;background-size:cover;background-attachment:fixed'], [' .background-motion', 'display:none']] as [string, string][]),
      [' main', `background:${openGlassPanel ? 'transparent' : panel};border-radius:0;padding-top:76px;min-height:calc(100svh - 32px)`],
      ...sideHeader, [' .logo', `width:36px;height:36px;border-radius:50%;background:${openGlassCopy ? appearance.buttonColor : panel};color:${openGlassCopy ? appearance.buttonStyle.color : ink};margin:0`],
      [' .profile-header', `display:grid;grid-template-columns:36px minmax(0,1fr);gap:16px;align-items:center;text-align:left;padding:18px 14px;border-radius:14px;background:${openGlassCopy ? 'transparent' : panel + 'e6'};${openGlassCopy ? '' : 'backdrop-filter:blur(12px)'}`],
      [' .profile-header h1', 'font-size:30px'],
      ...mixed, [' a', `border:1px solid ${line}44;backdrop-filter:blur(14px);box-shadow:0 8px 22px #00000012`],
      [' footer', `background:${openGlassCopy ? 'transparent' : panel + 'e6'};border-radius:12px;padding:16px;margin-top:auto`]
    ]; break;
    case 'torn': styles = [
      [' main', 'border-radius:0;padding-top:32px;padding-bottom:20px'],
      [' .cover', 'height:160px;margin:-32px -20px 0'],
      [' .cover-fallback', customBackground ? `background:${wash}` : 'background:url("/profile-decorations/meadow.png") center/cover no-repeat'],
      [' .profile-header', `display:block;text-align:left;margin-top:-68px;margin-bottom:20px;padding:0 0 18px;border-bottom:1px dashed ${line}88`],
      [' .profile-header::before', `content:"";position:absolute;z-index:-1;left:-20px;right:-20px;top:60px;height:32px;background:${panel};clip-path:polygon(0 48%,5% 30%,10% 45%,15% 20%,20% 40%,25% 24%,30% 50%,35% 28%,40% 45%,45% 22%,50% 40%,55% 30%,60% 50%,65% 23%,70% 38%,75% 27%,80% 45%,85% 30%,90% 43%,95% 24%,100% 45%,100% 100%,0 100%);pointer-events:none`],
      [' .logo', `width:84px;height:118px;border-radius:48px 48px 4px 4px;margin:0 auto 18px;border:5px solid ${panel};background:${wash};color:${ink}`],
      [' .profile-header h1', 'margin:0 0 10px;font-size:34px'],
      [' ul', 'gap:12px;padding-left:6px'],
      [' a', `border:1px solid ${line}33;border-radius:${radius};min-height:64px;padding:12px 14px;box-shadow:2px 3px 0 ${line}22`],
      [' footer', 'padding-top:28px'],
      [' a::before', `content:"";position:absolute;left:-5px;top:calc(50% - 4px);width:8px;height:8px;border-radius:50%;background:${panel};border:1px solid ${line}77;pointer-events:none`]
    ]; break;
    case 'seal': styles = [
      [' main', `border:1px solid ${line};border-radius:0;padding:54px 24px 32px`],
      [' .profile-header', 'display:block;text-align:center;padding-top:4px;margin-bottom:32px'],
      [' .profile-header::before', 'content:"";position:absolute;z-index:0;top:0;left:calc(50% - 50px);width:100px;height:100px;background:url("/profile-decorations/gold-seal.png") center/contain no-repeat;pointer-events:none'],
      [' .logo', `position:relative;z-index:1;width:52px;height:52px;margin:24px auto 40px;border:0;background:transparent;color:${ink};border-radius:50%`],
      [' .profile-header h1', 'font-size:40px;line-height:1.2;margin:0 0 16px'],
      [' ul', 'gap:0'], [' a', `min-height:84px;border:0;border-radius:0;border-bottom:1px solid ${line}88;padding:16px 4px`]
    ]; break;
    case 'tag': styles = [
      [' main', `margin-top:36px;border:3px double ${line};border-radius:0;padding-top:100px;clip-path:polygon(14% 0,86% 0,100% 48px,100% calc(100% - 32px),92% 100%,8% 100%,0 calc(100% - 32px),0 48px)`],
      [' main::before', 'content:"";display:block;position:absolute;z-index:2;top:-16px;left:calc(50% - 36px);width:72px;height:112px;background:url("/profile-decorations/tag-cord.png") top center/contain no-repeat;pointer-events:none'],
      [' .profile-header', 'display:block;text-align:center;margin-bottom:28px'],
      [' .logo', `width:40px;height:40px;margin:0 auto 16px;background:transparent;color:${ink};border-radius:0`],
      [' .profile-header h1', 'font-size:38px;margin:0 0 14px'],
      [' a', `min-height:76px;border-radius:${radius};box-shadow:1px 3px 8px #00000016`]
    ]; break;
    case 'gallery': styles = [
      [' main', `border-radius:0;background:${openPanel};padding-top:64px`], ...sideHeader,
      [' .logo', `width:48px;height:104px;border-radius:0;background:${line};color:${panel}`],
      [' .profile-header', `display:grid;grid-template-columns:48px minmax(0,1fr);gap:20px;align-items:center;text-align:left;border-bottom:1px solid ${line};padding-bottom:30px`],
      [' .profile-header h1', 'font-size:34px'],
      ...grid, [' a', `min-height:148px;border:1px solid ${line};border-radius:${radius}`]
    ]; break;
    case 'poster': styles = [
      [' main', `border-radius:0;padding-top:40px;background:${openPanel}`],
      [' .profile-header', 'display:block;text-align:left;padding-top:32px'], [' .logo', `position:absolute;top:0;right:0;width:28px;height:28px;border:2px solid ${ink};border-radius:4px;margin:0`],
      [' .profile-header h1', 'font-size:48px;line-height:1.05;letter-spacing:-1px;margin:0 0 18px;font-weight:600'],
      [' ul', 'gap:18px;padding-right:5px;padding-bottom:5px'],
      [' a', `min-height:88px;border:3px solid ${ink};box-shadow:5px 5px 0 ${ink};border-radius:${radius};font-size:18px`],
      [' .arrow svg', 'width:26px;height:26px'],
      [' main::after', `content:"";display:block;position:absolute;right:16px;bottom:18px;width:38px;height:38px;background:${wash};clip-path:polygon(50% 0,62% 36%,100% 50%,62% 63%,50% 100%,37% 63%,0 50%,37% 36%);pointer-events:none`]
    ]; break;
    case 'window-grid': styles = [
      [' main', `border:3px solid ${ink};border-radius:16px;padding-top:68px;box-shadow:inset 0 0 0 10px ${wash},5px 5px 0 ${ink}`],
      [' main::before', `content:"";display:block;position:absolute;inset:0 0 auto;height:38px;border-bottom:3px solid ${ink};background:${wash};pointer-events:none`],
      [' main::after', `content:"";display:block;position:absolute;left:14px;top:10px;width:16px;height:16px;border:2px solid ${ink};border-radius:50%;background:${accent};box-shadow:24px 0 0 ${ink},48px 0 0 ${ink};pointer-events:none`],
      ...sideHeader, [' .logo', `width:44px;height:44px;border:2px solid ${ink};border-radius:4px;background:${panel};color:${ink}`],
      [' .profile-header', `display:grid;grid-template-columns:44px minmax(0,1fr);gap:12px;align-items:center;text-align:left;border:2px solid ${ink};border-radius:4px;background:${base};margin:-28px -8px 28px;padding:20px 8px 24px`],
      [' .profile-header h1', 'font-size:30px'], ...grid,
      [' a', `border:2px solid ${ink};border-radius:${radius};box-shadow:3px 4px 0 ${ink};min-height:140px`]
    ]; break;
    case 'ticket': styles = [
      [' main', `border:2px solid ${ink};border-radius:0;padding-top:36px;background:${panel}`],
      [' main::before', `content:"";display:block;position:absolute;left:-12px;top:220px;width:24px;height:24px;border:2px solid ${ink};border-radius:50%;background:${base};pointer-events:none`],
      [' main::after', `content:"";display:block;position:absolute;right:-12px;top:220px;width:24px;height:24px;border:2px solid ${ink};border-radius:50%;background:${base};pointer-events:none`],
      [' .profile-header', `display:flex;flex-direction:column;text-align:center;border-bottom:2px dashed ${line};padding-bottom:24px`],
      [' .logo', `order:2;width:32px;height:32px;border:2px solid ${ink};border-radius:4px;margin:18px auto 0`],
      [' .profile-copy', 'order:1'], [' .profile-header h1', 'font-size:42px;line-height:1.2;margin:0 0 12px'],
      [' ul', `gap:12px;padding-left:0;border-left:1px dashed ${line}66`],
      [' a', `min-height:80px;border:0;border-radius:${radius};box-shadow:none`],
      [' .link-number', `display:block;min-width:28px;text-align:center;font-size:14px;border-right:1px dashed ${line}77;padding-right:8px`]
    ]; break;
    case 'rail': styles = [
      [' main', `border-radius:0;background:${openPanel};padding-top:44px`],
      [' .profile-header', `display:grid;grid-template-columns:52px minmax(0,1fr);column-gap:16px;align-items:start;text-align:left;padding:0 0 28px;border-bottom:1px solid ${line}66`],
      [' .logo', `grid-column:1;grid-row:1;width:52px;height:52px;margin:0;border-radius:${avatarRadius(52)};border:1px solid ${line}66`],
      [' .profile-copy', 'grid-column:2;grid-row:1;min-width:0'], [' .profile-header h1', 'font-size:30px;margin:0 0 8px'],
      [' ul', `gap:12px;padding-left:18px;border-left:2px solid ${line}55`],
      [' a', `min-height:76px;border:1px solid ${line}66`],
      [' a::before', `content:"";position:absolute;width:10px;height:10px;border:2px solid ${line};background:${panel};border-radius:50%;left:-25px;top:calc(50% - 5px);pointer-events:none`],
      [' a.rail-outline', `min-height:64px;padding:12px 16px;border:0;border-bottom:1px solid ${line}73;border-radius:0;box-shadow:none`],
      [' a.rail-outline::before', 'content:none'],
      [' .link-number', 'display:block;min-width:24px;font-size:12px']
    ]; break;
    case 'ribbon': styles = [
      [' main', `border-radius:0;padding-top:44px;background:${openPanel}`], [' .profile-header', 'display:block;text-align:center'],
      [' .logo', `width:60px;height:60px;margin:0 auto 16px;border-radius:${avatarRadius(60)};border:1px solid ${line}66`],
      [' .profile-copy', `display:inline-block;max-width:100%;padding:12px 18px;background:${line}1f`],
      [' .profile-header h1', 'font-size:32px;margin:0 0 8px'],
      [' ul', 'gap:12px;padding:0'], [' a', `min-height:64px;border-radius:${radius};border:1px solid ${line}33;box-shadow:none;padding:12px 16px`],
      [' .link-item[data-rhythm="1"], ' + s + ' .link-item[data-rhythm="3"]', 'margin-left:18px;margin-right:0'],
      [' .link-item[data-rhythm="0"], ' + s + ' .link-item[data-rhythm="2"]', 'margin-left:0;margin-right:18px']
    ]; break;
    case 'notebook': styles = [
      [' main', `border:1px solid ${line}44;border-radius:0;padding-left:38px;background-color:${panel};background-image:repeating-linear-gradient(transparent 0 31px,${line}14 31px 32px)`],
      [' main::before', `content:"";display:block;position:absolute;top:0;bottom:0;left:25px;width:1px;background:${line}77;pointer-events:none`],
      [' main::after', `content:"";display:block;position:absolute;left:8px;top:22px;bottom:16px;width:10px;background:radial-gradient(circle,${base} 0 4px,${line}66 4px 5px,transparent 5px) 0 0/10px 32px;pointer-events:none`],
      [' .profile-header', `display:grid;grid-template-columns:minmax(0,1fr) 48px;gap:12px;align-items:start;text-align:left;padding:12px 0 28px;border-bottom:1px solid ${line}66`],
      [' .logo', `grid-column:2;grid-row:1;width:48px;height:48px;margin:0;border-radius:${avatarRadius(48)};transform:none;border:1px solid ${line}66`],
      [' .profile-copy', 'grid-column:1;grid-row:1;min-width:0'],
      [' .profile-header h1', 'font-size:32px;margin:0 0 8px'], [' ul', 'gap:8px'],
      [' a', `min-height:80px;border:0;border-radius:0;border-bottom:1px solid ${line}55;padding-left:0;padding-right:0;gap:8px`],
      [' .link-number', 'display:block;min-width:22px;font-size:12px']
    ]; break;
    case 'arch': styles = [
      [' main', 'padding-top:40px;border-radius:0'],
      [' .profile-header', 'display:block;text-align:center;border:0;border-radius:0;background:transparent;padding:0'],
      [' .arch-hero', `position:relative;display:flex;align-items:flex-end;justify-content:center;width:156px;height:172px;margin:0 auto 18px;padding-bottom:16px;border-radius:78px 78px 0 0;overflow:hidden;background:linear-gradient(135deg,${wash},${line}33)`],
      [' .arch-hero .cover', 'position:absolute;inset:0;width:100%;height:100%;max-height:none;margin:0;border-radius:0'],
      [' .arch-hero .logo', `position:relative;z-index:1;width:76px;height:76px;border-radius:${avatarRadius(76)};border:1px solid ${line}66;margin:0;background:${wash};color:${ink}`],
      [' .profile-header h1', 'font-size:30px;margin:0 0 8px'], [' ul', 'gap:12px'], [' a', `min-height:64px;padding:12px 16px;border:1px solid ${line}44`]
    ]; break;
    case 'staircase': styles = [
      [' main', `border-radius:0;padding-top:44px;background:${openPanel}`],
      [' .profile-header', 'display:grid;grid-template-columns:minmax(0,1fr) 44px;gap:12px;align-items:end;text-align:left'],
      [' .logo', `grid-column:2;grid-row:1;width:44px;height:44px;margin:0;border-radius:${avatarRadius(44)};border:1px solid ${line}66`],
      [' .profile-copy', 'grid-column:1;grid-row:1;min-width:0'], [' .profile-header h1', 'font-size:34px;margin:0 0 8px'],
      [' ul', 'gap:18px;padding-right:4px;padding-bottom:4px'], [' a', `min-height:82px;border:1px solid ${line};box-shadow:4px 4px 0 ${line}66`],
      [' .link-item[data-rhythm="0"], ' + s + ' .link-item[data-rhythm="2"]', 'margin-right:20px'],
      [' .link-item[data-rhythm="1"], ' + s + ' .link-item[data-rhythm="3"]', 'margin-left:20px']
    ]; break;
  }
  const paper = !customBackground && ['collage', 'torn', 'tag', 'notebook'].includes(composition) ? rules([
    ['', 'background-image:url("/profile-decorations/paper.png");background-size:360px auto;background-repeat:repeat;background-attachment:fixed;background-blend-mode:multiply'],
    ...(appearance.surfaceColor === template.palette.surface ? [[' main', 'background-image:url("/profile-decorations/paper.png");background-size:360px auto;background-repeat:repeat;background-blend-mode:multiply']] as [string, string][] : []),
    [' .background-motion', 'display:none']
  ]) : '';
  const initialFont = { editorial: 24, bicolor: 36, portrait: 36, scallop: 32, collage: 32, window: 24, botanical: 36, glass: 18, torn: 36, seal: 26, tag: 22, gallery: 26, poster: 16, 'window-grid': 22, ticket: 18, rail: 26, ribbon: 28, notebook: 24, arch: 32, staircase: 22 }[composition];
  return `${rules([
    ['', 'display:flow-root'],
    [' main', 'padding:32px 20px 28px;min-height:calc(100svh - 32px)'],
    [' main::before, ' + s + ' main::after', 'display:none'],
    [' .profile-header', 'display:block;border:0;padding:0;margin:0 0 28px;text-align:center'],
    [' .profile-copy', 'min-width:0'],
    [' .profile-header h1', 'font-size:32px;grid-column:auto;margin:16px 0 12px;line-height:1.3'],
    [' .description', 'grid-column:auto;font-size:15px;margin:0;line-height:1.7'],
    [' .logo', `width:88px;height:88px;margin:0 auto 22px;grid-column:auto;grid-row:auto;border:0;outline:0;border-radius:50%;background:${wash};color:${ink};box-shadow:none`],
    [' img.logo', 'object-fit:contain;object-position:center'],
    [' .logo.avatar-initial', 'display:grid;place-items:center;line-height:1'],
    [' .cover', 'height:160px;margin:-32px -20px 28px'],
    [' ul', 'grid-template-columns:minmax(0,1fr);gap:12px;padding:0'],
    [' .category', 'grid-column:1/-1;margin:12px 0 0'],
    [' a', `min-height:72px;height:auto;flex-direction:row;align-items:center;padding:14px 16px;gap:12px;box-shadow:none;border:1px solid transparent;border-radius:${radius}`],
    [' .link-copy', 'width:auto;padding-right:0;min-width:0;overflow-wrap:anywhere'],
    [' .arrow', 'position:static'], [' .link-number', 'display:none;flex-shrink:0'],
    [' .platform-icon', 'width:40px;height:40px;flex-shrink:0'],
    [' footer', 'margin-top:auto;padding-top:48px']
  ])}\n${rules(styles)}\n${['editorial', 'scallop', 'botanical', 'seal', 'rail', 'notebook'].includes(composition) ? rules([[' a.filled-button', `border-radius:${radius}`]]) : ''}\n${paper}\n${rules([[' .logo.avatar-initial', `font-size:${initialFont}px`]])}
@media(max-width:340px){${s} main{width:calc(100% - 24px)}${s} a{gap:8px}${s} .profile-header h1{overflow-wrap:anywhere}${s} .link-copy{font-size:14px}}
@media(prefers-reduced-motion:reduce){${s} .link-item{transform:none}${s} .logo{transform:none}}
`;
};
