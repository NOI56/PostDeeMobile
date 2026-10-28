const app = document.querySelector('#app');
const names = { overview:'ภาพรวม', incidents:'สถานะระบบ', support:'แชทช่วยเหลือ', members:'สมาชิก', posts:'โพสต์', trials:'สิทธิ์ทดลอง', channels:'ช่องทางที่เชื่อม', reports:'รายงาน', audit:'ประวัติผู้ดูแล', deletions:'ประวัติการลบบัญชี' };
const paths = { overview:'M3 11 12 3l9 8M5 10v11h5v-7h4v7h5V10', incidents:'M12 3 2 20h20L12 3M12 10v4M12 17h.01',support:'M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.7A8 8 0 1 1 21 12M8 10h8M8 14h5',members:'M20 21v-2a7 7 0 0 0-14 0v2M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0', posts:'M6 3h12a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2M8 8h8M8 12h8M8 16h4', trials:'M9 3h6M10 3v7l-5 9q-1 2 2 2h10q3 0 2-2l-5-9V3M8 15h8', channels:'M10 13a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-2 2M14 11a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l2-2', reports:'M5 21V12M12 21V3M19 21V8', audit:'M12 8v5l4 2M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0', deletions:'M3 6h18M8 6V4h8v2M6 6l1 14h10l1-14M10 11v6M14 11v6' };
const labels = { BASIC:'ฟรี', STARTER:'Starter', PRO:'Pro', ACTIVE:'ใช้งานอยู่', NOT_STARTED:'ยังไม่เริ่ม', EXPIRED:'หมดอายุ', REVOKED:'ยกเลิกแล้ว', DRAFT:'ร่าง', QUEUED:'รอส่ง', PUBLISHING:'กำลังส่ง', PUBLISHED:'ส่งถึงช่องทางแล้ว', PARTIAL_PUBLISHED:'ส่งถึงบางช่องทาง', FAILED:'ส่งไม่สำเร็จ', GRANT:'ให้สิทธิ์', EXTEND:'ต่อเวลา', REVOKE:'ยกเลิกสิทธิ์', TIKTOK:'TikTok', YOUTUBE_SHORTS:'YouTube Shorts', INSTAGRAM_REELS:'Instagram Reels', FACEBOOK_REELS:'Facebook Reels', PENDING:'ยังไม่เสร็จ · ลองใหม่ได้', COMPLETED:'ลบเรียบร้อย', INVESTIGATING:'กำลังตรวจสอบ', IDENTIFIED:'พบสาเหตุ · กำลังแก้ไข', MONITORING:'แก้แล้ว · กำลังติดตามผล', RESOLVED:'ปิดประกาศแล้ว', WAITING_TEAM:'รอทีมงานตอบ', WAITING_MEMBER:'รอลูกค้า', CLOSED:'ปิดเรื่องแล้ว', MEMBER:'ลูกค้า', TEAM:'ทีมงาน', BOT:'Dot (AI)' };
const messages = { ADMIN_ACCESS_DENIED:'บัญชีนี้ยังไม่ได้รับสิทธิ์ผู้ดูแล PostDee', ADMIN_OWNER_REQUIRED:'เฉพาะเจ้าของระบบสามารถเปลี่ยนสิทธิ์ทดลองได้', ADMIN_REAUTH_REQUIRED:'กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่ เพื่อยืนยันตัวตนก่อนเปลี่ยนสิทธิ์', ADMIN_MEMBER_CHANGED:'อีเมลบัญชีเปลี่ยนแล้ว กรุณาค้นหาสมาชิกและตรวจสอบใหม่', ADMIN_TRIAL_CHANGED:'สิทธิ์มีการเปลี่ยนแปลง กรุณาปิดหน้าต่างแล้วโหลดข้อมูลล่าสุดก่อน', ADMIN_TRIAL_ALREADY_ACTIVE:'บัญชีนี้มีสิทธิ์ทดลองอยู่แล้ว ใช้การต่อเวลาแทน', ADMIN_TRIAL_NOT_ACTIVE:'ไม่พบสิทธิ์ทดลองที่ยังใช้งานอยู่', ADMIN_TRIAL_EXTENSION_LIMIT:'ต่อเวลาได้ไม่เกิน 90 วันนับจากวันนี้', ADMIN_TRIAL_INVALID:'กรุณาระบุแพ็กเกจ ระยะเวลา และเหตุผลอย่างน้อย 3 ตัวอักษร', ADMIN_REQUEST_CONFLICT:'หมายเลขคำขอนี้ใช้กับข้อมูลอื่นแล้ว กรุณาตรวจประวัติก่อน', ADMIN_TRIAL_UNAVAILABLE:'ยังยืนยันผลการเปลี่ยนสิทธิ์ไม่ได้ ใช้ปุ่มตรวจผลคำขอเดิม หรือตรวจประวัติผู้ดูแล', ADMIN_DATA_UNAVAILABLE:'ยังโหลดข้อมูลไม่ได้ กรุณาลองใหม่', ADMIN_FILTER_INVALID:'ตัวกรองหรือช่วงวันที่ไม่ถูกต้อง', ADMIN_MEMBER_NOT_FOUND:'ไม่พบบัญชีสมาชิกนี้แล้ว',
  ADMIN_DELETION_INVALID:'กรุณาพิมพ์ยืนยันให้ตรง และระบุเหตุผล 3–500 ตัวอักษรโดยไม่มีอีเมล', ADMIN_DELETE_PROTECTED:'ลบบัญชีผู้ดูแลระบบจากหน้านี้ไม่ได้', ADMIN_ACCOUNT_DELETION_UNAVAILABLE:'ยังยืนยันผลการลบไม่ได้ ใช้ปุ่มลองอีกครั้งด้วยคำขอเดิม หรือตรวจประวัติการลบบัญชี',
  ACCOUNT_DELETION_UNAVAILABLE:'ระบบลบบัญชียังปิดอยู่บนเซิร์ฟเวอร์นี้ ยังไม่มีข้อมูลใดถูกลบ', ACCOUNT_DELETION_AUTHORIZATION_UNAVAILABLE:'บันทึกการยืนยันการลบไม่สำเร็จ ยังไม่มีข้อมูลใดถูกลบ ลองอีกครั้งด้วยคำขอเดิม', ACCOUNT_WRITE_DRAIN_FAILED:'บัญชีนี้มีงานที่ยังทำไม่เสร็จ รอสักครู่แล้วลองอีกครั้งด้วยคำขอเดิม', ACCOUNT_UPLOADS_DRAINING:'มีวิดีโอกำลังอัปโหลดเสร็จ รอสักครู่แล้วลองอีกครั้งด้วยคำขอเดิม',
  ACCOUNT_MEDIA_CLEANUP_UNAVAILABLE:'ระบบลบวิดีโอยังไม่พร้อม ยังไม่มีข้อมูลใดถูกลบ', ACCOUNT_SOCIAL_CLEANUP_UNAVAILABLE:'ระบบถอดการเชื่อมต่อโซเชียลยังไม่พร้อม ยังไม่มีข้อมูลใดถูกลบ', ACCOUNT_SOCIAL_CLEANUP_FAILED:'ถอดการเชื่อมต่อโซเชียลยังไม่ครบ ข้อมูลบัญชียังอยู่ ลองอีกครั้งด้วยคำขอเดิม', ACCOUNT_PUBLISH_CLEANUP_FAILED:'ยกเลิกโพสต์ที่รอส่งยังไม่ครบ ลองอีกครั้งด้วยคำขอเดิม',
  ACCOUNT_MEDIA_CLEANUP_FAILED:'ลบวิดีโอยังไม่ครบ ลองอีกครั้งด้วยคำขอเดิม', ACCOUNT_IDENTITY_DELETE_FAILED:'ลบข้อมูลแล้ว แต่ยังลบการเข้าสู่ระบบไม่สำเร็จ ลองอีกครั้งด้วยคำขอเดิม', ACCOUNT_UPLOAD_STATE_CLEANUP_FAILED:'ลบเกือบเสร็จแล้ว ลองอีกครั้งด้วยคำขอเดิม',
  ADMIN_INCIDENT_INVALID:'กรุณาใส่หัวข้อ 3–80 ตัวอักษร (บรรทัดเดียว) ข้อความถึงลูกค้า 3–500 ตัวอักษร และเลือกสถานะ', ADMIN_INCIDENT_LIMIT:'มีประกาศที่ยังเปิดอยู่ครบ 5 เรื่องแล้ว ปิดเรื่องที่แก้แล้วก่อนสร้างใหม่', ADMIN_INCIDENT_CHANGED:'ประกาศนี้ถูกแก้ไขโดยผู้ดูแลคนอื่นแล้ว ปิดหน้าต่างแล้วโหลดข้อมูลล่าสุดก่อน', ADMIN_INCIDENT_RESOLVED:'ประกาศนี้ปิดแล้ว หากปัญหากลับมาให้สร้างประกาศใหม่', ADMIN_INCIDENT_NOT_FOUND:'ไม่พบประกาศนี้แล้ว', ADMIN_INCIDENT_UNAVAILABLE:'ยังยืนยันการบันทึกประกาศไม่ได้ กดบันทึกอีกครั้ง ระบบจะไม่สร้างประกาศซ้ำ',
  ADMIN_SUPPORT_THREAD_NOT_FOUND:'ไม่พบแชทนี้แล้ว บัญชีอาจถูกลบ', ADMIN_SUPPORT_THREAD_CHANGED:'ลูกค้าส่งข้อความใหม่ระหว่างนั้น อ่านข้อความล่าสุดก่อนปิดเรื่อง', ADMIN_SUPPORT_UNAVAILABLE:'ยังส่งหรือโหลดแชทไม่ได้ กดส่งอีกครั้ง ระบบจะไม่ส่งซ้ำ', ADMIN_SUPPORT_MEMBER_DELETING:'บัญชีนี้กำลังถูกลบ ตอบแชทไม่ได้แล้ว', SUPPORT_MESSAGE_INVALID:'พิมพ์คำตอบ 1–1,000 ตัวอักษร', SUPPORT_MESSAGE_CONFLICT:'คำตอบนี้ถูกแก้หลังส่งไม่สำเร็จ กดส่งอีกครั้งเพื่อส่งเป็นข้อความใหม่', ADMIN_SUPPORT_BOT_UNCONFIGURED:'เซิร์ฟเวอร์ยังไม่ได้ตั้งค่า SUPPORT_BOT_PROVIDER และ OpenAI จึงเปิด Dot ไม่ได้' };
