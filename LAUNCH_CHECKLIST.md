# LAUNCH_CHECKLIST.md

เช็กลิสต์ก่อนเปิดใช้งานจริง / ทดสอบกับผู้ใช้จริง สำหรับ PostDee

> ภาพรวม: โครงสร้างหลักและ adapter มีแล้ว แต่ provider/device E2E หลายรายการยัง
> ไม่ผ่าน จึงยังห้ามถือว่าเปิดใช้จริงครบ เพื่อลดความเสี่ยงให้ตั้งค่าชุดทดสอบและ
> ผ่านเช็กลิสต์ตามลำดับด้านล่างก่อน Production

---

## 0) Staging แยกจาก Production

- [x] เตรียม `render.staging.yaml` และเทสต์ว่าชื่อ service/database แยกจาก Production
- [x] ตรวจสิทธิ์และสร้าง Free PostgreSQL แยกสำเร็จโดยไม่ใช้ฐาน Production ร่วมกัน
- [x] สร้าง Blueprint `postdee-api-staging` จาก branch
      `codex/ai-edit-thai-timing-staging`
- [x] ใส่ dummy staging-only values สำหรับ health-only โดยไม่ใช้ Production credentials
- [x] API deploy, Prisma migration และ `GET /health` ผ่านบน Render Staging
- [x] สร้าง Firebase Staging, เปิด Email/Google, จำกัด Android API key และตั้ง
      `FIREBASE_PROJECT_ID` บน Render ให้ตรงกัน
- [x] ตั้ง RevenueCat Test Store products/entitlements/current offering และ
      authenticated sandbox webhook; transport/auth smoke ได้ HTTP 202 ตามคาด
- [x] Test Store purchase E2E ผ่านบน Android Emulator ด้วย Firebase UID
      (เป็นราคาทดสอบและไม่มีการเรียกเก็บเงินจริง)
- [x] Deploy true server resync, ตั้ง server REST key ใน Render Staging และทดสอบ
      Restore/resync E2E บน Android Emulator แล้ว
- [x] เตรียม RevenueCat Play Store app/products/entitlements/default offering,
      production Android public SDK key และ signed AAB แล้ว
- [ ] ยืนยันสิทธิ์ Play Console ด้วยมือถือ Android จริง แล้วสร้าง Play Console
      app/subscriptions, service credentials และ internal testing; Emulator ใช้
      ยืนยันบัญชีขั้นตอนนี้ไม่ได้
- [ ] เปลี่ยน R2/Gemini/Groq เป็น credentials ของ Staging จริงก่อน functional smoke
- [x] ตั้ง Staging เริ่มต้นเป็น `SOCIAL_PUBLISHER=disabled`; กำหนดให้สลับ
      PostPeer เฉพาะ controlled test ด้วยบัญชีทดสอบแล้วสลับกลับ
- [x] เตรียม Android Debug Firebase config แยกด้วย application id
      `com.postdee.postdee_mobile.staging`; Release ยังใช้ Production
- [x] Android Emulator ผ่าน Google Sign-In → Firebase ID token → Render Staging API
- [ ] ผ่าน smoke test ใน `docs/STAGING.md` ก่อน merge หรือ deploy Production

---

## 1) สลับ provider เป็นของจริง (ตัวแปร env ของ API)

ค่าเริ่มต้นทั้งหมดเป็น `mock`/`memory` และใน `NODE_ENV=production` เซิร์ฟเวอร์จะไม่
ยอมสตาร์ทถ้า `AUTH_PROVIDER=mock` หรือ `BILLING_PROVIDER=mock`

| ตัวแปร | จาก → เป็น | คีย์/สิ่งที่ต้องมี |
|---|---|---|
| `NODE_ENV` | `development` → `production` | — |
| `AUTH_PROVIDER` | `mock` → `firebase` | `FIREBASE_PROJECT_ID` |
| `BILLING_PROVIDER` | `mock` → `store` หรือ `revenuecat` | webhook token + REST key (ดูข้อ 6) |
| `VIDEO_STORAGE` | `mock` → `r2` | `CLOUDFLARE_R2_*` |
| `CAPTION_PROVIDER` | `mock` → `gemini` | `GEMINI_API_KEY` |
| `TRANSCRIPTION_PROVIDER` | `mock` → `groq` | `GROQ_API_KEY` |
| `EDIT_PLAN_PROVIDER` | `mock` → `groq` (หรือ `openai`) | `GROQ_API_KEY` |
| `SOCIAL_PUBLISHER` | `mock` → `postpeer` | (ดูข้อ 5) |
| `PUBLISH_QUEUE` | `memory` → `bullmq` | `REDIS_URL` (Upstash) |
| `*_STORE` (post/subscription/analytics/template/captionUsage/aiEditUsage) | `memory` → `prisma` | `DATABASE_URL` |

