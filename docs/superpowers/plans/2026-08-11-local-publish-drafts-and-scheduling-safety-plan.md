# แผนฉบับร่าง การตั้งค่ารายแพลตฟอร์ม และความปลอดภัยของการส่งโพสต์

วันที่: 2026-08-11
สถานะ: source implementation และ automated tests อยู่ใน integration worktree; ยังต้อง apply
migration แบบ API-first และทดสอบ release candidate บนอุปกรณ์จริง/Staging/provider

## เป้าหมาย

ให้ผู้ขายเก็บงานโพสต์ที่ยังไม่พร้อมเผยแพร่ไว้ในเครื่อง กลับมาแก้ต่อได้ และเห็น
ผลลัพธ์การเผยแพร่ของแต่ละแพลตฟอร์มก่อนยืนยัน โดยไม่สร้างโพสต์หรือใช้ทรัพยากร
ฝั่งบริการจนกว่าจะกดโพสต์จริง พร้อมตรึง settings/บัญชีปลายทางและแยกผลส่งสำเร็จ
ออกจากคำว่าเผยแพร่สาธารณะ

## สัญญาของฉบับร่างในเครื่อง

- ใช้ stable authenticated user ID แยกพื้นที่ของแต่ละบัญชี (เป็น Firebase UID
  เมื่อใช้ระบบยืนยันตัวตนจริง); session ที่ไม่มี stable UID เปิด draft store ไม่ได้
- Production Firebase refresh ผูก live UID กับ ID token ใน snapshot เดียวและเทียบกับ
  owner ของ session/ร่างก่อนและหลัง async boundary; หากบัญชีเปลี่ยนต้อง fail closed
  และหยุด remote step ที่เหลือ ไม่ส่งร่างหรือวิดีโอต่อภายใต้บัญชีใหม่
- คัดลอกวิดีโอ หน้าปกที่เรนเดอร์ รูปต้นทางของหน้าปก (ถ้ามี) และ manifest แบบ
  versioned ไปยัง Application Support ของแอป ไม่อ้าง path ต้นทางเดิม
- การกดบันทึกร่างไม่เรียก publishing readiness, upload/create-post, R2,
  PostPeer/แพลตฟอร์ม, publish queue หรือ post-quota accounting
- Draft ไม่ใช่ API resource และไม่มี `PostStatus.DRAFT`; `GET /posts` ไม่คืนรายการนี้
- ไม่มี cross-device sync การติดตั้งหรืออุปกรณ์อื่นจึงไม่เห็นร่างเดียวกัน แต่ไฟล์ใน
  Application Support อาจถูกรวมใน backup ของระบบปฏิบัติการตามการตั้งค่าอุปกรณ์
- เมื่อโพสต์จากร่างได้รับการตอบรับเข้าคิวแล้ว Mobile จึงลบร่างในเครื่อง ถ้าขั้นตอน
  ก่อนรับเข้าคิวล้มเหลวจะเก็บร่างไว้ และถ้าลบร่างหลังเข้าคิวไม่สำเร็จต้องแจ้งคำเตือน
- TikTok `INBOX_DRAFT` และ Facebook `PAGE_DRAFT` ไม่ใช่ร่างในเครื่อง เมื่อกด Post
  ต้องอัปโหลด สร้าง server Post เข้าคิว เรียก provider และใช้ post unit ตามปกติ

## สัญญาการเลือกปลายทางและ Review

- หลังโหลด connection แล้วไม่มีแพลตฟอร์มใดถูกเลือกอัตโนมัติ ผู้ขายเลือกทีละรายการ
  หรือกด `เลือกทั้งหมด` เอง
- ใช้ progressive UI: แถวที่ยังไม่เลือกไม่แสดงรายละเอียด; เมื่อเลือกจึงเห็น summary
  กับปุ่มตั้งค่า และเปิดรายละเอียดเฉพาะแพลตฟอร์มนั้นใน bottom sheet
- ร่างจำค่าปลายทางที่ผู้ขายเลือกไว้ หาก connection หายต้องเชื่อมใหม่ก่อนโพสต์
- Review แสดง display name หรือ external account id ของบัญชี/channel/page ที่เชื่อม
  สำหรับทุกปลายทาง; ถ้าระบุตัวตนไม่ได้ต้องปิดการยืนยันและให้ refresh/reconnect
- Review แสดงผลที่ระบบจะขอแยกต่อแพลตฟอร์ม:
  - TikTok: `INBOX_DRAFT`; `DIRECT_POST/SELF_ONLY` ยังปิดจน creator-info,
    privacy/interaction choices, consent และ TikTok audit ครบ
  - YouTube Shorts: title 1–100 ตัวอักษร (ห้าม `<`/`>`),
    `private|unlisted|public`, made-for-kids, realistic synthetic-media และ
    `communityGuidelinesCertified: true`
  - Instagram: `shareToFeed: true|false`; ไม่มี Private รายโพสต์
  - Facebook Page Video: `PUBLISH|PAGE_DRAFT`; ห้ามเรียกความสามารถนี้ว่า Reels
