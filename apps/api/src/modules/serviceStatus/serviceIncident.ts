import { AdminError } from '../admin/trialAccess.js';

// Customer-facing service notices that administrators publish during an
// outage. They are broadcast to every app user, so they never carry member data.
export const serviceIncidentStages = ['INVESTIGATING', 'IDENTIFIED', 'MONITORING', 'RESOLVED'] as const;
export type ServiceIncidentStage = typeof serviceIncidentStages[number];
export const serviceIncidentPlatforms = ['TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS', 'FACEBOOK_REELS'] as const;
export type ServiceIncidentPlatform = typeof serviceIncidentPlatforms[number];
export const maxActiveServiceIncidents = 5;

export type ServiceIncidentDraft = { title: string; message: string;
  platforms: ServiceIncidentPlatform[]; stage: ServiceIncidentStage };
export type ServiceIncident = ServiceIncidentDraft & { id: string; version: number; createdBy: string;
  updatedBy: string; startedAt: string; updatedAt: string; resolvedAt: string | null };
export type CreateServiceIncident = { id: string; actorId: string; draft: ServiceIncidentDraft };
export type UpdateServiceIncident = CreateServiceIncident & { expectedVersion: number };
export type ServiceIncidentPage = { rows: ServiceIncident[]; nextCursor?: string };
export type ServiceIncidentStore = {
  active: () => Promise<ServiceIncident[]>;
  list: (options: { cursor?: string }) => Promise<ServiceIncidentPage>;
  create: (command: CreateServiceIncident) => Promise<ServiceIncident>;
  update: (command: UpdateServiceIncident) => Promise<ServiceIncident>;
};

const invalid = () => new AdminError('ADMIN_INCIDENT_INVALID', 400);
// Newlines are allowed in the message; other control characters are not.
const readText = (value: unknown, max: number, allowNewlines: boolean) => {
  if (typeof value !== 'string') throw invalid();
  const text = value.trim();
  const control = allowNewlines ? /[\x00-\x09\x0b-\x1f\x7f]/ : /[\x00-\x1f\x7f]/;
  if (text.length < 3 || text.length > max || control.test(text)) throw invalid();
  return text;
};
export const readServiceIncidentDraft = (body: Record<string, unknown>): ServiceIncidentDraft => {
  const platforms = body.platforms;
  if (!Array.isArray(platforms) || platforms.length > serviceIncidentPlatforms.length ||
      new Set(platforms).size !== platforms.length ||
      !platforms.every(p => serviceIncidentPlatforms.includes(p as ServiceIncidentPlatform)) ||
      !serviceIncidentStages.includes(body.stage as ServiceIncidentStage)) throw invalid();
  return { title: readText(body.title, 80, false), message: readText(body.message, 500, true),
    platforms: serviceIncidentPlatforms.filter(p => platforms.includes(p)), stage: body.stage as ServiceIncidentStage };
};
export const sameServiceIncidentDraft = (incident: ServiceIncidentDraft, draft: ServiceIncidentDraft) =>
  incident.title === draft.title && incident.message === draft.message && incident.stage === draft.stage &&
  incident.platforms.join() === draft.platforms.join();
// A retried create returns the incident it already made; a reused id with other content is a conflict.
export const replayServiceIncidentCreate = (existing: ServiceIncident, command: CreateServiceIncident) => {
  if (existing.createdBy !== command.actorId || existing.version !== 1 ||
      !sameServiceIncidentDraft(existing, command.draft)) throw new AdminError('ADMIN_REQUEST_CONFLICT');
  return existing;
};
export const assertServiceIncidentCreatable = (command: CreateServiceIncident, activeCount: number) => {
  if (command.draft.stage === 'RESOLVED') throw invalid();
  if (activeCount >= maxActiveServiceIncidents) throw new AdminError('ADMIN_INCIDENT_LIMIT');
};
// Returns the stored incident when this exact update already landed (a retry
// after a lost response); otherwise throws why the update cannot apply.
export const checkServiceIncidentUpdate = (current: ServiceIncident | null, command: UpdateServiceIncident) => {
  if (!current) throw new AdminError('ADMIN_INCIDENT_NOT_FOUND', 404);
  if (current.version === command.expectedVersion + 1 && current.updatedBy === command.actorId &&
      sameServiceIncidentDraft(current, command.draft)) return current;
  if (current.resolvedAt) throw new AdminError('ADMIN_INCIDENT_RESOLVED');
  if (current.version !== command.expectedVersion) throw new AdminError('ADMIN_INCIDENT_CHANGED');
  return null;
};
export const readServiceIncidentCursor = (cursor?: string): { time: Date; id: string } | undefined => {
  if (!cursor) return;
  try {
    const [time, id] = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8')) as unknown[];
    if (typeof time !== 'string' || typeof id !== 'string' || !id || id.length > 64 || new Date(time).toISOString() !== time) throw new Error();
    return { time: new Date(time), id };
  } catch { throw new AdminError('ADMIN_FILTER_INVALID', 400); }
};
export const serviceIncidentCursor = (incident: ServiceIncident) =>
  Buffer.from(JSON.stringify([incident.startedAt, incident.id])).toString('base64url');
export const serviceIncidentPageSize = 50;

export const createMemoryServiceIncidentStore = ({ now = () => new Date() }: { now?: () => Date } = {}): ServiceIncidentStore => {
  const rows = new Map<string, ServiceIncident>();
  const newestFirst = (a: ServiceIncident, b: ServiceIncident) =>
    b.startedAt.localeCompare(a.startedAt) || b.id.localeCompare(a.id);
  const active = () => [...rows.values()].filter(r => !r.resolvedAt).sort(newestFirst);
  return {
    active: async () => structuredClone(active()),
    list: async ({ cursor }) => {
      const after = readServiceIncidentCursor(cursor);
      const sorted = [...rows.values()].sort(newestFirst).filter(r => !after ||
        r.startedAt < after.time.toISOString() || (r.startedAt === after.time.toISOString() && r.id < after.id));
      const page = sorted.slice(0, serviceIncidentPageSize);
      return structuredClone({ rows: page,
        ...(sorted.length > serviceIncidentPageSize ? { nextCursor: serviceIncidentCursor(page.at(-1)!) } : {}) });
    },
    create: async command => {
      const existing = rows.get(command.id);
      if (existing) return structuredClone(replayServiceIncidentCreate(existing, command));
      assertServiceIncidentCreatable(command, active().length);
      const time = now().toISOString();
      const incident: ServiceIncident = { ...command.draft, id: command.id, version: 1, createdBy: command.actorId,
        updatedBy: command.actorId, startedAt: time, updatedAt: time, resolvedAt: null };
      rows.set(command.id, incident);
      return structuredClone(incident);
    },
    update: async command => {
      const current = rows.get(command.id) ?? null;
      const replay = checkServiceIncidentUpdate(current, command);
      if (replay) return structuredClone(replay);
      const time = now().toISOString();
      const incident: ServiceIncident = { ...current!, ...command.draft, version: current!.version + 1,
        updatedBy: command.actorId, updatedAt: time, resolvedAt: command.draft.stage === 'RESOLVED' ? time : null };
      rows.set(command.id, incident);
      return structuredClone(incident);
    }
  };
};
