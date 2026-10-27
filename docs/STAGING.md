# PostDee Staging

## ทดสอบลบบัญชีกับบริการจริง — 26 ตุลาคม 2026

ผู้ใช้อนุมัติให้รวม PR #36 เข้า `main` หลัง CI ผ่าน แล้ว deploy Staging และอนุมัติการทดสอบ
ด้วยบัญชีทดสอบใช้แล้วทิ้ง ผ่าน Staging ทั้ง 2 ทาง Production ยัง user-suspended ไม่ถูกแตะ

- รวม PR #36 เป็น `35890b1` (CI Backend API และ Flutter Mobile ผ่าน) แล้ว deploy
  `dep-dbfepmnavr4c73dsis80` เป็น Live 06:03:28 UTC; startup ใช้ migration
  `20261026010000_admin_account_deletions` สำเร็จ รวม 25 migrations
- กุญแจ service account ใหม่สร้างไม่ได้เพราะ organization policy ห้ามสร้างกุญแจ จึงให้เจ้าของ
  เพิ่มบทบาท **Firebase Authentication Admin** ให้บัญชีบริการเดิม `postdee-admin-verifier`
  ที่ Render Staging ใช้อยู่แล้ว ไม่สร้างหรืออัปโหลดกุญแจใหม่และไม่แก้ secret ใน Render
- ตั้ง `FIREBASE_AUTH_DELETE_ENABLED=true` และ `UPLOAD_PROTOCOL_MODE=multipart` ชั่วคราว
  (merge เฉพาะ 2 ค่า) deploy `dep-dbff3f8m7kps738rtp30` Live 06:24:21 UTC ที่ `296bee1`
  ซึ่งต่างจาก `35890b1` เฉพาะ Mobile/เอกสาร; startup ผ่าน ยืนยันว่ากุญแจ Firebase ใช้ได้
- **ทาง 1 ลบในแอป (`DELETE /account`)** 07:15 UTC: สคริปต์บนเครื่องเจ้าของสร้างบัญชี
  `@example.com` ใหม่ → เทมเพลต 201 → readiness 200 → ลบ 200 ภายในราว 2 วินาที →
  token เดิมได้ 401 → เข้าสู่ระบบด้วยรหัสเดิมได้ `INVALID_LOGIN_CREDENTIALS`
  (Firebase เปิด email enumeration protection) และ Firebase Console ค้นหาไม่พบบัญชี
- **ทาง 2 ลบจากหน้าแอดมิน** 07:35:25 UTC: เจ้าของลบบัญชี `@example.com` ที่ 2 จาก
  `/admin` ได้ข้อความ "ลบบัญชีแล้ว" ประวัติการลบบัญชีแสดง "ลบเรียบร้อย" พร้อมเหตุผล
  ไม่มีอีเมลในบันทึก และ Firebase Console ค้นหาไม่พบบัญชี
- log ของ Render ไม่มี error/warning ระหว่างทดสอบ (บริการนี้ไม่มี request log ให้ตรวจ)
- คืนค่า `FIREBASE_AUTH_DELETE_ENABLED=false` และ `UPLOAD_PROTOCOL_MODE=dual` แล้ว
  deploy `dep-dbfg74o473hc73d2mjsg` Live 07:40:27 UTC ที่ `d113879` (API ไม่เปลี่ยน)
  เจ้าของถอดบทบาท Firebase Authentication Admin ออกจาก `postdee-admin-verifier` แล้ว
  ภาพหน้า IAM ยืนยันว่าเหลือเฉพาะ Firebase Authentication Viewer