- ปลายทางที่ยังระบุรูปแบบเผยแพร่ไม่ได้หรือไม่มี identity ต้องปิดปุ่มยืนยัน ไม่เดา
  เป้าหมายหรือใช้ค่าเริ่มต้นแทน; API ยัง resolve/snapshot/revalidate target จริงเอง
- ค่าเริ่มต้น Mobile คือ TikTok inbox draft, YouTube Private แต่คำตอบบังคับยังว่าง,
  Instagram share-to-feed และ Facebook ยังไม่เลือก จึง fail closed จนกรอกครบ

## สัญญา API, Target และ Backward Compatibility

- Migration `20260811130000_add_platform_publish_configuration` เพิ่ม
  `Post.platformSettings`, internal `Post.platformTargets`,
  `PlatformPublish.deliveryOutcome` และ internal `providerPostId` แบบ nullable
- deploy ต้อง API-first: apply migration, ตรวจ readiness
  `platformSettingsVersion: 1` แล้วจึงปล่อย Mobile; version ไม่ใช่ provider health
- เมื่อส่ง `platformSettings` ต้องมี exact object ครบทุก selected platform; settings
  เป็นส่วนหนึ่งของ idempotent intent การเปลี่ยนค่าใต้ request ID เดิมตอบ `409`
- client/row เก่าที่ไม่มี settings ใช้ค่าเดิม: TikTok direct SELF_ONLY, YouTube
  Private, Instagram share-to-feed, Facebook Page publish; result เก่าที่ outcome
  เป็น null ยังอ่านได้แต่พิสูจน์ visibility เดิมไม่ได้
- Post ใหม่ snapshot connected account ภายใน ตรวจซ้ำก่อน commit และก่อน worker call;
  connection ที่หาย/เปลี่ยนต้อง fail closed. `platformTargets` และ `providerPostId`
  ห้ามออก public API/queue/log. queued legacy row ที่ไม่มี snapshot ต้อง audit/drain
  ก่อนเปิด provider
- `deliveryOutcome` คือ `LIVE|PRIVATE|UNLISTED|DRAFT`; platform status
  `PUBLISHED` หมายถึง provider ยืนยัน delivery ที่ขอ ไม่จำเป็นต้องเป็น public

## สัญญาการตั้งเวลาและโพสต์เลย

- การสร้างและเลื่อนเวลาโพสต์ต้องเป็นเวลาในอนาคตอย่างเคร่งครัด และไม่เกิน 30 วัน
  จากเวลาปัจจุบันของ API; Mobile ใช้กรอบเดียวกันก่อนส่ง
- ร่างอาจถูกเปิดหลังเวลาที่จำไว้ผ่านไปแล้ว แต่ต้องเลือกเวลาใหม่หรือเปลี่ยนเป็นโพสต์เลย
  ก่อนเริ่ม readiness/upload
- `POST /posts/:id/publish-now` ใช้เฉพาะโพสต์ของผู้ใช้ที่ยัง `QUEUED` และมี
  `scheduledAt`; endpoint ล้าง schedule แบบ owner/status/เวลาเดิม compare-and-set
  ใน post store ก่อน แล้วจึงแทน queue job เป็น `READY`
- ห้ามจำลอง “โพสต์เลย” ด้วยการ PATCH เวลาเป็นเวลาปัจจุบัน Queue failure ต้องคงเวลาเดิม
  ด้วย conditional rollback เฉพาะเมื่อแถวยังอยู่ในสถานะที่คำขอนี้สร้างไว้ ห้ามเขียนทับ
  state ที่เดินหน้าต่อแล้ว
- readiness แบบ fail-closed ครอบคลุม create, reschedule และ publish-now; cancel
  ยังใช้ได้เมื่อ social publishing ปิด

## สัญญาการส่งซ้ำและสถานะผลลัพธ์

- แต่ละ local draft มี `clientRequestId` คงที่ตลอดอายุการส่งและใช้ค่าเดิมหลัง app
  restart, timeout หรือ lost response; client เก่าที่ไม่ส่ง key ยังใช้ได้ แต่ทุกคำขอ
  เป็น attempt ใหม่และไม่มี deduplication guarantee
- API สร้าง deterministic owner-scoped post แบบ database-first แล้วจึง enqueue:
  ครั้งแรกสำเร็จตอบ `201`; intent เดิม/key เดิมตอบ `200 idempotentReplay: true` และ
  ซ่อม queue job ของ `QUEUED` row; intent ที่ไม่ตรงหรือ original post จบ `FAILED`
  ตอบ `409` โดยไม่อ้างว่าสร้างรายการใหม่