> ✅ ทดสอบแล้วว่าคีย์ใช้ได้จริง: **Gemini, Cloudflare R2, Groq**

---

## 2) ฐานข้อมูล (Render PostgreSQL)

- [x] สร้าง Render PostgreSQL และ API แล้ว; ต้องตรวจ `DATABASE_URL` และ secrets
      ใน Dashboard ซ้ำก่อนเปิดจริง เพราะสถานะที่บันทึกไว้เป็น snapshot แบบลงวันที่
- [ ] รัน migration: `npm run prisma:migrate:deploy`
      (รวม migration ใหม่ `*_add_partial_published_status` สำหรับสถานะ
      `PARTIAL_PUBLISHED` ที่เพิ่งเพิ่ม)
- [ ] ตั้ง `*_STORE=prisma` ทุกตัว แล้วทดสอบ `GET /posts`, `POST /posts`,
      `GET /billing/subscription`

---

## 3) Worker แยก (สำคัญ — จำเป็นเมื่อ `PUBLISH_QUEUE=bullmq`)

- [ ] Deploy **worker service แยก** ที่รัน `npm run worker:publish`
- ⚠️ ถ้าไม่มี worker: โพสต์ทันทีและตั้งเวลา **จะค้างสถานะ QUEUED** ไม่ถูกประมวลผล
- worker ตัวนี้เป็นคนอัปเดตสถานะโพสต์ (QUEUED → PUBLISHED/PARTIAL_PUBLISHED/FAILED)
  Retry ทำเฉพาะ error ที่ยืนยันว่าปลอดภัย; network/timeout หรือ outcome ที่ไม่
  แน่นอนต้องหยุดและให้ผู้ใช้ตรวจปลายทางก่อน เพื่อไม่สร้างโพสต์ซ้ำ

---

## 4) การลบวิดีโอชั่วคราว (R2 lifecycle) — ต้องแยกประเภทไฟล์ก่อน

- การลบวิดีโอทันทีหลังโพสต์ถูก **ปิดเป็นค่าเริ่มต้น** (กัน PostPeer ดึงไฟล์ไม่ทันแล้ว
  โพสต์หลุดเงียบ)
- [ ] ห้ามตั้ง lifecycle ลบทั้ง prefix `uploads/` ภายใน 7 วัน เพราะโพสต์อาจตั้งเวลา
      ล่วงหน้าได้นานกว่านั้น ให้แยก prefix ของไฟล์ AI ชั่วคราวออกจากไฟล์ที่รอโพสต์ก่อน
      แล้วจึงตั้งอายุเฉพาะ prefix ชั่วคราว
- ✅ ตอนผู้ใช้ลบบัญชี API จะไล่ลบทุก object ใต้ owner prefix ของ Firebase UID
      ก่อนลบฐานข้อมูล; lifecycle ยังจำเป็นเป็นตาข่ายสำหรับ signed upload ที่มาช้า
- signed download URL ตั้งอายุขั้นต่ำ 1 ชม. แล้ว (ให้ PostPeer/Gemini ดึงทัน)

---

## 5) PostPeer (การโพสต์จริง — หัวใจของแอป)

- [ ] `SOCIAL_PUBLISHER=postpeer`, ตั้ง `POSTPEER_API_KEY`
- [ ] ในแอป ให้ผู้ใช้ทดสอบเชื่อมบัญชีผ่าน PostPeer แล้วกด refresh จนสถานะขึ้น connected
- [ ] `POSTPEER_*_ACCOUNT_ID` เป็น optional legacy/operator id เท่านั้น สำหรับ setup ที่ไม่มี per-user connection store
- [x] Profile creation ใส่ชื่อ pseudonymous ที่ PostPeer บังคับและ ensure `User`
      ก่อนบันทึก profile แล้ว