ยังไม่ครอบคลุม: บัญชีทดสอบไม่มีการเชื่อมโซเชียลหรือไฟล์อัปโหลด จึงยังไม่ได้ยืนยันการลบ
integration/โปรไฟล์ที่ PostPeer จริง และการลบ object จริงใน R2 (เรียก owner-prefix cleanup
กับ prefix ว่างเท่านั้น) ทาง 1 เรียก API โดยตรง ไม่ได้กดผ่าน UI ในแอปบนมือถือ รายละเอียดอยู่ใน
[บันทึกแผน](superpowers/plans/2026-10-25-account-deletion-postpeer-profile.md#staging-real-service-acceptance-2026-10-26)

## Facebook Page Reels — 24 ตุลาคม 2026

[Deploy `dep-dbdqk7sipgvc739q4r50`](https://dashboard.render.com/web/srv-d9bb72ojs32c739osa5g/deploys/dep-dbdqk7sipgvc739q4r50)
เป็น **Live** ที่ source `342470fbc2f656ca4a3d289ddcd500ce58177a6e` จาก `main`
เวลา 01:41:49 น. ไทย (23 ตุลาคม 2026 เวลา 18:41:49 UTC).

- วางแพตช์บนฐาน `a4efd65` และรักษา platform settings, captions, target snapshots,
  TikTok Direct Post และ billing ของ `main` ล่าสุด ไม่คัดลอกสาขาเก่าทับระบบใหม่.
- Facebook ส่ง `contentType: 'reel'` เสมอ รวมโหมด `PAGE_DRAFT`; คง
  `published`, `isAiGenerated` และบัญชีเจ้าของโพสต์ ไม่มี Page feed fallback.
- ซิงก์ `REVENUECAT_SUBSCRIPTION_ENVIRONMENT=SANDBOX` ตาม Staging Blueprint
  ก่อนรุ่นใหม่เริ่มทำงาน; ไม่มี schema/dependency/migration ใหม่จากแพตช์ Reels.
- ตรวจด้วย Node `22.23.3`: API 2,577 tests ผ่าน/25 ข้าม (4 ชุดต้องใช้ฐานข้อมูล
  ทดสอบแยก), typecheck, build, Prisma generate/validate และ built-server
  `/health`/`/ready` ผ่าน. Backend CI ของ source เดียวกันผ่านแล้ว.
- หลัง Live: `/health` และ `/ready` ตอบ HTTP 200, database/queue `ok`,
  `/ready` มี `Cache-Control: no-store`; `/posts` ที่ไม่มี token ตอบ 401.
  ไม่พบ app error logs ในช่วง 18:40:31–18:42:33 UTC ที่ตรวจ.
- Mobile targeted tests 253 ผ่าน/1 ข้ามและ analyze ผ่าน; full suite ในเครื่อง
  หยุดเพราะ PowerShell หน่วยความจำไม่พอหลัง 2,525 ผ่าน/5 ข้าม จึงไม่ถือว่า
  full suite ผ่านจากการรันในเครื่อง. Full Mobile suite และ analyze ของ source
  เดียวกันผ่านครบแล้วบน GitHub พร้อม Backend API ที่
  [CI run 40005219097](https://github.com/NOI56/PostDeeMobile/actions/runs/40005219097).
- รอบนี้ deploy เฉพาะ API Staging ไม่แจก APK และไม่ resume/deploy Production.
  ยังไม่ได้โพสต์ Reel จริง; provider delivery, draft และ custom thumbnail E2E
  ต้องตรวจด้วยเพจทดสอบที่เชื่อมบัญชีแล้ว.

## รวมชุด Staging เข้า main — 20 ตุลาคม 2026

ผู้ใช้อนุมัติ main/push หลังตรวจรายการค้าง จึงรวม runtime `0a43e7b`, เอกสาร
ส่งมอบ `39f96f9` และผลตรวจ DB integration `ad788aa` เข้า `main` แบบ fast-forward
จากฐาน `c2777a8` เอกสารสถานะรอบนี้ไม่เปลี่ยน API runtime, dependencies,
Mobile, CI, schema หรือ migrations จากชุดที่ทดสอบแล้ว

API tree ตรงรุ่นที่ build/ตรวจและ deploy บน Staging ผล DB-enabled suite ผ่าน
138 files/2,323 tests ไม่มี skip และ DB tests 18/18 ผ่านทั้ง UTC/Asia/Bangkok
พร้อมตรวจ cleanup และปิด local fixture แล้ว รายละเอียดด้านล่าง

ก่อน push ตรวจ Render ใน My Workspace พบ Production `postdee-api` ยัง
user-suspended แม้มี auto-deploy `commit`; Staging มี auto-deploy `off`
commit เอกสารการรวมใช้ `[skip render]` เพื่อส่ง source/CI ตามคำขอโดยคงบริการเดิม
ไม่ resume/redeploy หรือแก้ Dashboard/Blueprint/environment/ฐานข้อมูลในรอบนี้
API Staging ที่บันทึกไว้ยังเป็น source `0a43e7b`; การรวมเอกสารไม่ต้อง deploy ซ้ำ
Provider/device และ live admin-to-Mobile acceptance ยังเป็นงานตรวจแยกต่างหาก

## ส่งมอบชุดแก้ Staging — 20 ตุลาคม 2026

[Deploy `dep-dbbmva3bc2fs73bnpemg`](https://dashboard.render.com/web/srv-d9bb72ojs32c739osa5g/deploys/dep-dbbmva3bc2fs73bnpemg)
เป็น **Live** ที่ source `0a43e7b273415578d15ae3f8e970c66b362ac48e` จาก branch
`codex/staging-readiness-20261020` เวลา 20:43:18 น. ไทย (13:43:18 UTC)
วันที่ 20 ตุลาคม 2026 ใช้เวลา 1 นาที 18 วินาที ณ ตอน deploy ยังไม่ merge เข้า
`main`; การรวมภายหลังอยู่ในหัวข้อด้านบน

- Remote shell ของ instance ใหม่ `wf8ss` ยืนยัน SHA ตรง, Node `22.23.3`,
  npm `10.9.9`, Firebase Admin `14.5.0` และ Morgan `1.12.1`; ไม่มี Firestore/
  Google Cloud Storage clients หลัง prune ค่า Node 26.12.0 ด้านล่างเป็นก่อน deploy
- Startup พบ 20 migrations/ไม่มี pending, backlog guard ผ่านด้วยคิวว่าง,
  ใช้ port 10000 และ memory scheduler คง flags Social `postpeer`, guard `true`,
  push `mock`, account deletion `false` และ admin Staging ตามเดิม
- หลัง deploy `/health`/`/ready` HTTP 200 พร้อม database/queue `ok` และ `no-store`;
  `/posts`/publishing readiness ที่ไม่ส่ง token ตอบ 401 ไม่พบ error-level logs
  ในช่วง 13:42:00–13:44:21 UTC ที่ตรวจ
- Remote shell หลัง deploy ตรวจ `SELECT 1` ใน read-only transaction ผ่าน,
  migrations 20 รายการและ publish backlog 0; ทดสอบสร้าง/อ่าน/แก้ไขแถว User
  จำลองใน transaction แล้วบังคับ rollback ผ่าน ตรวจซ้ำว่าไม่มีแถวจำลองค้าง
- ไม่ sync Blueprint หรือแก้ service environment, ไม่ส่งโพสต์/Push จริง และ
  Production API/database ยังคง user-suspended; ณ ตอน deploy remote `main`
  ยังเป็น `c2777a8`

ผลส่งมอบอยู่ใน `D:\PostDeeMobile\artifacts\staging-prep-20261020\deployment.json`
และภาพ `staging-live.png`; `summary.json` เก็บผลขั้นเตรียม source เดิม
การแก้เอกสารหลัง deploy ไม่เปลี่ยน API SHA ที่รันอยู่และไม่ต้อง deploy API ซ้ำ
ผล deploy นี้ยังไม่ยืนยัน provider/device E2E; DB integration tests 18 กรณี
ที่ข้ามในรอบก่อน deploy ผ่านบนฐาน local แยกแล้วตามบันทึก follow-up ด้านล่าง

รอบนี้เตรียม source ใน managed worktree จาก `main`
`c2777a8f93048d88efb596fddbaa7244dc0f3595` ซึ่งตรวจตรงกับ remote แล้ว
ไม่ใช้ checkout เก่า `D:\PostDeeMobile` ที่ยังมีงานค้างเป็นชุด deploy และไม่คัดลอก
เอกสารหรือโค้ดทั้งไฟล์จาก branch เก่าทับระบบปัจจุบัน

- ชุดแก้ที่เลือก: Firebase Admin `14.5.0`, Morgan `1.12.1` และ scoped override
  เฉพาะ `@prisma/config@6.19.3` ให้ใช้ `deepmerge-ts@8.0.2`; คง Prisma 6.19.3
- ปรับ FCM sender ให้ใช้ modular `firebase-admin/app` และ
  `firebase-admin/messaging` พร้อม regression tests 13 กรณี ผลตรวจด้านล่าง
  เป็นของ candidate นี้ ไม่ใช้ผลจาก checkout เก่ามารับรองแทน
- ปรับ Blueprint/tests/docs ให้โครงสร้างตรงกับ Staging ที่อ่านสถานะไว้ก่อนหน้า:
  Web `starter`, branch `main`, หนึ่ง instance, auto-deploy `off` และ PostgreSQL
  `basic-256mb`, 1 GB, major version `18`, ปิดการเชื่อมต่อฐานจากภายนอก
  (`basic_256mb` เป็นชื่อแผนที่ Render API ส่งกลับ ส่วน YAML ใช้ขีดกลาง)
- คง CI, admin/trial access, publishing และ Mobile ปัจจุบันจาก `main`
  รวมถึง ElevenLabs transcription/Gemini planning; ไม่มี schema/migration ใหม่

ผลตรวจ candidate หลังเพิ่ม Node engine pin ในเครื่องด้วย Node 22.23.3/npm 10.9.9:

- API เต็มชุด `--maxWorkers=2` ผ่าน 136 files/2,305 tests
  และข้าม 2 files/18 tests ใน `adminDatabase.test.ts`/`adminUsageDatabase.test.ts`
  เพราะยังไม่ได้ตั้ง `ADMIN_TEST_DATABASE_URL` จึงยังไม่ยืนยัน DB integration สองชุดนี้
- Typecheck, build รวม admin assets, Prisma generate 6.19.3/validate/helper checks,
  shared catalog parity 100 รายการ และ generator tests 22 กรณีผ่าน
- Dependency tree ไม่มีปัญหา; production audit `--omit=dev` ที่รวม optional
  dependencies เหลือ 0 findings ทุกระดับ; clean install 446 packages และ tree check
  ผ่านโดย package/lock hashes ไม่เปลี่ยน ยืนยันซ้ำหลัง Node pin ใน
  `predeploy-clean-install-result.json`
- Blueprint ผ่าน current official JSON schema; ไม่มี Render CLI ในเครื่องจึงยัง
  ไม่ได้ตรวจแบบ platform-aware ไม่มี Mobile changes จึงไม่ได้รัน Flutter ซ้ำ
- รอบ default workers พบ profile 100-image test timeout 15 วินาทีระหว่างงาน
  parallel; ตรวจ targeted ซ้ำผ่าน 2 files/26 tests และเต็มชุด workers 2 ผ่าน
  โดยไม่เปลี่ยน source หรือ timeout เพื่อให้ผ่าน

### ตรวจ DB integration เพิ่มเติม — 20 ตุลาคม 2026

- ใช้ source เดียวกับ API ที่ deploy (`0a43e7b`; HEAD ขณะทดสอบ `39f96f9`
  เพิ่มเฉพาะเอกสาร)
  และ Node 22.23.3/npm 10.9.9 สร้าง PostgreSQL 18.1 cluster ใหม่ในเครื่อง
  ฟังเฉพาะ `127.0.0.1:55439` ฐาน `postdee_admin_fixture` และ apply migrations
  เดิมครบ 20 รายการ ไม่มี migration ใหม่ ไม่เชื่อมฐาน Staging/Production
- `adminDatabase.test.ts` และ `adminUsageDatabase.test.ts` ผ่าน **18/18**
  ทั้ง DB session timezone `UTC` และ `Asia/Bangkok` โดยตรวจค่า timezone
  ผ่าน connection ใหม่ก่อนรันแต่ละรอบ ครอบคลุม trial/audit transaction,
  rollback, คำขอซ้ำ/คำขอพร้อมกัน, การแบ่งหน้า, ช่วงเวลา และ report snapshot
- รัน API เต็มชุดพร้อม `ADMIN_TEST_DATABASE_URL` บน session `Asia/Bangkok`
  ด้วย `--maxWorkers=2` ผ่าน **138 files/2,323 tests ไม่มี skip** ใน 54.35 วินาที
  ไม่พบปัญหาที่ต้องแก้โค้ด ผล 2,305 pass/18 skip ด้านบนเป็นประวัติก่อน deploy
- ข้อมูลจำลอง 1,000 บัญชี/10,000 โพสต์/20,000 ผลส่ง: รายงานพร้อมกัน 15 ครั้ง
  ได้ผลถูกต้องทั้งหมด รายงานแรกที่นับ query ใช้ 1 SELECT; เวลาตอบรายงาน p95
  ในรอบ targeted คือ UTC 225.03 ms และ Bangkok 190.36 ms ตัวเลขนี้เป็นผล local
  ไม่ใช่การยืนยันกำลังรองรับโหลดของ Staging
- หลังทดสอบตรวจตารางแอปทั้ง 18 ตารางว่าง ไม่มี connection/transaction อื่นค้าง
  ปิด cluster ที่สร้างรอบนี้แล้วและพอร์ต 55439 ปิด เก็บ logs/ผลตรวจที่
  `D:\PostDeeMobile\artifacts\db-tests-20261020\summary.json`
  รอบนี้แก้เฉพาะเอกสารผลตรวจ ไม่ deploy ซ้ำ และยังไม่ยืนยัน provider/device E2E

หลักฐาน deploy อยู่ที่ `D:\PostDeeMobile\artifacts\staging-prep-20261020\deployment.json`
ผลข้างต้นไม่ใช่การ deploy หรือ provider/device E2E; ผลอ่าน DB จริงเพิ่มเติมอยู่ด้านล่าง

ผลอ่าน Render ก่อนเตรียมชุดนี้ใน `My Workspace`: Staging API ตอบ `/health`
HTTP 200; deploy `dep-dba83jqjnfac73enqm40` เป็น `live` ที่ commit
`1cf755eba9b156f95bb818eb2d5ee7fb7c0efd86` ตั้งแต่ 18 ตุลาคม 2026 และฐานข้อมูล
Basic 256 MB/1 GB PostgreSQL 18 เป็น `available` ผลนี้ยังไม่ใช่การ deploy หรือ
ทดสอบ candidate ใหม่ ส่วน Production API/database ถูก suspend โดยผู้ใช้และไม่ได้เปลี่ยน

**ยังห้าม sync Blueprint ทั้งไฟล์:** ผล predeploy ด้านล่างยืนยันว่า live
Social เป็น `postpeer` ต่างจาก YAML `disabled` การ sync อาจทับค่าที่ใช้อยู่
รอบนี้จึง deploy เฉพาะ SHA ที่ตรวจแล้วโดยรักษา Dashboard environment แทน และรักษา
credentials/ข้อมูลของ Staging แยกจาก Production ค่า `sync: false` ไม่ได้ยืนยัน
ว่า key ใช้งานกับ provider ได้
Render ไม่อัปเดต keys เหล่านี้ระหว่าง sync Blueprint เดิม; key ใหม่ต้องเพิ่มใน
Dashboard เอง ตาม [Blueprint specification](https://render.com/docs/blueprint-spec).

### บันทึกผลตรวจก่อน deploy

รายการนี้เป็นหลักฐานก่อน deploy; ผลของ instance ใหม่อยู่ที่หัวข้อส่งมอบด้านบน:

- ก่อน deploy process ใช้ Node `26.12.0` และไม่มี `NODE_VERSION` override จึงเพิ่ม exact
  engine pin `22.23.3` ใน package/lock ของ candidate ให้ตรง runtime ที่ใช้ตรวจ
  ผลตรวจ candidate หลังเพิ่ม pin ผ่านตามรายการด้านบน
- Live `SOCIAL_PUBLISHER=postpeer`, backlog guard `true`, `PUSH_SENDER=mock`
  และ account deletion `false` จึงคง Dashboard flags; ไม่ sync Blueprint,
  ไม่ merge เข้า `main` เพื่อหลีกเลี่ยง Production auto-deploy และไม่เปลี่ยนแผน/เครือข่าย
- `DATABASE_URL` ตรง host/database ของ Staging; R2 bucket เป็น `postdee-staging`
  และ Firebase project `project-798caf7e-85b8-45e3-af7` ตรง mobile Debug config
  และต่างจาก Production `postdee-3c163` ตรวจ service-account project ตรงกันและ
  มี private key พร้อม credentials ที่จำเป็น 8 keys โดยไม่แสดงค่าลับ
  ผลนี้ยืนยันการตั้งค่า/การมี key เท่านั้น ไม่ยืนยัน key validity หรือ provider E2E
- Read-only DB transaction `SELECT 1` ผ่าน; applied migration names 20 รายการ
  ตรง source และ Staging `1cf755e` ไม่มี migration ใหม่ และ publish backlog เป็น 0
  ไม่ได้เปิด external DB allowlist หรือเขียนข้อมูลทดสอบ
- Fresh install 446 packages → Prisma generate → prune ผ่าน; local runtime
  หลัง prune โหลด Firebase SDK/serve admin assets และตอบ `/health`/`/ready` 200
  หลักฐานแยกอยู่ใน `pruned-runtime-summary.json` ของโฟลเดอร์ artifacts รอบนี้
- Public checks ก่อน deploy ตอบ `/health`/`/ready` HTTP 200 พร้อม DB/queue `ok`
  และ `no-store`; ไม่ส่ง token แล้ว `/posts`/publishing readiness ตอบ 401
  ผลนี้เป็นของ Staging รุ่นเดิม ไม่ใช่หลักฐานว่า candidate ใหม่ขึ้นแล้ว

ตรวจ SHA/runtime/health/ready/migrations ของ instance ใหม่หลัง manual deploy แล้ว
DB integration ที่ข้ามผ่านบน local fixture แล้ว; ยังต้องทดสอบ provider/device E2E
รอบนี้ไม่มีการส่ง Push หรือสร้างโพสต์ทดสอบจริง

## ส่งมอบลูกเล่นระหว่างส่งโพสต์ แบบ 3 — 18 ตุลาคม 2026

- Runtime/CI source `5c83b3a` บนฐาน `main` ที่ตรวจล่าสุด `1cf755e` ผ่าน
  [CI 39110380204](https://github.com/NOI56/PostDeeMobile/actions/runs/39110380204):
  Flutter 2,437 pass/2 optional skips, analyze, build-guard 17 tests, API 2,291
  pass/18 optional skips, generator 22 tests, TypeScript/build/Prisma/audit
- ใช้ opt-in Test Store และ build number 12026 เพื่อข้ามปัญหา Flutter ในเครื่อง
  โดยคงค่าบัญชี/แพ็กเกจเดิม ตรวจ APK จริงและเซ็นด้วย debug key เดิมในเครื่อง
  ZIP payload ทั้ง 857 รายการตรงกันก่อน/หลังเซ็น ไม่มี private key/config ส่งขึ้น CI
- [API deploy dep-dba83jqjnfac73enqm40](https://dashboard.render.com/web/srv-d9bb72ojs32c739osa5g/deploys/dep-dba83jqjnfac73enqm40)
  เป็น Live ที่ `1cf755e` เวลา 15:24:35 GMT+7 ก่อนติดตั้ง APK โค้ด API ตรงกับ
  candidate `5c83b3a` และ main ที่รวมเฉพาะ Mobile/receipt ในภายหลัง จึงไม่ต้อง
  deploy API เดิมซ้ำ รุ่นนี้นำ route fix ชื่อ YouTube จาก main ไปใช้ด้วย ไม่มี migration ใหม่
- Startup ยืนยัน 20 migrations ไม่มี pending; health/ready ตอบ 200 พร้อม DB/queue
  ok และ unauthenticated posts/publishing-readiness ตอบ 401 ไม่พบ app error ใหม่
  ค่า service/flags/secrets/network/auto-deploy และ Production ไม่เปลี่ยน
- อัปเดต emulator `12025` → `12026` ผ่าน volume-aware helper สำเร็จ รักษา UID,
  adopted volume, first-install, บัญชี, ร่าง, ช่องทาง 2/4 และ Pro 244/250 ทั้ง Home
  กับ Account ตรวจ Home/Calendar/filter/รายละเอียดเดิม/Account และกลับ Home ผ่าน
  ไม่พบ fatal/unhandled/E Flutter/crash ใน log 907 บรรทัด
- ครั้งแรกอ่านแพ็กเกจไม่สำเร็จ แต่ read-only refresh หนึ่งครั้งกลับมา Pro ตามเดิม
  สาเหตุยังไม่ยืนยัน ไม่แก้สิทธิ์/บัญชี ไม่มีการส่งคลิป ซื้อ สร้าง AI หรือบันทึกฟอร์ม
  ไม่มีโพสต์กำลังส่งจริง จึงยังไม่ยืนยัน active animation/FPS บน native รอบนี้
  รายละเอียดโพสต์ยังต้องเปิดใหม่หลัง parent refresh เพื่อดูผลที่ใหม่ขึ้น
- [แผนและหลักฐาน](superpowers/plans/2026-10-18-publishing-motion.md) ระบุ source,
  SDK/config/APK/signature hashes และข้อจำกัดครบ เก็บหลักฐานที่
  `artifacts/publishing-motion-20261018` ในเครื่อง ไม่ใส่ artifacts เข้า Git

## ส่งมอบ account deletion authorization — 14 ตุลาคม 2026

- ผู้ใช้อนุญาต main/push/deploy หลังแก้ช่องทาง retry ลบบัญชี Source เริ่มจาก
  main `1bf125c` เป็น `5ebb0ac` และ follow-up `3481f3f` ที่เพิ่ม await การแปลงโลโก้
  เพื่อผ่าน Flutter analyzer รุ่นใหม่ ทั้ง main และ branch งาน push แล้ว
  งานเดิมที่ยังไม่ commit และ QA artifacts ถูกเก็บไว้ ไม่แก้ Production
- CI [`38452410378`](https://github.com/NOI56/PostDeeMobile/actions/runs/38452410378)
  ที่ SHA `3481f3fcff4c78d11b954a45906341a784d7654c` ผ่าน API 1,871 tests,
  Mobile เต็ม 2,189 tests, build/analyze/Prisma และ generator 22 tests
  มีการทดสอบ migration บน PostgreSQL 18.1 จำลองและ Prisma จริง 16 กรณี
  ก่อนส่งมอบ ไม่สร้างหรือติดตั้ง APK ใหม่
- [Render `dep-db785nvavr4c73a1cm80`](https://dashboard.render.com/web/srv-d9bb72ojs32c739osa5g/deploys/dep-db785nvavr4c73a1cm80)
  เป็น Live ที่ source เดียวกันเวลา 02:15:41 GMT+7 ใช้ 2m06s
  Start command ลง migration ก่อนเปิด API ตรวจภายในฐาน Staging ยืนยัน
  migration `20261014003000_authorize_account_deletion` สำเร็จ รวม 17 รายการ
  คอลัมน์ proof nullable ไม่มี default และไม่มีการเติมสิทธิ์ให้ข้อมูลเดิม
- `/health` และ `/ready` ตอบ 200 พร้อม DB/queue ok; ไม่ส่ง token แล้ว
  account/publishing readiness และ POST purchase-readiness ตอบ 401
  หน้าร้าน noikub เดิมเปิดได้ มี 2 ลิงก์ ตรวจ error log ของ instance ใหม่ไม่พบ
  ไม่ได้ทดสอบลบบัญชีหรือ cleanup ผ่าน Firebase/provider จริง
- คง Firebase project/ฐานข้อมูล Staging เดิม, 1 instance,
  `FIREBASE_AUTH_DELETE_ENABLED=false`, `SOCIAL_PUBLISHER=disabled` และ
  `PUBLISH_QUEUE=memory`; auto-deploy ปิดอยู่ ไม่แก้ secret/plan/network rules
  Production API ยัง user-suspended และไม่มี deployment ใหม่
- เอกสาร receipt เท่านั้นไม่ต้อง deploy ซ้ำ รายละเอียดอยู่ใน
  `superpowers/plans/2026-10-14-account-deletion-authorization.md`
  ข้อจำกัด TypeScript fixtures เดิม 142 จุด และ Redis/หลาย process/
  Firebase/provider/device acceptance ยังไม่ถือว่าปิดงาน

## ส่งมอบ security fixes จาก main ปัจจุบัน — 13 ตุลาคม 2026

- ใช้ baseline remote `main` ล่าสุด `f5dea16` ที่ fetch แล้ว (เริ่มจาก `c4e5220`) แยก branch
  `codex/security-main-delivery` และเก็บงานที่ยังไม่ commit ใน worktree เดิมไว้
  ไม่ใช้ patch จาก branch เก่าทับหน้าลิงก์ร้าน/เผยแพร่เว็บไซต์หรือระบบโพสต์ใหม่
- API เพิ่ม purchase-readiness protocol 1 แบบ additive และคง GET preparation
  สำหรับแอปเก่าไว้ก่อน โดยล็อก owner ใน transaction สุดท้ายของ User/Post/
  Subscription; เปิด owner marker ใน legacy ด้วย ไม่เปลี่ยน schema/provider
  หรือ Production flags คิวข้ามหลาย process และ provider calls ที่เริ่มแล้ว
  ยังมีข้อจำกัด
- แอปรักษา draft/ธีม/รูป/หน้าร้านและ pending purchase เดิม พร้อมเพิ่ม generation
  guards, bound HTTP/native auth และ push recipient UID ต้องส่ง API additive
  ก่อนติดตั้ง APK ใหม่ การเปลี่ยน GET เป็น read-only เป็นขั้นปล่อยแยกภายหลัง
- รวม source และตรวจโค้ดซ้ำแล้ว เพิ่ม test 148 กรณี ผ่าน API 1,816 tests,
  build/schema และ Flutter 2,171 tests/analyze ผู้ใช้อนุญาตให้ใช้ test/build
  ตามปกติของโปรเจกต์สำหรับการส่งมอบนี้ โดยยกเว้น sandbox ของ skill
  Runtime `9244f16` push เข้า main แล้ว และ deploy เป็น Live บน STAGING
  [dep-db71pfbl550s73ag4uo0](https://dashboard.render.com/web/srv-d9bb72ojs32c739osa5g/deploys/dep-db71pfbl550s73ag4uo0)
  เมื่อ 18:59:41 GMT+7; `/health` และ `/ready` ผ่าน ตรวจพบ migrations เดิม 16
  ชุด ไม่มีค้าง APK8017 ติดตั้งทับด้วยลายเซ็นเดิม ข้อมูลร้าน/session ยังอยู่
  ตรวจ Home/Calendar/Account/ร้าน noikub 2 ลิงก์, ราคา Test Store และเปิด/ปิด
  ฟอร์มยืนยันเบอร์ผ่าน ไม่ส่ง OTP ไม่ซื้อจริง ไม่โพสต์หรือลบบัญชีจริง
  ผล CI/smoke เก่าไม่ใช่ผลชุดใหม่ Production API ยัง user-suspended
  เอกสารส่งมอบอยู่ใน `superpowers/plans/2026-10-13-security-main-delivery.md`

## ส่งมอบ API และตรวจภาพ/วิดีโอ R2 — 8 ตุลาคม 2026

- ผู้ใช้อนุญาต deploy Staging และตรวจสื่อเพิ่มจากงาน source/main เดิม
  [Render dep-db3m2g59fdbs73ecbib0](https://dashboard.render.com/web/srv-d9bb72ojs32c739osa5g/deploys/dep-db3m2g59fdbs73ecbib0)
  เป็น Live ที่ source `9baa18c3483b2abd9b6f0ac619e74c00e15cbec6`, instance
  `gc9v8`; API/runtime ตรงกับ code `36dbacc` ที่ผ่าน CI เดิม
- Build ผ่านและมี 14 migrations ไม่มี pending; schema/lock/source configuration
  ไม่มีส่วนต่างจากรุ่น API เดิม `ae65b9d` ยืนยัน Staging DB/Firebase project
  เดิม และคง `SOCIAL_PUBLISHER=disabled`, memory scheduler 1 instance
  ไม่เปลี่ยน Production/แพ็กบริการหรือซื้อบริการเพิ่ม
- `/health` และ `/ready` ตอบ 200 พร้อม DB/queue `ok` และ readiness `no-store`;
  ไม่ส่ง token แล้ว posts/publishing readiness ตอบ 401
  SDK token เดิมเรียก `/auth/me` ได้ 200 owner ตรง และ
  `/posts?includeMedia=true&limit=3` ได้ 200, `private, no-store`, posts 0
  ส่วน `limit=0` ได้ 400 `INVALID_POST_LIMIT`; publishing readiness ยังตอบ
  503 `SOCIAL_PUBLISHING_UNAVAILABLE` พร้อม `private, no-store` ตามที่ปิดไว้
  การปลอม owner header ไม่แทน Firebase owner แต่ยังไม่ใช่หลักฐานสองบัญชีจริง
- อ่าน metadata/R2 ของ owner เดิมอย่างเดียว: video keys จาก managed upload
  เก่า 2 รายการตอบ 404 และรูป profile ที่มีอยู่ตอบ Range 206 `image/png`
  64 bytes จึงยังไม่มีโพสต์/คลิปจริงที่ใช้ยืนยัน native Home preview
- ตรวจ R2 แยกด้วยไฟล์สร้างใหม่ 2 keys ภายใต้ synthetic-owner namespace:
  PNG 833 bytes กับ H.264 MP4 1 วินาที 180×320 ขนาด 1,892 bytes
  PUT/GET ได้ 200; bytes/SHA/MIME ตรง, Range 206 ได้ 64 bytes พร้อม
  Content-Range/prefix ตรง และ ffmpeg decode ภาพ/คลิปในเครื่องผ่านทั้งคู่
  ลบเฉพาะ 2 keys ใหม่นี้ใน finally และ GET 404 ยืนยัน cleanup ครบ
  ไม่เขียน DB/post/quota/customer/provider และไม่บันทึก signed URL/token/UID
- หลักฐานที่ redacted เก็บเฉพาะในเครื่องที่ `artifacts/staging-api-20261008`
  ได้แก่ deployment/authenticated-media receipts, R2 results และรูปหน้า Live;
  ไม่ใส่ artifacts เข้า Git เอกสารสรุปอยู่ในแผนรวมงาน
- ยังไม่ยืนยัน Home ที่มี cover/video จริงหรือการแยกสอง authorized owners;
  provider acceptance/crash recovery, Redis worker, multi-instance และ
  Production gates ยังเหมือนเดิม ไม่อ้างว่าพร้อมใช้งาน Production ทั้งระบบ

## รวมงานค้างและเครื่องมือทดสอบ — 8 ตุลาคม 2026

- ชุดลด UI ข้างล่างเข้าและ push `main` แล้วที่ `b1f793c`; source แอป `aafd076`
  ผ่าน CI `37749129032` จึงถือเป็นงานส่งมอบขั้นแรก ไม่ใช่งานค้างใหม่
- ชุดรวมงาน `36dbaccb1d23ee46f9c970f2fdd8fff3d32b01d0` commit/push และเข้า
  remote `main` แล้ว local/origin main ตรงกัน; CI source เดียวกัน
  `37754460435` ผ่าน Backend API และ Flutter Mobile แล้ว ชุดนี้เพิ่ม Home ผ่าน
  `GET /posts?includeMedia=true&limit=3`,
  `/ready`, ปิดระบบแบบรอให้งานเสร็จ, กู้สถานะโพสต์จากผลที่บันทึกครบ และ
  ครอบคลุม owner barrier ของ GET/HEAD ที่อาจเปลี่ยนสถานะ รวม URL ตัวพิมพ์และ
  ท้าย slash ของ social/billing และ `/uploads/:uploadId`; รอคำขอเดิมจบก่อนลบ
  บัญชี ส่วนเตรียม User มีในแต่ละ route ของ main แล้วหลัง validation/quota
  จึงรักษาของเดิมและไม่เพิ่ม upsert ซ้ำ ไม่มี migration/การเปิด provider/
  เปลี่ยน Render หรือ dependency lock; สถานะหลักฐานอยู่ใน
  `superpowers/plans/2026-10-08-integrate-pending-main-work.md`
- Helper `tool/postdee-staging.ps1` เปิด `POSTDEE_STAGING_BUILD=true` ชัดเจน
  แม้ ignored config เดิมไม่มีค่านี้ ป้ายอยู่ในแถบเล็ก 18 dp ไม่ทับปุ่ม;
  production ปิดโดยค่าเริ่มต้นและไม่เปลี่ยนสิทธิ์ล็อกอินหรือแพ็กเกจ
- Launcher Windows `tool/launch-postdee-android.ps1` หา worktree ที่เป็น `main`
  จริง, SDK จาก environment/local.properties/ตำแหน่งผู้ใช้ และ Flutter/ignored
  Test Store overlay จาก common workspace ใช้ helper ตรวจค่าเดิมก่อน build
  โดยไม่ฝังชื่อผู้ใช้หรือคัดลอก key เข้า Git

```powershell
# ตรวจตำแหน่งอย่างเดียว: ไม่เปิดแอป ไม่ build ไม่ install และไม่เรียก adb
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\launch-postdee-android.ps1 -ResolveOnly
# เปิดรุ่นที่ build จาก main; ใช้ AVD ที่เปิดอยู่หรือเลือกชื่อที่มีอยู่จริง
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\launch-postdee-android.ps1 -AvdName PostDee_Pixel
```

Launcher ไม่ fetch/push/deploy และไม่รับรองว่า main ที่ checkout เท่ากับ remote
ล่าสุด ต้องตรวจ SHA ก่อนเริ่ม QA ใช้ `install -r` โดยคง AVD/keystore เดิม;
หาก signature ไม่ตรงจะหยุด ไม่ uninstall/ล้างข้อมูลเพื่อแก้ผ่าน
`-ResolveOnly` กับ parser ผ่านแล้ว; API 1,609 tests/107 files, Flutter 1,588 tests,
final badge/Home 45 tests, analyze และ Staging APK build ผ่านในเครื่อง
ติดตั้งแบบ `install -r` ด้วยลายเซ็นเดิมแล้ว บัญชี/session ลิงก์ร้าน และ Free 0/3
ยังอยู่ Native เห็น Home/ปฏิทิน/ลิงก์ร้าน/บัญชี, ลิงก์ 2 รายการ, YouTube 1/4
และมีเฉพาะ 4 ช่องทาง หน้าสร้างโพสต์ 4 ขั้นพร้อมร่าง (1) เป็น full-screen ไม่มี
dock และปิด X โดยไม่แก้ไขกลับ Home ได้ ป้าย Staging ไม่มีเส้นใต้
ไม่ได้กด save/publish/ซื้อแพ็กเกจ/OTP/แก้การเชื่อมต่อ CI รุ่นนี้ผ่านทั้ง 2 jobs
และตั้งใจข้าม APK build บน main push; ใช้ APK ที่ build/ตรวจจริงในเครื่อง
APK build/install ตรงกัน 281,390,530 bytes, Flutter 3.44.1 / Dart 3.12.1,
SHA256 `e5620b662a051bd9b0f889fae60f867cbbeaa14ae3bea558eba7c8c7b84cedd7`
source/runtime/signature receipt รายละเอียดอยู่ในแผนรวมงาน และไม่ใช่ provider E2E
API ชุดนี้ deploy และตรวจ Staging เพิ่มตามผลวันที่ 8 ตุลาคมข้างต้นแล้ว
แต่ Home ของบัญชีที่ตรวจไม่มีโพสต์ จึงยังไม่ยืนยัน nonempty native preview
รุ่นมือถือใหม่ยังแสดง placeholder ได้เมื่อ API เก่าไม่ส่ง URL

## ส่งมอบชุดลด UI มือถือ — 8 ตุลาคม 2026

- Source `aafd0769bd6ded57339531d7dbc1129de2590c67` บน
  `codex/mobile-ui-cleanup-staging` รวม `main` ล่าสุด `81f0b9f` แล้ว จึงเก็บ
  ลูกเล่นแท็บด้านล่าง หน้าสร้างโพสต์ 4 ขั้น และเทมเพลตเว็บ 100 แบบครบ
- เอาการ์ดยอดวิว/ไลก์เดือนนี้ออกจาก Home, เอารายการ Shopee/Lazada ที่ยังไม่รองรับ
  ออกจากหน้าช่องทาง และเอาเมนูเทมเพลตแคปชัน/ลิงก์หน้าโปรไฟล์ออกจาก Account
  เทมเพลตยังเลือกในหน้าสร้างโพสต์ และลิงก์ร้านยังเปิดจากแท็บด้านล่างได้
- [CI รุ่นรวม 37749129032](https://github.com/NOI56/PostDeeMobile/actions/runs/37749129032)
  ใช้ source/workflow SHA เต็มข้างต้นและผ่านทั้งสอง jobs: Flutter analyze / 1,571 tests,
  Backend 104 files / 1,556 tests, generator 22 tests, build/schema/audit และ APK build
- ดาวน์โหลด CI artifact และตรวจ receipt/source/config/package/signature แล้ว;
  ขนาด 285,747,082 bytes, SHA256
  `444a6385f13f63c2e450e70bfaa0cfd48264c6fe7a2953f750bae978529c6a9d`
  ตรงกับไฟล์จริง ใช้ Flutter 3.47.6 / Dart 3.13.5 และไม่ได้ติดตั้ง APK ของ CI
- APK ในเครื่องสร้างจาก source เดียวกันด้วย Flutter 3.44.1 / Dart 3.12.1
  ใช้ Staging defines ที่ tracked และ RevenueCat Test Store overlay เดิมที่อยู่
  เฉพาะในเครื่อง ไม่คัดลอกหรือส่ง SDK key ขึ้น Git; ขนาด 303,482,075 bytes
  และ SHA256 `a99cc8b2fb3b80802aeda26f3526984cce705494e8a3ee06c9da7ddf81264099`
- Package `com.postdee.postdee_mobile.staging`, version `0.1.0-staging` / code 1,
  min/target SDK 24/36 และลายเซ็น debug เดิม ติดตั้ง `install -r -t` บน
  emulator-5556 สำเร็จ โดย installed APK hash ตรงกับไฟล์ที่สร้าง
- เปิดแอปใหม่แล้วบัญชีเดิมยังอยู่, YouTube เชื่อม 1/4, แพ็กฟรี 0/3;
  Native smoke ยืนยัน Home ไม่มีการ์ดสถิติ, Account ไม่มีสอง shortcut และ
  หน้าช่องทางมีเฉพาะ TikTok/YouTube/Instagram/Facebook โดยไม่กดบันทึกข้อมูล
  โพสต์ ซื้อแพ็กเกจ เชื่อม/ยกเลิกบัญชี หรือขอ OTP
- Source API, workflow และ Staging infrastructure ไม่มีส่วนต่างจาก `main`
  จึงไม่ต้อง deploy Render หรือเพิ่ม migration; `/health` ตอบ HTTP 200
  เวลา 15:16:53 Asia/Bangkok วันที่ 8 ตุลาคม 2026
- APK ของ CI ใช้ config ตัวอย่างที่ปิด RevenueCat และ Runner debug key;
  ใช้ APK ในเครื่องที่มี Test Store overlay และ key เดิมสำหรับเครื่องจำลอง
  หลักฐาน build/config/hash อยู่ใน ignored `apps/mobile/build` ไม่ใส่ APK หรือ
  ข้อมูลบัญชีไว้ใน Git; การส่งขึ้น App Store/Play Store ไม่อยู่ในรอบนี้

## ส่งมอบเทมเพลตโครงหน้าใหม่และแก้กรอบโลโก้ — 7 ตุลาคม 2026

- รุ่นปัจจุบัน `ae65b9d5eacddf6f9cf000bdb4efb44b4e82b3e0` บน
  `codex/profile-compositions-integrated-staging` รวมบัญชีจาก `main` `ebc9c47`,
  หน้าสร้างโพสต์ 4 ขั้น และเทมเพลตโครงใหม่ 5 หมวด × 20 แบบ ใช้ `contain`
  จัดโลโก้ร้านตรงกลางให้เห็นรูปครบ โดยเก็บกรอบ/สีและการครอปภาพปกตามเดิม
- [CI 37633935019](https://github.com/NOI56/PostDeeMobile/actions/runs/37633935019)
  ผ่าน API 104 ไฟล์ / 1,556 tests, Flutter analyze / 1,559 tests,
  build/schema/audit และสร้าง APK Staging ด้วย Flutter 3.47.6 / Dart 3.13.5
- [Render dep-db35c71srm7s73e5sf1g](https://dashboard.render.com/web/srv-d9bb72ojs32c739osa5g/deploys/dep-db35c71srm7s73e5sf1g)
  เริ่ม 21:24:28 และ Live 21:26:27 Asia/Bangkok ใช้เวลา 1m59s;
  source/instance `mrmmb` ตรง SHA เต็ม มี 14 migrations ไม่มี pending,
  port 10000, publisher disabled และ memory scheduler ตามเดิม
- Runtime แบบอ่านอย่างเดียวผ่าน stable IDs 100, โลโก้ contain/จัดกลาง 100,
  ภาพปกยัง cover 100 และ PNG 8 ไฟล์ ใช้ข้อมูลจำลองในหน่วยความจำ ไม่แก้ฐานข้อมูล
  หรือหน้าเว็บลูกค้า การตรวจเว็บในเครื่องผ่านกรอบ Gallery/Portrait กับรูปกว้าง/สูง
  ที่ 320/393px ทั้ง 8 กรณี ไม่มีล้นหน้าและเห็นขอบรูปครบ
- APK source/config/hash ตรง receipt; config ตัวอย่างที่ tracked ตรงค่าทดสอบ
  ในเครื่องทั้ง 9 ข้อ เซ็นสำเนาด้วย key เดิมแล้วติดตั้ง `install -r` บน emulator-5556
  สำเร็จ Installed SHA256 ตรง `efaccc5c683a7e41cbbe01373859c68c301e0bf3b75fb641d476bee1cb26d228`;
  package `com.postdee.postdee_mobile.staging`, version `0.1.0-staging` / code 1,
  min/target SDK 24/36 บัญชี/ร่าง/preferences ตรงกับก่อนติดตั้ง
- Native A3/D3 แสดงโลโก้เต็มรูปตรงกลางกรอบเดิมและยกเลิกตัวอย่างได้ ลิงก์เดิม
  2 รายการยังอยู่ ไม่มีปุ่ม pause หรือ visual overflow ที่สังเกต หลัง smoke ร่างและ
  Flutter preferences ตรงเดิม บัญชีเดิมยืนยันจาก token-owner identity ที่ตรง
  namespace ของร่าง; Firebase session/token payload เปลี่ยนและยังเป็น opaque
  จึงไม่อ้างว่าทุก preference file ตรงทุก byte หลังเปิดแอป ไม่พบ crash/Flutter/
  RenderFlex markers ใน process ที่ตรวจ เปิด picker หมวดหรูหราไว้ให้ผู้ใช้แล้ว
- ไม่มี migration/secret/แพ็กบริการใหม่ ไม่ merge `main` หรือ deploy Production
  และไม่กด Apply/Save/Update/Publish หรือแก้ข้อมูลหน้าเว็บลูกค้าระหว่าง QA; public browser/รูป R2,
  iOS และเครื่องจริงยังไม่ยืนยัน รายละเอียดและหลักฐานอยู่ใน
  `docs/superpowers/plans/2026-10-07-profile-template-categories.md`

## ประวัติส่งมอบโครงหน้าใหม่ — รุ่นทดลอง `9c7fa74`

- Source `9c7fa74cc6910063fc88a66568860ac64609f02f` บน
  `codex/profile-compositions-integrated-staging` รวมหน้าบัญชีจาก `main` ล่าสุด
  `ebc9c47` หน้าสร้างโพสต์ 4 ขั้นจาก Live `550f73a` และเทมเพลต 100 แบบโครงใหม่
  ผ่านการตรวจ Git blob/delta ว่าแต่ละระบบและเอกสารยังอยู่ครบ
- [CI 37623591224](https://github.com/NOI56/PostDeeMobile/actions/runs/37623591224)
  ผ่าน API 1,555 และ Flutter 1,556 tests พร้อม analyze/build/schema/audit
- [Render dep-db342ek9v7es73astung](https://dashboard.render.com/web/srv-d9bb72ojs32c739osa5g/deploys/dep-db342ek9v7es73astung)
  Live เวลา 19:57:18 Asia/Bangkok; Source และ instance `bsf55` ตรง SHA เต็ม
  มี 14 migrations ไม่มี pending, port 10000, social publisher disabled
  และ memory scheduler ตาม configuration เดิม ไม่เพิ่ม migration/secret/แพ็กบริการ
- Runtime fixtures แบบอ่านอย่างเดียวผ่าน 100 IDs, 5 หมวด × 20 โครง,
  PNG 8 ไฟล์, ธีมเดิม 7 แบบ และ headers ของ route จำลอง โดยไม่แก้ profile ลูกค้า
- [APK CI 37627939566](https://github.com/NOI56/PostDeeMobile/actions/runs/37627939566)
  ผ่านทั้งสอง jobs และสร้าง APK จาก source `9c7fa74` สำเร็จ ใช้ Flutter 3.47.6 /
  Dart 3.13.5 และ config ตัวอย่างที่ tracked ซึ่งตรงค่าทดสอบในเครื่องทั้ง 9 ข้อ
  ไม่ส่ง private JSON/key ไป GitHub; Flutter-tool บน Windows ค้างตอนเริ่มทำงาน
  จึงใช้ CI สร้างแทน (ไม่อ้างว่า local analyze ผ่าน) เซ็น APK ที่ดาวน์โหลดด้วย
  debug key เดิมในเครื่องแล้ว ลายเซ็นตรงกับแอปเดิม ติดตั้งแบบ `install -r` บน
  emulator-5556 สำเร็จ APK ที่ติดตั้งตรงไฟล์ที่ตรวจ บัญชี/ร่าง/preferences ทุกไฟล์
  ตรงกับก่อนติดตั้ง แอปเปิด Home และแพ็กเกจ Free เดิมได้ ตรวจ native 15 ตัวอย่าง
  บัญชี และสร้างโพสต์แล้ว ข้อมูลบัญชี/ร่าง/Flutter preferences เดิมไม่เปลี่ยน
- ผลตรวจรุ่น `9c7fa74` เป็น provisional: พบกรอบแกลเลอรีตัดขอบโลโก้ร้าน
  ชุดแก้ใช้ `contain` ตรงกลางกรอบทั้งเว็บและมือถือสำหรับโลโก้ที่อัปโหลดใน
  100 เทมเพลต โดยเก็บกรอบ/สี/ตัวอักษรย่อและการครอปภาพปก/พื้นหลังไว้ตามเดิม
  Local API 1,556 tests/build ผ่าน จากนั้นรุ่นแก้ `ae65b9d` ผ่าน CI และส่ง
  API/APK ที่ตรงกันตาม receipt ปัจจุบันด้านบน งานนี้ไม่แก้ข้อมูลหน้าเว็บลูกค้า
- ไม่ merge `main` หรือ deploy Production; ข้อจำกัดตรวจเว็บสาธารณะ/รูป R2 ผ่าน
  browser ยังเหมือนเดิมตามสิทธิ์ที่บล็อกและคำข้ามตรวจเว็บก่อนหน้า รายละเอียดอยู่
  `docs/superpowers/plans/2026-10-07-profile-template-categories.md`

### สร้าง APK Staging ผ่าน GitHub Actions แบบเลือกเปิด

Workflow `ci.yml` มี input `build_staging_apk` ค่าเริ่มต้น `false` และ
`apk_source_ref` สำหรับระบุ source มือถือที่ต้องการตรวจและสร้างโดยตรง การเปิด
build ยังรัน checks เดิมก่อน ใช้ `staging_build_number` ระบุ version code
เพื่ออัปเดตแอปเดิมได้ โดยรับจำนวนเต็ม 1–2100000000 เท่านั้น; ค่าว่างใช้ค่า
จาก pubspec ตามเดิม ค่า input ผ่าน environment และ quoted shell array
โดยไม่แทรกลง shell command โดยตรง ตั้งแต่ 2026-10-24 (security Batch 6)
`apk_source_ref` ต้องเป็น commit ที่อยู่บน branch ของ repository นี้ (workflow
fetch ทุก branch แล้วตรวจด้วย `git for-each-ref --contains HEAD refs/remotes/origin`)
ref ของ pull request จาก fork จะถูกปฏิเสธก่อนรัน checks

ตัวเลือก `staging_test_store_billing` ค่าเริ่มต้น `false` คง APK ที่ปิด billing
ไว้ตามเดิม เปิดได้เฉพาะ manual dispatch ที่เปิด `build_staging_apk` ด้วย
เมื่อเลือก `true` ต้องตั้ง repository secret
`POSTDEE_REVENUECAT_TEST_STORE_ANDROID_API_KEY` เป็น public Android Test Store
SDK key เดิมที่ขึ้นต้น `test_` เท่านั้น ไม่มีการอัปโหลด signing key หรือ private
configuration Helper `scripts/prepare_staging_ci_defines.py` ตรวจ allowlist,
Staging API, Firebase, mock-auth และ base-billing ก่อนสร้าง merged defines
ใน `RUNNER_TEMP` โดยไม่พิมพ์ key/config และไม่แก้ไฟล์ใน checkout
หาก key หายหรือค่าผิดจะหยุดก่อน build; secret อยู่เฉพาะขั้นตอนเตรียม Test Store

Artifact `postdee-staging-debug-<runId>` อายุ 3 วันมีเฉพาะ APK/receipt ไม่มี
merged defines Receipt ระบุ source SHA, mode billing, config/APK hash,
build flags และ package/version code ที่อ่านจาก APK จริง ต้องเทียบ receipt
กับ source/config ที่ตั้งใจใช้ แล้วเซ็นสำเนา APK ด้วย debug key เดิมในเครื่อง
ก่อนอัปเดตแอปแบบเก็บข้อมูล สำหรับ emulator ที่ติดตั้งบน adopted volume
ให้ส่ง APK ที่เซ็นแล้วเข้า `Invoke-PostDeeAndroidApkUpdate` ใน
`apps/mobile/tool/android-install-volume.ps1` เพื่อรักษา UID/volume และตรวจว่า
version code ไม่ลดลง ห้ามติดตั้งทับด้วย raw `adb install` สำหรับเครื่องที่ใช้ Test Store อยู่
ให้เลือกโหมด Test Store เพื่อคง billing เดิม การสร้าง APK สำเร็จยังต้องตามด้วย
การตรวจ signature/package และ smoke-test แอปที่ติดตั้งจริง

## ส่งมอบหน้าสร้างโพสต์ 4 ขั้น — 7 ตุลาคม 2026

- ส่ง candidate `550f73aba0dc90ebd3e0039181b89733d0e104f3` บน branch
  `codex/post-create-wizard-staging` ตามคำอนุญาต push/deploy ของผู้ใช้
  ใช้ baseline `630e20a` ซึ่งรวมระบบโลโก้และเทมเพลต 100 แบบไว้ครบ แยกงาน
  Account ที่กำลังแก้อยู่ออก; `main` ยังเป็น `bcd7153` ไม่มี merge หรือ deploy Production
- [CI run 37612609890](https://github.com/NOI56/PostDeeMobile/actions/runs/37612609890)
  ยืนยัน head SHA ตรง candidate และผ่านทั้ง Flutter Mobile (1475 tests/analyze)
  และ Backend API (1469 tests/build/Prisma/catalog checks/dependency audit)
- [Render deploy dep-db32ki2jnfac738gcicg](https://dashboard.render.com/web/srv-d9bb72ojs32c739osa5g/deploys/dep-db32ki2jnfac738gcicg)
  เป็น specific-commit deploy ของ `postdee-api-staging`; Source และ checkout log
  ตรง SHA เต็ม แสดง **Deploy succeeded | Live** เวลา 18:19:22 Asia/Bangkok
  ใช้เวลา 1m54s Start log ยืนยัน 14 migrations และไม่มี pending migration,
  publisher `disabled`, listener port 10000 และ scheduler ตาม configuration เดิม
- API tree ตรงรุ่น Live ก่อนหน้า `fc087c4` ไม่มี backend/schema/migration ใหม่
  ไม่เปลี่ยนแผนบริการ secrets หรือ provider gates และ Auto-Deploy ยังคงปิด
  การ Live หลัง internal health check ของ Render ไม่ใช่หลักฐาน HTTP/browser
  E2E ของโดเมนสาธารณะ; รอบนี้เคารพสิทธิ์ที่บล็อกไว้และคำข้ามตรวจเว็บก่อนหน้า
- UI มือถือส่งผ่าน APK ไม่ได้อัปเดตจาก Render โดยอัตโนมัติ สร้าง APK Staging
  จาก clean candidate ผ่านแล้ว SHA-256:
  `0424f85f7f104cb514ca38f4ac375bb536d503481d1881820babfdf224c7be01`
  ตรวจ package/API/Firebase และ runtime assets ที่ไม่ว่างครบทั้งสามไฟล์
  ใช้ base Staging configuration เดิม (Firebase เปิด, mock auth/billing ปิด)
  ไม่ติดตั้งซ้ำขณะเครื่องจำลองกำลังใช้งานร่วมกัน โดย composer runtime ตรงรุ่น
  ที่ผ่าน native smoke ก่อนหน้าครบทั้ง 4 ไฟล์หลัง normalize line endings
- หลักฐาน CI, APK และภาพ `composer-staging-deploy-live.jpg` อยู่ใน task
  visualization folder; รายละเอียดขอบเขตและข้อจำกัดการทดสอบอยู่ใน
  `docs/superpowers/plans/2026-06-06-mobile-ui-refresh.md`

## ส่งมอบโลโก้แพลตฟอร์ม — 6 ตุลาคม 2026

- ผู้ใช้อนุญาต push และ deploy ชุดโลโก้ขึ้น Staging แล้ว ส่ง feature commit
  `fec5763a8bc5b143448e9af864ec08a9174acbf0` บน
  `codex/pinterest-mobile-ui`; `main` ยังคงเป็น `bcd7153` ไม่มีการ merge ในรอบนี้
- [GitHub CI run 37456579263](https://github.com/NOI56/PostDeeMobile/actions/runs/37456579263)
  ตรวจ SHA ข้างต้นและผ่านทั้ง Flutter Mobile กับ Backend API รวม analyze,
  tests, production build, Prisma validate และ production dependency audit
- [Render deploy dep-db2do6ei0phs73eagveg](https://dashboard.render.com/web/srv-d9bb72ojs32c739osa5g/deploys/dep-db2do6ei0phs73eagveg)
  ของ `postdee-api-staging` แสดง **Deploy succeeded | Live** โดย Source เป็น
  `fec5763` Log ยืนยัน checkout SHA เต็ม, build สำเร็จ และ service Live เวลา
  **18:33:27 น. Asia/Bangkok** ใช้เวลา 1m49s
- Start log ระบุฐาน `postdee_staging`, migrations 14 รายการ และ
  `No pending migrations to apply.` ไม่มี schema/migration ใหม่ในงานโลโก้
  ระบบฟัง port 10000, scheduler เริ่ม และ social publisher ยังเป็น `disabled`
- การเลือก specific commit ผ่าน Dashboard ปิด Auto-Deploy ของ Staging
  ตามขั้นตอน Render; Settings แสดง disabled หลัง deploy ต้องรวมรุ่นนี้เข้า
  branch ที่บริการติดตามก่อนเปิด Auto-Deploy อีกครั้งเพื่อไม่ให้รุ่นเก่ามาแทน
  ไม่ได้เปลี่ยนแผนบริการ, env secrets หรือ deploy Production
- เบราว์เซอร์ปฏิเสธการเข้าถึง `postdee-api-staging.onrender.com` เพราะ saved
  permission block จึงไม่ได้ตรวจหน้า Live หรือ PNG ผ่านช่องทางอื่นเพื่อเลี่ยง
  การบล็อก ผล Live ข้างต้นยืนยันจาก Render ไม่ใช่ผล browser E2E/HTTP ของหน้าเว็บ
  All-seven artwork/asset parity/layout checks ผ่านในเครื่องตามแผนโลโก้
- หลักฐานภาพ `platform-logo-staging-deploy-live.png`, DOM snapshot และ
  `platform-logo-github-ci.json` อยู่ในโฟลเดอร์ visualization ของงาน
  รายละเอียด local/native verification และข้อจำกัดอยู่ใน
  `docs/superpowers/plans/2026-10-06-profile-platform-logos.md`

ตรวจสถานะ 5 ตุลาคม 2026: API และฐานข้อมูล Staging กลับเป็น Active แล้ว และ
Link in Bio รุ่นใหม่ขึ้น Staging เวลา **18:26 น. Asia/Bangkok** ส่วน Production
ยัง suspended รอบนี้ไม่มีการ deploy Production จ่ายเงิน เปลี่ยนแผน หรือแก้
configuration ของบริการ

## ผลตรวจ Link in Bio บน Staging — 5 ตุลาคม 2026

- PR [#13](https://github.com/NOI56/PostDeeMobile/pull/13) merge เข้า `main` เป็น
  `97a7b89b0984f7e41b0422a9c542d6cc9f91e0c9`; feature commit `43773ba`
  มี API/mobile tree ตรงกับ merge commit ที่ส่งขึ้น Staging
- Render service `srv-d9bb72ojs32c739osa5g`, deploy
  `dep-db1ohp142hec73dksqqg` แสดง Live เวลา 18:26 น. Log ยืนยันว่า migration
  `20261005180000_add_link_in_bio_profile` ถูกนำไปใช้ และ migrations ทั้ง 13 รายการ
  เสร็จครบแล้ว ไม่ใช่เพียงการ validate schema หรือ generate client ในเครื่อง
- [x] แอป Android Staging ที่ล็อกอิน Firebase เผยแพร่ชื่อ `PostDee Demo`, slug
  `postdee-demo-20261005` สำเร็จบน API จริง
- [x] หน้า `/p/postdee-demo-20261005` ตอบ HTTP `200` โดยไม่ต้องล็อกอิน พร้อม
  `Cache-Control: no-store` และ CSP `script-src 'none'` การตรวจ HTTP นี้ยืนยัน
  response ของหน้าที่เผยแพร่ ไม่ใช่หลักฐานการแสดงผลในเบราว์เซอร์จริง
- [x] URL `https://EXAMPLE.com` ถูกคืนในรูป canonical
  `https://example.com/` และปุ่มคัดลอก URL ที่ยืนยันแล้วแสดง native toast สำเร็จ
- [x] Flutter 1,048 tests, API 1,106 tests, analyze/build, Prisma schema/helper
  checks ผ่าน; GitHub CI ของ PR และ `main` รวม unsigned iOS build ผ่าน
  ผล iOS นี้ยืนยันการ build เท่านั้น ยังไม่ใช่การติดตั้งหรือทดสอบบน iPhone จริง
- [x] หน้าเว็บทดสอบในเครื่องผ่าน browser QA ทั้งขนาดมือถือและ desktop ก่อนทดสอบ
  Staging โดยไม่ถือว่าผล local เป็นการตรวจหน้าเว็บบนโดเมน Live
- [ ] การแสดงผลหน้าเว็บ Staging จริงในเบราว์เซอร์และการเปิดลิงก์จากแอปยังไม่ยืนยัน
  การเข้าถึงโดเมน Live ผ่าน browser ถูก saved user-permission block แม้ผู้ใช้
  อนุญาตรอบนี้แล้ว จึงไม่ได้ใช้ browser อื่นหรือ HTTP เป็นทางเลี่ยงการบล็อก
- [x] ยกเลิกเผยแพร่จากแอปผ่านหน้าที่ยืนยันและ DELETE response สำเร็จ สถานะเปลี่ยน
  เป็นยังไม่ได้เผยแพร่ และนำ URL/ปุ่มคัดลอก/ปุ่มเปิดเว็บออก โดยชื่อหน้าและลิงก์
  canonical เดิมหนึ่งรายการยังอยู่ให้แก้ไขหรือเผยแพร่ใหม่
- [x] หลัง unpublish กดตรวจสถานะเว็บไซต์ผ่าน authenticated owner GET ได้สถานะ
  ยังไม่ได้เผยแพร่และไม่มีปุ่มคัดลอก/เปิดเว็บ จากนั้น force-stop/start โดยไม่ล้าง
  ข้อมูล แอปกลับ Home ด้วยบัญชีเดิม เปิดผ่านการ์ด Home และ reload API ได้สถานะ
  ไม่เผยแพร่ตรงเดิม ชื่อ `PostDee Demo`, slug และลิงก์ `https://example.com/`
  หนึ่งรายการยังอยู่ครบในรอบ restart นี้
- [x] เผยแพร่ตัวอย่างเดิมซ้ำ เปลี่ยนชื่อเป็น `PostDee Demo Updated` แล้วกดอัปเดต
  หน้าเว็บไซต์และ authenticated owner GET สำเร็จ snapshot ที่เผยแพร่อัปเดตแล้ว
  ยังคง URL เดิมพร้อมปุ่มคัดลอก/เปิดเว็บที่ยืนยันจาก API และไม่มีคำเตือนว่ามี
  การแก้ไขที่ยังไม่ได้เผยแพร่หรือสถานะไม่ทราบผล การตรวจนี้ไม่รวมกดเปิดโดเมนจริง
- [x] หลังอัปเดต ยกเลิกเผยแพร่ผ่าน confirmation อีกครั้งและ owner GET คืนสถานะ
  ไม่เผยแพร่ โดยไม่มีปุ่มคัดลอก/เปิดเว็บ ตัวอย่างปัจจุบันชื่อ
  `PostDee Demo Updated`, slug เดิมและลิงก์ canonical หนึ่งรายการ ถูกทิ้งไว้
  **ไม่เผยแพร่** ในหน้าแก้ไขส่วนตัว
- [ ] หน้า Live `404` หลังยกเลิกเผยแพร่ยังไม่ได้เรียกเพราะเคารพ domain block
  ข้างต้น ห้ามนับว่า full publish → live browser → unpublish/anonymous `404`
  E2E ผ่านแล้ว และห้ามอ้างว่าตัวอย่างข้างต้นยังเป็นหน้าสาธารณะที่เปิดอยู่
- [ ] การลบบัญชีจริงแล้วหน้าเว็บหายยังไม่ผ่าน และยังคงปิด Firebase account
  deletion จน durable owner barrier และ release gates ที่ระบุด้านล่างครบ

ผลนี้ยืนยันการเผยแพร่/อัปเดต/ยกเลิกเผยแพร่และโหลดสถานะ Link in Bio ผ่านแอป/API
รวมการอ่านหน้าแบบ anonymous ในรอบเผยแพร่แรกบน Staging แต่ยังไม่ยืนยัน browser
E2E บนโดเมนจริง หรือ provider E2E ของ Gemini, RevenueCat, R2 หรือ PostPeer ใน
release candidate นี้ และไม่อนุญาตให้เปิด Production ก่อนผ่าน gates ที่เหลือ

Dashboard ระบุ Web Service Staging เป็นแผน `Starter` ที่ตั้งไว้อยู่แล้ว
รอบเปลี่ยนเมนูและเพิ่มเว็บหน้าโปรไฟล์นี้ไม่ได้ซื้อหรือเปลี่ยนแผนบริการ
รอบเตรียม source วันที่ 20 ตุลาคมปรับ Blueprint ให้ตรง Starter/Basic ที่อ่านพบ
โดยยังไม่ได้ sync หรือเปลี่ยนบริการ รายการ Free/expiry ในบันทึกเก่าเป็นประวัติ
ไม่ใช่แผนหรือวันหมดอายุปัจจุบัน

บันทึกสถานะ 4 ตุลาคม 2026: Render Dashboard แสดง **Workspace suspended**
เพราะค้างชำระ และไม่แสดงปุ่ม Manual Deploy ของ `postdee-api-staging` ในรอบนั้น
`/health` ตอบ HTTP `503` พร้อม `x-render-routing: suspend` บริการยังติดตาม
`main` แต่ commit ที่ deploy สำเร็จล่าสุดใน Dashboard คือ `208b4e5` การ push/merge
โค้ดใหม่จึงไม่ใช่หลักฐานว่าบริการกลับมาใช้งานได้ ต้องคืนสถานะ workspace แล้ว
deploy และตรวจ candidate SHA, `/health`, migration และ provider gates เดิมอีกครั้ง
ก่อนทดสอบบริการจริง รอบนี้ไม่มีการจ่ายเงินหรือเปลี่ยนแผน Render

ทบทวนเอกสาร ณ 10 สิงหาคม 2026: **Blueprint ใน repository ติดตาม `main` แต่การ
deploy สำเร็จหรือ `/health` ผ่านไม่ได้ยืนยันว่า R2, Gemini/ElevenLabs, Firebase,
RevenueCat หรือ PostPeer ผ่าน E2E ใน release candidate เดียวกัน** ผลที่ระบุว่า
ผ่านด้านล่างเป็นบันทึกการทดสอบเดิมและต้องตรวจซ้ำตามรายการก่อน Production

- Blueprint: `postdee-staging` (`exs-d9bb3it7vvec73ceggl0`)
- API: `postdee-api-staging` (`srv-d9bb72ojs32c739osa5g`)
- URL: `https://postdee-api-staging.onrender.com`
- Database ในบันทึก Free เดิม: `postdee-postgres-staging` (`dpg-d9bb66ojs32c739oqt10-a`)
- Database expiry ในบันทึก Free เดิม: 14 สิงหาคม 2026; ปัจจุบันอ่านพบแผน Basic
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

ไฟล์ `render.staging.yaml` ระบุทรัพยากร Staging แยกดังนี้ โดยการปรับ source
รอบนี้ยังไม่ได้นำไป sync กับ Render:

- Web Service: `postdee-api-staging`
- PostgreSQL: `postdee-postgres-staging`
- Database/User: `postdee_staging`
- Region: Singapore
- Branch: `main`
- Auto-deploy: `off`; ใช้ manual deployment หลังตรวจชุด source/config แล้ว
- Build/test keeps platform-native optional tools; after the Prisma migration,
  startup prunes development and optional packages. Firebase Auth remains
  available, while unused Firestore/Google Cloud Storage clients are not kept in
  the running Staging service.
- Web plan: `starter`, หนึ่ง instance
- Database plan: `basic-256mb`, disk 1 GB, PostgreSQL major version `18`
- Database `ipAllowList: []` ปิด external connections; ไม่เปิด allowlist เพื่อข้าม
  ข้อจำกัดการ query ผ่าน MCP
- Production safety guards ยังเปิดผ่าน `NODE_ENV=production`
- Push และ Firebase account deletion ยังปิดไว้ในรอบแรก

Render Dashboard และ Blueprint ตาม `main` เหมือนกัน แต่ก่อน sync ยังต้องตรวจ
live environment diff ตามข้อกำหนดด้านบน การตรงกันเฉพาะ branch/plan ไม่ได้ยืนยัน
provider flags หรือ credentials

## ค่าใช้จ่ายและข้อจำกัด

- Staging ที่อ่านพบใช้ Web Starter และ Database Basic ซึ่งเป็นทรัพยากรแบบเสียเงิน
  การปรับ Blueprint ในเครื่องไม่ได้ซื้อ อัปเกรด หรือลดแผนบริการ
- ตรวจ Billing/Usage และราคาจาก Dashboard ก่อนสร้างหรือเปลี่ยนทรัพยากรทุกครั้ง
  ไม่ใช้ราคาและวันหมดอายุของ Free จากบันทึกเดือนกรกฎาคมแทนสถานะปัจจุบัน
- หากต้องสร้าง Staging ใหม่ ให้ใช้ชื่อ/ฐาน/credentials ชุดทดสอบแยก ห้ามนำไปชี้
  ฐาน Production เพื่อประหยัดค่าใช้จ่าย
- Bandwidth และ build minutes ยังนับตามโควตา workspace

อ้างอิง: [Render Free instances](https://render.com/docs/free) และ
[Render pricing](https://render.com/pricing)

## Secrets ที่ต้องเป็นชุดทดสอบ

กรอกค่า `sync: false` ใน Render Dashboard เท่านั้น ห้ามใส่ค่าจริงใน Git หรือแชต:

- `CLOUDFLARE_R2_*`: ใช้ bucket สำหรับ Staging เท่านั้น
- `FIREBASE_PROJECT_ID`: ใช้ Firebase project สำหรับ Staging เท่านั้น
- `REVENUECAT_WEBHOOK_AUTH_TOKEN`: ใช้ RevenueCat Test Store/webhook ของ Staging
- `REVENUECAT_REST_API_V1_KEY`: server-only key สำหรับอ่าน subscriber ตอนผู้ใช้
  กด Restore และตรวจ TRANSFER; ห้ามใช้ mobile SDK key แทนและห้ามใส่ใน Flutter
- `GEMINI_API_KEY` และ `ELEVENLABS_API_KEY`: ควรใช้ key จำกัดโควตาสำหรับ Staging

### Billing environment isolation (Batch 1 source change)

Before an authorized API rollout, set
`REVENUECAT_SUBSCRIPTION_ENVIRONMENT=SANDBOX` for isolated Staging and
`PRODUCTION` for production. The respective Blueprints now declare these
values; this source change does not modify the live dashboard. The separate
`REVENUECAT_ADDON_ENVIRONMENT` must also match the intended purchases.
Production rejects Test Store and unproven subscription purchase metadata.
TRANSFER requires the server REST v1 key to reconcile existing users from
subscriber readback. Verify source revocation, destination activation and
provider-failure retries in Staging before any production release. No schema
or mobile update is required. See
`docs/superpowers/plans/2026-10-23-billing-security-batch1.md` for owner actions
and historical-grant limits.

## สถานะ AI transcription ที่ถือเป็นข้อมูลจริง

หน้า AI ตัดต่อและ Subtitle Studio ถูกถอดจากเมนูใช้งานปัจจุบันแล้ว โดยใช้
Link in Bio แทนและยังเก็บ AI แคปชัน รายการ AI edit ต่อไปนี้เป็นบันทึกของ
backend/compatibility เดิม ไม่ใช่ความสามารถที่โฆษณาในแอปรุ่นนี้

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

`render.staging.yaml` ประกาศ `FIREBASE_SERVICE_ACCOUNT_JSON` เป็นค่าลับ
(`sync: false`) สำหรับ service account ของ Firebase project ที่ใช้กับ Staging
เท่านั้น (ห้ามใช้ของ production เพราะ token ของ Staging จะตรวจไม่ผ่านและทุกคน
login ไม่ได้) เมื่อใส่แล้ว API จะเช็คทุกคำขอว่าบัญชีถูกปิดหรือ token ถูกเพิกถอน
หรือไม่ ถ้ายังไม่ใส่ API ยังทำงานได้แต่จะเช็คแค่ลายเซ็น token
ยังคงใช้ `PUSH_SENDER=mock` และ `FIREBASE_AUTH_DELETE_ENABLED=false` เพื่อป้องกัน
การลบผู้ใช้หรือยิง Push ผิดระบบ
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
kids/synthetic/certification; Instagram share-to-feed; Facebook Page Reels แบบ
publish/page-draft. TikTok direct/`SELF_ONLY` เป็น legacy compatibility และยังห้าม
เปิดให้ client ใหม่จน creator-info/consent/audit ครบ.
`FACEBOOK_REELS` คง enum เดิม แต่ส่ง PostPeer `platform: 'facebook'` กับ
`platformSpecificData.contentType: 'reel'` เสมอ ไม่มี Page feed fallback; คง
`PUBLISH|PAGE_DRAFT`, optional `isAiGenerated`, captions และ target snapshots เดิม.
ยังต้องผ่าน Page Reel/draft E2E ด้วยบัญชีจริง หน้าปกที่ส่งเป็น best effort และ
ต้องตรวจการแสดงจริง โดย provider อาจเลือกหน้าปกเอง หลัง deploy publisher ใหม่
งาน queued/scheduled Facebook เดิมจะใช้เส้นทาง Page Reels ด้วย ไม่มี migration
หรือ client field/environment variable ใหม่ และไม่ใช้เพดาน Page Video กับ Reels
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

1. ตรวจ `My Workspace`, Billing/Usage และทรัพยากรเดิมก่อน ปัจจุบันมี Staging
   service/database อยู่แล้ว ให้เปิดของเดิมแทนสร้างซ้ำ
2. ตรวจ source SHA ที่จะปล่อยจาก `main` และ Blueprint path `render.staging.yaml`
   โดยรักษา manual deployment ไว้
3. ตรวจชื่อ `postdee-api-staging`/`postdee-postgres-staging`, แผน Starter/Basic,
   disk 1 GB, PostgreSQL 18 และ external DB allowlist ที่ปิดอยู่
4. ตรวจ live environment diff โดยไม่เปิดเผยค่า secret และยืนยัน provider flags
   รวมถึง credentials ชุดทดสอบก่อน sync; ห้ามคัดลอกค่าจาก Production
5. ถ้าจำเป็นต้องสร้างใหม่จริงจึงเลือก **New → Blueprint** และ repository
   `NOI56/PostDeeMobile` ตรวจชื่อและยอดเงินก่อนสร้าง พร้อมใส่ `sync: false`
   keys เอง กรณีอัปเดตของเดิมต้องเพิ่ม key ใหม่ใน Dashboard ด้วยตนเอง
6. หลังได้รับอนุญาตให้ deploy ให้ตรวจ candidate SHA, migration, `/health` และ
   `/ready`; ผล health เดิมไม่รับรอง candidate ใหม่
7. สร้าง mobile build ที่ตั้ง `API_BASE_URL=https://<staging-host>` แล้วทดสอบด้วย
   บัญชีและวิดีโอทดสอบเท่านั้น

Android Staging รองรับเฉพาะ Debug ในตอนนี้:

```powershell
cd apps/mobile
powershell.exe -ExecutionPolicy Bypass -File .\tool\postdee-staging.ps1 -Command run
powershell.exe -ExecutionPolicy Bypass -File .\tool\postdee-staging.ps1 -Command build-apk
```

helper จะตรวจ API, Firebase Auth, local mock auth, Google server client id และ
RevenueCat Test Store ก่อนเรียก Flutter โดยเลือก `staging.local.json` ถ้ามี หรือ
ใช้ `staging.local.example.json` ที่ไม่มี secret เป็นค่าเริ่มต้น สำหรับ `run` และ
`build-apk` ต้องมีไฟล์ ignored `revenuecat.local.json` ซึ่งกำหนด
`ENABLE_REVENUECAT_BILLING=true` และ public SDK key ที่ขึ้นต้น `test_` ผ่าน
`REVENUECAT_API_KEY` หรือ `REVENUECAT_ANDROID_API_KEY` เท่านั้น ถ้ารันจาก Git
worktree helper จะค้นใน worktree ก่อน แล้วค้น `apps/mobile/revenuecat.local.json`
จาก ancestor workspace โดยไม่คัดลอกหรือแสดง key หากไม่พบหรือเป็น Production key
คำสั่งจะหยุดทันที แทนการ fallback ไป direct Google Play ที่ใช้ไม่ได้กับ package
`.staging` แบบ sideload; คำสั่ง `test` ไม่บังคับไฟล์นี้

ห้ามใส่ webhook token, RevenueCat subscriber REST key, Google service account
หรือ backend secret อื่นใน mobile config และห้ามใช้คำสั่ง `flutter build apk`
ตรง ๆ สำหรับ APK Staging ที่จะติดตั้ง เพราะหากลืมส่ง Dart defines แอปจะปิด
Firebase Auth/RevenueCat ตามค่าเริ่มต้นที่ปลอดภัย ห้ามใช้ Staging กับ `--profile`
หรือ `--release` เพราะสอง build type นี้ยังใช้ Firebase Production หากเปลี่ยน
เครื่อง/CI ต้องเพิ่ม Debug SHA-1/SHA-256 ของ keystore ใหม่นั้นใน Firebase Staging
ก่อน Google Sign-In จะทำงาน

`/health` ตรวจเพียงว่า process ของ API ตอบได้ ไม่ได้ตรวจ R2, Firebase, Gemini/ElevenLabs
หรือ RevenueCat จึงต้องผ่าน smoke test ด้านล่างก่อนเรียก Staging ว่าใช้งานฟังก์ชันจริงได้

ก่อนทดสอบ Firebase ต้องสร้าง mobile staging Firebase config ที่ตรงกับ
`FIREBASE_PROJECT_ID` ของ Staging ด้วย หากแอปยังใช้ Firebase project เดิม token จะ
อยู่คนละ project และ backend จะตอบ 401 ห้ามแก้ด้วยการชี้ Staging กลับไป project ผู้ใช้จริง

ถ้าหน้าสรุปก่อนสร้างแสดงทรัพยากร Production หรือยอดเงินที่ไม่คาดไว้ ให้ยกเลิกและ
ตรวจ Blueprint path/ชื่อ service ใหม่ก่อนเสมอ

## Smoke test ก่อนอนุญาตให้ deploy Production

Staging ติดตาม `main` และปิด auto-deploy การ merge หรือ CI ผ่านยังไม่ทำให้
candidate ขึ้น Staging ต้อง manual deploy ชุดที่ตรวจแล้วและยืนยัน SHA จริง
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
      Page Reels publish/page-draft พร้อมชื่อ/id ของบัญชี/channel/page ทุกปลายทาง;
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
        Reels, Facebook Page Reels publish/page-draft, scheduling,
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
- [ ] ทดสอบ create/reschedule ว่ารับเฉพาะเวลาอนาคตไม่เกิน 14 วันสำหรับ Starter
      หรือ 30 วันสำหรับ Pro และคงคิวเดิมหลังลดแพ็กหรือเปลี่ยนกติกา และทดสอบ
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
- ตรวจ retention/backup และค่าใช้จ่ายของฐาน Basic ปัจจุบัน; วันหมดอายุ Free
  ในบันทึกเก่าไม่ใช่เหตุให้สร้างหรือลบฐานปัจจุบัน
- หากยกเลิก Staging ให้ลบ Blueprint, service, database และ revoke keys ชุดทดสอบ
