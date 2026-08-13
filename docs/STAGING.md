# PostDee Staging

ทบทวนเอกสาร ณ 10 สิงหาคม 2026: **Blueprint ใน repository ติดตาม `main` แต่การ
deploy สำเร็จหรือ `/health` ผ่านไม่ได้ยืนยันว่า R2, Gemini/ElevenLabs, Firebase,
RevenueCat หรือ PostPeer ผ่าน E2E ใน release candidate เดียวกัน** ผลที่ระบุว่า
ผ่านด้านล่างเป็นบันทึกการทดสอบเดิมและต้องตรวจซ้ำตามรายการก่อน Production

- Blueprint: `postdee-staging` (`exs-d9bb3it7vvec73ceggl0`)
- API: `postdee-api-staging` (`srv-d9bb72ojs32c739osa5g`)
- URL: `https://postdee-api-staging.onrender.com`
- Database: `postdee-postgres-staging` Free (`dpg-d9bb66ojs32c739oqt10-a`)
- Database expiry: 14 สิงหาคม 2026
- บันทึกเดิม — Firebase: project `project-798caf7e-85b8-45e3-af7`, Email/Google เปิดแล้ว;
  Google Sign-In → Firebase ID token → Render Staging API ผ่านบน Android Emulator
- บันทึกเดิม — RevenueCat: Test Store products/entitlements/current offering และ sandbox-only
  webhook ตั้งแล้ว; purchase และ true Restore/resync E2E ผ่านบน Emulator ด้วย
  Firebase UID หลัง deploy backend และตั้ง server REST key แล้ว
- บันทึกเดิมระบุว่า R2 รับวิดีโอทดสอบจากแอปได้ แต่ยังต้องตรวจยืนยันว่า bucket Production ไม่มี
  object จากรอบทดสอบและลบ object ทดสอบที่อัปโหลดสำเร็จด้วยตนเอง
- บันทึกการทดสอบเดิมระบุว่าเคยตั้ง `ELEVENLABS_API_KEY` ชุด Staging แล้ว และ
  รุ่นปัจจุบันแยกเสียง M4A ขนาดเล็กก่อนส่งถอดเสียง อย่างไรก็ตาม repository
  มองไม่เห็นค่า secret ปัจจุบัน จึงต้องยืนยัน Dashboard และทดสอบคลิป 38 MB ซ้ำ
  บน release candidate เพื่อยืนยัน timing, cleanup และโควตา
  ส่วน Gemini ยังต้องผ่าน functional E2E แยก ขณะที่ Social ถูกคืนเป็น
  `disabled` หลังผ่าน connected-account E2E เฉพาะ YouTube Shorts Private
  แบบโพสต์ทันทีหนึ่งครั้ง; แพลตฟอร์มอื่น การตั้งเวลา และ Production ยังไม่ผ่าน

Staging ใช้ทดสอบโค้ดและผู้ให้บริการจริงก่อนส่งเข้า Production โดยต้องไม่ใช้ฐานข้อมูล
bucket วิดีโอ Firebase project หรือ webhook token ชุดเดียวกับผู้ใช้จริง

## โครงสร้างที่เตรียมไว้

ไฟล์ `render.staging.yaml` สร้างทรัพยากรแยกดังนี้:

- Web Service: `postdee-api-staging`
- PostgreSQL: `postdee-postgres-staging`
- Database/User: `postdee_staging`
- Region: Singapore
- Branch: `main`
- Build/test keeps platform-native optional tools; after the Prisma migration,
  startup prunes development and optional packages. Firebase Auth remains
  available, while unused Firestore/Google Cloud Storage clients are not kept in
  the running Staging service.
- Web/Database plan: `free`
- Production safety guards ยังเปิดผ่าน `NODE_ENV=production`
- Push และ Firebase account deletion ยังปิดไว้ในรอบแรก

Render Dashboard และ Blueprint ต้องตาม `main` เหมือนกัน เพื่อไม่ให้การ sync Blueprint
ครั้งถัดไปเปลี่ยน Staging กลับไป branch เก่า

## ค่าใช้จ่ายและข้อจำกัด

- Web Service แบบ Free มีค่า compute เริ่มต้น $0 แต่จะหยุดเมื่อไม่มี traffic 15 นาที
  และการปลุกกลับอาจใช้เวลาประมาณหนึ่งนาที
- PostgreSQL แบบ Free มีพื้นที่ 1 GB, ไม่มี backup และหมดอายุ 30 วัน
- Render อนุญาต Free PostgreSQL ที่ active ได้หนึ่งตัวต่อ workspace เท่านั้น
- หาก Production ใช้โควตา Free PostgreSQL อยู่แล้ว **ให้หยุดก่อนสร้าง** ห้ามชี้
  Staging ไปฐาน Production วิธีแยกที่ถูกต้องถัดไปคือ Basic-256mb ประมาณ $6/เดือน
  หรือสร้าง Staging ใน workspace ทดสอบที่แยกจริง
- Bandwidth และ build minutes ยังนับตามโควตา workspace

