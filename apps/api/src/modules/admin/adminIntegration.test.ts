import request from 'supertest';
import { describe, expect, it } from 'vitest';
import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import { createMemoryTrialAccessStore } from './trialAccess.js';
import { createSubscriptionStoreFromConfig } from '../subscriptions/subscriptionStoreFactory.js';

describe('trial access across real application routes', () => {
  it('grants, restores, expires and revokes access without altering paid entitlements or other members', async () => {
    let time=new Date(); const now=()=>time;
    const config=readServerConfig({NODE_ENV:'test',DATABASE_URL:'postgresql://unused@127.0.0.1:55439/postdee_admin_fixture',AUTH_PROVIDER:'firebase',FIREBASE_PROJECT_ID:'fixture',TRIAL_ACCESS_ENABLED:'true',
      ADMIN_CONSOLE_ENABLED:'true',ADMIN_CONSOLE_ORIGIN:'http://localhost:4174',ADMIN_ENVIRONMENT:'LOCAL',ADMIN_OWNER_UIDS:'owner',
      ADMIN_FIREBASE_WEB_CONFIG:JSON.stringify({apiKey:'fixture',authDomain:'fixture.firebaseapp.com',projectId:'fixture',appId:'fixture'}),
      BILLING_PROVIDER:'revenuecat',REVENUECAT_WEBHOOK_AUTH_TOKEN:'fixture',REVENUECAT_REST_API_V1_KEY:'fixture'});
    const trials=createMemoryTrialAccessStore({now});
    const verifier={verifyIdToken:async(id:string)=>({id,provider:'firebase' as const,email:`${id}@example.com`,authenticatedAtSeconds:time.getTime()/1000})};
    const app=createApp({config,now,trialAccessStore:trials,firebaseVerifier:verifier,adminFirebaseVerifier:verifier,
      adminDataSource:{member:async id=>id==='member'?{id,email:'member@example.com',paidPlan:'BASIC'}:null,view:async()=>({rows:[]})},
      revenueCatSubscriberClient:{loadSubscriber:async()=>({observedAtMs:time.getTime(),activeEntitlements:[]})}});
    const billing=async(id='member')=>(await request(app).get('/billing/subscription').set('Authorization',`Bearer ${id}`).expect(200)).body.subscription;
    const mutate=async(action:string,expectedVersion:number,requestId:string)=>request(app).post('/admin/api/trials')
      .set('Authorization','Bearer owner').set('Origin','http://localhost:4174').set('X-PostDee-Admin','1')
      .send({action,expectedVersion,requestId,userId:'member',expectedEmail:'member@example.com',plan:'PRO',days:7,reason:'ทดสอบสิทธิ์โดยไม่ซื้อจริง'}).expect(200);
    expect((await billing()).plan).toBe('BASIC');
    await mutate('GRANT',0,'c418d66d-3ee5-4ba0-947d-6aef0aa22cef');
    const pro=await billing(); expect(pro.plan).toBe('PRO'); expect(pro.monthlyPostLimit).toBe(250); expect(pro.canUseAiCaptions).toBe(true); expect(pro.purchasedPlan).toBe('BASIC');
    await request(app).post('/billing/purchase-readiness').set('Authorization','Bearer member').send({}).expect(409);
    await request(app).post('/billing/purchase-readiness').set('Authorization','Bearer member').send({purchaseConfirmationProtocol:2}).expect(200);
    expect((await billing('other')).plan).toBe('BASIC');
    const resync=await request(app).post('/billing/revenuecat/resync').set('Authorization','Bearer member').send({}).expect(200);
    expect(resync.body.plan).toBe('BASIC');
    expect(resync.body.effectivePlan).toBe('PRO');
    expect(resync.body.purchasedPlan).toBe('BASIC');
    await mutate('REVOKE',1,'73f9b17c-7a6d-45cb-97c7-d9e69bd78cd9'); expect((await billing()).plan).toBe('BASIC');
    await mutate('GRANT',2,'5d5f59cd-e793-4f1f-8195-53943b46a26a');
    time=new Date(time.getTime()+8*86400000); expect((await billing()).plan).toBe('BASIC');
    expect(await trials.history()).toHaveLength(3);
  });
  it('uses the same effective access factory for background workers and keeps the paid store intact', async () => {
    const trials=createMemoryTrialAccessStore();
    const store=createSubscriptionStoreFromConfig({config:{subscriptionStore:'memory',trialAccessEnabled:true},trialStore:trials});
    const user={id:'paid-member',provider:'firebase' as const};
    await store.activatePlan(user,'STARTER');
    await trials.mutate({requestId:'worker',actorId:'owner',userId:user.id,action:'GRANT',plan:'PRO',days:7,reason:'ทดสอบสิทธิ์ worker',expectedVersion:0});
    expect(await store.getPlan(user)).toBe('PRO');
    await trials.mutate({requestId:'worker-revoke',actorId:'owner',userId:user.id,action:'REVOKE',plan:'PRO',days:7,reason:'จบการทดสอบ worker',expectedVersion:1});
    expect(await store.getPlan(user)).toBe('STARTER');
  });
  it('confirms purchased Starter separately while a Pro trial remains effective', async () => {
    const trials=createMemoryTrialAccessStore();const id='paid-trial-member';
    const command={requestId:'grant',actorId:'owner',userId:id,action:'GRANT' as const,plan:'PRO' as const,days:7,expectedVersion:0,reason:'ทดสอบสิทธิ์ซื้อซ้อนทดลอง'};
    await trials.mutate(command);
    const app=createApp({config:readServerConfig({NODE_ENV:'test',DATABASE_URL:'postgresql://unused@127.0.0.1:55439/postdee_admin_fixture',
      TRIAL_ACCESS_ENABLED:'true',BILLING_PROVIDER:'revenuecat',REVENUECAT_WEBHOOK_AUTH_TOKEN:'fixture',REVENUECAT_REST_API_V1_KEY:'fixture'}),
      trialAccessStore:trials,revenueCatSubscriberClient:{loadSubscriber:async()=>({observedAtMs:Date.now(),activeEntitlements:[{id:'starter',productId:'postdee_starter_monthly',expiresAt:'2100-01-01T00:00:00Z'}]})}});
    const result=await request(app).post('/billing/revenuecat/resync').set('x-postdee-user-id',id).send({}).expect(200);
    expect(result.body).toMatchObject({plan:'STARTER',effectivePlan:'PRO',purchasedPlan:'STARTER',subscription:{plan:'STARTER'}});
    const current=await request(app).get('/billing/subscription').set('x-postdee-user-id',id).expect(200);
    expect(current.body.subscription).toMatchObject({plan:'PRO',purchasedPlan:'STARTER'});
    await trials.mutate({...command,requestId:'revoke',action:'REVOKE',expectedVersion:1});
    const after=await request(app).get('/billing/subscription').set('x-postdee-user-id',id).expect(200);
    expect(after.body.subscription).toMatchObject({plan:'STARTER',purchasedPlan:'STARTER'});
  });
});