const incidentPlatforms = ['TIKTOK','YOUTUBE_SHORTS','INSTAGRAM_REELS','FACEBOOK_REELS'];
const platformsText = list => list?.length ? list.map(translate).join(', ') : 'ทั้งแอป';
const h = (tag, attributes = {}, ...children) => { const e = document.createElement(tag); for(const [k,v] of Object.entries(attributes)) {
  if(k.startsWith('on')) e.addEventListener(k.slice(2),v); else if(v !== false && v != null) e.setAttribute(k,String(v)); }
  for(const c of children.flat(Infinity)) if(c != null) e.append(c instanceof Node ? c : document.createTextNode(String(c))); return e; };
const icon = key => { const s=document.createElementNS('http://www.w3.org/2000/svg','svg'); s.setAttribute('viewBox','0 0 24 24'); s.setAttribute('fill','none'); s.setAttribute('stroke','currentColor'); s.setAttribute('stroke-width','1.7'); s.setAttribute('stroke-linecap','round'); s.setAttribute('stroke-linejoin','round'); s.setAttribute('aria-hidden','true'); const p=document.createElementNS(s.namespaceURI,'path'); p.setAttribute('d',paths[key]||paths.members); s.append(p); return s; };
const button = (text, action, cls='', attributes={}) => h('button',{type:'button',class:cls,onclick:action,...attributes},text);
const translate = v => v === '' ? '—' : labels[v] ?? v ?? '—';
const when = value => value ? new Intl.DateTimeFormat('th-TH',{dateStyle:'medium',timeStyle:'short',timeZone:'Asia/Bangkok'}).format(new Date(value)) : '—';
const whenUtc = value => new Intl.DateTimeFormat('th-TH',{dateStyle:'medium',timeStyle:'short',timeZone:'UTC'}).format(new Date(value));
const trialActive = t => t && !t.revokedAt && Date.parse(t.startsAt)<=Date.now() && Date.parse(t.expiresAt)>Date.now();
const trialText = t => !t ? 'ไม่มี' : t.revokedAt ? 'ยกเลิกแล้ว' : Date.parse(t.startsAt)>Date.now() ? 'ยังไม่เริ่ม' : !trialActive(t) ? 'หมดอายุ' : `${translate(t.plan)} · เหลือ ${Math.ceil((Date.parse(t.expiresAt)-Date.now())/86400000)} วัน`;
let boot, auth, firebase, currentUser, previewToken, session, epoch=0, loadEpoch=0, view='members', page={rows:[]}, query='', appliedQuery='', cursor, status='', platform='', from='', through='', reportScope='ALL_ACCOUNTS', error='', success='', busy=false, csvBusy=false, selected=null, drawerAction='DETAIL', selectedPlan='PRO', days=7, reason='', deleteConfirm='', reviewing=false, pending=null, controllers=new Set(), readController=null, refreshTimer=null, refreshFailed=false, refreshReset=false, loadedFilters=null, editing=null, chat=null, chatTimer=null;
let supportPendingCount=null, supportCountFailed=false, supportCountTimer=null, supportCountController=null, supportCountEpoch=0;
const api = async (path, body, csv=false, controller=new AbortController()) => { const captured=epoch; controllers.add(controller);
  try { const token=previewToken || await currentUser?.getIdToken(); if(!token) throw new Error('กรุณาเข้าสู่ระบบ');
    if(captured!==epoch) throw new Error('บัญชีเปลี่ยนแล้ว');
    const r=await fetch(`/admin/api/${path}`,{ method:body?'POST':'GET',headers:{Authorization:`Bearer ${token}`,...(body?{'Content-Type':'application/json','X-PostDee-Admin':'1'}:{})},body:body?JSON.stringify(body):undefined,signal:controller.signal,cache:'no-store'});
    if(captured!==epoch) throw new Error('บัญชีเปลี่ยนแล้ว');let data;
    try{data=csv&&r.ok?await r.text():await r.json();}catch{const failure=new Error(r.status===429?'โหลดข้อมูลบ่อยเกินไป กรุณารอสักครู่แล้วลองใหม่':r.status===401?'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่':r.status===403?'บัญชีนี้ไม่มีสิทธิ์เข้าถึงข้อมูล':'ยังโหลดข้อมูลไม่ได้ กรุณาลองใหม่');failure.status=r.status;throw failure;}
    if(captured!==epoch || controller.signal.aborted) throw new Error('บัญชีเปลี่ยนแล้วหรือยกเลิกการโหลด');
    if(!r.ok) { const failure=new Error(messages[data.code] || `ดำเนินการไม่ได้ (${r.status})`); failure.status=r.status; failure.code=data.code; throw failure; } return data;
  } catch(e) { if(e.name==='TypeError')throw new Error('เชื่อมต่อระบบไม่ได้ กรุณาตรวจอินเทอร์เน็ตแล้วลองใหม่');throw e; }
  finally { controllers.delete(controller); }
};
const logout = async () => { epoch++; loadEpoch++; stopSupportCount();supportPendingCount=null;supportCountFailed=false;clearInterval(refreshTimer); refreshTimer=null; controllers.forEach(c=>c.abort()); controllers.clear(); readController=null; currentUser=null; previewToken=null; session=null; page={rows:[]}; loadedFilters=null; selected=null; editing=null; chat=null; clearInterval(chatTimer); chatTimer=null; pending=null; reason='';deleteConfirm='';busy=false;csvBusy=false;refreshFailed=false;refreshReset=false;
  if(auth) await firebase.signOut(auth); renderLogin(); };
async function login() { const generation=++epoch;error=''; renderLogin(true); try {
  if(boot.previewToken) previewToken=boot.previewToken;
  else { const [{initializeApp}, sdk]=await Promise.all([import('https://www.gstatic.com/firebasejs/13.0.0/firebase-app.js'),import('https://www.gstatic.com/firebasejs/13.0.0/firebase-auth.js')]);
    firebase=sdk; auth ||= sdk.getAuth(initializeApp(boot.firebaseWeb)); await sdk.setPersistence(auth,sdk.inMemoryPersistence);
    currentUser=(await sdk.signInWithPopup(auth,new sdk.GoogleAuthProvider())).user; }
  if(generation!==epoch)return;session=await api('session');if(generation!==epoch)return;await load();syncRefreshClock();syncSupportCountClock();
} catch(e) { if(generation!==epoch)return;error=e.message; currentUser=null; previewToken=null; session=null; if(auth) await firebase.signOut(auth); renderLogin(); } }
function renderLogin(loading=false) { document.body.classList.remove('has-drawer'); app.removeAttribute('aria-busy');
  app.replaceChildren(h('main',{class:'login'},h('section',{class:'login-panel'},h('div',{class:'brand'},'PostDee'),h('h1',{},'เข้าสู่ระบบผู้ดูแล'),
    h('p',{class:'notice'},'จัดการสมาชิก สิทธิ์ทดลอง และตรวจผลโพสต์ด้วยบัญชีที่ได้รับสิทธิ์'),h('div',{class:'environment'},boot?.previewToken?'LOCAL · ข้อมูลตัวอย่าง':boot?.environment||'กำลังโหลด'),
    error?h('p',{class:'error',role:'alert'},error):null,button(loading?'กำลังเข้าสู่ระบบ…':boot?.previewToken?'เปิดข้อมูลตัวอย่าง':'เข้าสู่ระบบด้วย Google',login,'primary',{disabled:loading}),
    h('p',{class:'footer-note'},'บัญชี Google ทั่วไปจะเข้าถึงข้อมูลผู้ดูแลไม่ได้')))); }
const filters = () => ({ view, query:appliedQuery, ...(cursor?{cursor}:{}), ...(status?{status}:{}), ...(platform?{platform}:{}), ...(from?{from}:{}), ...(through?{through}:{}), ...(view==='reports'?{reportScope}:{}) });
const refreshPaused = (automatic=false) => !session || document.hidden || busy || csvBusy || !!readController || !!selected || !!editing || !!chat || reviewing || !!pending ||
  (automatic && ['INPUT','TEXTAREA','SELECT'].includes(document.activeElement?.tagName?.toUpperCase()));
