# PostDee Staging

สถานะล่าสุดจากการอ่าน Render และเรียก health check เมื่อ 20 ตุลาคม 2026:

- Workspace: `My Workspace` (ผู้ใช้ยืนยันแล้ว)
- API `postdee-api-staging` ไม่ถูก suspend, ใช้แผน `starter`, branch `main`,
  หนึ่ง instance และปิด auto-deploy; `GET /health` ตอบ HTTP 200
- Deploy ล่าสุด `dep-dba83jqjnfac73enqm40` เป็น `live` ตั้งแต่ 18 ตุลาคม 2026,
  commit `1cf755eba9b156f95bb818eb2d5ee7fb7c0efd86`; ยังไม่มีชุดแก้ dependency/FCM รอบนี้
- Database `postdee-postgres-staging` เป็น `available`, แผน `basic_256mb`,
  1 GB, PostgreSQL 18; วันหมดอายุของ Free เดิมด้านล่างไม่ใช่สถานะปัจจุบัน
- ไม่พบ error-level logs ในช่วง 19:09–20:09 น. เวลาไทยของวันที่ตรวจ
- การลอง `SELECT 1` ผ่าน Render MCP ถูกบล็อกเพราะฐานข้อมูลปิดการเชื่อมต่อจากภายนอก
  ด้วย IP allowlist; ไม่ได้เปลี่ยน allowlist หรือยืนยัน query ผ่านช่องทางนี้
- ตรวจเฉพาะสถานะและ health ไม่ได้ deploy, เปลี่ยน config, ตรวจ secrets หรือทำ provider E2E

Blueprint ใน repository ยังเป็นแผน `free` และ branch ชั่วคราวตามหัวข้อด้านล่าง
ซึ่งต่างจาก live configuration ต้องทบทวนความต่างก่อนใช้ Blueprint sync/deploy
รายละเอียดการตรวจอยู่ใน `artifacts/dependency-fixes-20261020/summary.json`

บันทึกสถานะเดิม ณ 15 กรกฎาคม 2026: **Render/Database และ Google Auth บน Android
Debug ผ่านในรอบนั้น; ผลทดสอบยังครอบคลุมเพียงบางส่วน**

รายการผ่านแล้วและ provider setup ในบันทึกเดือนกรกฎาคมด้านล่างเป็นหลักฐานจาก
รอบเดิม ผล read-only รอบล่าสุดยืนยันสถานะ infrastructure ตามหัวข้อด้านบน
แต่ไม่ได้ตรวจ provider configuration หรือทำ functional smoke tests เหล่านี้ซ้ำ

- Blueprint: `postdee-staging` (`exs-d9bb3it7vvec73ceggl0`)
- API: `postdee-api-staging` (`srv-d9bb72ojs32c739osa5g`)
- URL: `https://postdee-api-staging.onrender.com`
- Database ในบันทึกเดิม: `postdee-postgres-staging` Free (`dpg-d9bb66ojs32c739oqt10-a`)
- Database expiry ในบันทึก Free เดิม: 14 สิงหาคม 2026 (ปัจจุบันเป็นแผน Basic แล้ว)
- Firebase: project `project-798caf7e-85b8-45e3-af7`, Email/Google เปิดแล้ว;
  Google Sign-In → Firebase ID token → Render Staging API ผ่านบน Android Emulator
- RevenueCat: Test Store products/entitlements/current offering และ sandbox-only
  webhook ตั้งแล้ว; purchase และ true Restore/resync E2E ผ่านบน Emulator ด้วย
  Firebase UID หลัง deploy backend และตั้ง server REST key แล้ว
- R2, Gemini และ Groq ยังเป็น dummy staging-only; Social ยัง `disabled` และยังไม่
  ผ่าน connected-account E2E

Staging ใช้ทดสอบโค้ดและผู้ให้บริการจริงก่อนส่งเข้า Production โดยต้องไม่ใช้ฐานข้อมูล
bucket วิดีโอ Firebase project หรือ webhook token ชุดเดียวกับผู้ใช้จริง

