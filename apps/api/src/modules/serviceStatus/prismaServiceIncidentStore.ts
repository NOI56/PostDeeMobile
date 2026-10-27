import { Prisma, type PrismaClient } from '@prisma/client';
import { AdminError } from '../admin/trialAccess.js';
import {
  assertServiceIncidentCreatable, checkServiceIncidentUpdate, readServiceIncidentCursor, replayServiceIncidentCreate,
  serviceIncidentCursor, serviceIncidentPageSize,
  type ServiceIncident, type ServiceIncidentPlatform, type ServiceIncidentStage, type ServiceIncidentStore
} from './serviceIncident.js';

export type PrismaServiceIncidentClient = Pick<PrismaClient, 'serviceIncident' | '$transaction'>;
type Row = Prisma.ServiceIncidentGetPayload<object>;
const map = (r: Row): ServiceIncident => ({ id: r.id, title: r.title, message: r.message,
  platforms: r.platforms as ServiceIncidentPlatform[], stage: r.stage as ServiceIncidentStage, version: r.version,
  createdBy: r.createdBy, updatedBy: r.updatedBy, startedAt: r.startedAt.toISOString(),
  updatedAt: r.updatedAt.toISOString(), resolvedAt: r.resolvedAt?.toISOString() ?? null });
const newestFirst = [{ startedAt: 'desc' as const }, { id: 'desc' as const }];

export const createPrismaServiceIncidentStore = (prisma: PrismaServiceIncidentClient,
  now: () => Date = () => new Date()): ServiceIncidentStore => ({
  active: async () => (await prisma.serviceIncident.findMany({ where: { resolvedAt: null }, orderBy: newestFirst, take: 20 })).map(map),
  list: async ({ cursor }) => {
    const after = readServiceIncidentCursor(cursor);
    const rows = (await prisma.serviceIncident.findMany({ orderBy: newestFirst, take: serviceIncidentPageSize + 1,
      where: after ? { OR: [{ startedAt: { lt: after.time } }, { startedAt: after.time, id: { lt: after.id } }] } : {} })).map(map);
    const page = rows.slice(0, serviceIncidentPageSize);
    return { rows: page, ...(rows.length > serviceIncidentPageSize ? { nextCursor: serviceIncidentCursor(page.at(-1)!) } : {}) };
  },
  create: async command => {
    try {
      // Serializable keeps two owners from both slipping past the open-notice cap.
      return await prisma.$transaction(async tx => {
        const existing = await tx.serviceIncident.findUnique({ where: { id: command.id } });
        if (existing) return replayServiceIncidentCreate(map(existing), command);
        assertServiceIncidentCreatable(command, await tx.serviceIncident.count({ where: { resolvedAt: null } }));
        const time = now();
        return map(await tx.serviceIncident.create({ data: { ...command.draft, id: command.id, version: 1,
          createdBy: command.actorId, updatedBy: command.actorId, startedAt: time, updatedAt: time } }));
      }, { isolationLevel: 'Serializable', maxWait: 5000, timeout: 10000 });
    } catch (error) {
      if (error instanceof AdminError) throw error;
      // A concurrent submit of the same id (P2002) or a serialization retry (P2034).
      if (error instanceof Prisma.PrismaClientKnownRequestError && ['P2002', 'P2034'].includes(error.code)) {
        const existing = await prisma.serviceIncident.findUnique({ where: { id: command.id } });
        if (existing) return replayServiceIncidentCreate(map(existing), command);
      }
      throw error;
    }
  },
  update: async command => {
    const time = now();
    const { count } = await prisma.serviceIncident.updateMany({
      where: { id: command.id, version: command.expectedVersion, resolvedAt: null },
      data: { ...command.draft, version: command.expectedVersion + 1, updatedBy: command.actorId, updatedAt: time,
        resolvedAt: command.draft.stage === 'RESOLVED' ? time : null } });
    const row = await prisma.serviceIncident.findUnique({ where: { id: command.id } });
    if (count === 1 && row) return map(row);
    const replay = checkServiceIncidentUpdate(row ? map(row) : null, command);
    if (replay) return replay;
    throw new AdminError('ADMIN_INCIDENT_CHANGED');
  }
});
