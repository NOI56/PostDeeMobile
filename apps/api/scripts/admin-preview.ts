// Local fixture only: no databases, credentials, cloud services or real member records.
import express from 'express';
import { randomUUID } from 'node:crypto';
import { registerAdminConsole } from '../src/modules/admin/adminRoutes.js';
import { activeTrial, createMemoryTrialAccessStore } from '../src/modules/admin/trialAccess.js';
import type { AdminDataSource, AdminMember, AdminView } from '../src/modules/admin/adminDataSource.js';
import type { AdminReportSummary } from '../src/modules/admin/adminUsageReport.js';
import { adminChannelResult } from '../src/modules/admin/adminDataSource.js';
import { createMemoryAdminAccountDeletionStore } from '../src/modules/admin/adminAccountDeletion.js';
import { createMemoryServiceIncidentStore } from '../src/modules/serviceStatus/serviceIncident.js';
import { createMemorySupportChatStore } from '../src/modules/supportChat/supportChat.js';

const app = express(); app.use(express.json({ limit: '16kb' }));
const viewer = process.argv.includes('--viewer'); const emptyTrials = process.argv.includes('--empty-trials');
const portArguments = process.argv.slice(2).filter(value => value === '--port' || value.startsWith('--port='));
const requestedPort = portArguments[0]?.slice('--port='.length);
if (portArguments.length > 1 || (requestedPort !== undefined && (!/^\d+$/.test(requestedPort) || Number(requestedPort) < 1024 || Number(requestedPort) > 65535))) {
  throw new Error('Use one --port=<integer> between 1024 and 65535 for the local fixture.');
}
const port = requestedPort === undefined ? (emptyTrials ? 4176 : 4174) + (viewer ? 1 : 0) : Number(requestedPort);
const trials = createMemoryTrialAccessStore();
const accountDeletions = createMemoryAdminAccountDeletionStore();
const support = createMemorySupportChatStore();
await support.postFromMember({ userId:'fixture-mali', id:randomUUID(), body:'โพสต์ลง TikTok เมื่อเช้าขึ้นว่าส่งไม่สำเร็จ ต้องทำยังไงคะ' });
await support.postFromMember({ userId:'fixture-narin', id:randomUUID(), body:'ขอสอบถามเรื่องแพ็กเกจ Pro ครับ' });
const time = new Date().toISOString();
const members: AdminMember[] = [
  { id:'fixture-mali',email:'mali@example.com',displayName:'Mali S.',paidPlan:'BASIC',createdAt:time,updatedAt:time,postCount:12,channelCount:2 },
  { id:'fixture-narin',email:'narin@example.com',displayName:'Narin P.',paidPlan:'STARTER',createdAt:time,updatedAt:time,postCount:28,channelCount:3 },
  { id:'fixture-ploy',email:'ploy@example.com',displayName:'Ploy K.',paidPlan:'PRO',createdAt:time,updatedAt:time,postCount:43,channelCount:4 }
];
if (!emptyTrials) await trials.mutate({ requestId:randomUUID(),actorId:'fixture-owner',userId:'fixture-mali',action:'GRANT',plan:'PRO',days:7,reason:'ข้อมูลจำลองสำหรับตรวจหน้าจอ',expectedVersion:0 });
const member = async (id: string): Promise<AdminMember | null> => { const found=members.find(r=>r.id===id);const asOf=new Date();return found ? {...found,trial:await trials.find(id),monthKey:time.slice(0,7),postUnits:0,quotaPostUnits:0,captionRequests:0,editMinutes:0,
  asOf:asOf.toISOString(),window:{from:asOf.toISOString().slice(0,7)+'-01T00:00:00.000Z',until:asOf.toISOString(),timezone:'UTC'}} : null; };