- เมื่อได้ idempotency `409` Mobile เก็บร่างเดิมและ block ปุ่ม Post ตาม draft ID เพื่อ
  ไม่ให้อัปโหลดซ้ำจากการกดอีกครั้ง ผู้ใช้ต้องกด `เริ่มรายการโพสต์ใหม่`, อ่านคำเตือนว่า
  อาจโพสต์ซ้ำ และยืนยันก่อนระบบสร้าง draft/request ID ใหม่ โดยยังเก็บร่างเดิมไว้ตรวจ
- enqueue แรกที่ล้มเหลวตอบ `503` แต่เก็บ durable post row เพื่อให้ same-key replay
  ซ่อมคิว จึงไม่เพิ่ม post/quota ซ้ำ
- Mobile แสดง `QUEUED`, `PUBLISHING`, `PUBLISHED`, `PARTIAL_PUBLISHED` ตามจริง
  และระบุ replay ว่าเป็นรายการเดิม; status ที่ไม่รู้จักห้ามแสดง success และต้องเก็บร่าง
- ขอบเขตนี้ยังไม่ deduplicate remote upload: manifest ยังไม่เก็บ video/cover key ที่
  upload สำเร็จ lost-response retry จึงอาจทิ้ง object ใหม่ที่ไม่ได้อ้างถึง ต้องมี
  key reuse หรือ cleanup/lifecycle ที่พิสูจน์กับ R2 ก่อน Production

## Recovery baseline ที่ห้ามถอยหลัง

- RevenueCat webhook และ restore/resync ต้องใช้ cursor ต่อผู้ใช้และธุรกรรม
  Serializable เดียวกัน รับเฉพาะ observation ที่ใหม่กว่าอย่างเคร่งครัด; timestamp
  ที่เก่าหรือเท่ากันห้ามย้อน entitlement และ fallback clock ต้องถูกระบุเป็น residual risk
- `scheduledAt` ของ create/reschedule ต้องเป็น RFC 3339 ที่มี timezone และวันที่ปฏิทิน
  ถูกต้อง ก่อนบังคับเงื่อนไขอนาคต/+30 วัน ห้ามกลับไปใช้ parser แบบ permissive
- การนับ post units ต้อง deduplicate แพลตฟอร์มและ reserve quota/insert post แบบ atomic;
  Prisma ใช้ Serializable transaction และ retry write conflict ก่อนตรวจโควตาซ้ำ
- ต้องรักษา main/recovery publishing readiness, 9:16/rotation, mounted guards,
  watermark cleanup, Subtitle Studio/SFX/cover และ baseline/no-regression tests เดิม
  การเพิ่ม drafts/settings ห้ามเปลี่ยนสิ่งเหล่านี้เป็นคำอ้างว่า provider หรือ Production พร้อม
- Production account deletion ใช้ `FIREBASE_AUTH_DELETE_ENABLED=false` ตาม release
  policy จน durable full-user mutation barrier/drain ผ่าน หากสภาพแวดล้อมใดตั้ง flag
  ขัดกัน ต้องถือเป็น blocking configuration mismatch ไม่ใช่ readiness evidence

## งานและหลักฐาน

1. [x] เพิ่ม stable UID, live Firebase UID+token snapshot, owner-change fail-closed
   และแยก draft directory ต่อบัญชี
2. [x] เพิ่ม versioned/validated local file store พร้อมสำเนา video/cover และ recovery
3. [x] เชื่อมบันทึก เปิด แก้ และลบร่างใน Upload โดยไม่มี publish-side effect
4. [x] เอาการเลือกแพลตฟอร์มอัตโนมัติออกและเพิ่ม explicit select-all/clear-all
5. [x] เพิ่ม per-platform outcome/connected-account identity ใน Review และ block
   unknown outcome, incomplete settings หรือ missing identity
6. [x] ใช้ future-only/+30-day policy ร่วมกันใน Upload, Calendar และ API
7. [x] เพิ่ม owner-scoped publish-now endpoint และ Mobile client/action
8. [x] เพิ่ม stable draft request ID, database-first create/replay repair, `409`
   contract และ explicit-confirm new-attempt flow ที่เก็บร่างเดิม
9. [x] แสดง server lifecycle/replay ตามจริงและเก็บร่างเมื่อ status ไม่รู้จัก
10. [x] เพิ่ม progressive per-platform UI, exact settings validation/local restore
11. [x] เพิ่ม nullable schema migration, settings/target snapshot, redaction,
    provider target revalidation และ delivery outcome