function updateFreshness() { const node=app.querySelector('.refresh-status');if(!node)return;
  const stamp=page.asOf||page.checkedAt;const stale=refreshFailed || (stamp && Date.now()-Date.parse(stamp)>=120000);
  node.classList.toggle('stale',!!stale);node.replaceChildren(document.createTextNode(`${stale?'ข้อมูลอาจไม่เป็นปัจจุบัน · ':''}${stamp?'อ้างอิงข้อมูลเมื่อ '+when(stamp):'ยังไม่มีข้อมูลที่ยืนยันแล้ว'} · ${selected||editing||chat||reviewing||pending||csvBusy?'พักการรีเฟรชระหว่างทำรายการ':'อัปเดตอัตโนมัติทุก 60 วินาทีเมื่อเปิดดูหน้านี้'}`));
  const refreshButton=app.querySelector('.refresh-button');if(refreshButton)refreshButton.disabled=refreshPaused();
}
function syncRefreshClock() { clearInterval(refreshTimer);refreshTimer=null;
  if(session&&!document.hidden)refreshTimer=setInterval(()=>{updateFreshness();void refreshData(true);},60000);
}
// This small read updates only the badge, including while a reply or form is open.
// Opening a thread does not clear it: it counts conversations waiting for the team.
function paintSupportBadge(node=app.querySelector('.support-badge')) {
  if(!node)return;const positive=supportPendingCount>0;
  node.replaceChildren(document.createTextNode(positive?(supportPendingCount>99?'99+':String(supportPendingCount)):supportCountFailed?'!':''));
  const label=supportCountFailed?`ยังอัปเดตจำนวนแชทไม่ได้${positive?` · ยืนยันล่าสุด ${supportPendingCount} เรื่องรอทีมงานตอบ`:''}`:`${supportPendingCount??0} เรื่องรอทีมงานตอบ`;
  node.setAttribute('aria-label',label);node.setAttribute('title',label);node.classList.toggle('stale',supportCountFailed);
  if(positive||supportCountFailed)node.removeAttribute('hidden');else node.setAttribute('hidden','');
}
function supportBadge() { const node=h('span',{class:'support-badge',role:'status','aria-live':'polite','aria-atomic':'true'});paintSupportBadge(node);return node; }
function stopSupportCount() { clearInterval(supportCountTimer);supportCountTimer=null;supportCountEpoch++;supportCountController?.abort();supportCountController=null; }
async function refreshSupportCount() {
  if(!session||document.hidden||supportCountController)return;
  const generation=epoch,ticket=++supportCountEpoch,controller=new AbortController();supportCountController=controller;
  const timeout=setTimeout(()=>controller.abort(),10000);
  try { const data=await api('support/pending-count',undefined,false,controller);
    if(generation!==epoch||ticket!==supportCountEpoch||controller.signal.aborted)return;
    if(!Number.isSafeInteger(data.count)||data.count<0)throw new Error('Invalid support count');
    supportPendingCount=data.count;supportCountFailed=false;paintSupportBadge();
  } catch { if(generation===epoch&&ticket===supportCountEpoch&&session&&!document.hidden){supportCountFailed=true;paintSupportBadge();} }
  finally { clearTimeout(timeout);if(supportCountController===controller)supportCountController=null; }
}
function syncSupportCountClock() { stopSupportCount();if(session&&!document.hidden){void refreshSupportCount();supportCountTimer=setInterval(()=>{void refreshSupportCount();},30000);} }
function refreshSupportCountAfterChange() { supportCountEpoch++;supportCountController?.abort();supportCountController=null;void refreshSupportCount(); }
document.addEventListener('visibilitychange',()=>{updateFreshness();syncRefreshClock();syncSupportCountClock();});
async function refreshData(automatic=false) { if(refreshPaused(automatic))return;return load(false,{refresh:true,automatic}); }
async function load(append=false, options={}) { if(csvBusy || (options.refresh&&refreshPaused(options.automatic)))return;
  readController?.abort();const controller=new AbortController();readController=controller;
  const ticket=++loadEpoch;const generation=epoch;const request={...filters(),...(options.cursor?{cursor:options.cursor}:{}),...(options.refresh?{cursor:undefined}:{})};
  const hadLaterPages=!!cursor;busy=true;error='';if(!options.automatic)render();else updateFreshness();
  try { const result=await api('view',request,false,controller);if(ticket!==loadEpoch||generation!==epoch)return;
    page=append?{...result,rows:[...page.rows,...result.rows]}:result;cursor=request.cursor;loadedFilters=request;refreshFailed=false;refreshReset=!!options.refresh&&hadLaterPages;
  } catch(e) { if(ticket===loadEpoch&&generation===epoch&&!controller.signal.aborted){error=e.message;refreshFailed=true;} }
  finally { if(ticket===loadEpoch&&generation===epoch){readController=null;busy=false;render();} }
}
function navigate(next) { if(pending||csvBusy||editing||chat)return; view=next; selected=null; reviewing=false; page={rows:[]};loadedFilters=null;cursor=undefined;status='';platform='';from='';through='';success='';refreshFailed=false;refreshReset=false;
  if(next==='reports'){const today=new Date().toISOString().slice(0,10);from=today.slice(0,7)+'-01';through=today;reportScope='ALL_ACCOUNTS';}return load(); }
const fieldSelect = (caption, items, value, onChange) => { const e=h('select',{disabled:csvBusy,onchange:event=>{if(!csvBusy)return onChange(event.target.value);}},items.map(([id,name])=>h('option',{value:id,selected:id===value},name))); return h('label',{},caption,e); };
async function openMember(member) { if(busy||csvBusy)return;readController?.abort();readController=null;const ticket=++loadEpoch;const generation=epoch;busy=true;error='';render();try {
 if(pending)throw new Error('กรุณาตรวจผลคำขอเดิมให้เสร็จก่อนเปลี่ยนสิทธิ์รายการอื่น');
 const result=await api('member',{userId:member.id});if(ticket!==loadEpoch||generation!==epoch)return;
 selected=result.member;drawerAction='DETAIL';reason='';deleteConfirm='';reviewing=false;pending=null;
 }catch(e){if(ticket===loadEpoch&&generation===epoch)error=e.message;}finally{if(ticket===loadEpoch&&generation===epoch){busy=false;render();}} }
