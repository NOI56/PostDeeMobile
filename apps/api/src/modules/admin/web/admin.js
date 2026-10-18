const app = document.querySelector('#app');
const names = { overview:'ภาพรวม', members:'สมาชิก', posts:'โพสต์', trials:'สิทธิ์ทดลอง', channels:'ช่องทางที่เชื่อม', reports:'รายงาน', audit:'ประวัติผู้ดูแล' };
const paths = { overview:'M3 11 12 3l9 8M5 10v11h5v-7h4v7h5V10', members:'M20 21v-2a7 7 0 0 0-14 0v2M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0', posts:'M6 3h12a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2M8 8h8M8 12h8M8 16h4', trials:'M9 3h6M10 3v7l-5 9q-1 2 2 2h10q3 0 2-2l-5-9V3M8 15h8', channels:'M10 13a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-2 2M14 11a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l2-2', reports:'M5 21V12M12 21V3M19 21V8', audit:'M12 8v5l4 2M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0' };
const labels = { BASIC:'ฟรี', STARTER:'Starter', PRO:'Pro', ACTIVE:'ใช้งานอยู่', EXPIRED:'หมดอายุ', REVOKED:'ยกเลิกแล้ว', DRAFT:'ร่าง', QUEUED:'รอส่ง', PUBLISHING:'กำลังส่ง', PUBLISHED:'ส่งสำเร็จ', PARTIAL_PUBLISHED:'สำเร็จบางช่องทาง', FAILED:'ส่งไม่สำเร็จ', GRANT:'ให้สิทธิ์', EXTEND:'ต่อเวลา', REVOKE:'ยกเลิกสิทธิ์', TIKTOK:'TikTok', YOUTUBE_SHORTS:'YouTube Shorts', INSTAGRAM_REELS:'Instagram Reels', FACEBOOK_REELS:'Facebook Page Video' };
const messages = { ADMIN_ACCESS_DENIED:'บัญชีนี้ยังไม่ได้รับสิทธิ์ผู้ดูแล PostDee', ADMIN_OWNER_REQUIRED:'เฉพาะเจ้าของระบบสามารถเปลี่ยนสิทธิ์ทดลองได้', ADMIN_REAUTH_REQUIRED:'กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่ เพื่อยืนยันตัวตนก่อนเปลี่ยนสิทธิ์', ADMIN_MEMBER_CHANGED:'อีเมลบัญชีเปลี่ยนแล้ว กรุณาค้นหาสมาชิกและตรวจสอบใหม่', ADMIN_TRIAL_CHANGED:'สิทธิ์มีการเปลี่ยนแปลง กรุณาปิดหน้าต่างแล้วโหลดข้อมูลล่าสุดก่อน', ADMIN_TRIAL_ALREADY_ACTIVE:'บัญชีนี้มีสิทธิ์ทดลองอยู่แล้ว ใช้การต่อเวลาแทน', ADMIN_TRIAL_NOT_ACTIVE:'ไม่พบสิทธิ์ทดลองที่ยังใช้งานอยู่', ADMIN_TRIAL_EXTENSION_LIMIT:'ต่อเวลาได้ไม่เกิน 90 วันนับจากวันนี้', ADMIN_TRIAL_INVALID:'กรุณาระบุแพ็กเกจ ระยะเวลา และเหตุผลอย่างน้อย 3 ตัวอักษร', ADMIN_REQUEST_CONFLICT:'หมายเลขคำขอนี้ใช้กับข้อมูลอื่นแล้ว กรุณาตรวจประวัติก่อน', ADMIN_TRIAL_UNAVAILABLE:'ยังยืนยันผลการเปลี่ยนสิทธิ์ไม่ได้ ใช้ปุ่มตรวจผลคำขอเดิม หรือตรวจประวัติผู้ดูแล', ADMIN_DATA_UNAVAILABLE:'ยังโหลดข้อมูลไม่ได้ กรุณาลองใหม่', ADMIN_FILTER_INVALID:'ตัวกรองหรือช่วงวันที่ไม่ถูกต้อง', ADMIN_MEMBER_NOT_FOUND:'ไม่พบบัญชีสมาชิกนี้แล้ว' };
const h = (tag, attributes = {}, ...children) => { const e = document.createElement(tag); for(const [k,v] of Object.entries(attributes)) {
  if(k.startsWith('on')) e.addEventListener(k.slice(2),v); else if(v !== false && v != null) e.setAttribute(k,String(v)); }
  for(const c of children.flat(Infinity)) if(c != null) e.append(c instanceof Node ? c : document.createTextNode(String(c))); return e; };
