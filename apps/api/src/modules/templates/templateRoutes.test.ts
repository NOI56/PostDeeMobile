import request from 'supertest';
import { describe, expect, it } from 'vitest';
import express from 'express';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import { registerTemplateRoutes } from './templateRoutes.js';
import type { TextTemplate, TemplateStore } from './templateStore.js';

describe('template routes', () => {
  it('requires authentication before reading templates in Firebase mode', async () => {
    const app = createApp({
      config: readServerConfig({
        AUTH_PROVIDER: 'firebase',
        FIREBASE_PROJECT_ID: 'postdee-test'
      }),
      firebaseVerifier: {
        verifyIdToken: async () => ({ id: 'seller-firebase', provider: 'firebase' })
      }
    });

    await request(app).get('/templates').expect(401);
  });

  it('lists templates from the in-memory store', async () => {
    const app = createApp();

    const response = await request(app).get('/templates').expect(200);

    expect(response.body).toEqual({
      status: 'ok',
      templates: []
    });
  });

  it('creates a reusable text template and returns it in the list', async () => {
    const app = createApp();

    const createResponse = await request(app)
      .post('/templates')
      .send({
        title: 'Affiliate disclosure',
        body: 'ลิงก์นี้เป็นลิงก์ Affiliate'
      })
      .expect(201);

    expect(createResponse.body.template).toMatchObject({
      title: 'Affiliate disclosure',
      body: 'ลิงก์นี้เป็นลิงก์ Affiliate'
    });
    expect(createResponse.body.template.id).toEqual(expect.any(String));

    const listResponse = await request(app).get('/templates').expect(200);

    expect(listResponse.body.templates).toEqual([createResponse.body.template]);
  });

  it('scopes templates by authenticated user', async () => {
    const app = createApp();

    const sellerATemplate = await request(app)
      .post('/templates')
      .set('x-postdee-user-id', 'seller-template-a')
      .send({
        title: 'Seller A disclosure',
        body: 'Seller A body'
      })
      .expect(201);

    await request(app)
      .post('/templates')
      .set('x-postdee-user-id', 'seller-template-b')
      .send({
        title: 'Seller B disclosure',
        body: 'Seller B body'
      })
      .expect(201);

    const sellerAList = await request(app)
      .get('/templates')
      .set('x-postdee-user-id', 'seller-template-a')
      .expect(200);

    expect(sellerAList.body.templates).toEqual([sellerATemplate.body.template]);
  });


  it('rejects templates without title or body', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/templates')
      .send({ title: 'Missing body' })
      .expect(400);

    expect(response.body).toEqual({
      status: 'error',
      message: 'title and body are required'
    });
  });

  it('supports async template repositories for future Prisma persistence', async () => {
    const template: TextTemplate = {
      id: 'template-1',
      title: 'Async template',
      body: 'Loaded from an async repository',
      createdAt: '2026-06-01T00:00:00.000Z'
    };
    const asyncStore: TemplateStore = {
      list: async () => [template],
      create: async () => template
    };
    const app = express();
    app.use(express.json());
    const router = express.Router();
    registerTemplateRoutes(
      router,
      (_request, response, next) => {
        response.locals.authUser = {
          id: 'async-template-user',
          provider: 'mock'
        };
        next();
      },
      asyncStore
    );
    app.use(router);

    const response = await request(app).get('/templates').expect(200);

    expect(response.body).toEqual({
      status: 'ok',
      templates: [template]
    });
  });
});
