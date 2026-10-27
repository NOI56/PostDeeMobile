import { describe, expect, it, vi } from 'vitest';

import { createPrismaTemplateRepository } from './prismaTemplateRepository.js';

describe('createPrismaTemplateRepository', () => {
  it('lists templates for the configured user', async () => {
    const createdAt = new Date('2026-06-01T00:00:00.000Z');
    const prisma = {
      template: {
        count: vi.fn(),
        deleteMany: vi.fn(),
        findMany: vi.fn().mockResolvedValue([
          {
            id: 'template-1',
            title: 'Disclosure',
            body: 'Affiliate link disclosure',
            createdAt
          }
        ]),
        create: vi.fn()
      }
    };
    const repository = createPrismaTemplateRepository({
      prisma
    });

    const templates = await repository.list({ userId: 'user-1' });

    expect(prisma.template.findMany).toHaveBeenCalledWith({
      where: { userId: 'user-1' },
      orderBy: { createdAt: 'desc' },
      take: 200
    });
    expect(templates).toEqual([
      {
        id: 'template-1',
        title: 'Disclosure',
        body: 'Affiliate link disclosure',
        createdAt: '2026-06-01T00:00:00.000Z'
      }
    ]);
  });

  it('deletes a template only for its owner', async () => {
    const prisma = {
      template: {
        count: vi.fn(),
        findMany: vi.fn(),
        create: vi.fn(),
        deleteMany: vi.fn()
          .mockResolvedValueOnce({ count: 1 })
          .mockResolvedValueOnce({ count: 0 })
      }
    };
    const repository = createPrismaTemplateRepository({ prisma });

    await expect(repository.remove({ userId: 'user-1', templateId: 't-1' })).resolves.toBe(true);
    await expect(repository.remove({ userId: 'user-2', templateId: 't-1' })).resolves.toBe(false);
    expect(prisma.template.deleteMany).toHaveBeenCalledWith({
      where: { id: 't-1', userId: 'user-1' }
    });
  });

  it('creates templates for the configured user', async () => {
    const createdAt = new Date('2026-06-01T00:00:00.000Z');
    const prisma = {
      template: {
        count: vi.fn(),
        deleteMany: vi.fn(),
        findMany: vi.fn(),
        create: vi.fn().mockResolvedValue({
          id: 'template-2',
          title: 'Contact',
          body: 'Line: @postdee',
          createdAt
        })
      }
    };
    const repository = createPrismaTemplateRepository({
      prisma
    });

    const template = await repository.create({
      userId: 'user-1',
      title: 'Contact',
      body: 'Line: @postdee'
    });

    expect(prisma.template.create).toHaveBeenCalledWith({
      data: {
        userId: 'user-1',
        title: 'Contact',
        body: 'Line: @postdee'
      }
    });
    expect(template).toEqual({
      id: 'template-2',
      title: 'Contact',
      body: 'Line: @postdee',
      createdAt: '2026-06-01T00:00:00.000Z'
    });
  });
});
