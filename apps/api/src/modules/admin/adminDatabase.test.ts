import { randomUUID } from 'node:crypto';
import { PrismaClient } from '@prisma/client';
import { afterAll, describe, expect, it } from 'vitest';
import { createPrismaTrialAccessStore } from './prismaTrialAccessStore.js';
import { createPrismaAdminDataSource } from './adminDataSource.js';
import type { AdminConsoleConfig } from './adminConfig.js';

// Opt-in only; refuse external hosts, default Postgres ports and existing app databases.
const databaseUrl = process.env.ADMIN_TEST_DATABASE_URL;
if (databaseUrl) {
  const url = new URL(databaseUrl);
  if (url.hostname !== '127.0.0.1' || url.port !== '55439' || url.pathname !== '/postdee_admin_fixture') {
    throw new Error('Admin DB tests require the dedicated loopback fixture cluster on port 55439');
  }
}
describe.skipIf(!databaseUrl)('admin PostgreSQL transactions and projections', () => {
  const prisma = new PrismaClient({ datasources: { db: { url: databaseUrl ?? 'postgresql://unused@127.0.0.1:55439/postdee_admin_fixture' } } });
  const ids: string[] = [];
  const now = () => new Date('2026-10-18T00:00:00Z');
  const store = createPrismaTrialAccessStore(prisma, now);
  const member = async () => {
    const id=`admin-fixture-${randomUUID()}`;ids.push(id);
    return prisma.user.create({data:{id,firebaseUid:id,email:`${id}@example.com`,displayName:'Fixture seller'}});
  };
  const command = (user: {id:string;email:string}) => ({requestId:randomUUID(),actorId:'fixture-owner',userId:user.id,
    expectedEmail:user.email,action:'GRANT' as const,plan:'PRO' as const,days:7,expectedVersion:0,reason:'ทดสอบฐานข้อมูลเฉพาะในเครื่อง'});
  const config: AdminConsoleConfig = {origin:'http://127.0.0.1:4174',environment:'LOCAL',ownerUids:['fixture-owner'],viewerUids:[],
    firebaseWeb:{apiKey:'fixture',authDomain:'fixture.firebaseapp.com',projectId:'fixture',appId:'fixture'}};
  afterAll(async()=>{
    await prisma.user.deleteMany({where:{id:{in:ids}}});
    await prisma.managedUploadOwner.deleteMany({where:{ownerId:{in:ids}}});
    await prisma.$disconnect();
  });
  it('matches existing platform schema values on a freshly migrated database', async()=>{
    const rows=await prisma.$queryRaw<{values:string[]}[]>`SELECT enum_range(NULL::"Platform")::text[] AS values`;
    expect(rows[0].values).toEqual(expect.arrayContaining(['SHOPEE_VIDEO','LAZADA_VIDEO']));
  });
  it('commits an atomic trial and audit, replays exactly once, and rejects modified commands', async()=>{
    const user=await member();const c=command(user);const trial=await store.mutate(c);
    expect(trial.version).toBe(1);expect(await store.mutate(c)).toEqual(trial);
    await expect(store.mutate({...c,days:14})).rejects.toMatchObject({code:'ADMIN_REQUEST_CONFLICT'});
    expect(await prisma.adminTrialAudit.count({where:{userId:user.id}})).toBe(1);
  });
  it('serializes simultaneous grants so only one command changes the entitlement', async()=>{
    const user=await member();const c=command(user);
    const results=await Promise.allSettled([store.mutate(c),store.mutate({...c,requestId:randomUUID()})]);
    expect(results.filter(r=>r.status==='fulfilled')).toHaveLength(1);
    expect((await store.find(user.id))?.version).toBe(1);
    expect(await prisma.adminTrialAudit.count({where:{userId:user.id}})).toBe(1);
  });
  it('rolls back the trial write if the audit write fails in the same real transaction', async()=>{
    const user=await member();
    const failing=new Proxy(prisma,{get(target,key){
      if(key==='$transaction')return (operation: (tx:unknown)=>Promise<unknown>, options:never)=>target.$transaction(async tx=>operation(new Proxy(tx,{
        get(transaction,property){if(property==='adminTrialAudit')return new Proxy(transaction.adminTrialAudit,{get(delegate,method){if(method==='create')return async()=>{throw new Error('fixture audit unavailable');};return Reflect.get(delegate,method);}});return Reflect.get(transaction,property);}
      })),options);
      return Reflect.get(target,key);
    }});
    await expect(createPrismaTrialAccessStore(failing,now).mutate(command(user))).rejects.toThrow('fixture audit unavailable');
    expect(await store.find(user.id)).toBeNull();
    expect(await prisma.adminTrialAudit.count({where:{userId:user.id}})).toBe(0);
  });
  it('checks reviewed identity inside the transaction and never creates a missing member', async()=>{
    const user=await member();
    await expect(store.mutate({...command(user),expectedEmail:'changed@example.com'})).rejects.toMatchObject({code:'ADMIN_MEMBER_CHANGED'});
    await expect(store.mutate(command({id:'missing-fixture',email:'missing@example.com'}))).rejects.toMatchObject({code:'ADMIN_MEMBER_NOT_FOUND'});
    expect(await store.find(user.id)).toBeNull();
  });
  it('preserves deletion tombstones and cascades trial records when a member is deleted', async()=>{
    const blocked=await member();
    await prisma.managedUploadOwner.create({data:{ownerId:blocked.id,status:'DELETED'}});
    await expect(store.mutate(command(blocked))).rejects.toMatchObject({code:'ACCOUNT_DELETION_IN_PROGRESS'});
    expect((await prisma.managedUploadOwner.findUnique({where:{ownerId:blocked.id}}))?.status).toBe('DELETED');
    const user=await member();await store.mutate(command(user));
    await prisma.user.delete({where:{id:user.id}});
    expect(await store.find(user.id)).toBeNull();
    expect(await prisma.adminTrialAudit.count({where:{userId:user.id}})).toBe(0);
  });
  it('queries actual schema fields, separates purchased plans, and reports bounded trial-period usage', async()=>{
    const user=await member();await store.mutate(command(user));
    await prisma.subscription.create({data:{userId:user.id,plan:'STARTER',status:'ACTIVE',currentPeriodEnd:new Date('2027-01-01T00:00:00Z')}});
    await prisma.realClipCaptionUsage.create({data:{userId:user.id,monthKey:'2026-10',createdAt:new Date('2026-10-18T00:01:00Z')}});
    await prisma.aiEditUsage.create({data:{userId:user.id,monthKey:'2026-10',minutes:2,createdAt:new Date('2026-10-18T00:01:00Z')}});
    const post=await prisma.post.create({data:{userId:user.id,caption:'Fixture caption',videoS3Key:'fixture/unused.mp4',selectedPlatforms:['TIKTOK','YOUTUBE_SHORTS'],status:'PARTIAL_PUBLISHED',createdAt:now()}});
    await prisma.platformPublish.create({data:{postId:post.id,platform:'TIKTOK',status:'FAILED',errorMessage:'token=secret signed-url=secret',createdAt:new Date('2026-10-18T00:01:00Z')}});
    const source=createPrismaAdminDataSource(prisma,config,()=>new Date('2026-10-19T00:00:00Z'));
    expect(await source.member(user.id)).toMatchObject({paidPlan:'STARTER',trial:{plan:'PRO'},postUnits:2,captionRequests:1,editMinutes:2});
    for(const view of ['overview','members','posts','trials','channels','audit','reports'] as const){
      const page=await source.view(view,{query:user.email});
      expect(Array.isArray(page.rows)).toBe(true);expect(JSON.stringify(page)).not.toContain('secret');
      if(view==='reports')expect(page.rows[0]).toMatchObject({captionRequests:1,editMinutes:2,postUnits:1,estimatedUsd:null,purchasedPlanNow:'STARTER'});
    }
    const rated=createPrismaAdminDataSource(prisma,{...config,costRates:{captionRequestUsd:0.01,editMinuteUsd:0.02,postUnitUsd:0.03}},()=>new Date('2026-10-19T00:00:00Z'));
    expect((await rated.view('reports',{query:user.email})).rows[0].estimatedUsd).toBe(0.08);
    expect((await source.view('posts',{query:user.email,status:'PUBLISHED'})).rows).toHaveLength(0);
  });
  it('pages newest posts without duplicates even when creation timestamps tie', async()=>{
    const user=await member();
    await prisma.post.createMany({data:Array.from({length:55},(_,i)=>({id:`${user.id}-${String(i).padStart(2,'0')}`,userId:user.id,caption:'Pagination fixture',videoS3Key:'fixture/unused.mp4',selectedPlatforms:['TIKTOK' as const],createdAt:now()}))});
    const data=createPrismaAdminDataSource(prisma,config,now);
    const first=await data.view('posts',{query:user.email});
    expect(first.rows).toHaveLength(50);expect(first.nextCursor).toBeTruthy();
    const second=await data.view('posts',{query:user.email,cursor:first.nextCursor});
    expect(second.rows).toHaveLength(5);expect(second.nextCursor).toBeUndefined();
    expect(new Set([...first.rows,...second.rows].map(r=>r.id)).size).toBe(55);
    await expect(data.view('posts',{query:user.email,cursor:'invalid'})).rejects.toMatchObject({code:'ADMIN_FILTER_INVALID'});
  });
});