const icon = key => { const s=document.createElementNS('http://www.w3.org/2000/svg','svg'); s.setAttribute('viewBox','0 0 24 24'); s.setAttribute('fill','none'); s.setAttribute('stroke','currentColor'); s.setAttribute('stroke-width','1.7'); s.setAttribute('stroke-linecap','round'); s.setAttribute('stroke-linejoin','round'); s.setAttribute('aria-hidden','true'); const p=document.createElementNS(s.namespaceURI,'path'); p.setAttribute('d',paths[key]||paths.members); s.append(p); return s; };
const button = (text, action, cls='', attributes={}) => h('button',{type:'button',class:cls,onclick:action,...attributes},text);
const translate = v => v === '' ? '—' : labels[v] ?? v ?? '—';
const when = value => value ? new Intl.DateTimeFormat('th-TH',{dateStyle:'medium',timeStyle:'short',timeZone:'Asia/Bangkok'}).format(new Date(value)) : '—';
const trialActive = t => t && !t.revokedAt && Date.parse(t.expiresAt)>Date.now();
const trialText = t => !t ? 'ไม่มี' : t.revokedAt ? 'ยกเลิกแล้ว' : !trialActive(t) ? 'หมดอายุ' : `${translate(t.plan)} · เหลือ ${Math.ceil((Date.parse(t.expiresAt)-Date.now())/86400000)} วัน`;
let boot, auth, firebase, currentUser, previewToken, session, epoch=0, loadEpoch=0, view='members', page={rows:[]}, query='', cursor, status='', platform='', from='', through='', error='', success='', busy=false, selected=null, drawerAction='GRANT', selectedPlan='PRO', days=7, reason='', reviewing=false, pending=null, controllers=new Set();
const api = async (path, body, csv=false) => { const captured=epoch; const controller=new AbortController(); controllers.add(controller);
  try { const token=previewToken || await currentUser?.getIdToken(); if(!token) throw new Error('กรุณาเข้าสู่ระบบ');
    if(captured!==epoch) throw new Error('บัญชีเปลี่ยนแล้ว');
    const r=await fetch(`/admin/api/${path}`,{ method:body?'POST':'GET',headers:{Authorization:`Bearer ${token}`,...(body?{'Content-Type':'application/json','X-PostDee-Admin':'1'}:{})},body:body?JSON.stringify(body):undefined,signal:controller.signal,cache:'no-store'});
    if(captured!==epoch) throw new Error('บัญชีเปลี่ยนแล้ว'); const data=csv&&r.ok?await r.text():await r.json();
    if(!r.ok) { const failure=new Error(messages[data.code] || `ดำเนินการไม่ได้ (${r.status})`); failure.status=r.status; throw failure; } return data;
  } finally { controllers.delete(controller); }
};
const logout = async () => { epoch++; loadEpoch++; controllers.forEach(c=>c.abort()); controllers.clear(); currentUser=null; previewToken=null; session=null; page={rows:[]}; selected=null; pending=null; reason='';
  if(auth) await firebase.signOut(auth); renderLogin(); };
async function login() { error=''; renderLogin(true); try {
  if(boot.previewToken) previewToken=boot.previewToken;
  else { const [{initializeApp}, sdk]=await Promise.all([import('https://www.gstatic.com/firebasejs/13.0.0/firebase-app.js'),import('https://www.gstatic.com/firebasejs/13.0.0/firebase-auth.js')]);
    firebase=sdk; auth ||= sdk.getAuth(initializeApp(boot.firebaseWeb)); await sdk.setPersistence(auth,sdk.inMemoryPersistence);
    currentUser=(await sdk.signInWithPopup(auth,new sdk.GoogleAuthProvider())).user; }
  session=await api('session'); await load();
} catch(e) { error=e.message; currentUser=null; previewToken=null; session=null; if(auth) await firebase.signOut(auth); renderLogin(); } }
function renderLogin(loading=false) { document.body.classList.remove('has-drawer'); app.removeAttribute('aria-busy');
  app.replaceChildren(h('main',{class:'login'},h('section',{class:'login-panel'},h('div',{class:'brand'},'PostDee'),h('h1',{},'เข้าสู่ระบบผู้ดูแล'),
    h('p',{class:'notice'},'จัดการสมาชิก สิทธิ์ทดลอง และตรวจผลโพสต์ด้วยบัญชีที่ได้รับสิทธิ์'),h('div',{class:'environment'},boot?.previewToken?'LOCAL · ข้อมูลตัวอย่าง':boot?.environment||'กำลังโหลด'),
    error?h('p',{class:'error',role:'alert'},error):null,button(loading?'กำลังเข้าสู่ระบบ…':boot?.previewToken?'เปิดข้อมูลตัวอย่าง':'เข้าสู่ระบบด้วย Google',login,'primary',{disabled:loading}),
    h('p',{class:'footer-note'},'บัญชี Google ทั่วไปจะเข้าถึงข้อมูลผู้ดูแลไม่ได้')))); }