วันที่ 20 ตุลาคม 2026 รัน API tests/build/typecheck, Prisma schema/helper checks,
Flutter analyze/tests และ build Android ARM64 debug ในเครื่องแล้ว ผลรอบแรกอยู่ใน
`artifacts/readiness-check-20261020/summary.json` จากนั้นแก้ dependency และ FCM SDK
พร้อมตรวจซ้ำบน Node 22.23.3/npm 10.9.9: API 747 tests, typecheck/build, Prisma
และ dependency tree ผ่าน และ production dependency audit เหลือ 0 รายการ ผลล่าสุด
อยู่ใน `artifacts/dependency-fixes-20261020/summary.json`
ชุดตรวจในเครื่องนี้ไม่ใช่ functional Staging E2E และยังไม่ได้ยืนยัน race บน PostgreSQL/Redis จริง
หรือ security validation ใน runner ที่มี sandbox ครบตาม security-audit skill
ยังต้องทดสอบ OTP และสลับบัญชีบนอุปกรณ์ทดสอบ รวมถึง provider E2E ของ patch ปัจจุบัน

ลำดับปล่อย billing: เพิ่ม purchase-readiness protocol 1 ก่อน → อัปเดตแอปให้รอ
readiness → ยุติ/ปิดการซื้อของรุ่นเก่าที่ไม่เรียก readiness → เปลี่ยน GET ให้
อ่านอย่างเดียว branch ปัจจุบันรวมการเปลี่ยน GET แล้ว จึงยังปล่อยข้ามขั้นไม่ได้
รุ่นเก่าสามารถซื้อแม้ GET ล้มเหลว ต้องตรวจ race เขียน User/Post/Subscription
หลังลบบัญชีกับ PostgreSQL จริง และ timeout/retry ของ Redis เพิ่มด้วย ส่วนคิว
ข้ามหลาย instance, provider call ที่เริ่มแล้ว, OS background push และการถอน
device token ยังเป็นงานค้าง การแยก draft ตาม UID ไม่ได้ลบข้อมูลเก่าในเครื่อง

## โครงสร้างที่เตรียมไว้

ไฟล์ `render.staging.yaml` สร้างทรัพยากรแยกดังนี้:

- Web Service: `postdee-api-staging`
- PostgreSQL: `postdee-postgres-staging`
- Database/User: `postdee_staging`
- Region: Singapore
- Branch ชั่วคราว: `codex/ai-edit-thai-timing-staging`
- Web/Database plan: `free`
- Production safety guards ยังเปิดผ่าน `NODE_ENV=production`
- Blueprint ใน repository ยังตั้ง `PUSH_SENDER=mock` และ
  `FIREBASE_AUTH_DELETE_ENABLED=false` สำหรับ Staging

Live service ใช้ `main` แล้วตามการตรวจ 20 ตุลาคม 2026 แต่ Blueprint ยังใช้
branch ชั่วคราว ต้องเลือก config ที่ตั้งใจใช้ให้ตรงกันก่อน deploy รุ่นถัดไป

## ค่าใช้จ่ายและข้อจำกัด

ข้อจำกัดและราคาส่วนนี้เป็นข้อมูลที่บันทึกตอนเตรียม Staging เดิม ยังไม่ได้ตรวจราคา/
นโยบายล่าสุดในวันที่ทบทวนเอกสาร ให้ตรวจ Dashboard และแหล่งอ้างอิงก่อนสร้างใหม่

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
- `GEMINI_API_KEY` และ `GROQ_API_KEY`: ควรใช้ key จำกัดโควตาสำหรับ Staging

