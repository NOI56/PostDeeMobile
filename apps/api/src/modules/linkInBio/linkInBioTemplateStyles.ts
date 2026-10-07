import type { LinkInBioAppearance } from './linkInBioAppearance.js';
import { getProfileTemplate } from './profileTemplateCatalog.generated.js';
import { linkInBioCompositionStyles } from './linkInBioCompositionStyles.js';

// Layout strings come from the generated catalog, never from request CSS.
// Custom colors and fonts still come from the validated appearance snapshot.
export const linkInBioTemplateStyles = (appearance: LinkInBioAppearance) => {
  const template = getProfileTemplate(appearance.templateId);
  if (!template) return '';
  const root = 'body[data-template]';
  const radius = appearance.buttonRadius === 'pill' ? '999px' : appearance.buttonRadius === 'square' ? '4px' : '16px';
  return `
${root} main{width:min(100% - 32px,520px);min-height:calc(100svh - 32px);margin:16px auto;padding:36px 20px 24px;border:0;border-radius:20px;background:${appearance.surfaceColor};box-shadow:none;display:flex;flex-direction:column;overflow:hidden}
${root} .profile-header{position:relative;z-index:1;display:block;min-width:0;text-align:center;padding:0;margin:0 0 28px;border:0}
${root} .profile-header h1{font-size:28px;line-height:1.4;margin:16px 0 8px}
${root} .description{font-size:15px;line-height:1.7;margin:0}
${root} .logo{width:88px;height:88px;object-fit:cover;display:block;margin:0 auto 16px;border:0;outline:0;border-radius:50%}
${root} .avatar-initial{display:grid;place-items:center;font-size:36px;background:${appearance.background.gradientColor}}
${root} .cover{display:block;width:calc(100% + 40px);height:140px;max-height:none;object-fit:cover;margin:-36px -20px 24px;border-radius:0}
${root} .cover-fallback{background:linear-gradient(135deg,${appearance.buttonColor},${appearance.background.gradientColor})}
${root} ul{position:relative;z-index:1;gap:12px}
${root} .link-item{min-width:0}
${root} .category{font-size:14px;margin:12px 0 0}
${root} a{position:relative;min-height:64px;padding:12px 16px;gap:12px;border:1px solid transparent;border-radius:${radius};box-shadow:none}
${root} .link-copy{line-height:1.5;gap:2px}
${root} .platform-icon{width:40px;height:40px}
${root} .featured-label{font-size:11px;align-self:auto;padding:0;margin:0;background:transparent;color:inherit;border-radius:0;line-height:1.4}
${root} .featured{outline:2px solid var(--pd-link-text);outline-offset:2px}
${root} footer{position:relative;z-index:1;margin-top:auto;padding-top:48px;font-size:12px}
${root}[data-header="left"] .profile-header{text-align:left}
${root}[data-header="left"] .logo{width:64px;height:64px;margin:0 0 16px}
${root}[data-header="split"] .profile-header{display:grid;grid-template-columns:64px minmax(0,1fr);column-gap:16px;align-items:center;text-align:left}
${root}[data-header="split"] .logo{grid-column:1;grid-row:1/3;width:64px;height:64px;margin:0}
${root}[data-header="split"] .profile-header h1{grid-column:2;margin:0 0 8px}
${root}[data-header="split"] .description{grid-column:2}
${root}[data-header="cover"] .profile-header{margin-top:-64px}
${root}[data-header="cover"] .logo{position:relative;box-shadow:0 0 0 5px ${appearance.surfaceColor}}
${root}[data-header="badge"] .profile-header{padding:24px 16px;border:1px solid ${appearance.buttonColor};border-radius:12px}
${root}[data-header="badge"] .logo{border:1px solid ${appearance.buttonColor};padding:4px}
${root}[data-avatar="rounded"] .logo{border-radius:20px}
${root}[data-avatar="square"] .logo{border-radius:4px}
${root}[data-links="grid"] ul{grid-template-columns:repeat(2,minmax(0,1fr))}
${root}[data-links="grid"] .category{grid-column:1/-1}
${root}[data-links="grid"] a{height:100%;min-height:112px;flex-direction:column;align-items:flex-start;padding:14px;gap:10px}
${root}[data-links="grid"] .link-copy{flex:1;width:100%;padding-right:12px}
${root}[data-links="grid"] .arrow{position:absolute;right:12px;bottom:14px}
${root}[data-button="outline"] a{border-color:var(--pd-link-button)}
${root}[data-button="outline"] a.custom-button{background:var(--pd-link-button)}
${root}[data-button="soft"] a{border-color:${appearance.background.gradientColor};box-shadow:0 3px 10px #00000008}
${root}[data-button="raised"] a{border:2px solid ${appearance.nameStyle.color};box-shadow:4px 4px 0 ${appearance.nameStyle.color}}
${root}[data-button="raised"] ul{gap:16px;padding-right:4px}
${root}[data-decoration="line"] .profile-header{border-bottom:1px solid ${appearance.buttonColor};padding-bottom:24px}
${root}[data-decoration="frame"] main{border:1px solid ${appearance.buttonColor}}
${root}[data-decoration="dots"] main::before{content:'';position:absolute;top:12px;right:12px;width:84px;height:64px;background:radial-gradient(circle,${appearance.buttonColor} 1.5px,transparent 2px) 0 0/12px 12px;opacity:.3;pointer-events:none}
${root}[data-decoration="stripe"] main::before,${root}[data-decoration="stripe"] main::after{content:'';position:absolute;width:72px;height:24px;background:repeating-linear-gradient(135deg,${appearance.nameStyle.color} 0 2px,transparent 2px 8px);opacity:.35;pointer-events:none}
${root}[data-decoration="stripe"] main::before{top:12px;right:-12px;transform:rotate(35deg)}
${root}[data-decoration="stripe"] main::after{bottom:12px;left:-12px;transform:rotate(35deg)}
@media(max-width:400px){${root} main{padding:32px 20px 24px;margin:16px auto}${root} .cover{margin:-32px -20px 24px}${root} .profile-header h1{font-size:26px}${root} a{padding:12px 14px}}
${linkInBioCompositionStyles(appearance)}
`;
};