function closeDrawer() { if(pending||busy)return; selected=null;reviewing=false;error='';render();document.querySelector('.text')?.focus(); }
function startTrial(action) { if(pending||busy||session.role!=='OWNER')return;drawerAction=action;selectedPlan=trialActive(selected.trial)?selected.trial.plan:'PRO';days=7;reason='';reviewing=false;error='';render(); }
function memberDetails() { if(pending||busy)return;drawerAction='DETAIL';reviewing=false;error='';render(); }
// Members who signed in by phone may have no email; they confirm with the UID.
const deletionConfirmation = member => member?.email || member?.id || '';
const deletionReady = () => { const r=reason.trim();return !!selected&&!!deleteConfirm.trim()&&deleteConfirm.trim().toLowerCase()===deletionConfirmation(selected).toLowerCase()&&r.length>=3&&r.length<=500&&!r.includes('@'); };
function startDeletion() { if(pending||busy||session.role!=='OWNER'||!selected)return;drawerAction='DELETE';deleteConfirm='';reason='';reviewing=false;error='';render(); }
const retryPending = () => pending?.kind==='DELETE' ? submitDeletion() : submitTrial();
function clearFilters() { if(csvBusy)return;query='';appliedQuery='';status='';platform='';from='';through='';cursor=undefined;return load(); }
function emptyState() {
 if(busy)return h('div',{class:'empty',role:'status'},'กำลังโหลดข้อมูล…');
 if(error)return h('div',{class:'empty'},h('h2',{},'ยังยืนยันข้อมูลไม่ได้'),h('p',{},'ลองโหลดข้อมูลอีกครั้ง'),button('ลองใหม่',()=>load()));
 if(appliedQuery.trim()||(['posts','reports','support'].includes(view)&&(status||platform||from||through)))return h('div',{class:'empty',role:'status'},
   h('h2',{},'ไม่พบข้อมูลที่ตรงกับการค้นหาหรือตัวกรอง'),h('p',{},'ลองเปลี่ยนคำค้น หรือดูรายการทั้งหมด'),button('ล้างการค้นหาและตัวกรอง',clearFilters));
 const copy={
   members:['ยังไม่มีสมาชิก','สมาชิกจะแสดงเมื่อมีบัญชีเข้ามาใช้งาน PostDee'],
   posts:['ยังไม่มีโพสต์','โพสต์จะแสดงหลังสมาชิกสร้างหรือส่งโพสต์จากแอป'],
   trials:['ยังไม่มีสิทธิ์ทดลอง','เปิดหน้าสมาชิกเพื่อตรวจบัญชี แล้วเลือกให้สิทธิ์ทดลอง'],
   reports:reportScope==='LATEST_TRIAL'?['ยังไม่มีรายงานช่วงทดลองล่าสุด','เลือกทุกบัญชีเพื่อดูการใช้งานของสมาชิกที่ไม่ได้รับสิทธิ์ทดลอง']:['ยังไม่มีรายงานการใช้งาน','รายงานแสดงทุกบัญชีที่ตรงกับการค้นหาและช่วงวันที่ แม้ยังไม่ได้รับสิทธิ์ทดลอง'],
   audit:['ยังไม่มีประวัติการจัดการสิทธิ์','ประวัติจะแสดงเมื่อผู้ดูแลยืนยันให้สิทธิ์ ต่อเวลา หรือยกเลิกสิทธิ์ทดลอง'],
   channels:['ยังไม่มีช่องทางที่เชื่อม','ช่องทางจะแสดงหลังสมาชิกเชื่อมบัญชีโซเชียลจากแอป'],
   deletions:['ยังไม่มีประวัติการลบบัญชี','ประวัติจะแสดงเมื่อเจ้าของระบบลบบัญชีตามคำขอของสมาชิก'],
   support:['ยังไม่มีแชท','ข้อความที่ลูกค้าส่งจากเมนูแชทกับทีมงานในแอปจะแสดงที่นี่'],
   incidents:['ระบบปกติ · ยังไม่มีประกาศ',session.role==='OWNER'?'เมื่อแอปมีปัญหา กดสร้างประกาศใหม่ ลูกค้าจะเห็นแถบแจ้งบนหน้าแรกของแอป':'เจ้าของระบบเป็นผู้สร้างประกาศเมื่อแอปมีปัญหา']
 };
 const [title,detail]=copy[view];
 return h('div',{class:'empty',role:'status'},h('h2',{},title),h('p',{},view==='trials'&&session.role!=='OWNER'?'เจ้าของระบบสามารถให้สิทธิ์ทดลองจากหน้าสมาชิกได้':detail),
   ['trials','reports'].includes(view)?button('ดูสมาชิก',()=>navigate('members')):null);
}
function table() {
 const definitions={members:[['member','สมาชิก'],['paidPlan','แพ็กเกจที่ซื้อ'],['trial','สิทธิ์ทดลอง'],['updatedAt','อัปเดตข้อมูลล่าสุด']],
 trials:[['member','สมาชิก'],['paidPlan','แพ็กเกจที่ซื้อ'],['trial','สิทธิ์ทดลอง'],['trialStatus','สถานะ']],
 posts:[['email','สมาชิก'],['caption','แคปชัน'],['status','สถานะ'],['channels','ผลแต่ละช่องทาง'],['failureReason','สาเหตุที่บันทึก'],['createdAt','สร้างเมื่อ'],['scheduledAt','ตั้งเวลา'],['help','แนวทางตรวจสอบ']],
 channels:[['email','สมาชิก'],['platform','ช่องทาง'],['displayName','ชื่อบัญชี'],['status','สถานะที่บันทึก'],['connectedAt','เชื่อมเมื่อ']],
 reports:[['email','สมาชิก'],['purchasedPlanNow','แพ็กเกจที่ซื้อปัจจุบัน'],
   ...((page.reportScope||reportScope)==='LATEST_TRIAL'?[['plan','ทดลองล่าสุด'],['startsAt','เริ่มทดลอง'],['expiresAt','สิ้นสุดทดลอง']]:[]),
   ['captionRequests','AI แคปชัน (ครั้ง)'],['editMinutes','AI ตัดต่อ (นาที)'],['quotaPostUnits','หน่วยช่องทางที่เลือก'],['postUnits','ผลส่งที่บันทึก'],
   ['livePostUnits','เผยแพร่สาธารณะ'],['draftPostUnits','ส่งเป็นร่าง'],['otherDeliveredPostUnits','ส่งถึงแบบอื่น/ไม่ทราบการมองเห็น'],['failedPostUnits','ส่งไม่สำเร็จ'],['pendingPostUnits','รอส่ง/กำลังส่ง'],['estimatedUsd','ต้นทุนประมาณ (USD)']],
 audit:[['createdAt','เมื่อ'],['actorId','รหัสผู้ดูแล'],['email','สมาชิก'],['action','การจัดการ'],['plan','แพ็กเกจ'],['reason','เหตุผล'],['before','ก่อนเปลี่ยน'],['after','หลังเปลี่ยน']],
 deletions:[['createdAt','เริ่มเมื่อ'],['userId','รหัสบัญชี (UID)'],['status','สถานะ'],['lastErrorCode','ผลล่าสุด'],['completedAt','ลบเสร็จเมื่อ'],['actorId','รหัสผู้ดูแล'],['reason','เหตุผล']],
 support:[['status','สถานะ'],['supportMember','สมาชิก'],['lastPreview','ข้อความล่าสุด'],['lastSender','ล่าสุดจาก'],['lastMessageAt','เมื่อ'],['supportAction','']],
 incidents:[['stage','สถานะ'],['title','หัวข้อ'],['message','ข้อความถึงลูกค้า'],['platforms','ช่องทางที่กระทบ'],['startedAt','เริ่มเมื่อ'],['updatedAt','อัปเดตล่าสุด'],['resolvedAt','ปิดเมื่อ'],...(session.role==='OWNER'?[['incidentAction','จัดการ']]:[])]};
 const cols=definitions[view]||[];
 if(!page.rows.length)return emptyState();
 const cell=(row,key)=> { if(key==='member')return button(h('span',{},h('span',{class:'member-name'},row.displayName||row.email),h('div',{class:'member-email'},row.email)),()=>openMember(row),'text');
   if(key==='supportMember')return h('span',{},h('span',{class:'member-name'},row.displayName||row.email||'บัญชีที่ไม่มีอีเมล'),h('div',{class:'member-email'},row.email||row.userId));
   if(key==='lastPreview')return h('span',{class:'pre-line'},row.lastPreview);
   if(key==='supportAction')return button('เปิดแชท',()=>openChat(row.userId),row.status==='WAITING_TEAM'?'primary':'');
   if(view==='support'&&key==='status')return h('span',{},translate(row.status),row.teamRequested?h('div',{class:'team-flag'},'ลูกค้าขอคุยกับทีมงาน'):null);
   if(view==='incidents'&&(key==='title'||key==='message'))return h('span',{class:'pre-line'},row[key]);
   if(key==='platforms')return platformsText(row.platforms); if(key==='resolvedAt'&&!row.resolvedAt)return 'ยังเปิดอยู่';
   if(key==='incidentAction')return row.resolvedAt?'—':button('อัปเดต / ปิดประกาศ',()=>openIncident(row));
   if(key==='trial')return trialText(row.trial); if(key==='estimatedUsd')return row[key]==null?'ยังไม่ได้ตั้งอัตรา':Number(row[key]).toFixed(4);
   if(['createdAt','updatedAt','scheduledAt','connectedAt','startsAt','expiresAt','completedAt','startedAt','resolvedAt','lastMessageAt'].includes(key))return when(row[key]);
   if(key==='lastErrorCode')return row[key]?messages[row[key]]||row[key]:'—';
   if(key==='before'||key==='after'){const t=row[key];return t?`${translate(t.plan)} · ${when(t.expiresAt)}${t.revokedAt?' · ยกเลิก':''}`:'ไม่มี';}
   return translate(row[key]); };
 return h('div',{class:'table-wrap',tabindex:0,'aria-label':'ตารางข้อมูล เลื่อนแนวนอนได้'},h('table',{class:view},h('thead',{},h('tr',{},cols.map(([,caption])=>h('th',{scope:'col'},caption)))),
   h('tbody',{},page.rows.map(row=>h('tr',{class:selected&&selected.id===row.id?'chosen':''},cols.map(([key])=>h('td',{},cell(row,key))))))));
}
function render() { if(!session)return renderLogin();const focusedSearch=document.activeElement?.getAttribute('data-focus')==='search';const selection=focusedSearch?[document.activeElement.selectionStart,document.activeElement.selectionEnd]:null;
 document.body.classList.toggle('has-drawer',!!selected||!!editing||!!chat); app.setAttribute('aria-busy',busy?'true':'false');
 const side=h('aside',{class:'sidebar'},h('div',{class:'brand'},'PostDee'),button('เมนู',()=>side.classList.toggle('open'),'menu-toggle',{'aria-label':'เปิดเมนูผู้ดูแล'}),
   h('nav',{class:'nav','aria-label':'เมนูผู้ดูแล'},Object.entries(names).map(([id,name])=>button(h('span',{},icon(id),h('span',{},name),id==='support'?supportBadge():null),()=>navigate(id),id===view?'selected':'',{'aria-current':id===view?'page':false,disabled:!!pending||csvBusy}))),
   h('div',{class:'role'},icon('members'),h('span',{},session.role==='OWNER'?'เจ้าของระบบ':'ผู้ดูแล · ดูข้อมูล')));
 const searchLabel=view==='deletions'?'ค้นหารหัสบัญชี (UID)':'ค้นหาชื่อหรืออีเมล';
 const q=h('input',{type:'search',placeholder:searchLabel,value:query,maxlength:120,disabled:csvBusy,'data-focus':'search','aria-label':searchLabel,oninput:e=>{if(!csvBusy)query=e.target.value;}});
 const form=h('form',{class:'search',onsubmit:e=>{e.preventDefault();if(csvBusy)return;appliedQuery=query;cursor=undefined;return load();}},h('label',{},q),h('button',{type:'submit',class:'primary',disabled:busy||csvBusy},'ค้นหา'));
 const content=h('section',{class:'content','aria-label':names[view]},success?h('p',{class:'success',role:'status'},success):null,error?h('div',{class:'error',role:'alert'},h('p',{},error),refreshFailed?button('ลองโหลดใหม่',()=>refreshData(),'',{disabled:refreshPaused()}):null):null);
 content.append(h('div',{class:'data-freshness'},h('p',{class:'refresh-status',role:'status','aria-live':'polite'}),button('รีเฟรชข้อมูล',()=>refreshData(),'refresh-button',{disabled:refreshPaused()})));
 if(refreshFailed&&loadedFilters)content.append(h('p',{class:'notice',role:'status'},'แสดงข้อมูลที่ยืนยันล่าสุด การโหลดข้อมูลหรือตัวกรองใหม่ยังไม่สำเร็จ'));
 if(refreshReset)content.append(h('p',{class:'notice',role:'status'},'อัปเดตข้อมูลแล้ว · แสดงหน้าแรกเพื่อไม่รวมรายการจากคนละรอบข้อมูล'));
 if(pending&&!selected)content.append(h('p',{class:'notice'},pending.kind==='DELETE'?'มีคำขอลบบัญชีที่ยังยืนยันผลไม่ได้ ตรวจคำขอเดิมก่อนทำรายการใหม่':'มีคำขอเปลี่ยนสิทธิ์ที่ยังยืนยันผลไม่ได้ ตรวจคำขอเดิมก่อนทำรายการใหม่'),button('ตรวจผลคำขอเดิม',retryPending,'primary',{disabled:busy}));
 if(!['overview','incidents'].includes(view))content.append(form);
 if(view==='incidents'&&page.signals)content.append(signalsPanel(page.signals));
 if(view==='incidents')content.append(h('p',{class:'notice'},'ประกาศที่ยังเปิดอยู่จะแสดงเป็นแถบแจ้งบนหน้าแรกของแอปให้ลูกค้าทุกคนเห็น เมื่อเปิดหรือรีเฟรชหน้าแรก · ห้ามใส่อีเมล ชื่อ หรือข้อมูลของลูกค้าในประกาศ'),
   session.role==='OWNER'?button('สร้างประกาศใหม่',()=>openIncident(),'primary',{disabled:busy||!!pending}):h('p',{class:'notice'},'บัญชีผู้ดูแลนี้ดูประกาศได้อย่างเดียว'));
 if(view==='support'&&page.bot){const bot=page.bot;const configured=bot.provider!=='off';
   content.append(h('section',{class:'bot-card','aria-label':'ผู้ช่วย AI Dot'},h('div',{},h('h2',{},`Dot ผู้ช่วย AI · ${bot.enabled?'เปิดอยู่':'ปิดอยู่'}`),
     h('p',{class:'notice'},!configured?'เซิร์ฟเวอร์นี้ยังไม่ได้ตั้งค่า SUPPORT_BOT_PROVIDER จึงยังเปิด Dot ไม่ได้'
       :bot.enabled?`Dot ตอบลูกค้าก่อนจากประกาศสถานะ คำถามที่พบบ่อย และผลโพสต์ล่าสุดของลูกค้า แล้วส่งต่อทีมงานเมื่อไม่แน่ใจ${bot.updatedAt?' · เปลี่ยนล่าสุด '+when(bot.updatedAt):''}`
       :'เมื่อเปิด ข้อความแชทของลูกค้าจะถูกส่งให้ OpenAI ประมวลผล ตรวจว่านโยบายความเป็นส่วนตัวแจ้งเรื่องนี้แล้วก่อนเปิด')),
     session.role==='OWNER'&&configured?button(bot.enabled?'ปิด Dot':'เปิด Dot',toggleBotGlobal,bot.enabled?'danger':'primary',{disabled:busy}):null));}
 if(view==='support')content.append(h('div',{class:'filters'},fieldSelect('สถานะ',[['','ทั้งหมด'],...['WAITING_TEAM','WAITING_MEMBER','CLOSED'].map(id=>[id,translate(id)])],status,v=>{status=v;cursor=undefined;load();})),
   h('p',{class:'notice'},'ลูกค้าเห็นคำตอบในแชทของแอปและได้รับการแจ้งเตือน · ลูกค้าไม่เห็นว่าผู้ดูแลคนไหนตอบ · ห้ามขอรหัสผ่านหรือข้อมูลบัตรจากลูกค้า'));
 if(view==='posts')content.append(h('div',{class:'filters'},
   fieldSelect('สถานะ',[['','ทั้งหมด'],...['DRAFT','QUEUED','PUBLISHING','PUBLISHED','PARTIAL_PUBLISHED','FAILED'].map(id=>[id,translate(id)])],status,v=>{status=v;cursor=undefined;load();}),
   fieldSelect('ช่องทาง',[['','ทั้งหมด'],...['TIKTOK','YOUTUBE_SHORTS','INSTAGRAM_REELS','FACEBOOK_REELS'].map(id=>[id,translate(id)])],platform,v=>{platform=v;cursor=undefined;load();}),
   h('label',{},'ตั้งแต่ (UTC)',h('input',{type:'date',value:from,disabled:csvBusy,onchange:e=>{if(csvBusy)return;from=e.target.value;cursor=undefined;load();}})),
   h('label',{},'ถึง (UTC)',h('input',{type:'date',value:through,disabled:csvBusy,onchange:e=>{if(csvBusy)return;through=e.target.value;cursor=undefined;load();}}))));
 if(view==='reports'){
   const scope=fieldSelect('ขอบเขตรายงาน',[['ALL_ACCOUNTS','ทุกบัญชี'],['LATEST_TRIAL','ช่วงทดลองล่าสุด']],reportScope,value=>{reportScope=value;cursor=undefined;return load();});scope.querySelector('select').setAttribute('aria-label','ขอบเขตรายงาน');
   content.append(h('div',{class:'filters report-filters'},scope,
     h('label',{},'ตั้งแต่ (UTC)',h('input',{type:'date',value:from,disabled:csvBusy,'aria-label':'รายงานตั้งแต่ (UTC)',onchange:e=>{if(csvBusy)return;from=e.target.value;cursor=undefined;return load();}})),
     h('label',{},'ถึง (UTC)',h('input',{type:'date',value:through,disabled:csvBusy,'aria-label':'รายงานถึง (UTC)',onchange:e=>{if(csvBusy)return;through=e.target.value;cursor=undefined;return load();}})),button('ล้างช่วงวันที่',()=>{if(csvBusy)return;from='';through='';cursor=undefined;return load();},'',{disabled:busy||csvBusy})));
   const scopeShown=page.reportScope||reportScope;
   content.append(h('p',{class:'notice'},scopeShown==='LATEST_TRIAL'?'เฉพาะช่วงทดลองล่าสุดของแต่ละบัญชีที่ตรงเงื่อนไข ตัดช่วงตามวันที่เลือกและวันยกเลิก/หมดอายุ ไม่รวมประวัติทดลองช่วงก่อน':'ทุกบัญชีที่ตรงเงื่อนไข รวมบัญชีฟรีและบัญชีที่ซื้อแพ็กเกจ แม้ไม่เคยได้รับสิทธิ์ทดลอง'));
   if(page.window)content.append(h('p',{class:'notice'},`ช่วงข้อมูล (UTC): ${page.window.from?whenUtc(page.window.from)+' (รวมเวลาเริ่ม)':'ตั้งแต่เริ่มบันทึก'} ถึง ${whenUtc(page.window.until)} (ไม่รวมเวลาสิ้นสุด)`));
   content.append(h('p',{class:'notice'},'หน่วยช่องทางที่เลือกนับตามโพสต์ที่สร้าง รวมร่างและรายการที่ยังไม่ส่ง ไม่ใช่ยอดเผยแพร่สำเร็จ · ผลส่งที่บันทึกแยกเผยแพร่สาธารณะ ร่าง การมองเห็นแบบอื่น ส่งไม่สำเร็จ และรอส่ง'));
   if(page.summary){const metrics=[['memberCount','บัญชีที่ตรงเงื่อนไข'],['captionRequests','AI แคปชัน (ครั้ง)'],['editMinutes','AI ตัดต่อ (นาที)'],['quotaPostUnits','หน่วยช่องทางที่เลือก'],['postUnits','ผลส่งที่บันทึก'],['livePostUnits','เผยแพร่สาธารณะ'],['draftPostUnits','ส่งเป็นร่าง'],['otherDeliveredPostUnits','ส่งถึงแบบอื่น/ไม่ทราบการมองเห็น'],['failedPostUnits','ส่งไม่สำเร็จ'],['pendingPostUnits','รอส่ง/กำลังส่ง'],['estimatedUsd','ต้นทุนประมาณ (USD)']];
     content.append(h('section',{class:'report-totals','aria-label':'ยอดรวมรายงาน'},h('h2',{},scopeShown==='LATEST_TRIAL'?'ยอดรวมช่วงทดลองล่าสุดที่ตรงเงื่อนไข · ทุกหน้า':'ยอดรวมทุกบัญชีที่ตรงเงื่อนไข · ทุกหน้า'),h('div',{class:'summary'},metrics.map(([key,label])=>h('div',{class:'summary-item'},h('div',{class:'muted'},label),h('div',{class:`summary-value${key==='estimatedUsd'&&page.summary[key]==null?' text-value':''}`},key==='estimatedUsd'?(page.summary[key]==null?'ยังไม่ได้ตั้งอัตรา':Number(page.summary[key]).toFixed(4)):page.summary[key]??'—'))))));
   }
 }
 if(view==='overview')content.append(h('div',{class:'summary'},page.rows.map(r=>h('div',{class:'summary-item'},h('div',{class:'muted'},r.label),h('div',{class:'summary-value'},r.value)))));
 else {const count=page.total!=null?`แสดง ${page.rows.length} จาก ${page.total} ${view==='members'?'สมาชิก':'รายการ'}`:`${page.rows.length} รายการ${view==='reports'?'ในหน้านี้':'ที่โหลด'}`;
   content.append(h('div',{class:'tools'},h('p',{class:'count'},busy?'กำลังโหลด…':count),view==='reports'?button(csvBusy?'กำลังเตรียม CSV…':'ดาวน์โหลด CSV หน้านี้',downloadCsv,'',{disabled:busy||csvBusy||!page.rows.length,'aria-describedby':!busy&&!page.rows.length?'csv-help':null}):null),table());
   if(view==='reports'&&!busy&&!page.rows.length)content.append(h('p',{class:'notice',id:'csv-help'},'ดาวน์โหลด CSV ได้เมื่อหน้านี้มีข้อมูล ลองตรวจช่วงวันที่และขอบเขตรายงาน'));}
 if(view==='reports')content.append(h('p',{class:'notice'},'CSV อ่านข้อมูลล่าสุดตามตัวกรองของหน้านี้อีกครั้ง ยอดอาจเปลี่ยนจากหน้าจอหากมีการใช้งานเพิ่ม'));
 if(page.nextCursor)content.append(button('โหลดรายการถัดไป',()=>load(view!=='reports',{cursor:page.nextCursor}),'next',{disabled:busy||csvBusy}));
 if(page.note)content.append(h('p',{class:'notice'},page.note));
 content.append(h('p',{class:'footer-note'},`${boot.previewToken?'ข้อมูลตัวอย่างสำหรับตรวจหน้าจอ · ':''}แสดงเวลาประเทศไทย · ตัวกรองและช่วงรายงานใช้ UTC${page.checkedAt?' · โหลดข้อมูลเมื่อ '+when(page.checkedAt):''}`));
 app.replaceChildren(h('div',{class:'shell'},side,h('main',{class:'workspace'},h('header',{class:'topbar'},h('h1',{},names[view]),h('div',{class:'right'},
   h('span',{class:`environment ${session.environment==='PRODUCTION'?'production':''}`},boot.previewToken?'LOCAL · ตัวอย่าง':session.environment),button('ออกจากระบบ',logout))),content)));
 if(selected){app.querySelector('.shell').inert=true;renderDrawer();}
 else if(editing){app.querySelector('.shell').inert=true;renderIncidentDrawer();}
 else if(chat){app.querySelector('.shell').inert=true;renderChatDrawer();}
 else if(focusedSearch){q.focus({preventScroll:true});if(selection)q.setSelectionRange?.(...selection);}
 updateFreshness();
}
function renderDrawer() { const active=trialActive(selected.trial); const viewer=session.role!=='OWNER';const details=viewer||drawerAction==='DETAIL';
 const title=details?'ข้อมูลสมาชิก':drawerAction==='DELETE'?(reviewing?'ยืนยันการลบบัญชี':'ลบบัญชีสมาชิก'):reviewing?'ตรวจสอบสิทธิ์':({GRANT:'ให้สิทธิ์ทดลอง',EXTEND:'ต่อเวลาทดลอง',REVOKE:'ยกเลิกสิทธิ์ทดลอง'})[drawerAction];
 const drawer=h('section',{class:'drawer',role:'dialog','aria-modal':'true','aria-label':title},h('header',{},h('h2',{},title),button('×',closeDrawer,'close',{'aria-label':'ปิดรายละเอียด',disabled:!!pending})));
 drawer.append(h('span',{class:'label'},'บัญชีที่เลือก'),h('div',{class:'identity'},selected.email),h('p',{class:'context'},`แพ็กเกจที่ซื้อ: ${translate(selected.paidPlan)} · ทดลอง: ${trialText(selected.trial)}`));
 if(selected.monthKey)drawer.append(h('p',{class:'notice'},`การใช้เดือน ${selected.monthKey} (UTC): หน่วยช่องทางที่เลือก ${selected.quotaPostUnits??selected.postUnits} · AI แคปชัน ${selected.captionRequests} ครั้ง · AI ตัดต่อ ${selected.editMinutes} นาที · หน่วยที่เลือกไม่ใช่ยอดเผยแพร่สำเร็จ`));
 if(details){drawer.append(h('p',{class:'notice'},`สมัครเมื่อ ${when(selected.createdAt)} · โพสต์ ${selected.postCount??0} รายการ · เชื่อม ${selected.channelCount??0} ช่องทาง`));
   if(selected.paidExpiresAt)drawer.append(h('p',{class:'notice'},`วันสิ้นสุดแพ็กเกจที่ซื้อที่บันทึกไว้: ${when(selected.paidExpiresAt)}`));
   if(selected.trial)drawer.append(h('p',{class:'notice'},`ช่วงทดลอง: ${when(selected.trial.startsAt)} ถึง ${when(selected.trial.expiresAt)}`));
   if(viewer)drawer.append(h('p',{class:'notice'},'บัญชีผู้ดูแลนี้มีสิทธิ์ดูข้อมูลเท่านั้น'));
   else {drawer.append(h('p',{class:'notice'},'การเปิดข้อมูลสมาชิกยังไม่เปลี่ยนสิทธิ์ เลือกการจัดการด้านล่างเมื่อต้องการทำรายการ'));
     drawer.append(h('div',{class:'stack'},...(active?[button('ต่อเวลาทดลอง',()=>startTrial('EXTEND'),'primary'),button('ยกเลิกสิทธิ์ทดลอง',()=>startTrial('REVOKE'),'danger')]:[button('ให้สิทธิ์ทดลอง',()=>startTrial('GRANT'),'primary')])));
     drawer.append(h('div',{class:'stack'},h('p',{class:'notice'},'ใช้เมื่อสมาชิกขอลบบัญชี และยืนยันแล้วว่าคำขอมาจากเจ้าของบัญชี'),button('ลบบัญชีนี้',startDeletion,'danger')));}
   drawer.append(h('div',{class:'drawer-actions'},button('ปิด',closeDrawer)));
 }
 else if(drawerAction==='DELETE'&&reviewing){drawer.append(h('div',{class:'review'},h('p',{},'ลบบัญชีถาวร'),h('p',{},selected.email||selected.id),h('p',{},`รหัสบัญชี: ${selected.id}`),h('p',{},`เหตุผล: ${reason.trim()}`)));
   if(error)drawer.append(h('p',{class:'error',role:'alert'},error));
   drawer.append(h('p',{class:'notice'},'ข้อมูลจะถูกลบทันทีและกู้คืนไม่ได้ · ไม่ยกเลิกแพ็กเกจในร้านค้า · บันทึกในประวัติการลบบัญชี'),h('div',{class:'drawer-actions'},button('กลับไปแก้ไข',()=>{reviewing=false;render();},'',{disabled:busy||!!pending}),button(busy?'กำลังลบ…':pending?'ลองอีกครั้งด้วยคำขอเดิม':'ลบบัญชีถาวร',submitDeletion,'danger',{disabled:busy})));}
 else if(drawerAction==='DELETE'){const expected=deletionConfirmation(selected);
   const review=button('ตรวจสอบก่อนลบ',()=>{if(!deletionReady())return;error='';reviewing=true;render();},'danger',{disabled:!deletionReady()});
   const sync=()=>{review.disabled=!deletionReady();};
   const confirm=h('input',{type:'text',value:deleteConfirm,autocomplete:'off',spellcheck:'false','data-focus':'delete-confirm','aria-label':`พิมพ์ ${expected} เพื่อยืนยัน`,oninput:e=>{deleteConfirm=e.target.value;sync();}});
   const reasonInput=h('textarea',{maxlength:500,minlength:3,required:true,placeholder:'เช่น คำขอทางอีเมลวันที่ 26 ต.ค. (ห้ามใส่อีเมลหรือชื่อลูกค้า)','aria-label':'เหตุผล',oninput:e=>{reason=e.target.value;sync();}},reason);
   drawer.append(h('p',{class:'error'},'ลบบัญชีถาวร ย้อนกลับไม่ได้'),h('p',{class:'notice'},'ลบโพสต์ เทมเพลต วิดีโอ หน้าเว็บร้านค้า การเชื่อมต่อโซเชียล และการเข้าสู่ระบบของสมาชิก · ไม่ยกเลิกแพ็กเกจใน Google Play / App Store'),
     h('div',{class:'stack'},h('label',{},h('span',{class:'label'},`พิมพ์ ${expected} เพื่อยืนยัน`),confirm),h('label',{},h('span',{class:'label'},'เหตุผล (ห้ามมีอีเมล)'),reasonInput)));
   if(error)drawer.append(h('p',{class:'error',role:'alert'},error));
   drawer.append(h('div',{class:'drawer-actions'},button('กลับไปข้อมูลสมาชิก',memberDetails),review));}
 else if(reviewing){drawer.append(h('div',{class:'review'},h('p',{},`${translate(drawerAction)} · ${translate(selectedPlan)}`),drawerAction!=='REVOKE'?h('p',{},`${days} วัน${drawerAction==='EXTEND'?' ต่อจากวันสิ้นสุดเดิม':' นับจากเวลายืนยัน'}`):h('p',{},'ยกเลิกเฉพาะสิทธิ์ทดลอง แพ็กเกจที่ซื้อยังคงเดิม'),h('p',{},`เหตุผล: ${reason}`)));
   if(error)drawer.append(h('p',{class:'error',role:'alert'},error));
   drawer.append(h('p',{class:'notice'},'ไม่รีเซ็ตโควตา · ไม่เรียกเก็บเงินอัตโนมัติ'),h('div',{class:'drawer-actions'},button('กลับไปแก้ไข',()=>{reviewing=false;render();},'',{disabled:busy||!!pending}),button(busy?'กำลังตรวจผล…':pending?'ตรวจผลคำขอเดิม':'ยืนยัน',submitTrial,drawerAction==='REVOKE'?'danger':'primary',{disabled:busy})));}
 else {const plan=fieldSelect('แพ็กเกจ',[['STARTER','Starter'],['PRO','Pro']],selectedPlan,v=>selectedPlan=v); plan.className='stack';if(drawerAction!=='GRANT')plan.querySelector('select').disabled=true;
   const radios=h('div',{class:'durations'},[7,14,30].map(n=>h('label',{class:'duration'},h('input',{type:'radio',name:'days',value:n,checked:n===days,onchange:()=>days=n}),`${n} วัน`)));
   const reasonInput=h('textarea',{maxlength:500,minlength:3,required:true,placeholder:'ระบุเหตุผลในการให้สิทธิ์ทดลอง','aria-label':'เหตุผล',oninput:e=>{reason=e.target.value;e.target.setCustomValidity('');}},reason);
   drawer.append(h('div',{class:'stack'},plan,drawerAction==='REVOKE'?h('p',{class:'notice'},'สิทธิ์ทดลองจะหยุดทันที แพ็กเกจที่ซื้อยังคงเดิม'):h('fieldset',{},h('legend',{},'ระยะเวลา'),radios),h('label',{},h('span',{class:'label'},'เหตุผล'),reasonInput)));
   if(error)drawer.append(h('p',{class:'error',role:'alert'},error));
   drawer.append(h('p',{class:'notice'},'ไม่รีเซ็ตโควตา · ไม่เรียกเก็บเงินอัตโนมัติ'),h('div',{class:'drawer-actions'},button('กลับไปข้อมูลสมาชิก',memberDetails),button('ตรวจสอบสิทธิ์',()=>{if(reason.trim().length<3){reasonInput.setCustomValidity('ระบุเหตุผลอย่างน้อย 3 ตัวอักษร');reasonInput.reportValidity();return;} error='';reviewing=true;render();},'primary')));
 }
 if(pending&&!busy){const deletion=pending.kind==='DELETE';drawer.append(button(deletion?'ดูประวัติการลบบัญชี':'ดูประวัติผู้ดูแล',()=>{selected=null;view=deletion?'deletions':'audit';query=deletion?pending.userId:pending.expectedEmail;appliedQuery=query;cursor=undefined;load();}));}
 const backdrop=h('div',{class:'drawer-backdrop',onclick:closeDrawer}); app.append(backdrop,drawer);
 drawer.querySelector('button:not(:disabled),select:not(:disabled),input:not(:disabled),textarea:not(:disabled)')?.focus();
 drawer.addEventListener('keydown',e=>{if(e.key==='Escape')closeDrawer();if(e.key==='Tab'){const focusable=[...drawer.querySelectorAll('button,input,select,textarea')].filter(n=>!n.disabled);const first=focusable[0],last=focusable.at(-1);if(e.shiftKey&&document.activeElement===first){e.preventDefault();last?.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus();}}});
}
// A create keeps one browser-made id until the server confirms, so pressing save again replays instead of posting twice.
// Sentry areas with errors in the last window. Dot sees only the area label;
// the issue titles and links here are for administrators.
function signalsPanel(snapshot) {
 if(!snapshot.configured)return h('section',{class:'signals'},h('h2',{},'สัญญาณอัตโนมัติจาก Sentry'),
   h('p',{class:'notice'},'ยังไม่ได้ตั้งค่า SENTRY_SIGNALS_TOKEN บนเซิร์ฟเวอร์ Dot จึงยังไม่รู้ข้อผิดพลาดของระบบโดยอัตโนมัติ'));
 const rows=snapshot.signals.map(s=>h('div',{class:'signal'},h('div',{},h('strong',{},s.label),h('div',{class:'muted'},`พบล่าสุด ${when(s.lastSeen)} · ${s.issues.length} ปัญหาใน Sentry`),
   h('ul',{},s.issues.map(i=>h('li',{},i.permalink?h('a',{href:i.permalink,target:'_blank',rel:'noopener noreferrer'},`${i.shortId} · ${i.title}`):`${i.shortId} · ${i.title}`)))),
   session.role==='OWNER'?button('สร้างประกาศจากสัญญาณนี้',()=>openIncident(null,{title:`${s.label} มีปัญหาชั่วคราว`.slice(0,80),platforms:s.platform?[s.platform]:[]}),'',{disabled:busy||!!pending}):null));
 return h('section',{class:'signals'},h('h2',{},'สัญญาณอัตโนมัติจาก Sentry'),
   h('p',{class:'notice'},snapshot.failed?'อ่านข้อมูลจาก Sentry ไม่สำเร็จ ตรวจ token และสิทธิ์ event:read':
     rows.length?'Dot ใช้ชื่อส่วนที่มีปัญหาเพื่อแจ้งลูกค้าว่าระบบตรวจพบข้อผิดพลาด (ไม่ส่งรายละเอียด error) ยืนยันกับลูกค้าด้วยการสร้างประกาศ':
     'ไม่พบข้อผิดพลาดใหม่ในช่วงล่าสุด'),...rows);
}
function openIncident(row, draft) { if(busy||csvBusy||pending||editing||session.role!=='OWNER')return;
 editing=row?{action:'UPDATE',id:row.id,expectedVersion:row.version,title:row.title,message:row.message,platforms:[...row.platforms],stage:row.stage}
   :{action:'CREATE',id:crypto.randomUUID(),title:draft?.title??'',message:'',platforms:draft?.platforms??[],stage:'INVESTIGATING'};
 reviewing=false;error='';success='';render(); }
