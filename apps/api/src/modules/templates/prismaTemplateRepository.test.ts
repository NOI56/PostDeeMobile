import { describe, expect, it, vi } from 'vitest';

import { createPrismaTemplateRepository } from './prismaTemplateRepository.js';

describe('createPrismaTemplateRepository', () => {
  it('lists templates for the configured user', async () => {
    const createdAt = new Date('2026-06-01T00:00:00.000Z');
    const prisma = {
      template: {
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
      orderBy: { createdAt: 'desc' }
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

  it('creates templates for the configured user', async () => {
    const createdAt = new Date('2026-06-01T00:00:00.000Z');
    const prisma = {
      template: {
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