- [x] รองรับ `202 pending/publishing` ด้วย bounded poll ประมาณ 2 นาที, ไม่สร้าง
      external id ปลอม และ `GET /posts` คืน user-scoped `platformResults` แล้ว
- [x] Controlled-first request ใช้ YouTube `private` และ TikTok `SELF_ONLY`
      (`draft: false`) แล้ว; ก่อนเปิด public ต้องเพิ่มตัวเลือก privacy ที่ผู้ใช้ยืนยัน
- [ ] ทดสอบโพสต์จริง 1 คลิปด้วยบัญชี disposable ที่เชื่อมแล้ว: TikTok,
      YouTube Shorts, Instagram Reels และ Facebook Page Video พร้อมตรวจ URL/ID,
      partial/failed และ outcome-unknown ก่อน retry
- หมายเหตุ: `FACEBOOK_REELS` เป็นชื่อ compatibility ภายใน แต่ PostPeer ปัจจุบัน
  ส่ง Facebook Page Video ไม่ใช่ Reels จึงห้ามใช้คำว่า Facebook Reels ใน Store
- หมายเหตุ: Shopee/Lazada ยังไม่รองรับใน PostPeer mapping (เพิ่มภายหลัง)

---

## 6) Subscription / การเก็บเงิน

- [x] เลือก RevenueCat เป็นเส้นทางหลัก: มือถือใช้ `purchases_flutter` + backend
      `BILLING_PROVIDER=revenuecat` + `REVENUECAT_WEBHOOK_AUTH_TOKEN`
- [x] สร้าง Test Store products `postdee_starter_monthly` / `postdee_pro_monthly`,
      entitlements, current offering และ webhook ของ Staging
- [x] ทดสอบซื้อ Test Store ด้วย Firebase UID บน Android Emulator สำเร็จ
- [x] Deploy `POST /billing/revenuecat/resync`, ตั้ง server REST key ใน Render
      Staging และทดสอบ true Restore/resync E2E บน Android Emulator แล้ว
- [x] เตรียม RevenueCat Play Store app, Starter/Pro products, entitlements,
      default offering, production Android public SDK key และ signed AAB แล้ว
- [ ] ทดสอบ renew/cancel/refund และ replay ด้วย Test Store
- [ ] ยืนยัน Play Console ด้วยมือถือ Android จริง จากนั้นสร้าง Play Console
      app/subscriptions, service credentials และ internal testing แล้วอัปโหลด AAB
      เพื่อทดสอบซื้อ/Restore ผ่าน Google Play จริง; Emulator ใช้ยืนยันบัญชีไม่ได้
- [ ] ตั้ง product ใน App Store Connect และทดสอบซื้อบน iOS sandbox แยกต่างหาก
- ✅ มีตาข่ายกันหมดอายุแล้ว: ถ้า webhook พลาด ระบบจะตัดเป็น BASIC เมื่อเลย
      `currentPeriodEnd`

---

## 7) Firebase (Auth + Phone + Push)

- [x] ไฟล์ config มีครบแล้ว (`google-services.json`, `GoogleService-Info.plist`)
- [x] เพิ่ม SHA-1 และ SHA-256 ของ release keystore ใน Firebase และอัปเดต
      `google-services.json` ให้มี Android OAuth client ของ Release แล้ว (14 ก.ค. 2026)
- [x] Staging: เปิด Email/Password และ Google, เพิ่ม Debug SHA-1/SHA-256 และผ่าน
      Google Sign-In/token/API smoke บน Android Emulator
- [ ] Production: เปิด/ยืนยัน provider **Google, Apple, Phone, Cloud Messaging**
- [ ] iOS: เพิ่ม capability "Sign in with Apple" + "Push Notifications" + อัป APNs key
- [x] Android Debug Staging build ด้วย `staging.local.json`; ห้ามใช้ไฟล์นี้กับ
      Profile/Release ซึ่งยังผูก Firebase Production