const data: AdminDataSource = { member, view: async (view: AdminView, options) => {
  const asOf=new Date();const window={from:options.from?.toISOString()??null,until:new Date(Math.min(asOf.getTime(),options.until?.getTime()??Infinity)).toISOString(),timezone:'UTC' as const};
  const people=await Promise.all(members.map(r=>member(r.id))).then(rows=>rows.filter((r):r is AdminMember=>!!r));
  const filtered=people.filter(r=>`${r.email} ${r.displayName}`.toLowerCase().includes(options.query.toLowerCase()));
  const ids=new Set(filtered.map(r=>r.id));
  const rows = view==='overview' ? [{label:'สมาชิกทั้งหมด',value:people.length},{label:'แพ็กเกจที่ซื้อยังใช้งานได้',value:2},
    {label:'สิทธิ์ทดลองที่ใช้งานอยู่',value:people.filter(r=>activeTrial(r.trial??null)).length},{label:'โพสต์ · ส่งถึงช่องทางแล้ว',value:2},{label:'โพสต์ · ส่งไม่สำเร็จ',value:1}]
    : view==='members' ? filtered
    : view==='trials' ? filtered.filter(r=>r.trial).map(r=>({...r,trialStatus:activeTrial(r.trial??null)?'ACTIVE':r.trial?.revokedAt?'REVOKED':'EXPIRED'}))
    : view==='audit' ? (await trials.history()).filter(r=>ids.has(r.userId)).map(r=>({...r,email:members.find(m=>m.id===r.userId)?.email}))
    : view==='deletions' ? (await accountDeletions.history()).filter(r=>!options.query||r.userId===options.query)
    : view==='reports' ? filtered.filter(r=>options.reportScope==='ALL_ACCOUNTS'||r.trial).map(r=>{
      const i=members.findIndex(found=>found.id===r.id);const latest=options.reportScope!=='ALL_ACCOUNTS';
      const usageFrom=latest?new Date(Math.max(Date.parse(r.trial!.startsAt),options.from?.getTime()??-Infinity)).toISOString():window.from;
      const usageUntil=latest?new Date(Math.min(Date.parse(window.until),Date.parse(r.trial!.expiresAt),r.trial!.revokedAt?Date.parse(r.trial!.revokedAt):Infinity)).toISOString():window.until;
      const included=(!usageFrom||Date.parse(time)>=Date.parse(usageFrom))&&Date.parse(time)<Date.parse(usageUntil);
      return {userId:r.id,email:r.email,plan:r.trial?.plan??null,startsAt:r.trial?.startsAt??null,expiresAt:r.trial?.expiresAt??null,revokedAt:r.trial?.revokedAt??null,usageFrom,usageUntil,
        captionRequests:included?i:0,editMinutes:included?i*2:0,quotaPostUnits:included?i+4:0,postUnits:included?i+3:0,livePostUnits:included?i+1:0,draftPostUnits:included?1:0,otherDeliveredPostUnits:0,failedPostUnits:included?1:0,pendingPostUnits:0,estimatedUsd:null,purchasedPlanNow:r.paidPlan};})
    : view==='channels' ? filtered.map((r,i)=>({id:`connection-${i}`,email:r.email,platform:i%2?'YOUTUBE_SHORTS':'TIKTOK',displayName:r.displayName,connectedAt:time,status:'ข้อมูลตัวอย่าง · ไม่ได้เชื่อมบัญชีจริง'}))
    : people.flatMap((r,i)=>{
      const result=[{platform:'TIKTOK',status:'PUBLISHED',deliveryOutcome:'DRAFT'},
        {platform:'YOUTUBE_SHORTS',status:'PUBLISHED',deliveryOutcome:'LIVE'},
        {platform:'TIKTOK',status:'FAILED',deliveryOutcome:null}][i];
      return ids.has(r.id)?[{id:`post-${i}`,email:r.email,caption:'ตัวอย่างโพสต์สำหรับตรวจหน้าผู้ดูแล',...result,channels:adminChannelResult(result),createdAt:time,scheduledAt:null,help:result.status==='FAILED'?'ตัวอย่าง: ตรวจบนช่องทางก่อนส่งซ้ำ':''}]:[];
    })
        .filter(r=>(!options.status||r.status===options.status)&&(!options.platform||r.platform===options.platform));
  const sum=(key:string)=>rows.reduce((total,row)=>total+Number((row as Record<string,unknown>)[key]??0),0);
  const summary:AdminReportSummary|undefined=view==='reports'?{memberCount:rows.length,captionRequests:sum('captionRequests'),editMinutes:sum('editMinutes'),quotaPostUnits:sum('quotaPostUnits'),postUnits:sum('postUnits'),
    livePostUnits:sum('livePostUnits'),draftPostUnits:sum('draftPostUnits'),otherDeliveredPostUnits:sum('otherDeliveredPostUnits'),failedPostUnits:sum('failedPostUnits'),pendingPostUnits:sum('pendingPostUnits'),estimatedUsd:null}:undefined;
  return { rows, total:rows.length,asOf:asOf.toISOString(),window,...(view==='reports'?{reportScope:options.reportScope??'LATEST_TRIAL',summary}:{}), note:view==='reports'?'รายงานจำลอง ไม่มีค่าใช้จ่ายจริง':view==='overview'||view==='posts'?'ส่งถึงช่องทางแล้วรวมการส่งเป็นร่างด้วย · ข้อมูลตัวอย่าง ไม่ได้โพสต์จริง':undefined };
} };
const previewToken = viewer ? 'fixture-viewer' : 'fixture-owner';
registerAdminConsole(app,{config:{origin:`http://127.0.0.1:${port}`,environment:'LOCAL',ownerUids:['fixture-owner'],viewerUids:['fixture-viewer'],
  firebaseWeb:{apiKey:'fixture',authDomain:'fixture.firebaseapp.com',projectId:'fixture',appId:'fixture'}},data,trials,testOnly:true,testPreviewToken:previewToken,
  incidents:createMemoryServiceIncidentStore(),support,notifySupportReply:async()=>undefined,
  // Fixture deletion only removes the in-memory sample member.
  accountDeletions,deleteAccount:async userId=>{const index=members.findIndex(r=>r.id===userId);if(index>=0)members.splice(index,1);return {status:200,body:{status:'ok'}};},
  authenticate:(req,res,next)=>{const id=req.get('authorization')?.replace('Bearer ','');
    if(!['fixture-owner','fixture-viewer'].includes(id??'')){res.sendStatus(401);return;}
    res.locals.authUser={id,provider:'firebase',email:`${id}@example.com`,authenticatedAtSeconds:Date.now()/1000};next();}});
const server=app.listen(port,'127.0.0.1');
server.once('listening',()=>process.stdout.write(`LOCAL fixture admin: http://127.0.0.1:${port}/admin\n`));
server.once('error',error=>{process.stderr.write(`Local fixture could not listen on 127.0.0.1:${port}: ${error.message}\n`);process.exitCode=1;});