function closeIncident() { if(busy)return; editing=null;reviewing=false;error='';render(); }
const incidentReady = () => { const t=editing.title.trim(),m=editing.message.trim(); return t.length>=3&&t.length<=80&&!/[\r\n]/.test(t)&&m.length>=3&&m.length<=500; };
function renderIncidentDrawer() { const creating=editing.action==='CREATE';
 const title=reviewing?(creating?'ตรวจสอบก่อนประกาศ':'ตรวจสอบการเปลี่ยนแปลง'):creating?'สร้างประกาศใหม่':'อัปเดตประกาศ';
 const drawer=h('section',{class:'drawer',role:'dialog','aria-modal':'true','aria-label':title},h('header',{},h('h2',{},title),button('×',closeIncident,'close',{'aria-label':'ปิดหน้าต่างประกาศ',disabled:busy})));
 if(reviewing){drawer.append(h('span',{class:'label'},'ตัวอย่างที่ลูกค้าจะเห็นบนหน้าแรกของแอป'),
     h('div',{class:'review incident-preview'},h('p',{class:'muted'},translate(editing.stage)),h('p',{class:'incident-title'},editing.title.trim()),
       h('p',{class:'pre-line'},editing.message.trim()),h('p',{class:'muted'},`ช่องทางที่กระทบ: ${platformsText(editing.platforms)}`)));
   if(editing.stage==='RESOLVED')drawer.append(h('p',{class:'notice'},'เมื่อปิดประกาศ แถบแจ้งจะหายจากแอปของลูกค้า และแก้ไขประกาศนี้อีกไม่ได้'));
   if(error)drawer.append(h('p',{class:'error',role:'alert'},error));
   drawer.append(h('div',{class:'drawer-actions'},button('กลับไปแก้ไข',()=>{reviewing=false;error='';render();},'',{disabled:busy}),
     button(busy?'กำลังบันทึก…':creating?'ประกาศถึงลูกค้า':editing.stage==='RESOLVED'?'ปิดประกาศ':'บันทึกการเปลี่ยนแปลง',submitIncident,'primary',{disabled:busy})));}
 else {const review=button('ตรวจสอบก่อนบันทึก',()=>{if(!incidentReady())return;error='';reviewing=true;render();},'primary',{disabled:!incidentReady()});
   const sync=()=>{review.disabled=!incidentReady();};
   const titleInput=h('input',{type:'text',value:editing.title,maxlength:80,autocomplete:'off',placeholder:'เช่น TikTok ส่งคลิปช้ากว่าปกติ','aria-label':'หัวข้อ',oninput:e=>{editing.title=e.target.value;sync();}});
   const messageInput=h('textarea',{maxlength:500,placeholder:'เกิดอะไรขึ้น กระทบอะไร และลูกค้าควรทำอย่างไร เช่น โพสต์ที่ตั้งเวลาไว้จะส่งต่ออัตโนมัติ ไม่ต้องส่งซ้ำ','aria-label':'ข้อความถึงลูกค้า',oninput:e=>{editing.message=e.target.value;sync();}},editing.message);
   const stage=fieldSelect('สถานะ',(creating?['INVESTIGATING','IDENTIFIED','MONITORING']:['INVESTIGATING','IDENTIFIED','MONITORING','RESOLVED']).map(id=>[id,translate(id)]),editing.stage,v=>{editing.stage=v;});stage.className='stack';
   const platforms=h('fieldset',{},h('legend',{},'ช่องทางที่กระทบ (ไม่เลือก = ทั้งแอป)'),h('div',{class:'platform-options'},incidentPlatforms.map(id=>h('label',{class:'duration'},
     h('input',{type:'checkbox',value:id,checked:editing.platforms.includes(id),onchange:e=>{editing.platforms=e.target.checked?[...editing.platforms,id]:editing.platforms.filter(p=>p!==id);}}),translate(id)))));
   drawer.append(h('div',{class:'stack'},h('label',{},h('span',{class:'label'},'หัวข้อ (บรรทัดเดียว 3–80 ตัวอักษร)'),titleInput),h('label',{},h('span',{class:'label'},'ข้อความถึงลูกค้า (3–500 ตัวอักษร)'),messageInput),stage,platforms),
     h('p',{class:'notice'},'ลูกค้าทุกคนเห็นข้อความนี้ ห้ามใส่อีเมล ชื่อ หรือข้อมูลของลูกค้า'));
   if(error)drawer.append(h('p',{class:'error',role:'alert'},error));
   drawer.append(h('div',{class:'drawer-actions'},button('ยกเลิก',closeIncident),review));}
 const backdrop=h('div',{class:'drawer-backdrop',onclick:closeIncident}); app.append(backdrop,drawer);
 drawer.querySelector('input:not(:disabled),button:not(:disabled)')?.focus();
 drawer.addEventListener('keydown',e=>{if(e.key==='Escape')closeIncident();if(e.key==='Tab'){const focusable=[...drawer.querySelectorAll('button,input,select,textarea')].filter(n=>!n.disabled);const first=focusable[0],last=focusable.at(-1);if(e.shiftKey&&document.activeElement===first){e.preventDefault();last?.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus();}}});
}
async function submitIncident(){ if(busy||csvBusy||!editing||session.role!=='OWNER')return;const generation=epoch;const {action,id,expectedVersion,title,message,platforms,stage}=editing;
 busy=true;error='';render();
 try{await api('incidents',{action,id,...(action==='UPDATE'?{expectedVersion}:{}),title:title.trim(),message:message.trim(),platforms,stage});if(generation!==epoch)return;
   success=action==='CREATE'?'ประกาศแล้ว · ลูกค้าจะเห็นแถบแจ้งเมื่อเปิดหรือรีเฟรชหน้าแรกของแอป':stage==='RESOLVED'?'ปิดประกาศแล้ว · แถบแจ้งจะหายจากแอปของลูกค้า':'บันทึกการเปลี่ยนแปลงแล้ว';
   editing=null;reviewing=false;busy=false;await load();}
 catch(e){if(generation!==epoch)return;error=e.message;busy=false;render();}}
