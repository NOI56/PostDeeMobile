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

// Templates are caption snippets; these ceilings sit well above real use and
// bound what one owner can keep in the shared database and list responses.
export const templateTitleMaxLength = 120;
export const templateBodyMaxLength = 5000;
export const maxTemplatesPerOwner = 200;

export type TemplateStore = {
  // Newest first, at most maxTemplatesPerOwner rows.
  list: (filter: { userId: string }) => TextTemplate[] | Promise<TextTemplate[]>;
  count: (filter: { userId: string }) => number | Promise<number>;
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
        .reverse()
        .slice(0, maxTemplatesPerOwner)
        .map(({ userId: _userId, ...template }) => template),
    count: ({ userId }) => templates.filter((template) => template.userId === userId).length,
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
