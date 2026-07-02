import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { createApp } from '../../app.js';
import { createInMemorySocialConnectionStore } from '../socialConnections/socialConnectionStore.js';

describe('account routes', () => {
  const ownedUploadKey = (userId: string, fileName: string, uploadId = 'clip') =>
    'uploads/' + encodeURIComponent(userId) + '/' + uploadId + '/' + fileName;
  const createPostAs = (app: ReturnType<typeof createApp>, userId: string) =>
    request(app)
      .post('/posts')
      .set('x-postdee-user-id', userId)
      .send({
        caption: 'ของดีบอกต่อ',
        videoS3Key: ownedUploadKey(userId, 'demo.mp4'),
        platforms: ['TIKTOK'],
        subscriptionPlan: 'PRO'
      })
      .expect(201);

  const createTemplateAs = (app: ReturnType<typeof createApp>, userId: string) =>
    request(app)
      .post('/templates')
      .set('x-postdee-user-id', userId)
      .send({ title: 'โปรโมชั่น', body: 'ลดราคาวันนี้' })
      .expect(201);

  it('permanently deletes all data for the authenticated user', async () => {
    const app = createApp();

    await createPostAs(app, 'seller-to-delete');
    await createTemplateAs(app, 'seller-to-delete');

    const postsBefore = await request(app)
      .get('/posts')
      .set('x-postdee-user-id', 'seller-to-delete')
      .expect(200);
    expect(postsBefore.body.posts).toHaveLength(1);

    const deleteResponse = await request(app)
      .delete('/account')
      .set('x-postdee-user-id', 'seller-to-delete')
      .expect(200);
    expect(deleteResponse.body).toEqual({ status: 'ok' });

    const postsAfter = await request(app)
      .get('/posts')
      .set('x-postdee-user-id', 'seller-to-delete')
      .expect(200);
    expect(postsAfter.body.posts).toEqual([]);

    const templatesAfter = await request(app)
      .get('/templates')
      .set('x-postdee-user-id', 'seller-to-delete')
      .expect(200);
    expect(templatesAfter.body.templates).toEqual([]);
  });

  it("leaves other users' data intact", async () => {
    const app = createApp();

    await createPostAs(app, 'seller-a');
    await createPostAs(app, 'seller-b');

    await request(app)
      .delete('/account')
      .set('x-postdee-user-id', 'seller-a')
      .expect(200);

    const sellerAPosts = await request(app)
      .get('/posts')
      .set('x-postdee-user-id', 'seller-a')
      .expect(200);
    expect(sellerAPosts.body.posts).toEqual([]);

    const sellerBPosts = await request(app)
      .get('/posts')
      .set('x-postdee-user-id', 'seller-b')
      .expect(200);
    expect(sellerBPosts.body.posts).toHaveLength(1);
  });

  it('removes social connections when the account is deleted', async () => {
    const socialConnectionStore = createInMemorySocialConnectionStore();
    const app = createApp({ socialConnectionStore });

    await socialConnectionStore.upsert({
      userId: 'seller-social-delete',
      platform: 'TIKTOK',
      postPeerAccountId: 'acct-tiktok-delete'
    });

    await request(app)
      .delete('/account')
      .set('x-postdee-user-id', 'seller-social-delete')
      .expect(200);

    await expect(
      socialConnectionStore.getAccountId({
        userId: 'seller-social-delete',
        platform: 'TIKTOK'
      })
    ).resolves.toBeUndefined();
  });
});