// The open conversation polls every 10 seconds and repaints only its message
// log, so a reply being typed is never redrawn away.
let chatNodes=null;
async function openChat(userId) { if(busy||csvBusy||pending||editing||chat)return;const generation=epoch;busy=true;error='';success='';render();
 try{const data=await api('support/thread',{userId});if(generation!==epoch)return;
   chat={userId,...data,botGlobal:!!page.bot?.enabled,draft:'',outgoing:null,error:'',sending:false,refreshing:false};
   chatTimer=setInterval(()=>{void refreshChat();},10000);
 }catch(e){if(generation===epoch)error=e.message;}finally{if(generation===epoch){busy=false;render();}} }
function closeChat() { if(!chat||chat.sending)return;clearInterval(chatTimer);chatTimer=null;chat=null;chatNodes=null;error='';return load(); }
async function refreshChat() { if(!chat||chat.sending||chat.refreshing||document.hidden)return;const current=chat;const generation=epoch;current.refreshing=true;
 try{const data=await api('support/thread',{userId:current.userId});if(generation!==epoch||chat!==current)return;
   const changed=data.thread.lastMessageId!==current.thread.lastMessageId||data.thread.status!==current.thread.status||!!current.error;
   Object.assign(current,{thread:data.thread,messages:data.messages,hasEarlier:data.hasEarlier,member:data.member,error:''});
   if(changed)paintChat();
 }catch(e){if(generation===epoch&&chat===current){current.error=e.message;paintChat();}}
 finally{current.refreshing=false;} }
