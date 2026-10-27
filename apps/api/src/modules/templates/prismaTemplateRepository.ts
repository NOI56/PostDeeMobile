import {
  maxTemplatesPerOwner,
  type CreateTemplateInput,
  type TemplateStore,
  type TextTemplate
} from './templateStore.js';

type PrismaTemplate = {
  id: string;
  title: string;
  body: string;
  createdAt: Date;
};

type TemplateDelegate = {
  findMany: (args: {
    where: { userId: string };
    orderBy: { createdAt: 'desc' };
    take: number;
  }) => Promise<PrismaTemplate[]>;
  count: (args: { where: { userId: string } }) => Promise<number>;
  create: (args: {
    data: {
      userId: string;
      title: string;
      body: string;
    };
  }) => Promise<PrismaTemplate>;
  deleteMany: (args: { where: { id: string; userId: string } }) => Promise<{ count: number }>;
};

export type PrismaTemplateClient = {
  template: TemplateDelegate;
};

const mapTemplate = (template: PrismaTemplate): TextTemplate => ({
  id: template.id,
  title: template.title,
  body: template.body,
  createdAt: template.createdAt.toISOString()
});

export const createPrismaTemplateRepository = ({
  prisma
}: {
  prisma: PrismaTemplateClient;
}): TemplateStore => ({
  list: async ({ userId }) => {
    const templates = await prisma.template.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      take: maxTemplatesPerOwner
    });

    return templates.map(mapTemplate);
  },
  count: ({ userId }) => prisma.template.count({ where: { userId } }),
  create: async (input: CreateTemplateInput) => {
    const template = await prisma.template.create({
      data: {
        userId: input.userId,
        title: input.title,
        body: input.body
      }
    });

    return mapTemplate(template);
  },
  remove: async ({ userId, templateId }) => {
    const result = await prisma.template.deleteMany({
      where: { id: templateId, userId }
    });

    return result.count > 0;
  }
});
