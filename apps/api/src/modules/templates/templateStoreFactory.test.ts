import { describe, expect, it, vi } from 'vitest';

import { createTemplateStoreFromConfig } from './templateStoreFactory.js';

describe('createTemplateStoreFromConfig', () => {
  it('uses the in-memory store by default', async () => {
    const store = createTemplateStoreFromConfig({
      config: {
        templateStore: 'memory',
        templateStoreUserId: 'local-dev-user'
      }
    });

    const template = await store.create({
      userId: 'local-dev-user',
      title: 'Memory template',
      body: 'Stored locally'
    });

    expect(await store.list({ userId: 'local-dev-user' })).toEqual([template]);
  });

  it('uses the Prisma repository when configured', async () => {
    const createdAt = new Date('2026-06-01T00:00:00.000Z');
    const prisma = {
      template: {
        findMany: vi.fn().mockResolvedValue([
          {
            id: 'template-1',
            title: 'Prisma template',
            body: 'Stored in database',
            createdAt
          }
        ]),
        create: vi.fn()
      }
    };
    const store = createTemplateStoreFromConfig({
      config: {
        templateStore: 'prisma',
        templateStoreUserId: 'user-1'
      },
      prisma
    });

    expect(await store.list({ userId: 'user-1' })).toEqual([
      {
        id: 'template-1',
        title: 'Prisma template',
        body: 'Stored in database',
        createdAt: '2026-06-01T00:00:00.000Z'
      }
    ]);
    expect(prisma.template.findMany).toHaveBeenCalledWith({
      where: { userId: 'user-1' },
      orderBy: { createdAt: 'desc' }
    });
  });

  it('requires a Prisma client when Prisma storage is configured', () => {
    expect(() =>
      createTemplateStoreFromConfig({
        config: {
          templateStore: 'prisma',
          templateStoreUserId: 'user-1'
        }
      })
    ).toThrow('Prisma template store requires a Prisma client');
  });
});