function paintChat() { if(!chat||!chatNodes)return;const {log,status:statusNode,error:errorNode,send,close,reply,botToggle}=chatNodes;
 const atBottom=log.scrollHeight-log.scrollTop-log.clientHeight<48;
 log.replaceChildren(...(chat.hasEarlier?[h('p',{class:'muted'},'แสดง 200 ข้อความล่าสุด')]:[]),...chat.messages.map(m=>h('div',{class:`bubble ${m.sender==='TEAM'?'team':m.sender==='BOT'?'bot':'member'}`},
   h('div',{class:'pre-line'},m.body),h('div',{class:'bubble-meta'},`${m.sender==='TEAM'?(m.byYou?'คุณ':'ทีมงาน'):m.sender==='BOT'?'Dot (AI)':'ลูกค้า'} · ${when(m.createdAt)}`))));
 if(atBottom)log.scrollTop=log.scrollHeight;
 statusNode.textContent=`สถานะ: ${translate(chat.thread.status)}${chat.thread.teamRequested?' · ลูกค้าขอคุยกับทีมงาน':''}${chat.member?` · แพ็กเกจที่ซื้อ ${translate(chat.member.paidPlan)}`:''} · อัปเดตทุก 10 วินาทีขณะเปิดแชท`;
 errorNode.replaceChildren(...(chat.error?[h('p',{class:'error',role:'alert'},chat.error)]:[]));
 reply.disabled=chat.sending;send.disabled=chat.sending||!chat.draft.trim();
 send.textContent=chat.sending?'กำลังส่ง…':chat.outgoing?'ส่งอีกครั้ง':'ส่งคำตอบ';
 close.disabled=chat.sending||chat.thread.status==='CLOSED';
 botToggle.hidden=!chat.botGlobal;botToggle.disabled=chat.sending;
 botToggle.textContent=chat.thread.botEnabled?'ปิด Dot ในแชทนี้':'เปิด Dot ในแชทนี้'; }