- `FIREBASE_SERVICE_ACCOUNT_JSON`: service account ของ Firebase project สำหรับ
  Staging เท่านั้น (ห้ามใช้ของ production เพราะ token ของ Staging จะตรวจไม่ผ่าน
  และทุกคน login ไม่ได้) เมื่อใส่แล้ว API จะเช็คว่าบัญชีถูกปิด/ถูกเพิกถอน
  token หรือไม่ในทุกคำขอ ถ้ายังไม่ใส่ API ยังทำงานได้แต่จะเช็คแค่ลายเซ็น token

ใช้ `PUSH_SENDER=mock` และ `FIREBASE_AUTH_DELETE_ENABLED=false` เพื่อป้องกันการลบ
ผู้ใช้หรือยิง Push ผิดระบบ แม้จะมี service account แล้วก็ตาม
รวมถึงใช้ `SOCIAL_PUBLISHER=disabled` ซึ่งจะล้มเหลวแบบชัดเจนและไม่สร้างโพสต์ปลอม
เมื่อจะทดสอบ Social จริง ให้เพิ่ม `POSTPEER_API_KEY` ชุดทดสอบใน Dashboard แล้ว
สลับเป็น `SOCIAL_PUBLISHER=postpeer` เฉพาะช่วงทดสอบแบบควบคุม

Production มีบันทึก disposable-account API/R2/Firebase smoke ผ่านแล้วทั้ง legacy
และ managed multipart และ `render.yaml` เปิด account deletion ไว้ ผลนั้นไม่ใช่
การทดสอบ Staging และไม่ครอบคลุม mobile E2E บนเครื่องจริง เครือข่ายช้า หรือ
security remediation เดือนตุลาคม ห้ามนำ service account ของ Production มาใช้แทน

โค้ด Social ปัจจุบัน ensure ผู้ใช้ก่อนบันทึก profile, ส่งชื่อ profile แบบ
pseudonymous ที่ PostPeer กำหนดให้มี, poll ผล `202 pending/publishing` ประมาณ 2 นาที
โดยไม่สร้าง external id ปลอม และคืน `platformResults` ใน `GET /posts` แล้ว ค่า
controlled-first คือ YouTube `private` และ TikTok `SELF_ONLY` (`draft: false`).
`FACEBOOK_REELS` ใช้ enum เดิม แต่ส่ง PostPeer `platform: 'facebook'` กับ
`platformSpecificData.contentType: 'reel'` เสมอ เพื่อโพสต์ Facebook Page Reels
เท่านั้น ไม่มี fallback เป็น Page feed video; ยังต้องทดสอบด้วยบัญชีจริงให้ครบ.
Retry ทำได้เฉพาะ error ที่ยืนยันว่า provider ยังไม่รับงาน; outcome ที่ไม่แน่นอนต้อง
ตรวจปลายทางก่อนกดใหม่

ค่าปัจจุบันของ Render Staging ใช้ `FIREBASE_PROJECT_ID=project-798caf7e-85b8-45e3-af7`
แล้ว ส่วน Android API key จำกัดไว้เฉพาะ package
`com.postdee.postdee_mobile.staging` และ Debug SHA-1 ของเครื่องทดสอบ

## ขั้นตอนสร้างใหม่หรือกู้คืน Staging

1. เปิด Render Dashboard แล้วตรวจ Billing/Usage ก่อนว่ามี Free PostgreSQL อยู่หรือไม่
2. เลือก **New → Blueprint** และ repository `NOI56/PostDeeMobile`
3. เลือก branch `codex/ai-edit-thai-timing-staging`
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

`/health` ตรวจเพียงว่า process ของ API ตอบได้ ไม่ได้ตรวจ R2, Firebase, Gemini/Groq
หรือ RevenueCat จึงต้องผ่าน smoke test ด้านล่างก่อนเรียก Staging ว่าใช้งานฟังก์ชันจริงได้

ก่อนทดสอบ Firebase ต้องสร้าง mobile staging Firebase config ที่ตรงกับ
`FIREBASE_PROJECT_ID` ของ Staging ด้วย หากแอปยังใช้ Firebase project เดิม token จะ
อยู่คนละ project และ backend จะตอบ 401 ห้ามแก้ด้วยการชี้ Staging กลับไป project ผู้ใช้จริง