const filters = () => ({ view, query, ...(cursor?{cursor}:{}), ...(status?{status}:{}), ...(platform?{platform}:{}), ...(from?{from}:{}), ...(through?{through}:{} ) });
async function load(append=false) { const ticket=++loadEpoch; busy=true; error=''; render(); try { const result=await api('view',filters()); if(ticket!==loadEpoch)return;
  page=append?{...result,rows:[...page.rows,...result.rows]}:result;
} catch(e) { if(ticket===loadEpoch) error=e.message; } finally { if(ticket===loadEpoch){busy=false;render();} } }
function navigate(next) { if(pending)return; view=next; selected=null; reviewing=false; page={rows:[]}; cursor=undefined;status='';platform='';from='';through='';success='';load(); }
const fieldSelect = (caption, items, value, onChange) => { const e=h('select',{onchange:event=>onChange(event.target.value)},items.map(([id,name])=>h('option',{value:id,selected:id===value},name))); return h('label',{},caption,e); };
async function openMember(member, action='GRANT') { const ticket=++loadEpoch;busy=true;error='';render();try {
 if(pending)throw new Error('กรุณาตรวจผลคำขอเดิมให้เสร็จก่อนเปลี่ยนสิทธิ์รายการอื่น');
 const result=await api('member',{userId:member.id});if(ticket!==loadEpoch)return;
 selected=result.member;drawerAction=action;selectedPlan=trialActive(selected.trial)?selected.trial.plan:'PRO';days=7;reason='';reviewing=false;pending=null;
 }catch(e){if(ticket===loadEpoch)error=e.message;}finally{if(ticket===loadEpoch){busy=false;render();}} }