อ้างอิง: [Render Free instances](https://render.com/docs/free) และ
[Render pricing](https://render.com/pricing)

## Secrets ที่ต้องเป็นชุดทดสอบ

กรอกค่า `sync: false` ใน Render Dashboard เท่านั้น ห้ามใส่ค่าจริงใน Git หรือแชต:

- `CLOUDFLARE_R2_*`: ใช้ bucket สำหรับ Staging เท่านั้น
- `FIREBASE_PROJECT_ID`: ใช้ Firebase project สำหรับ Staging เท่านั้น
- `REVENUECAT_WEBHOOK_AUTH_TOKEN`: ใช้ RevenueCat Test Store/webhook ของ Staging
- `REVENUECAT_REST_API_V1_KEY`: server-only key สำหรับอ่าน subscriber ตอนผู้ใช้
  กด Restore; ห้ามใช้ mobile SDK key แทนและห้ามใส่ใน Flutter
- `GEMINI_API_KEY` และ `ELEVENLABS_API_KEY`: ควรใช้ key จำกัดโควตาสำหรับ Staging

## สถานะ AI transcription ที่ถือเป็นข้อมูลจริง

- `render.yaml` และ `render.staging.yaml` ใน `main` ตั้ง
  `TRANSCRIPTION_PROVIDER=elevenlabs` และ `EDIT_PLAN_PROVIDER=gemini`
- Production (`render.yaml`) และ Staging (`render.staging.yaml`) กำหนดค่า
  `GEMINI_CAPTION_MODEL=gemini-2.5-flash-lite` และ
  `GEMINI_EDIT_PLAN_MODEL=gemini-3.5-flash-lite` ไว้อย่างชัดเจน
- คำขอ transcript และ visual ของ Gemini 3.5 ใช้ structured JSON และไม่ส่ง
  `generationConfig.temperature` ส่วน Gemini 2.5 สำหรับ caption จะลองใหม่เมื่อ
  เกิดข้อผิดพลาดชั่วคราว แล้วใช้ local template เดิมโดยตรงหากยังไม่สำเร็จ โดยไม่
  เรียก Gemini รุ่นที่สอง
- ElevenLabs Scribe v2 เป็นตัวถอดเสียงพร้อมเวลา ส่วน Gemini ใช้วิดีโอพร็อกซี
  และ transcript เพื่อเลือกช่วง; หาก Gemini ใช้งานไม่ได้จะใช้กฎ PostDee
- เว้น `ELEVENLABS_TRANSCRIPTION_KEYTERMS` ว่างไว้จนกว่าจะวัดความคุ้มค่า
- การมี API key หรือค่ารุ่นโมเดลอยู่ใน Dashboard ไม่ได้แปลว่าโมเดลนั้นถูกเรียก
  ต้องตรวจค่า `TRANSCRIPTION_PROVIDER` ของ service ที่ Deploy จริงทุกครั้ง
- ทุก optional toggle ของ AI edit เริ่มปิด หน้า seller-facing ให้ผู้ใช้เปิดได้
  เฉพาะ subtitle, silence, repeated-speech และ `AI ใส่เอฟเฟกต์เสียงให้`;
  target-only ยังคงทำงานได้โดยไม่เปิด toggle ส่วนการ์ด colour/audio ถูกซ่อน
- AI SFX ใช้ `/ai-edits/prepare` และ AI minutes ตาม source duration เมื่อ
  sound-design analysis สำเร็จ. Recipe คืนเพียง allowlisted `soundId` กับ
  `sourceSeconds`; Mobile กำหนดเสียงที่ 25%, map ผ่านช่วงตัดจริง และ render จาก
  procedural WAV ภายในแอป. ไม่มี UI เลือกเสียง/เวลา/ความดังเอง. Provider หรือ
  timing unavailable ต้องได้รายการว่างแบบ fail closed และ unavailable-only
  ต้องไม่ลดนาที
- Staging ยังห้ามอ้าง AI SFX E2E ผ่านจน ElevenLabs quota กลับมา แล้วทดสอบทั้ง
  original/shortened clip, Preview/full export และ A/V sync บน Pixel 8 กับ
  iPhone จริง
- Transcript gaps are silence candidates only. The Android/iOS client confirms
  each candidate against the source waveform before rendering; failed or
  ambiguous verification keeps the original audio. Mobile ใช้ FFmpeg
  `silencedetect` เป็น final authority และส่งเฉพาะช่วงที่ยืนยันแล้วไปทุก render
  path; probe ที่สำเร็จแต่ไม่พบช่วงปลอดภัยแยกจาก probe ที่ล้มเหลว
- `transcript.boundarySegments` เป็นหลักฐานขอบประโยคภายในสำหรับจัด target แม้
  ปิดซับที่มองเห็นอยู่; หากหลักฐานไม่ปลอดภัย Mobile เก็บ planner cut เดิมและ
  แจ้งเตือน โดยไม่ย้อนใช้ raw segment
- การประกอบเวลา fragment ภาษาไทยเพื่อหาคำพูดซ้ำต้องตรงแบบ exact NFC และอยู่ใน
  reliable segment เดียวกันเท่านั้น หากพิสูจน์ไม่ได้ให้ fail closed และ
  repeat-only ที่ unavailable ไม่ลด AI minutes
- Color-only edits at original duration remain an internal/legacy QA route for
  Pro users and do not consume AI editing minutes; sellers cannot select this
  card from the current setup. เส้นทางทดสอบนี้ไม่ extract/upload/prepare;
  colour + shortening หรือความสามารถที่ต้องใช้เสียงยังเรียก prepareหนึ่งครั้ง
  ส่วน unknown enabled capability ต้องหยุดก่อนเกิด side effect

`render.staging.yaml` ปัจจุบันไม่ประกาศ `FIREBASE_SERVICE_ACCOUNT_JSON`, ใช้
`PUSH_SENDER=mock` และ `FIREBASE_AUTH_DELETE_ENABLED=false` เพื่อป้องกันการลบ
ผู้ใช้หรือยิง Push ผิดระบบ
รวมถึงใช้ `SOCIAL_PUBLISHER=disabled`. ในโค้ดชุดนี้
`GET /publishing/readiness`, `POST /posts`, `PATCH /posts/:id` และ
`POST /posts/:id/publish-now` จะตอบ `503 SOCIAL_PUBLISHING_UNAVAILABLE`;
create/reschedule/publish-now หยุดก่อนตรวจ upload readiness, อ่านโควตา, เขียน post
หรือเปลี่ยนคิว ส่วน `DELETE /posts/:id` ยังใช้ยกเลิกคิวเดิมได้

Mobile เรียก readiness หลังยืนยันและก่อนใส่ลายน้ำหรืออัปโหลด พร้อมแสดงข้อความไทย
เมื่อระบบปิดอยู่ แต่ `acceptingPosts: true` เป็นเพียง config gate ว่า API process
ไม่ได้ใช้ `disabled` เท่านั้น ไม่ได้ตรวจ PostPeer, R2, queue/worker หรือ connection
ของผู้ใช้. เมื่อเปิดรับงาน response ต้องมี `platformSettingsVersion: 1`; ให้ apply
Prisma migration และ deploy/ตรวจ API ก่อนปล่อย Mobile Phase 2; Mobile ปัจจุบัน
ตรวจทั้ง `acceptingPosts` และ integer version อย่างน้อย 1 และหยุดก่อน upload หาก
ไม่มี/ผิดรูปแบบ/เก่ากว่า. Client เก่าหรือการ
เปลี่ยน config หลัง preflight ยังอาจอัปโหลดไฟล์ก่อน
`POST /posts` ตอบ `503`; object แบบนั้นต้องถูกล้างด้วยนโยบายไฟล์ชั่วคราว

readiness ทั้งกรณี `200` และ `503` ส่ง `Cache-Control: private, no-store` เพื่อไม่ให้
เก็บผลเดิมไว้ใช้ซ้ำ. ค่านี้เป็นมาตรการป้องกันเท่านั้น และไม่ใช่หลักฐานว่า cache คือ
สาเหตุของผลทดสอบวันที่ 10 สิงหาคม

ฉบับร่างโพสต์เป็นข้อมูลในเครื่อง แยกด้วย stable authenticated UID ใต้ Application
Support และคัดลอกวิดีโอ/หน้าปกไว้ในพื้นที่ของแอป การกดบันทึกร่างไม่สร้าง API Post,
ไม่อัปโหลด R2, ไม่เรียก provider/queue และไม่ใช้ post quota; backend ไม่มีสถานะ
`DRAFT`. ร่างไม่ซิงก์ข้ามเครื่อง แต่อาจอยู่ใน OS backup ตามการตั้งค่าอุปกรณ์
เมื่อโพสต์ถูกรับเข้าคิวแล้ว Mobile จึงลบร่าง; ถ้าขั้นตอนก่อนรับเข้าคิวล้มเหลวต้อง
เก็บไว้ และถ้าลบหลังเข้าคิวไม่สำเร็จต้องแสดงคำเตือน พฤติกรรมนี้ยังต้องเก็บหลักฐานบน release candidate
จริงก่อนถือว่าผ่าน

`INBOX_DRAFT` ของ TikTok และ `PAGE_DRAFT` ของ Facebook เป็นร่างที่ provider หลัง
กด Post ไม่ใช่ร่างในเครื่อง: ต้องอัปโหลด สร้าง server Post เข้าคิว เรียก provider
และใช้โควตาตามจำนวนปลายทาง

แต่ละร่างเก็บ `clientRequestId` เดิมไว้ตลอดการส่ง รวมถึงหลังแอป restart หรือไม่ได้รับ
response. API สร้าง post แบบ database-first: ครั้งแรกสำเร็จตอบ `201`; การส่ง key เดิม
พร้อม intent เดิมตอบ `200 idempotentReplay: true` และซ่อม queue job ที่หายได้; intent
ที่เปลี่ยนหรือ post เดิมจบ `FAILED` ตอบ `409` โดยไม่อ้างว่าเข้าคิวใหม่ ส่วน client เก่า
ที่ไม่ส่ง key ยังใช้ได้แต่ไม่มีการป้องกันรายการซ้ำ หาก enqueue ครั้งแรกตอบ `503` แถว
`QUEUED` จะยังอยู่เพื่อให้ retry key เดิมซ่อมคิว ไม่ใช่ rollback แถวทิ้ง

การป้องกันนี้ครอบคลุม post/โควตา แต่ยังไม่ครอบคลุมไฟล์ remote: ร่างยังไม่เก็บ key
ของวิดีโอ/หน้าปกที่อัปโหลดสำเร็จ ดังนั้น lost response แล้ว retry อาจอัปโหลด object ใหม่
ก่อน API คืน post เดิม ต้องพิสูจน์การ reuse/cleanup และ R2 lifecycle ก่อน Production
หน้าผลลัพธ์ต้องแสดง `QUEUED`, `PUBLISHING`, `PUBLISHED` และ `PARTIAL_PUBLISHED`
ตาม response จริง; status ที่ไม่รู้จักห้ามแสดงว่าสำเร็จและต้องเก็บร่างไว้

เมื่อจะทดสอบ Social จริง ให้เพิ่ม `POSTPEER_API_KEY` ชุดทดสอบใน Dashboard ขณะที่
publisher ยัง `disabled`, ใช้บัญชี disposable เชื่อม/refresh, ตรวจและยกเลิก post
สถานะ `QUEUED`/ตั้งเวลาเดิมทั้งหมดก่อน แล้วจึงสลับเป็น
`SOCIAL_PUBLISHER=postpeer` เฉพาะช่วงทดสอบแบบควบคุม. Scheduler แบบ in-process
อ่าน post ครบกำหนดจาก Prisma ทุกประมาณ 5 วินาที จึงอาจส่งคิวเก่าทันทีหลังเปิด

Staging Blueprint จึงตั้ง `SOCIAL_PUBLISH_REQUIRE_EMPTY_BACKLOG=true` ไว้ด้วย.
เมื่อสลับเป็น PostPeer ระบบใช้ aggregate count เพียงคำสั่งเดียวแบบ atomic โดยกรองสถานะที่อยู่ใน
`QUEUED` หรือ `PUBLISHING` ของ post ทุกผู้ใช้ (รวมรายการที่ตั้งไว้ในอนาคต) ก่อนเริ่ม
scheduler และก่อนเปิดรับ HTTP traffic. ถ้าจำนวนรวมไม่เป็นศูนย์หรืออ่านฐานข้อมูลไม่ได้
deploy ใหม่จะไม่เริ่ม โดยไม่อ่านหรือแสดง id, ผู้ใช้, caption หรือ media; Production
Blueprint ไม่ถูกแก้

candidate ถัดไปอ่าน config ครั้งเดียวแล้วส่ง object เดียวกันให้ app และขั้นตอนเริ่ม
scheduler. ตอน startup ต้องเห็น log ที่ไม่มี secret ดังนี้:

- `Social publishing startup: mode=<disabled|enabled>; publisher=<disabled|postpeer>; emptyBacklogGuard=<not-enforced|enforced>`
- เมื่อเปิด PostPeer พร้อม guard ต้องเห็น `Social publishing activation guard passed: publish backlog is empty`
  หลัง scheduler start สำเร็จเท่านั้น

ห้ามตีความ deploy Live หรือ log scheduler/listener ทั่วไปเป็น guard pass. ก่อนกดโพสต์
รอบใหม่ต้องเก็บ startup mode, publisher, guard enforcement, guard-pass log และ
authenticated readiness `200` พร้อม header `private, no-store` จาก process เดียวกัน

โค้ด Social ปัจจุบัน ensure ผู้ใช้ก่อนบันทึก profile, ส่งชื่อ profile แบบ
pseudonymous ที่ PostPeer กำหนดให้มี, poll ผล `202 pending/publishing` ประมาณ 2 นาที
โดยไม่สร้าง external id ปลอม และคืน `platformResults` ใน `GET /posts` แล้ว ค่า
Phase 2 ใหม่คือ TikTok `INBOX_DRAFT`; YouTube title + Private/Unlisted/Public +
kids/synthetic/certification; Instagram share-to-feed; Facebook Page Video แบบ
publish/page-draft. TikTok direct/`SELF_ONLY` เป็น legacy compatibility และยังห้าม
เปิดให้ client ใหม่จน creator-info/consent/audit ครบ.
`FACEBOOK_REELS` เป็นชื่อภายในที่ตอนนี้ส่ง Facebook Page Video ไม่ใช่ Reels.
Instagram ไม่มี Private รายโพสต์ และ Facebook `PUBLISH` อาจเผยแพร่จริง จึงต้องใช้
เฉพาะบัญชี disposable ที่ไม่มีผู้ติดตามหรือข้อมูลจริง ส่วน `PAGE_DRAFT` ต้องมี
หลักฐาน final draft จาก provider ก่อนถือว่าสำเร็จ
Retry ทำได้เฉพาะ error ที่ยืนยันว่า provider ยังไม่รับงาน; outcome ที่ไม่แน่นอนต้อง
ตรวจปลายทางก่อนกดใหม่

Mobile Review ต้องแสดง display name หรือ external account id ของบัญชี/channel/page
ปลายทางทุกช่อง พร้อม outcome ที่ขอ หากชื่อ/id ว่าง ค่าบังคับไม่ครบ หรือ outcome ยัง
ระบุไม่ได้ ต้องปิดการยืนยันและให้ refresh/reconnect แทนการเดาเป้าหมาย ข้อมูลที่เห็นใน
Review ไม่แทน server control: API ยัง resolve/snapshot/revalidate account จริงเอง

Post ใหม่เก็บ `platformSettings` และ internal `platformTargets` snapshot จาก connection
ปัจจุบัน ตรวจซ้ำก่อน commit และก่อน worker call; connection ที่หายหรือเปลี่ยนต้อง fail
closed. API/queue response ต้องไม่คืน `platformTargets` หรือ `providerPostId`.
`deliveryOutcome` สาธารณะมี `LIVE|PRIVATE|UNLISTED|DRAFT`; `PUBLISHED` หมายถึงส่งตาม
intent สำเร็จ ไม่ได้แปลว่าสาธารณะเสมอ. แถวเก่าอาจเป็น null และ queued legacy row
อาจไม่มี target snapshot จึงต้อง inspect/drain ก่อนเปิด PostPeer.

owner coordinator เป็น memory map ภายใน API process เดียวและ serialize authenticated
route mutations กับ RevenueCat webhook application ใน process นั้น แต่ mutation ที่เริ่ม
ใน API instance อื่นอาจผ่าน durable-marker check ก่อนเริ่มลบแล้ว commit ภายหลังได้
อีกทั้ง worker ไม่ถือ lock
ตลอด provider call ดังนั้น account deletion ยังไม่ production-safe แม้รัน process เดียว
และห้าม scale/แยก real worker จนกว่าจะมี durable repository barrier/lease หรือ
transactional outbox/claim-and-drain ที่หยุดงานใหม่และ drain ทุก user mutation ก่อน cleanup
ทั้ง Production และ Staging ต้องคง `FIREBASE_AUTH_DELETE_ENABLED=false` จนกว่าจะผ่าน
gate นี้และ physical-device/slow-network cleanup tests; การมี service-account secret
อย่างเดียวไม่ถือว่าพร้อมเปิด

คำเตือนแยกจาก Staging: `render.yaml` ใน repository ปัจจุบันเลือก
`SOCIAL_PUBLISHER=postpeer` สำหรับ Production ทั้งที่ broader connected-account E2E
และ Production verification ยังไม่ผ่าน.
Repository ไม่ยืนยันค่าที่ deploy จริง และงาน safety gate นี้ไม่ได้แก้ Production
Blueprint; ต้องตัดสินใจนโยบาย fail-closed และยืนยัน Dashboard ก่อนเปิดให้ผู้ใช้จริง

บันทึกเดิมระบุว่า Render Staging ใช้
`FIREBASE_PROJECT_ID=project-798caf7e-85b8-45e3-af7` ส่วน Android API key จำกัดไว้เฉพาะ package
`com.postdee.postdee_mobile.staging` และ Debug SHA-1 ของเครื่องทดสอบ
ต้องยืนยันชื่อ project ปัจจุบันใน Dashboard ก่อนทดสอบ เพราะ Blueprint เก็บค่านี้
เป็น `sync: false`

## ขั้นตอนสร้างใหม่หรือกู้คืน Staging

1. เปิด Render Dashboard แล้วตรวจ Billing/Usage ก่อนว่ามี Free PostgreSQL อยู่หรือไม่
2. เลือก **New → Blueprint** และ repository `NOI56/PostDeeMobile`
3. เลือก branch `main`
4. กำหนด Blueprint path เป็น `render.staging.yaml`
5. ตรวจชื่อให้เป็น `postdee-api-staging` และ `postdee-postgres-staging` เท่านั้น
6. กรอก secrets ชุดทดสอบตามรายการข้างบนโดยไม่คัดลอกค่ากลับเข้า repository
7. สร้าง Blueprint และรอ migration/deploy สำเร็จ
8. เปิด `https://<staging-host>/health` และต้องได้ `status: ok`
9. สร้าง mobile build ที่ตั้ง `API_BASE_URL=https://<staging-host>` แล้วทดสอบด้วย
   บัญชีและวิดีโอทดสอบเท่านั้น

Android Staging รองรับเฉพาะ Debug ในตอนนี้:

```powershell
cd apps/mobile
Copy-Item staging.local.example.json staging.local.json
..\..\.tools\flutter\bin\flutter.bat run --debug --dart-define-from-file=staging.local.json
```

ห้ามใช้ `staging.local.json` กับ `--profile` หรือ `--release` เพราะสอง build type นี้
ยังใช้ Firebase Production หากเปลี่ยนเครื่อง/CI ต้องเพิ่ม Debug SHA-1/SHA-256 ของ
keystore ใหม่นั้นใน Firebase Staging ก่อน Google Sign-In จะทำงาน

`/health` ตรวจเพียงว่า process ของ API ตอบได้ ไม่ได้ตรวจ R2, Firebase, Gemini/ElevenLabs
หรือ RevenueCat จึงต้องผ่าน smoke test ด้านล่างก่อนเรียก Staging ว่าใช้งานฟังก์ชันจริงได้

ก่อนทดสอบ Firebase ต้องสร้าง mobile staging Firebase config ที่ตรงกับ
`FIREBASE_PROJECT_ID` ของ Staging ด้วย หากแอปยังใช้ Firebase project เดิม token จะ
อยู่คนละ project และ backend จะตอบ 401 ห้ามแก้ด้วยการชี้ Staging กลับไป project ผู้ใช้จริง

ถ้าหน้าสรุปก่อนสร้างแสดงทรัพยากร Production หรือยอดเงินที่ไม่คาดไว้ ให้ยกเลิกและ
ตรวจ Blueprint path/ชื่อ service ใหม่ก่อนเสมอ

## Smoke test ก่อนอนุญาตให้ deploy Production

Staging Blueprint ติดตาม `main` และ deploy เมื่อ checks ผ่าน ดังนั้นการ merge
เข้า `main` เป็นเพียงการส่งโค้ดไป Staging ไม่ใช่หลักฐานว่า checklist นี้ผ่าน
รายการด้านล่างเป็น release gate ก่อนนำ release candidate เดียวกันขึ้น Production

- [x] Firebase Google login, ID token และ API user/quota response ด้วยบัญชี Staging
- [ ] ทดสอบ local publish draft บน release candidate จริง: save/restart/restore,
      update/delete, สลับบัญชี, พื้นที่เต็ม และ publish success/failure โดยยืนยันว่า
      การบันทึกร่างไม่เรียก readiness/upload/create-post, ไม่แตะ R2/provider/queue/quota,
      ไม่มี server `DRAFT`, queue success ลบร่างและ pre-queue failure เก็บร่างไว้ รวมถึงตรวจ policy
      Android/iOS backup ให้ตรงกับ Privacy/Data Safety
- [ ] ยืนยันว่า connection ที่โหลดแล้วเริ่มเลือก 0 ช่องทาง ผู้ใช้ต้องเลือกเองหรือกด
      `เลือกทั้งหมด`; เลือกแล้วจึงเห็นปุ่มสรุป/ตั้งค่าของช่องนั้น ไม่วางทุก field บน
      หน้า main. Review ต้องแสดง TikTok inbox draft, YouTube visibility หลังกรอก
      title/kids/synthetic/certification ครบ, Instagram share-to-feed และ Facebook
      Page Video publish/page-draft พร้อมชื่อ/id ของบัญชี/channel/page ทุกปลายทาง;
      TikTok direct, identity ที่หาย, ค่าที่ไม่ครบ และ outcome ที่ไม่รู้ต้อง block
- [ ] Apply migration `20260811130000_add_platform_publish_configuration`, deploy API
      ก่อน Mobile และตรวจ readiness `platformSettingsVersion: 1`; ตรวจ Prisma JSON
      settings/targets กับ delivery outcome/provider id โดย public API/queue/log ไม่
      เปิดเผย target/provider ids
- [ ] ทดสอบ immediate/scheduled target snapshot: เปลี่ยนหรือตัด connection หลัง Review,
      ก่อน commit และก่อน worker call ต้อง fail closed; inspect/drain queued legacy-null
      backlog ซึ่งไม่มี snapshot ก่อนเปิด PostPeer
- [ ] ทดสอบ provider delivery จริงแยก `LIVE`, `PRIVATE`, `UNLISTED`, `DRAFT`; TikTok
      inbox และ Facebook Page draft ต้องมี final provider evidence, ใช้โควตา และ UI
      ต้องไม่เรียกว่าเผยแพร่สาธารณะ. ทดสอบ YouTube compliance/visibility และคง TikTok
      direct ปิดไว้จน creator-info/consent/audit ผ่าน
- [ ] ทดสอบ stable `clientRequestId` กับ Prisma/queue จริง: first `201`, lost-response
      replay `200 idempotentReplay: true` ได้ post เดิมและซ่อม job, intent mismatch กับ
      terminal failed replay ตอบ `409`, legacy no-key เป็น attempt ใหม่ และโควตาเพิ่ม
      เพียงครั้งเดียว รวม restart แอป/เซิร์ฟเวอร์และ queue-enqueue `503`
- [ ] หลัง idempotency `409` ยืนยันว่า draft เดิมยังอยู่และปุ่ม Post ถูกปิดตาม draft ID,
      กดซ้ำไม่ upload, ยกเลิกคำเตือนไม่สร้างรายการ และ `เริ่มรายการโพสต์ใหม่` จะสร้าง
      draft/request ID ใหม่เฉพาะหลังยืนยัน โดยไม่ลบร่างเดิม
- [ ] ยืนยันผลลัพธ์ Mobile ตาม status จริงทั้ง `QUEUED`, `PUBLISHING`, `PUBLISHED`,
      `PARTIAL_PUBLISHED`, replay label และ unknown-status ที่ไม่ลบร่าง/ไม่แสดงสำเร็จ
- [ ] จำลอง lost response หลังอัปโหลด แล้วตรวจว่า video/cover object ที่ไม่ได้ถูกอ้างถึง
      ถูก reuse หรือลบตามนโยบายจริง ห้ามนับ post-row idempotency ว่าแก้ R2 orphan แล้ว
- [x] Task 9 preflight: API 914/914, build/Prisma/typecheck, Flutter 759/759 และ
      analyze ผ่าน; fresh APK และ fixture SHA-256 ทั้ง 6 ไฟล์บันทึกใน
      `docs/testing/results/2026-08-08-ai-edit-correctness-pixel8.md` แล้ว
- [ ] Firebase Email/Password login ด้วยบัญชี Staging
- [ ] อัปโหลดไฟล์ไป bucket Staging และยืนยันว่าไม่มี object ใน bucket Production
      (อัปโหลดจาก Android ผ่านแล้ว แต่การยืนยันขอบเขต bucket และ cleanup ยังไม่ครบ)
- [ ] AI caption และ AI edit ใช้โควตา/ข้อมูลของบัญชีทดสอบ หลังยืนยันว่า
      `GEMINI_API_KEY` และ `ELEVENLABS_API_KEY` ใน Dashboard เป็นชุด Staging
      และ release candidate ล่าสุด deploy แล้ว ให้ทดสอบคลิป 38 MB ซ้ำ พร้อม
      ยืนยันว่า ElevenLabs รับเฉพาะ M4A ชั่วคราว,
      Gemini รับเฉพาะ visual proxy, cleanup สำเร็จ, provider failure ตอบ JSON
      502 โดยไม่หักโควตา และแอปแสดงข้อความลองใหม่ภาษาไทย)
      รอบ `6695e5f1d6050e0656c2bfd591fbbad745d80963` ยืนยัน fail-closed/no-charge
      แล้ว. สร้าง key Staging ใหม่อายุ 30 วัน จำกัดเฉพาะ Speech to Text และ
      deploy ตัวแปรแวดล้อมบน SHA เดิมแล้ว; health คืน HTTP 200 แต่การ rerun เวลา
      21:57 ICT ยังได้ upstream HTTP `401`, ไม่มี output และ PostDee quota คงเดิม
      178/178 นาที. ElevenLabs แสดงใช้ 9,994/10,000 workspace credits เหลือ 6,
      จึงมีแนวโน้มสูงว่า provider quota ไม่พอ แต่ยังไม่ยืนยันสาเหตุย่อยเพราะไม่มี
      upstream response detail. ห้ามเปิดเผย secret; รอรอบ reset หรือเติม quota
      ภายใต้การอนุมัติแยก แล้ว rerun `target-30` เพียงหนึ่งครั้ง
- [x] ยืนยัน `Candidate deploy SHA` ตรงกับ `Deployed Staging SHA` และบันทึก
      `API runtime code SHA`, health status/time, APK SHA-256 และ fixture SHA-256
      จริงใน `docs/testing/results/2026-08-08-ai-edit-correctness-pixel8.md`
- [ ] รัน Pixel 8 isolated matrix โดยเปิดทีละความสามารถตาม
      `docs/testing/AI_EDIT_THAI_CLIPS.md`; ต้องรวม target, subtitle, silence,
      repeat-safe, repeat-unsafe, local colour, colour + target และ combined
      ตอนนี้ `color-local` ผ่าน device/render checks พร้อม full export/no-charge
      แต่หลักฐานตรงว่าไม่มี upload/prepare ยังรอ Render log; `target-30` ถูกบล็อก
      ก่อน render/no-charge โดยสอดคล้องอย่างมากกับ provider quota ที่เหลือ 6
      credits; แถวที่พึ่ง API ยังค้างจน quota กลับมาและ rerun สำเร็จ
- [ ] บันทึก output codec, FPS, file size, audio peak และ A/V sync จากไฟล์จริง
      รายการเหล่านี้ยังเป็นงานทดสอบค้างและยังห้ามระบุว่า renderer แก้ครบแล้ว
- [x] RevenueCat Test Store purchase ให้ entitlement Pro กับ Firebase UID ทดสอบ
      บน Android Emulator (ราคาทดสอบ ไม่มีการเรียกเก็บเงินจริง)
- [x] Deploy backend ที่มี `POST /billing/revenuecat/resync`, ตั้ง
      `REVENUECAT_REST_API_V1_KEY` ใน Render Staging และทดสอบ true Restore/resync
      E2E บน Android Emulator แล้ว
- [ ] RevenueCat renew/cancel/refund และ replay อัปเดต entitlement ถูกต้อง
- [x] เตรียม RevenueCat Play Store app, Starter/Pro products, entitlements,
      default offering, production Android public SDK key และ signed AAB แล้ว
- [ ] สร้าง Play Console app/subscriptions, ตั้ง service credentials, เปิด
      internal testing และทดสอบ Google Play purchase/restore จริง ขั้นตอนเหล่านี้
      ยังติดการยืนยันสิทธิ์ Play Console ด้วยมือถือ Android จริง; Emulator ใช้
      ยืนยันไม่ได้ และ Test Store ไม่ถือเป็นหลักฐานของ flow นี้
- [x] Deploy release candidate `fcccb89642478ea70b2c89ccc507351f108dcb9e` แล้ว
      ยืนยันบน Pixel 8 ขณะ `SOCIAL_PUBLISHER=disabled` ว่า Mobile แสดงข้อความไทยจาก
      authenticated readiness ก่อน watermark/upload และ post units คง `249/250`.
      หลักฐานอยู่ที่ `docs/testing/results/2026-08-10-social-publishing-pixel8.md`
- [ ] ทดสอบ deployed write boundary โดยตรงให้ครบว่า authenticated `POST /posts`,
      `PATCH /posts/:id` และ `POST /posts/:id/publish-now` ตอบ
      `503 SOCIAL_PUBLISHING_UNAVAILABLE` โดยไม่มี post/quota/queue ใหม่ และ
      `DELETE /posts/:id` ยังยกเลิกคิวเดิมได้. รอบ Pixel 8 ข้างต้นหยุดที่ readiness
      จึงยังไม่ได้เรียก route เหล่านี้; automated tests ไม่แทน live evidence
- [ ] ตรวจ R2 หลังทดสอบ client เก่าหรือจำลอง race; หากไฟล์ถูกอัปโหลดก่อน
      authoritative `503` ต้องยืนยันว่า cleanup/lifecycle ลบ object ชั่วคราวนั้น
- [x] ทดสอบ activation guard บน Staging SHA
      `208b4e580ddd2291a7a32e718c2519d785730895`: deploy
      `dep-d9so44on74is7393ga30` แสดง runtime `enabled` / `postpeer` / guard
      `enforced`, ตามด้วย empty-backlog guard-pass, listener และ scheduler ก่อนรับโพสต์
- [ ] ก่อนรอบถัดไปให้ยืนยันว่า connection เป็นบัญชี disposable ของ Staging และ refresh
      สำเร็จ; ห้ามใช้บัญชีผู้ใช้หรือ Production. รอบนี้ไม่ได้พิสูจน์ account isolation
- [ ] ทดสอบ connected-account E2E ให้ครบทุกแพลตฟอร์มและเส้นทางที่โฆษณา
      - [x] YouTube Shorts Private แบบโพสต์ทันทีผ่านหนึ่งครั้งบน Pixel 8:
        กดส่งหนึ่งครั้ง ไม่มี retry, post/platform จบ `PUBLISHED`, มี provider
        URL/id จริง (เก็บแบบ private), ปลายทางระบุวิดีโอเป็น Private และโควตาสด
        เปลี่ยน `249/250` เป็น `248/250`
      - [ ] TikTok inbox draft, YouTube Phase 2 compliance/visibility, Instagram
        Reels, Facebook Page Video publish/page-draft, scheduling,
        ambiguous-outcome/retry และ exact-account/isolation/disposable proof
- [x] คืน Staging เป็น `SOCIAL_PUBLISHER=disabled` หลังทดสอบ โดย deploy
      `dep-d9socgon74is7393uedg` แสดง runtime `disabled` / publisher `disabled` /
      guard `not-enforced`, ไม่มี guard-pass, listener/health ผ่าน และ Environment
      read-back เป็น `disabled`. Rollback deploy แรก `dep-d9so77h42hec73bejge0`
      ยังเริ่มเป็น `enabled` จึงถูกบันทึกเป็น rollback ที่ไม่สำเร็จและแก้ซ้ำทันที
- [ ] เก็บ authenticated readiness หลัง rollback โดยตรงให้ได้ `503
      SOCIAL_PUBLISHING_UNAVAILABLE` พร้อม `Cache-Control: private, no-store`
- [ ] จำลอง async `202`/ผลไม่แน่นอนเพื่อยืนยันว่ารอ poll แบบ bounded, ไม่สร้าง id
      ปลอม และไม่ retry POST ซ้ำก่อนผู้ทดสอบตรวจปลายทาง
- [ ] ทดสอบ create/reschedule ว่ารับเฉพาะเวลาอนาคตไม่เกิน 30 วัน และทดสอบ
      owner-scoped `publish-now` ว่าย้าย schedule ที่ยัง `QUEUED` เป็น ready โดย
      queue failure คงเวลาเดิม; รวม retry และสถานะล้มเหลวไม่ให้ค้างผิดปกติ
- [ ] ก่อนเปิด account deletion หรือใช้หลาย API instance/separate real worker ให้ลง
      durable repository owner barrier/lease หรือ transactional outbox/claim-and-drain
      ครอบทุก authenticated user mutation, RevenueCat webhook และ worker
      provider call; ต้องหยุด mutation ใหม่, drain งานค้างก่อน cleanup และทดสอบทั้ง
      process เดียว/ข้าม process โดย process-local entry check ไม่ถือว่าผ่าน
- [ ] แทน Privacy Policy/Terms ที่แอประบุว่าเป็นเอกสารฉบับร่างด้วยฉบับตรวจทานและ HTTPS
      URL จริง พร้อมให้ Android Data Safety, iOS App Privacy และ backup disclosure ตรงกับ
      การเก็บ video/cover ของร่างใน Application Support
- [ ] เปิดทดสอบลบบัญชีภายหลังเมื่อ full mutation barrier/drain ข้างต้นผ่าน และมี
      Firebase service account ของ Staging เท่านั้น; ห้ามถือว่ามี secret แล้วพร้อมเปิด

## การล้างข้อมูล

- ลบบัญชีทดสอบและ object ใน R2 Staging หลัง smoke test รวมถึง object จากรอบอัปโหลด
  Android วันที่ 22 กรกฎาคม 2026 ซึ่ง upload session เสร็จสมบูรณ์แล้วและ abort ผ่าน API ไม่ได้
- ห้ามนำ dump หรือข้อมูลผู้ใช้ Production มา seed
- ก่อนฐาน Free หมดอายุ ให้ export เฉพาะข้อมูลจำลองที่จำเป็นหรือสร้างฐานใหม่
- หากยกเลิก Staging ให้ลบ Blueprint, service, database และ revoke keys ชุดทดสอบ
