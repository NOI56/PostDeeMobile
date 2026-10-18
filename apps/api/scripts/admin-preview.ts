// Local fixture only: no databases, credentials, cloud services or real member records.
import express from 'express';
import { randomUUID } from 'node:crypto';
import { registerAdminConsole } from '../src/modules/admin/adminRoutes.js';
import { activeTrial, createMemoryTrialAccessStore } from '../src/modules/admin/trialAccess.js';
import type { AdminDataSource, AdminMember, AdminView } from '../src/modules/admin/adminDataSource.js';

const app = express(); app.use(express.json({ limit: '16kb' }));
const viewer = process.argv.includes('--viewer'); const port = viewer ? 4175 : 4174;
const trials = createMemoryTrialAccessStore();
const time = new Date().toISOString();
const members: AdminMember[] = [
  { id:'fixture-mali',email:'mali@example.com',displayName:'Mali S.',paidPlan:'BASIC',createdAt:time,updatedAt:time,postCount:12,channelCount:2 },
  { id:'fixture-narin',email:'narin@example.com',displayName:'Narin P.',paidPlan:'STARTER',createdAt:time,updatedAt:time,postCount:28,channelCount:3 },
  { id:'fixture-ploy',email:'ploy@example.com',displayName:'Ploy K.',paidPlan:'PRO',createdAt:time,updatedAt:time,postCount:43,channelCount:4 }
];
await trials.mutate({ requestId:randomUUID(),actorId:'fixture-owner',userId:'fixture-mali',action:'GRANT',plan:'PRO',days:7,reason:'ข้อมูลจำลองสำหรับตรวจหน้าจอ',expectedVersion:0 });
const member = async (id: string): Promise<AdminMember | null> => { const found=members.find(r=>r.id===id); return found ? {...found,trial:await trials.find(id)} : null; };
const data: AdminDataSource = { member, view: async (view: AdminView, options) => {
  const people=await Promise.all(members.map(r=>member(r.id))).then(rows=>rows.filter((r):r is AdminMember=>!!r));
  const filtered=people.filter(r=>`${r.email} ${r.displayName}`.toLowerCase().includes(options.query.toLowerCase()));
  const ids=new Set(filtered.map(r=>r.id));
  const rows = view==='overview' ? [{label:'สมาชิกทั้งหมด',value:people.length},{label:'แพ็กเกจที่ซื้อยังใช้งานได้',value:2},
    {label:'สิทธิ์ทดลองที่ใช้งานอยู่',value:people.filter(r=>activeTrial(r.trial??null)).length},{label:'โพสต์ส่งสำเร็จ',value:64}]
    : view==='members' ? filtered
    : view==='trials' ? filtered.filter(r=>r.trial).map(r=>({...r,trialStatus:activeTrial(r.trial??null)?'ACTIVE':r.trial?.revokedAt?'REVOKED':'EXPIRED'}))
    : view==='audit' ? (await trials.history()).filter(r=>ids.has(r.userId)).map(r=>({...r,email:members.find(m=>m.id===r.userId)?.email}))
    : view==='reports' ? filtered.filter(r=>r.trial).map(r=>({userId:r.id,email:r.email,plan:r.trial!.plan,startsAt:r.trial!.startsAt,expiresAt:r.trial!.expiresAt,
      captionRequests:0,editMinutes:0,postUnits:0,estimatedUsd:null,purchasedPlanNow:r.paidPlan}))
    : view==='channels' ? filtered.map((r,i)=>({id:`connection-${i}`,email:r.email,platform:i%2?'YOUTUBE_SHORTS':'TIKTOK',displayName:r.displayName,connectedAt:time,status:'ข้อมูลตัวอย่าง · ไม่ได้เชื่อมบัญชีจริง'}))
    : filtered.flatMap((r,i)=>[{id:`post-${i}`,email:r.email,caption:'ตัวอย่างโพสต์สำหรับตรวจหน้าผู้ดูแล',status:i%2?'FAILED':'PUBLISHED',platform:i%2?'TIKTOK':'YOUTUBE_SHORTS',channels:i%2?'TikTok: ส่งไม่สำเร็จ':'YouTube Shorts: เผยแพร่แล้ว',createdAt:time,scheduledAt:null,help:i%2?'ตัวอย่าง: ต้องเชื่อมบัญชีใหม่':''}])
        .filter(r=>(!options.status||r.status===options.status)&&(!options.platform||r.platform===options.platform));
  return { rows, total:rows.length, note:view==='reports'?'รายงานจำลอง ไม่มีค่าใช้จ่ายจริง':undefined };
} };
const previewToken = viewer ? 'fixture-viewer' : 'fixture-owner';
registerAdminConsole(app,{config:{origin:`http://127.0.0.1:${port}`,environment:'LOCAL',ownerUids:['fixture-owner'],viewerUids:['fixture-viewer'],
  firebaseWeb:{apiKey:'fixture',authDomain:'fixture.firebaseapp.com',projectId:'fixture',appId:'fixture'}},data,trials,testOnly:true,testPreviewToken:previewToken,
  authenticate:(req,res,next)=>{const id=req.get('authorization')?.replace('Bearer ','');
    if(!['fixture-owner','fixture-viewer'].includes(id??'')){res.sendStatus(401);return;}
    res.locals.authUser={id,provider:'firebase',email:`${id}@example.com`,authenticatedAtSeconds:Date.now()/1000};next();}});
app.listen(port,'127.0.0.1',()=>process.stdout.write(`LOCAL fixture admin: http://127.0.0.1:${port}/admin\n`));