function renderChatDrawer() { const member=chat.member;const name=member?.displayName||member?.email||chat.userId;
 const drawer=h('section',{class:'drawer chat-drawer',role:'dialog','aria-modal':'true','aria-label':`แชทกับ ${name}`},
   h('header',{},h('h2',{},'แชทช่วยเหลือ'),button('×',closeChat,'close',{'aria-label':'ปิดแชท'})));
 const statusNode=h('p',{class:'context chat-status'});
 const log=h('div',{class:'chat-log',role:'log','aria-label':'ข้อความในแชท'});
 const reply=h('textarea',{maxlength:1000,placeholder:'พิมพ์คำตอบถึงลูกค้า','aria-label':'คำตอบถึงลูกค้า',oninput:e=>{chat.draft=e.target.value;
   // An edited draft is a new message; keep the old id only for an unchanged retry.
   if(chat.outgoing&&chat.outgoing.body!==chat.draft.trim())chat.outgoing=null;paintChat();}},chat.draft);
 const send=button('ส่งคำตอบ',submitReply,'primary');const close=button('ปิดเรื่อง',closeThread);const errorNode=h('div');
 const botToggle=button('',toggleThreadBot,'bot-toggle');
 chatNodes={log,status:statusNode,error:errorNode,send,close,reply,botToggle};
 drawer.append(h('span',{class:'label'},'สมาชิก'),h('div',{class:'identity'},name,member?.email&&member.email!==name?h('div',{class:'member-email'},member.email):null),statusNode,
   log,h('label',{class:'chat-reply'},h('span',{class:'label'},'ตอบลูกค้า'),reply),errorNode,
   h('p',{class:'notice'},'ปิดเรื่องเมื่อแก้ปัญหาแล้ว ถ้าลูกค้าส่งข้อความใหม่ แชทจะกลับมาเอง · Dot ยังช่วยตอบต่อหลังทีมงานตอบ ถ้าต้องการคุยเองให้ปิด Dot ในแชทนี้'),
   botToggle,h('div',{class:'drawer-actions'},close,send));
 const backdrop=h('div',{class:'drawer-backdrop',onclick:closeChat}); app.append(backdrop,drawer);
 paintChat();log.scrollTop=log.scrollHeight;reply.focus();
 drawer.addEventListener('keydown',e=>{if(e.key==='Escape')closeChat();if(e.key==='Tab'){const focusable=[...drawer.querySelectorAll('button,input,select,textarea')].filter(n=>!n.disabled);const first=focusable[0],last=focusable.at(-1);if(e.shiftKey&&document.activeElement===first){e.preventDefault();last?.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus();}}});
}
async function submitReply(){ if(!chat||chat.sending)return;const body=chat.draft.trim();if(!body)return;const current=chat;const generation=epoch;
 if(!current.outgoing||current.outgoing.body!==body)current.outgoing={id:crypto.randomUUID(),body};
 current.sending=true;current.error='';paintChat();
 try{const r=await api('support/reply',{userId:current.userId,id:current.outgoing.id,body});if(generation!==epoch||chat!==current)return;
   current.outgoing=null;current.draft='';chatNodes.reply.value='';
   if(!current.messages.some(m=>m.id===r.message.id))current.messages=[...current.messages,r.message];
   current.thread={...current.thread,status:'WAITING_MEMBER',lastSender:'TEAM',lastMessageId:r.message.id,lastMessageAt:r.message.createdAt,teamRequested:false};
   refreshSupportCountAfterChange();
 }catch(e){if(generation===epoch&&chat===current)current.error=e.message;}
 finally{if(chat===current){current.sending=false;paintChat();if(!current.error){chatNodes.log.scrollTop=chatNodes.log.scrollHeight;chatNodes.reply.focus();}}} }
async function closeThread(){ if(!chat||chat.sending)return;const current=chat;const generation=epoch;let changed=false;current.sending=true;current.error='';paintChat();
 try{const r=await api('support/close',{userId:current.userId,lastMessageId:current.thread.lastMessageId});if(generation!==epoch||chat!==current)return;current.thread=r.thread;refreshSupportCountAfterChange();}
 catch(e){if(generation===epoch&&chat===current){current.error=e.message;changed=e.code==='ADMIN_SUPPORT_THREAD_CHANGED';}}
 finally{if(chat===current){current.sending=false;paintChat();if(changed)void refreshChat();}} }
async function toggleThreadBot(){ if(!chat||chat.sending)return;const current=chat;const generation=epoch;current.sending=true;current.error='';paintChat();
 try{const r=await api('support/thread-bot',{userId:current.userId,enabled:!current.thread.botEnabled});if(generation!==epoch||chat!==current)return;current.thread=r.thread;}
 catch(e){if(generation===epoch&&chat===current)current.error=e.message;}
 finally{if(chat===current){current.sending=false;paintChat();}} }
async function toggleBotGlobal(){ if(busy||!page.bot||session.role!=='OWNER')return;const enable=!page.bot.enabled;
 if(enable&&!window.confirm('เปิด Dot ให้ตอบลูกค้าทุกคน?\n\nข้อความแชทของลูกค้าจะถูกส่งให้ OpenAI ประมวลผล (ไม่ส่งอีเมล เบอร์โทร หรือชื่อ) ตรวจว่านโยบายความเป็นส่วนตัวแจ้งเรื่องนี้แล้ว'))return;
 const generation=epoch;busy=true;error='';success='';render();
 try{const r=await api('support/bot-settings',{enabled:enable});if(generation!==epoch)return;page={...page,bot:r.bot};success=r.bot.enabled?'เปิด Dot แล้ว · Dot จะตอบข้อความใหม่ของลูกค้า':'ปิด Dot แล้ว · ข้อความใหม่จะรอทีมงานตอบ';}
 catch(e){if(generation===epoch)error=e.message;}finally{if(generation===epoch){busy=false;render();}} }
async function submitTrial(){ if(busy||csvBusy||pending?.kind==='DELETE')return;const generation=epoch;pending ||= {requestId:crypto.randomUUID(),userId:selected.id,expectedEmail:selected.email,action:drawerAction,plan:selectedPlan,days,reason:reason.trim(),expectedVersion:selected.trial?.version??0};
 busy=true;error='';render();try{await api('trials',pending);if(generation!==epoch)return;pending=null;selected=null;success='บันทึกสิทธิ์ทดลองแล้ว พร้อมประวัติการจัดการ';busy=false;await load();}catch(e){if(generation!==epoch)return;if(e.status>=400&&e.status<500)pending=null;error=e.message;busy=false;render();}}
// Keeps the reviewed request id until the server confirms, so a retry continues the same audited deletion.
async function submitDeletion(){ if(busy||csvBusy||session.role!=='OWNER'||(!pending&&!deletionReady()))return;const generation=epoch;
 pending ||= {kind:'DELETE',requestId:crypto.randomUUID(),userId:selected.id,expectedEmail:selected.email??'',reason:reason.trim()};
 const {kind,...request}=pending;busy=true;error='';render();
 try{await api('account-deletions',request);if(generation!==epoch)return;pending=null;selected=null;reviewing=false;deleteConfirm='';reason='';success='ลบบัญชีแล้ว · ดูบันทึกได้ที่ประวัติการลบบัญชี';busy=false;await load();}
 catch(e){if(generation!==epoch)return;if(e.status>=400&&e.status<500&&String(e.code||'').startsWith('ADMIN_'))pending=null;error=e.message;busy=false;render();}}
async function downloadCsv(){if(busy||csvBusy||selected||pending||view!=='reports'||!page.rows.length)return;const generation=epoch;const request={...(loadedFilters||filters()),csv:true};csvBusy=true;error='';render();
 try{const csv=await api('view',request,true);if(generation!==epoch||!session)return;const url=URL.createObjectURL(new Blob([csv],{type:'text/csv;charset=utf-8'}));const a=h('a',{href:url,download:request.reportScope==='LATEST_TRIAL'?'postdee-trial-report.csv':'postdee-usage-report.csv'});a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
 catch(e){if(generation===epoch)error=e.message;}finally{if(generation===epoch){csvBusy=false;render();}}}
try{const r=await fetch('/admin/config',{cache:'no-store'});if(!r.ok)throw new Error('ยังไม่ได้เปิดใช้หน้าแอดมิน');boot=await r.json();renderLogin();}catch(e){error=e.message;renderLogin();}