function closeDrawer() { if(pending||busy)return; selected=null;reviewing=false;error='';render();document.querySelector('.text')?.focus(); }
function table() {
 const definitions={members:[['member','สมาชิก'],['paidPlan','แพ็กเกจที่ซื้อ'],['trial','สิทธิ์ทดลอง'],['updatedAt','อัปเดตข้อมูลล่าสุด']],
 trials:[['member','สมาชิก'],['paidPlan','แพ็กเกจที่ซื้อ'],['trial','สิทธิ์ทดลอง'],['trialStatus','สถานะ']],
 posts:[['email','สมาชิก'],['caption','แคปชัน'],['status','สถานะ'],['channels','ผลแต่ละช่องทาง'],['failureReason','สาเหตุที่บันทึก'],['createdAt','สร้างเมื่อ'],['scheduledAt','ตั้งเวลา'],['help','แนวทางตรวจสอบ']],
 channels:[['email','สมาชิก'],['platform','ช่องทาง'],['displayName','ชื่อบัญชี'],['status','สถานะที่บันทึก'],['connectedAt','เชื่อมเมื่อ']],
 reports:[['email','สมาชิก'],['plan','ทดลอง'],['startsAt','เริ่ม'],['expiresAt','สิ้นสุด'],['captionRequests','AI แคปชัน (ครั้ง)'],['editMinutes','AI ตัดต่อ (นาที)'],['postUnits','ผลส่งที่บันทึก'],['estimatedUsd','ต้นทุนประมาณ (USD)'],['purchasedPlanNow','แพ็กเกจที่ซื้อปัจจุบัน']],
 audit:[['createdAt','เมื่อ'],['actorId','รหัสผู้ดูแล'],['email','สมาชิก'],['action','การจัดการ'],['plan','แพ็กเกจ'],['reason','เหตุผล'],['before','ก่อนเปลี่ยน'],['after','หลังเปลี่ยน']]};
 const cols=definitions[view]||[];
 if(!page.rows.length)return h('div',{class:'empty'},busy?'กำลังโหลดข้อมูล…':'ไม่พบข้อมูลตามที่ค้นหา');
 const cell=(row,key)=> { if(key==='member')return button(h('span',{},h('span',{class:'member-name'},row.displayName||row.email),h('div',{class:'member-email'},row.email)),()=>openMember(row),'text');
   if(key==='trial')return trialText(row.trial); if(key==='estimatedUsd')return row[key]==null?'ยังไม่ได้ตั้งอัตรา':Number(row[key]).toFixed(4);
   if(['createdAt','updatedAt','scheduledAt','connectedAt','startsAt','expiresAt'].includes(key))return when(row[key]);
   if(key==='before'||key==='after'){const t=row[key];return t?`${translate(t.plan)} · ${when(t.expiresAt)}${t.revokedAt?' · ยกเลิก':''}`:'ไม่มี';}
   return translate(row[key]); };
 return h('div',{class:'table-wrap',tabindex:0,'aria-label':'ตารางข้อมูล เลื่อนแนวนอนได้'},h('table',{class:view},h('thead',{},h('tr',{},cols.map(([,caption])=>h('th',{scope:'col'},caption)))),
   h('tbody',{},page.rows.map(row=>h('tr',{class:selected?.id===row.id?'chosen':''},cols.map(([key])=>h('td',{},cell(row,key))))))));
}
function render() { if(!session)return renderLogin(); document.body.classList.toggle('has-drawer',!!selected); app.removeAttribute('aria-busy');
 const side=h('aside',{class:'sidebar'},h('div',{class:'brand'},'PostDee'),button('เมนู',()=>side.classList.toggle('open'),'menu-toggle',{'aria-label':'เปิดเมนูผู้ดูแล'}),
   h('nav',{class:'nav','aria-label':'เมนูผู้ดูแล'},Object.entries(names).map(([id,name])=>button(h('span',{},icon(id),h('span',{},name)),()=>navigate(id),id===view?'selected':'',{'aria-current':id===view?'page':false,disabled:!!pending}))),
   h('div',{class:'role'},icon('members'),h('span',{},session.role==='OWNER'?'เจ้าของระบบ':'ผู้ดูแล · ดูข้อมูล')));
 const q=h('input',{type:'search',placeholder:'ค้นหาชื่อหรืออีเมล',value:query,maxlength:120,'aria-label':'ค้นหาชื่อหรืออีเมล',oninput:e=>query=e.target.value});
 const form=h('form',{class:'search',onsubmit:e=>{e.preventDefault();cursor=undefined;load();}},h('label',{},q),h('button',{type:'submit',class:'primary',disabled:busy},'ค้นหา'));
 const content=h('section',{class:'content','aria-label':names[view]},success?h('p',{class:'success',role:'status'},success):null,error?h('p',{class:'error',role:'alert'},error):null);
 if(pending&&!selected)content.append(h('p',{class:'notice'},'มีคำขอเปลี่ยนสิทธิ์ที่ยังยืนยันผลไม่ได้ ตรวจคำขอเดิมก่อนทำรายการใหม่'),button('ตรวจผลคำขอเดิม',submitTrial,'primary',{disabled:busy}));
 if(view!=='overview')content.append(form);
 if(view==='posts')content.append(h('div',{class:'filters'},
   fieldSelect('สถานะ',[['','ทั้งหมด'],...['DRAFT','QUEUED','PUBLISHING','PUBLISHED','PARTIAL_PUBLISHED','FAILED'].map(id=>[id,translate(id)])],status,v=>{status=v;cursor=undefined;load();}),
   fieldSelect('ช่องทาง',[['','ทั้งหมด'],...['TIKTOK','YOUTUBE_SHORTS','INSTAGRAM_REELS','FACEBOOK_REELS'].map(id=>[id,translate(id)])],platform,v=>{platform=v;cursor=undefined;load();}),
   h('label',{},'ตั้งแต่ (UTC)',h('input',{type:'date',value:from,onchange:e=>{from=e.target.value;cursor=undefined;load();}})),
   h('label',{},'ถึง (UTC)',h('input',{type:'date',value:through,onchange:e=>{through=e.target.value;cursor=undefined;load();}}))));
 if(view==='overview')content.append(h('div',{class:'summary'},page.rows.map(r=>h('div',{class:'summary-item'},h('div',{class:'muted'},r.label),h('div',{class:'summary-value'},r.value)))));
 else {const count=page.total!=null?`${page.total} ${view==='members'?'สมาชิก':'รายการ'}`:`${page.rows.length} รายการที่โหลด`;
   content.append(h('div',{class:'tools'},h('p',{class:'count'},busy?'กำลังโหลด…':count),view==='reports'?button('ดาวน์โหลด CSV หน้านี้',downloadCsv,'',{disabled:busy||!page.rows.length}):null),table());}
 if(page.nextCursor)content.append(button('โหลดรายการถัดไป',()=>{cursor=page.nextCursor;load(view!=='reports');},'next',{disabled:busy}));
 if(page.note)content.append(h('p',{class:'notice'},page.note));
 content.append(h('p',{class:'footer-note'},`${boot.previewToken?'ข้อมูลตัวอย่างสำหรับตรวจหน้าจอ · ':''}แสดงเวลาประเทศไทย · ${page.checkedAt?'ตรวจข้อมูลเมื่อ '+when(page.checkedAt):''}`));
 app.replaceChildren(h('div',{class:'shell'},side,h('main',{class:'workspace'},h('header',{class:'topbar'},h('h1',{},names[view]),h('div',{class:'right'},
   h('span',{class:`environment ${session.environment==='PRODUCTION'?'production':''}`},boot.previewToken?'LOCAL · ตัวอย่าง':session.environment),button('ออกจากระบบ',logout))),content)));
 if(selected){app.querySelector('.shell').inert=true;renderDrawer();}
}
function renderDrawer() { const active=trialActive(selected.trial); const viewer=session.role!=='OWNER';
 const title=viewer?'ข้อมูลสมาชิก':reviewing?'ตรวจสอบสิทธิ์':({GRANT:'ให้สิทธิ์ทดลอง',EXTEND:'ต่อเวลาทดลอง',REVOKE:'ยกเลิกสิทธิ์ทดลอง'})[drawerAction];
 const drawer=h('section',{class:'drawer',role:'dialog','aria-modal':'true','aria-label':title},h('header',{},h('h2',{},title),button('×',closeDrawer,'close',{'aria-label':'ปิดรายละเอียด',disabled:!!pending})));
 drawer.append(h('span',{class:'label'},'บัญชีที่เลือก'),h('div',{class:'identity'},selected.email),h('p',{class:'context'},`แพ็กเกจที่ซื้อ: ${translate(selected.paidPlan)} · ทดลอง: ${trialText(selected.trial)}`));
 if(selected.monthKey)drawer.append(h('p',{class:'notice'},`การใช้เดือน ${selected.monthKey}: โพสต์ ${selected.postUnits} หน่วย · AI แคปชัน ${selected.captionRequests} ครั้ง · AI ตัดต่อ ${selected.editMinutes} นาที`));
 if(viewer){drawer.append(h('p',{class:'notice'},`สมัครเมื่อ ${when(selected.createdAt)} · โพสต์ ${selected.postCount??0} รายการ · เชื่อม ${selected.channelCount??0} ช่องทาง`),h('p',{class:'notice'},'บัญชีผู้ดูแลนี้มีสิทธิ์ดูข้อมูลเท่านั้น'));}
 else if(active&&drawerAction==='GRANT'){drawer.append(h('p',{class:'notice'},`สิ้นสุด ${when(selected.trial.expiresAt)}`),button('ต่อเวลาทดลอง',()=>{drawerAction='EXTEND';render();},'primary'),button('ยกเลิกสิทธิ์ทดลอง',()=>{drawerAction='REVOKE';render();},'danger'));}
 else if(reviewing){drawer.append(h('div',{class:'review'},h('p',{},`${translate(drawerAction)} · ${translate(selectedPlan)}`),drawerAction!=='REVOKE'?h('p',{},`${days} วัน${drawerAction==='EXTEND'?' ต่อจากวันสิ้นสุดเดิม':' นับจากเวลายืนยัน'}`):h('p',{},'ยกเลิกเฉพาะสิทธิ์ทดลอง แพ็กเกจที่ซื้อยังคงเดิม'),h('p',{},`เหตุผล: ${reason}`)));
   if(error)drawer.append(h('p',{class:'error',role:'alert'},error));
   drawer.append(h('p',{class:'notice'},'ไม่รีเซ็ตโควตา · ไม่เรียกเก็บเงินอัตโนมัติ'),h('div',{class:'drawer-actions'},button('กลับไปแก้ไข',()=>{reviewing=false;render();},'',{disabled:busy||!!pending}),button(busy?'กำลังตรวจผล…':pending?'ตรวจผลคำขอเดิม':'ยืนยัน',submitTrial,drawerAction==='REVOKE'?'danger':'primary',{disabled:busy})));}
 else {const plan=fieldSelect('แพ็กเกจ',[['STARTER','Starter'],['PRO','Pro']],selectedPlan,v=>selectedPlan=v); plan.className='stack';if(drawerAction!=='GRANT')plan.querySelector('select').disabled=true;
   const radios=h('div',{class:'durations'},[7,14,30].map(n=>h('label',{class:'duration'},h('input',{type:'radio',name:'days',value:n,checked:n===days,onchange:()=>days=n}),`${n} วัน`)));
   const reasonInput=h('textarea',{maxlength:500,minlength:3,required:true,placeholder:'ระบุเหตุผลในการให้สิทธิ์ทดลอง','aria-label':'เหตุผล',oninput:e=>{reason=e.target.value;e.target.setCustomValidity('');}},reason);
   drawer.append(h('div',{class:'stack'},plan,drawerAction==='REVOKE'?h('p',{class:'notice'},'สิทธิ์ทดลองจะหยุดทันที แพ็กเกจที่ซื้อยังคงเดิม'):h('fieldset',{},h('legend',{},'ระยะเวลา'),radios),h('label',{},h('span',{class:'label'},'เหตุผล'),reasonInput)));
   if(error)drawer.append(h('p',{class:'error',role:'alert'},error));
   drawer.append(h('p',{class:'notice'},'ไม่รีเซ็ตโควตา · ไม่เรียกเก็บเงินอัตโนมัติ'),h('div',{class:'drawer-actions'},button('ยกเลิก',closeDrawer),button('ตรวจสอบสิทธิ์',()=>{if(reason.trim().length<3){reasonInput.setCustomValidity('ระบุเหตุผลอย่างน้อย 3 ตัวอักษร');reasonInput.reportValidity();return;} error='';reviewing=true;render();},'primary')));
 }
 if(!reviewing&&viewer)drawer.append(h('div',{class:'drawer-actions'},button('ปิด',closeDrawer)));
 if(pending&&!busy)drawer.append(button('ดูประวัติผู้ดูแล',()=>{selected=null;view='audit';query=pending.expectedEmail;cursor=undefined;load();}));
 const backdrop=h('div',{class:'drawer-backdrop',onclick:closeDrawer}); app.append(backdrop,drawer);
 drawer.querySelector('button:not(:disabled),select:not(:disabled),textarea:not(:disabled)')?.focus();
 drawer.addEventListener('keydown',e=>{if(e.key==='Escape')closeDrawer();if(e.key==='Tab'){const focusable=[...drawer.querySelectorAll('button,input,select,textarea')].filter(n=>!n.disabled);const first=focusable[0],last=focusable.at(-1);if(e.shiftKey&&document.activeElement===first){e.preventDefault();last?.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus();}}});
}
async function submitTrial(){ if(busy)return; pending ||= {requestId:crypto.randomUUID(),userId:selected.id,expectedEmail:selected.email,action:drawerAction,plan:selectedPlan,days,reason:reason.trim(),expectedVersion:selected.trial?.version??0};
 busy=true;error='';render();try{await api('trials',pending);pending=null;selected=null;success='บันทึกสิทธิ์ทดลองแล้ว พร้อมประวัติการจัดการ';busy=false;await load();}catch(e){if(e.status>=400&&e.status<500)pending=null;error=e.message;busy=false;render();}}
async function downloadCsv(){try{const csv=await api('view',{...filters(),csv:true},true);const url=URL.createObjectURL(new Blob([csv],{type:'text/csv;charset=utf-8'}));const a=h('a',{href:url,download:'postdee-trial-report.csv'});a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}catch(e){error=e.message;render();}}
try{const r=await fetch('/admin/config',{cache:'no-store'});if(!r.ok)throw new Error('ยังไม่ได้เปิดใช้หน้าแอดมิน');boot=await r.json();renderLogin();}catch(e){error=e.message;renderLogin();}