12. [ ] Apply migration/API-first และยืนยัน readiness version บน Staging
13. [ ] ทดสอบบน Android/iPhone จริง: save/restore/update/delete, แอป restart,
   สลับบัญชี, พื้นที่เต็ม, backup/restore behavior และ publish success/failure cleanup
14. [ ] ทดสอบ Staging first/replay/conflict, queue repair, truthful status,
   schedule/reschedule/publish-now และ lost-response R2 cleanup โดยได้รับอนุมัติแยก
15. [ ] ทดสอบ provider draft, YouTube compliance/visibility, target change/redaction,
    delivery outcome และ legacy-null backlog ด้วย disposable accounts
16. [ ] ลง durable repository owner barrier/lease หรือ transactional
   outbox/claim-and-drain ให้ครอบทุก user mutation family และ worker provider call;
   ต้อง drain งานค้างก่อน cleanup แล้วทดสอบทั้ง process เดียว/ข้าม process ก่อนเปิด
   Production account deletion หรือ scale API/separate real worker

## เกณฑ์ก่อน Production

- ห้ามอ้างว่า local drafts ซิงก์ข้ามเครื่องหรือถูกเก็บบน cloud ของ PostDee
- ต้องตรวจนโยบาย Android/iOS backup และทำ Privacy/Data Safety ให้ตรงกับ final binary
- ต้องยืนยันว่า sign-out/account deletion และการกลับเข้าสู่ UID เดิมมีพฤติกรรมตาม copy
  ที่ผู้ใช้เห็น หรือเพิ่ม cleanup flow ก่อนเผยแพร่ ปัจจุบัน account deletion ยังไม่
  production-safe: coordinator serialize authenticated route mutations และ RevenueCat
  webhook application เฉพาะใน API process เดียว จึง drain mutation ที่เริ่มใน instance
  อื่นไม่ได้ และ worker ไม่ถือ lease ตลอด provider call
- ต้องทดสอบสลับ Firebase account ระหว่าง token refresh/readiness/upload/create-post
  ว่า flow หยุด, ไม่สร้าง post ใต้ UID ใหม่ และร่างเดิมยังคงแยกอยู่กับ owner เดิม
- ต้องมีหลักฐานว่า save draft ไม่สร้าง upload/post/queue/quota side effect และว่า
  failure ก่อน queue acceptance ไม่ลบร่าง
- ต้องมีหลักฐาน per-platform Review, future/+30-day boundaries และ publish-now
  queue/persistence compensation ทั้ง automated และบน release candidate จริง
- ต้อง apply migration/API-first, ยืนยัน `platformSettingsVersion: 1`, และ audit/drain
  legacy-null queued backlog ก่อนปล่อย Mobile/เปิด PostPeer
- ต้องทดสอบ TikTok inbox และ Facebook Page draft ว่า provider ยืนยัน final draft,
  ใช้โควตา และ UI ไม่เรียกว่าสาธารณะ; TikTok direct ต้องปิดต่อจน creator-info,
  consent และ audit ครบ
- ต้องทดสอบ YouTube title/kids/synthetic/certification กับ Private/Unlisted/Public
  และไม่รับประกัน non-private ก่อน provider/API audit ผ่าน
- ต้องมีหลักฐาน target snapshot/revalidation เมื่อ disconnect/replace connection และ
  ยืนยันว่า `platformTargets`/`providerPostId` ไม่หลุดใน API, queue หรือ log
- ต้องมีหลักฐาน first `201`, replay `200`, safe `409`, queue `503` repair,
  exactly-once post unit และ truthful Mobile status หลัง app/API restart
- ต้องยืนยันว่า idempotency `409` ปิด Post ของ draft ID เดิม, การกดซ้ำไม่ upload,
  ยกเลิกคำเตือนไม่สร้างอะไร และยืนยันแล้วจึงได้ draft/request ID ใหม่โดยร่างเดิมยังอยู่
- post-row idempotency ไม่ถือว่าแก้ remote orphan ต้องพิสูจน์ reuse/cleanup ของ
  video/cover object และ R2 lifecycle แยก
- lock ปัจจุบันเป็น memory map ภายใน process, ครอบเฉพาะ route ที่ wire ไว้ และ worker
  ไม่ถือระหว่าง provider call; ห้ามเปิด Production account deletion รวมถึงห้าม
  multi-instance/separate real worker จน durable repository barrier ปิดรับ mutation ใหม่,
  drain ทุก user write ที่กำลังทำ และครอบ worker claim/provider critical section
- Privacy Policy/Terms ในแอปยังเป็น working draft ต้องแทนด้วยฉบับตรวจทาน/hosted
  และทำ Android Data Safety, iOS App Privacy, backup disclosure ให้ตรงกับ local media
