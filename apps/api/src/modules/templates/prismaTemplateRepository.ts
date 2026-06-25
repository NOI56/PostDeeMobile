import type { CreateTemplateInput, TemplateStore, TextTemplate } from './templateStore.js';

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
  }) => Promise<PrismaTemplate[]>;
  create: (args: {
    data: {
      userId: string;
      title: string;
      body: string;
    };
  }) => Promise<PrismaTemplate>;
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
      orderBy: { createdAt: 'desc' }
    });

    return templates.map(mapTemplate);
  },
  create: async (input: CreateTemplateInput) => {
    const template = await prisma.template.create({
      data: {
        userId: input.userId,
        title: input.title,
        body: input.body
      }
    });

    return mapTemplate(template);
  }
});
