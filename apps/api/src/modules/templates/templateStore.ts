import { randomUUID } from 'node:crypto';

export type TextTemplate = {
  id: string;
  title: string;
  body: string;
  createdAt: string;
};

export type CreateTemplateInput = {
  userId: string;
  title: string;
  body: string;
};

export type TemplateStore = {
  list: (filter: { userId: string }) => TextTemplate[] | Promise<TextTemplate[]>;
  create: (input: CreateTemplateInput) => TextTemplate | Promise<TextTemplate>;
  // Hard-deletes every template owned by userId. Used by account deletion.
  // Optional because the Prisma store relies on the User cascade instead.
  deleteAllForUser?: (userId: string) => Promise<void>;
};

export const createTemplateStore = (): TemplateStore => {
  const templates: Array<TextTemplate & { userId: string }> = [];

  return {
    list: ({ userId }) =>
      templates
        .filter((template) => template.userId === userId)
        .map(({ userId: _userId, ...template }) => template),
    create: (input) => {
      const template = {
        id: randomUUID(),
        userId: input.userId,
        title: input.title,
        body: input.body,
        createdAt: new Date().toISOString()
      };

      templates.push(template);
      const { userId: _userId, ...responseTemplate } = template;
      return responseTemplate;
    },
    deleteAllForUser: async (userId) => {
      for (let index = templates.length - 1; index >= 0; index -= 1) {
        if (templates[index].userId === userId) {
          templates.splice(index, 1);
        }
      }
    }
  };
};