- ✅ token รีเฟรชอัตโนมัติ + กู้ session ตอนเปิดแอปแล้ว (ไม่หลุดล็อกอินทุกครั้ง)
- ✅ มือถือส่ง device token ขึ้น `POST /devices` แล้ว (เก็บราย user, ลบตอนลบบัญชี)
- ✅ backend ยิงแจ้งเตือนผลโพสต์ (สำเร็จ/บางส่วน/ล้มเหลว) ไปยัง device ของ user หลังโพสต์เสร็จ ผ่าน `PublishNotifier` + `PushSender`
- ✅ เขียน adapter ส่งจริงด้วย firebase-admin ไว้แล้ว (`createFirebasePushSender`, โหลดแบบ dynamic import)
- ✅ ติดตั้ง `firebase-admin` ใน `apps/api` แล้ว (test/build ผ่าน, default ยังเป็น mock)
- ⏳ **เปิดใช้ push จริง** เมื่อพร้อม:
  1. ตั้ง `FIREBASE_SERVICE_ACCOUNT_JSON` ใน Render (service account key จาก Firebase Console → Project Settings → Service Accounts, เก็บเป็นความลับ)
  2. สลับ `PUSH_SENDER=firebase` (ทำหลังใส่ key แล้วเท่านั้น ไม่งั้น API จะ crash ตอนเริ่ม)
  3. ทดสอบส่ง push จริงบนเครื่อง
- [ ] ตั้ง `FIREBASE_AUTH_DELETE_ENABLED=true` หลังใส่ service account แล้ว
      จากนั้นทดสอบลบบัญชีจริง; โหมดนี้ใช้ Firebase Admin ตรวจ token ที่ถูก
      revoke/ลบแล้วด้วย

---

## 8) ทดสอบบนเครื่องจริง (smoke test ปลายทาง)

- [x] อัปเดต `ffmpeg_kit_flutter_new_video` เป็น `2.3.2` ซึ่งรวม FFmpeg 8.1.2
      และการแก้ CVE-2026-8461 สำหรับ Android/iOS แล้ว
- [x] Android API 34 Emulator: เลือกคลิป 720×1280, อ่าน metadata, เรนเดอร์ AI
      เป็น MP4 และเปิด preview/เลื่อนเวลาได้ด้วย FFmpeg 8.1.2
- [ ] ทดสอบ export ด้วย FFmpeg 8.1.2 บน Android และ iPhone จริงก่อนรับไฟล์
      จากผู้ใช้ทั่วไป ระหว่างนี้ให้ทดสอบเฉพาะคลิปที่ทีมสร้างหรือเชื่อถือได้
- [ ] ล็อกอิน Google + Apple + ยืนยันเบอร์ (OTP) สำเร็จ บนมือถือจริง
- [ ] อัปคลิป → โพสต์ทันที → ขึ้นจริงทุก capability ที่ระบุไว้ → provider URL/ID
      และ `GET /posts.platformResults` ตรงกัน (Facebook คือ Page Video)
- [ ] ตั้งเวลาโพสต์ → ปฏิทินแสดง → ถึงเวลาแล้วโพสต์จริง
- [ ] AI แคปชั่นจากคลิป (Starter ฟัง / Pro ฟัง+ดูเฟรม)
- [ ] AI ตัดต่อ/ซับ (Pro) + export บนเครื่อง
- [ ] ซื้อแพ็กเกจ (sandbox) → ปลดล็อกฟีเจอร์
- [ ] ลบบัญชี → โปรไฟล์/โพสต์/R2/Firebase UID หายจริง และแพ็กเกจใน Store
      ยังแสดงขั้นตอนจัดการสมาชิกแยกอย่างถูกต้อง

---

## 9) ภายหลัง (ไม่บล็อกการเปิด)

- [ ] Sentry (error tracking) — API, worker, mobile
- [x] FCM backend sender + device token endpoint มีในโค้ดแล้ว; งานที่เหลือคือ
      ใส่ service account, ตั้ง `PUSH_SENDER=firebase`, ตั้ง APNs และทดสอบเครื่องจริง
- [ ] Analytics: ตัวดึง views/likes จริงจากแพลตฟอร์ม (ตอนนี้แสดง 0)
- [ ] PostPeer: รองรับ Shopee/Lazada + ยิงรวมหลายแพลตฟอร์มในคอลเดียว
- [ ] รองรับ Shopee/Lazada ครบทั้ง backend (validation/Prisma enum) + โลโก้จริง
