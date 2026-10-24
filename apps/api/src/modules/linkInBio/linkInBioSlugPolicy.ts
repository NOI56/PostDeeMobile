// A slug released by a rename or account deletion stays unavailable to other
// owners for this long, so visitors following an old link cannot land on an
// impersonator's page. The previous owner may take it back meanwhile.
export const linkInBioSlugReservationDays = 30;
export const linkInBioSlugReservationMs = linkInBioSlugReservationDays * 24 * 60 * 60 * 1000;

// Each owner keeps at most this many released slugs reserved (newest first),
// so renaming repeatedly cannot squat on many names.
export const maxLinkInBioSlugReservationsPerOwner = 3;

const reservedSlugs = new Set([
  'about', 'account', 'admin', 'administrator', 'api', 'app', 'billing', 'contact',
  'help', 'legal', 'login', 'logout', 'mail', 'moderator', 'null', 'official',
  'policy', 'privacy', 'register', 'root', 'security', 'settings', 'signin',
  'signup', 'staff', 'status', 'support', 'system', 'team', 'terms', 'undefined',
  'verify', 'www'
]);

// Names a new claim may never use. Any slug containing the brand is reserved.
// An owner who already holds such a slug keeps it.
export const isReservedLinkInBioSlug = (slug: string) =>
  reservedSlugs.has(slug) || slug.includes('postdee');
