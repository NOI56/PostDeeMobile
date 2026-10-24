import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { createPrismaTemplateRepository, type PrismaTemplateClient } from './prismaTemplateRepository.js';
import { createTemplateStore } from './templateStore.js';

const createTemplate = (app: ReturnType<typeof createApp>, userId: string, body: Record<string, unknown>) =>
  request(app).post('/templates').set('x-postdee-user-id', userId).send(body);

// Templates live in the shared database and are listed whole, so each field and
// each owner's collection needs a ceiling well above real caption templates.
describe('template resource limits', () => {
  it('rejects a title or body longer than the template limits', async () => {
    const app = createApp();

    const longTitle = await createTemplate(app, 'seller-template-title', { title: 'x'.repeat(121), body: 'ok' }).expect(400);
    const longBody = await createTemplate(app, 'seller-template-body', { title: 'ok', body: 'x'.repeat(5001) }).expect(400);
    await createTemplate(app, 'seller-template-body', { title: 'x'.repeat(120), body: 'x'.repeat(5000) }).expect(201);

    expect(longTitle.body).toMatchObject({ status: 'error', code: 'TEMPLATE_FIELD_TOO_LONG' });
    expect(longBody.body).toMatchObject({ status: 'error', code: 'TEMPLATE_FIELD_TOO_LONG' });
  });

  it('stops one owner at 200 templates without affecting another owner', async () => {
    const app = createApp();

    for (let index = 0; index < 200; index += 1) {
      await createTemplate(app, 'seller-template-cap', { title: `t${index}`, body: 'b' }).expect(201);
    }
    const overCap = await createTemplate(app, 'seller-template-cap', { title: 'one more', body: 'b' }).expect(409);
    await createTemplate(app, 'seller-template-other', { title: 'first', body: 'b' }).expect(201);

    expect(overCap.body).toMatchObject({ status: 'error', code: 'TEMPLATE_LIMIT_REACHED' });
  });

  it('counts only the owner in the memory store', async () => {
    const store = createTemplateStore();
    await store.create({ userId: 'a', title: 't', body: 'b' });
    await store.create({ userId: 'b', title: 't', body: 'b' });

    expect(await store.count({ userId: 'a' })).toBe(1);
  });

  it('bounds the Prisma list and counts by owner', async () => {
    const prisma = {
      template: {
        findMany: vi.fn(async () => []),
        count: vi.fn(async () => 7),
        create: vi.fn()
      }
    };
    const repository = createPrismaTemplateRepository({ prisma: prisma as unknown as PrismaTemplateClient });

    await repository.list({ userId: 'seller-1' });
    await expect(repository.count({ userId: 'seller-1' })).resolves.toBe(7);

    expect(prisma.template.findMany).toHaveBeenCalledWith(expect.objectContaining({
      where: { userId: 'seller-1' },
      orderBy: { createdAt: 'desc' },
      take: 200
    }));
    expect(prisma.template.count).toHaveBeenCalledWith({ where: { userId: 'seller-1' } });
  });
});
