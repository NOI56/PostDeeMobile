# LAUNCH_CHECKLIST.md

เช็กลิสต์ก่อนเปิดใช้งานจริง / ทดสอบกับผู้ใช้จริง สำหรับ PostDee

> ภาพรวม: โค้ดและสถาปัตยกรรมพร้อมแล้ว (บั๊กระดับสูงอุดครบ, เทสต์เขียวทั้ง API
> และ mobile) เหลือขั้นตอน "เสียบคีย์ + ตั้งค่าโครงสร้างจริง + ทดสอบบนเครื่อง"
> ตามลำดับด้านล่าง

---

## 0) Staging แยกจาก Production

- [x] เตรียม `render.staging.yaml` และเทสต์ว่าชื่อ service/database แยกจาก Production
- [ ] ตรวจว่า workspace ยังมีสิทธิ์สร้าง Free PostgreSQL อีกหนึ่งตัว ถ้ามีฐาน Free
      อยู่แล้วให้หยุด ห้ามใช้ฐาน Production ร่วมกัน
- [ ] สร้าง Blueprint `postdee-api-staging` จาก branch
      `codex/ai-edit-thai-timing-staging`
- [ ] ใส่ R2/Firebase/RevenueCat/PostPeer credentials ชุดทดสอบเท่านั้น
- [x] ตั้ง Staging เริ่มต้นเป็น `SOCIAL_PUBLISHER=disabled`; สลับ PostPeer เฉพาะ
      controlled test ด้วยบัญชีทดสอบแล้วสลับกลับ
- [ ] เตรียม Firebase mobile config แยกที่ตรงกับ Staging project ก่อนทดสอบ login
- [ ] ผ่าน smoke test ใน `docs/STAGING.md` ก่อน merge หรือ deploy Production

---

## 1) สลับ provider เป็นของจริง (ตัวแปร env ของ API)

ค่าเริ่มต้นทั้งหมดเป็น `mock`/`memory` และใน `NODE_ENV=production` เซิร์ฟเวอร์จะไม่
ยอมสตาร์ทถ้า `AUTH_PROVIDER=mock` หรือ `BILLING_PROVIDER=mock`

| ตัวแปร | จาก → เป็น | คีย์/สิ่งที่ต้องมี |
|---|---|---|
| `NODE_ENV` | `development` → `production` | — |
| `AUTH_PROVIDER` | `mock` → `firebase` | `FIREBASE_PROJECT_ID` |
| `BILLING_PROVIDER` | `mock` → `store` หรือ `revenuecat` | (ดูข้อ 6) |
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
  และมี idempotency กันโพสต์ซ้ำตอน retry แล้ว

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
- [ ] ทดสอบโพสต์จริง 1 คลิป ครบทุกแพลตฟอร์มด้วยบัญชีทดสอบที่เชื่อมแล้ว
- หมายเหตุ: Shopee/Lazada ยังไม่รองรับใน PostPeer mapping (เพิ่มภายหลัง)

---

## 6) Subscription / การเก็บเงิน

- [ ] เลือกทางเดียวให้ตรงกันทั้งมือถือและ backend:
  - **Store IAP**: มือถือใช้ `in_app_purchase` + backend `BILLING_PROVIDER=store`
    (`/billing/store/verify`)
  - **RevenueCat**: มือถือใช้ `purchases_flutter` + backend
    `BILLING_PROVIDER=revenuecat` + `REVENUECAT_WEBHOOK_AUTH_TOKEN`
  - ⚠️ ถ้าไม่ตรงกัน การซื้อจะ fail (501)
- [ ] ตั้ง product ใน App Store Connect / Google Play, ทดสอบซื้อบน sandbox device
- ✅ มีตาข่ายกันหมดอายุแล้ว: ถ้า webhook พลาด ระบบจะตัดเป็น BASIC เมื่อเลย
      `currentPeriodEnd`

---

## 7) Firebase (Auth + Phone + Push)

- [x] ไฟล์ config มีครบแล้ว (`google-services.json`, `GoogleService-Info.plist`)
- [x] เพิ่ม SHA-1 และ SHA-256 ของ release keystore ใน Firebase และอัปเดต
      `google-services.json` ให้มี Android OAuth client ของ Release แล้ว (14 ก.ค. 2026)
- [ ] เปิด provider ใน Firebase Console: **Google, Apple, Phone, Cloud Messaging**
- [ ] iOS: เพิ่ม capability "Sign in with Apple" + "Push Notifications" + อัป APNs key
- [ ] build ด้วย `--dart-define=ENABLE_FIREBASE_AUTH=true` (+ `GOOGLE_SERVER_CLIENT_ID`)
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
- [ ] อัปคลิป → โพสต์ทันที → ขึ้นจริงทุกแพลตฟอร์ม → สถานะอัปเป็น PUBLISHED
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
