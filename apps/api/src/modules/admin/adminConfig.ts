export type AdminConsoleConfig = {
  origin: string; environment: 'STAGING' | 'PRODUCTION' | 'LOCAL'; ownerUids: string[]; viewerUids: string[];
  firebaseWeb: { apiKey: string; authDomain: string; projectId: string; appId: string };
  costRates?: { captionRequestUsd: number; editMinuteUsd: number; postUnitUsd: number };
};
export const readAdminConsoleConfig = (env: Record<string, string | undefined>): AdminConsoleConfig | undefined => {
  if (env.ADMIN_CONSOLE_ENABLED !== 'true') return undefined;
  if (env.AUTH_PROVIDER !== 'firebase' || env.TRIAL_ACCESS_ENABLED !== 'true') {
    throw new Error('Admin console requires Firebase auth and TRIAL_ACCESS_ENABLED=true');
  }
  const origin = new URL(env.ADMIN_CONSOLE_ORIGIN ?? '');
  if (origin.username || origin.password || origin.pathname !== '/' || origin.search || origin.hash ||
      (origin.protocol !== 'https:' && !(env.NODE_ENV !== 'production' && ['localhost', '127.0.0.1'].includes(origin.hostname)))) {
    throw new Error('Admin console requires an exact HTTPS origin');
  }
  const ids = (value: string | undefined) => [...new Set((value ?? '').split(',').map(s => s.trim()).filter(Boolean))];
  const ownerUids = ids(env.ADMIN_OWNER_UIDS);
  const viewerUids = ids(env.ADMIN_VIEWER_UIDS);
  if (!ownerUids.length || [...ownerUids, ...viewerUids].some(s => s.length > 128 || /[\s\x00-\x1f]/.test(s))) {
    throw new Error('Admin console requires explicit valid owner Firebase UIDs');
  }
  const input = JSON.parse(env.ADMIN_FIREBASE_WEB_CONFIG ?? '{}') as Record<string, unknown>;
  if (!input || Array.isArray(input) || !['apiKey', 'authDomain', 'projectId', 'appId'].every(key => typeof input[key] === 'string' && input[key])) {
    throw new Error('Admin Firebase public web configuration is incomplete');
  }
  if (input.projectId !== env.FIREBASE_PROJECT_ID || !/^[a-z0-9.-]+$/.test(String(input.authDomain))) {
    throw new Error('Admin Firebase web project must match the API Firebase project');
  }
  const environment = env.ADMIN_ENVIRONMENT;
  if (!['STAGING', 'PRODUCTION', 'LOCAL'].includes(environment ?? '')) throw new Error('ADMIN_ENVIRONMENT is required');
  if (env.NODE_ENV === 'production' && environment === 'LOCAL') throw new Error('Production runtimes cannot use the LOCAL admin label');
  let costRates: AdminConsoleConfig['costRates'];
  if (env.ADMIN_COST_RATES_JSON) {
    const rates = JSON.parse(env.ADMIN_COST_RATES_JSON) as Record<string, unknown>;
    if (!rates || Array.isArray(rates) || !['captionRequestUsd', 'editMinuteUsd', 'postUnitUsd'].every(key =>
      typeof rates[key] === 'number' && Number.isFinite(rates[key]) && Number(rates[key]) >= 0 && Number(rates[key]) <= 1000)) {
      throw new Error('Admin cost rates must be finite non-negative USD unit estimates');
    }
    costRates = rates as AdminConsoleConfig['costRates'];
  }
  return { origin: origin.origin, environment: environment as AdminConsoleConfig['environment'], ownerUids, viewerUids,
    firebaseWeb: { apiKey: String(input.apiKey), authDomain: String(input.authDomain), projectId: String(input.projectId), appId: String(input.appId) }, costRates };
};