ถ้าหน้าสรุปก่อนสร้างแสดงทรัพยากร Production หรือยอดเงินที่ไม่คาดไว้ ให้ยกเลิกและ
ตรวจ Blueprint path/ชื่อ service ใหม่ก่อนเสมอ

## Smoke test ก่อนอนุญาตให้ merge

เครื่องหมาย `[x]` ต่อไปนี้เก็บผลจากรอบเดิม ต้องตรวจบริการ/ฐานข้อมูลและ secrets
ชุดทดสอบใหม่ก่อนรัน release candidate รอบปัจจุบัน

- [ ] ตรวจหรือกู้คืน Staging service/database หลังวันหมดอายุที่บันทึกไว้ และยืนยัน
      ว่าใช้ Firebase/R2/RevenueCat/PostPeer ชุดทดสอบแยกจาก Production
- [x] Firebase Google login, ID token และ API user/quota response ด้วยบัญชี Staging
- [ ] Firebase Email/Password login ด้วยบัญชี Staging
- [ ] อัปโหลดไฟล์ไป bucket Staging และยืนยันว่าไม่มี object ใน bucket Production
- [ ] AI caption และ AI edit ใช้โควตา/ข้อมูลของบัญชีทดสอบ
- [ ] เปิด/ปิดความสามารถ AI แล้ว preview และเวลาใน timeline ถูกต้อง
- [ ] AI edit uploads only `audio/mp4` `.m4a` with `purpose=ai-edit-audio` for current production capabilities; verify the original video never leaves the device.
- [ ] AI edit no-audio/extraction/upload failures make no Groq call and consume no minute quota.
- [ ] Verify automatic and duplicate `POST /ai-edits/audio/cleanup`, owner isolation, the 25 MiB audio ceiling, and legacy `videoS3Key` compatibility in the Staging R2 bucket.
- [ ] Keep visual AI disabled: no 360p proxy pipeline exists yet.
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
- [ ] หลังสลับ `SOCIAL_PUBLISHER=postpeer` แบบตั้งใจแล้ว ให้ใช้บัญชี disposable
      เชื่อม/refresh และโพสต์แบบควบคุม: YouTube private, TikTok SELF_ONLY,
      Instagram Reels และ Facebook Page Reels (`contentType: 'reel'`) โดยยืนยัน
      ว่า Facebook เป็น Page Reel จริง ไม่มี Page feed fallback จากนั้นตรวจ provider URL,
      `GET /posts.platformResults` และสลับกลับ `disabled`
- [ ] จำลอง async `202`/ผลไม่แน่นอนเพื่อยืนยันว่ารอ poll แบบ bounded, ไม่สร้าง id
      ปลอม และไม่ retry POST ซ้ำก่อนผู้ทดสอบตรวจปลายทาง
- [ ] ตั้งเวลา, retry และสถานะล้มเหลวไม่ค้างผิดปกติ
- [ ] เปิดลบบัญชีเฉพาะเมื่อมี Firebase service account ของ Staging แล้วทดสอบ
      API/R2/Firebase cleanup และ retry ด้วยบัญชี disposable ของ Staging
- [ ] ทดสอบลบบัญชีจากมือถือจริง รวมเครือข่ายช้า/การอัปโหลดที่ยังทำงาน และ
      account/session guards ของ release candidate; ผล production API smoke เดิม
      ไม่ถือว่าผ่านรายการนี้

## การล้างข้อมูล

- ลบบัญชีทดสอบและ object ใน R2 Staging หลัง smoke test
- ห้ามนำ dump หรือข้อมูลผู้ใช้ Production มา seed
- ก่อนฐาน Free หมดอายุ ให้ export เฉพาะข้อมูลจำลองที่จำเป็นหรือสร้างฐานใหม่
- หากยกเลิก Staging ให้ลบ Blueprint, service, database และ revoke keys ชุดทดสอบ
