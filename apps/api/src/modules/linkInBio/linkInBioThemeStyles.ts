import type { LinkInBioAppearance, LinkInBioEffects } from './linkInBioAppearance.js';

export const isDecoratedLinkInBioTheme = (theme: string) => ['pink', 'garden', 'cards'].includes(theme);

// Decorative vectors are fixed UI shapes, never user-provided markup or images.
export const renderLinkInBioDecorations = (kind: LinkInBioEffects['stickers']) => {
  if (kind === 'none') return '';
  const shape = kind === 'hearts'
    ? '<path fill="#ed9dbb" d="M20 35C-4 20 4 2 15 7l5 5 5-5C36 2 44 20 20 35Z"/>'
    : kind === 'sparkles'
      ? '<path fill="#b89bdb" d="m20 2 5 12 13 6-13 5-5 13-6-13L2 20l12-6Z"/>'
      : '<g fill="#f5dce6"><ellipse cx="20" cy="10" rx="7" ry="10"/><ellipse cx="20" cy="10" rx="7" ry="10" transform="rotate(72 20 20)"/><ellipse cx="20" cy="10" rx="7" ry="10" transform="rotate(144 20 20)"/><ellipse cx="20" cy="10" rx="7" ry="10" transform="rotate(216 20 20)"/><ellipse cx="20" cy="10" rx="7" ry="10" transform="rotate(288 20 20)"/></g><circle cx="20" cy="20" r="5" fill="#e9bd58"/>';
  return `<div class="decorations" data-stickers="${kind}" aria-hidden="true">${[0, 1, 2, 3].map((index) => `<span class="sticker sticker-${index}"><svg viewBox="0 0 40 40" focusable="false">${shape}</svg></span>`).join('')}</div>`;
};

export const linkInBioThemeStyles = (appearance: LinkInBioAppearance) => {
  const decorated = isDecoratedLinkInBioTheme(appearance.themeId);
  const radius = appearance.buttonRadius === 'pill' ? '999px' : appearance.buttonRadius === 'square' ? '4px' : appearance.themeId === 'cards' ? '18px' : '16px';
  return `
.profile-header{min-width:0}.link-cta{font-size:13px;margin-top:4px;color:#8b67b5}.avatar-initial{display:grid;place-items:center;color:${appearance.nameStyle.color};font-size:48px;font-weight:600;background:${appearance.background.gradientColor}}
.background-motion{position:fixed;inset:-2%;pointer-events:none;z-index:0;animation:pd-background 18s ease-in-out infinite}
.decorations{position:fixed;inset:0;pointer-events:none;z-index:2;overflow:hidden}.sticker{position:absolute;width:28px;height:28px;opacity:.68;animation:pd-float 9s ease-in-out infinite}.sticker svg{width:100%;height:100%}.sticker-0{top:5%;left:4%}.sticker-1{top:7%;right:4%;width:22px;animation-delay:-3s}.sticker-2{bottom:10%;left:5%;width:22px;animation-delay:-5s}.sticker-3{bottom:9%;right:4%;animation-delay:-7s}
.entrance{animation:pd-enter .5s ease-out both}.motion-featured{animation:pd-featured 5s ease-in-out infinite}.motion-control{display:inline-flex;align-items:center;justify-content:center;gap:6px;cursor:pointer;margin-top:16px;padding:8px 12px;border:1px solid currentColor;border-radius:999px;font-size:12px;line-height:1.4;color:${appearance.brandStyle.color};font-family:${appearance.brandStyle.font === 'prompt' ? 'Prompt' : appearance.brandStyle.font === 'system' ? 'system-ui' : 'Anuphan'},sans-serif}.motion-control svg{width:14px;height:14px}.when-paused{display:none}
#pause-motion{position:fixed;left:0;top:0;opacity:0;width:1px;height:1px}#pause-motion:focus-visible~main .motion-control{outline:3px solid #d5a22f;outline-offset:4px}#pause-motion:checked~.background-motion,#pause-motion:checked~.decorations .sticker,#pause-motion:checked~main .motion-featured{animation-play-state:paused}#pause-motion:checked~main .entrance{animation:none;opacity:1;transform:none}#pause-motion:checked~main .when-running{display:none}#pause-motion:checked~main .when-paused{display:inline}
@keyframes pd-background{0%,100%{transform:translate3d(-.7%,-.5%,0) scale(1.02)}50%{transform:translate3d(.7%,.5%,0) scale(1.04)}}
@keyframes pd-float{0%,100%{transform:translateY(0) rotate(-8deg)}50%{transform:translateY(-10px) rotate(8deg)}}
@keyframes pd-enter{from{opacity:0;transform:translateY(10px)}to{opacity:1;transform:translateY(0)}}
@keyframes pd-featured{0%,80%,100%{transform:translateY(0)}88%{transform:translateY(-3px)}94%{transform:translateY(0)}}
${decorated ? `main{width:min(100% - 32px,480px);min-height:calc(100svh - 32px);margin:16px auto;padding:52px 8px 20px;border:0;border-radius:24px;box-shadow:none;display:flex;flex-direction:column}.brand{display:none}.profile-header{text-align:center;padding:20px 8px 0}.logo{width:112px;height:112px;border-radius:50%;margin:0 auto 16px;border:2px solid ${appearance.buttonColor};outline:3px solid ${appearance.background.gradientColor};outline-offset:5px}.avatar-initial{font-size:48px}.profile-header h1{margin:16px 0 8px;font-size:30px}.description{font-size:15px;margin:0 0 30px}.category{margin:12px 0 0;font-size:15px}.cover{width:calc(100% + 16px);margin:-52px -8px 24px;max-height:200px}.featured-label{font-size:11px;line-height:1.4}a{padding:14px 16px;min-height:68px}.featured{box-shadow:inset 0 0 0 1px currentColor}footer{margin-top:auto;padding-top:72px}body[data-theme="garden"] .profile-header{border-bottom:1px solid #71885255;margin-bottom:20px}body[data-theme="garden"] a{border-radius:16px}body[data-theme="cards"] main{padding-top:24px}body[data-theme="cards"] a{min-height:100px;border:1px solid #8b67b526;border-radius:18px;box-shadow:0 5px 18px #8b67b514}body[data-theme="cards"] .cover{margin-top:-24px}body[data-theme="cards"] .featured-label{align-self:flex-start;border-radius:999px;background:#eee1ff;padding:4px 10px;margin-bottom:6px;color:#8053b0}
@media(max-width:400px){main{margin:16px auto;padding:52px 8px 20px}h1{font-size:30px}.cover{width:calc(100% + 16px);margin:-52px -8px 24px}a{padding:14px 16px}}` : ''}
${decorated ? `body[data-theme="${appearance.themeId}"] a{border-radius:${radius}}` : ''}
.arrow svg{display:block}
@media(prefers-reduced-motion:reduce){.background-motion,.sticker,.entrance,.motion-featured{animation:none!important;transform:none!important;opacity:1}.motion-control,#pause-motion{display:none}.decorations .sticker{opacity:.68}}
`;
};
