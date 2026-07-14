# Google Play listing draft — PostDee

อัปเดตล่าสุด: 14 กรกฎาคม 2026

สถานะ: **เอกสารเตรียมข้อมูลเท่านั้น — ยังห้าม Submit หรือเปิด Production**

เอกสารนี้ยึดสถานะปัจจุบันจาก `README.md`, `ROADMAP.md`, UI ใน
`apps/mobile/lib/features` และ release manifest ที่สร้างในเครื่องล่าสุด
คำว่า “มีในโค้ด” ไม่เท่ากับ “ผ่านการทดสอบ production กับผู้ให้บริการแล้ว”

## 1. ข้อมูลแอปที่ยืนยันจากโปรเจกต์

| รายการ | ค่าปัจจุบัน | สถานะ |
| --- | --- | --- |
| ชื่อแอปบนเครื่อง | `PostDee` | ยืนยันจาก Android manifest |
| ชื่อแอปที่เสนอใน Google Play | `PostDee` (7 ตัวอักษร จากเพดาน 30) | พร้อมใช้ |
| Android application ID | `com.postdee.postdee_mobile` | ห้ามเปลี่ยนหลังเผยแพร่ |
| ประเภท | App | เสนอ |
| หมวดหมู่ | Business | TODO: เจ้าของผลิตภัณฑ์ยืนยันใน Play Console |
| ภาษาหลัก | ไทย (`th-TH`) | พร้อมเป็นภาษาหลัก |
| เวอร์ชันใน release manifest ล่าสุด | `0.1.0` (`versionCode` 1) | TODO: ตัดสินใจเลขเวอร์ชันจริงก่อนอัปโหลด AAB |
| Android ขั้นต่ำ | API 24 | ยืนยันจาก release manifest ล่าสุด |
| Target SDK | API 36 | ยืนยันจาก release manifest ล่าสุด |
| มีโฆษณา | ไม่พบ Ad SDK หรือพื้นที่โฆษณาในแอป | เสนอให้ตอบ “No”; ต้องตรวจ final AAB อีกครั้ง |
| การซื้อในแอป | Starter / Pro แบบสมาชิก | มี flow ในโค้ด แต่ Google Play products และ RevenueCat production ยังไม่พร้อม |

ข้อกำหนดข้อความปัจจุบันของ Google Play คือชื่อไม่เกิน 30 ตัวอักษร,
คำอธิบายสั้นไม่เกิน 80 ตัวอักษร และคำอธิบายเต็มไม่เกิน 4,000 ตัวอักษร
([Google Play Console Help](https://support.google.com/googleplay/android-developer/answer/9859152?hl=en-EN)).

## 2. ข้อความหน้าร้านภาษาไทย

ข้อความด้านล่างตั้งใจไม่รับรองว่าคลิปถูกเผยแพร่ถึงทุกแพลตฟอร์มแล้ว และไม่กล่าวถึง
ฟีเจอร์ prototype หรือ provider ที่ยังไม่ผ่าน production end-to-end

### ชื่อแอป

```text
PostDee
```

### Short description

64/80 ตัวอักษร:

```text
เตรียมคลิป แคปชั่น ตารางโพสต์ และตัดต่อวิดีโอสำหรับครีเอเตอร์ไทย
```

### Full description

```text
PostDee คือพื้นที่เตรียมงานวิดีโอสั้นสำหรับผู้ขายออนไลน์ ครีเอเตอร์ และนักการตลาดสายแอฟฟิลิเอตในไทย ช่วยจัดคลิป แคปชั่น และตารางงานไว้ในขั้นตอนเดียวก่อนนำไปเผยแพร่

จัดเตรียมคอนเทนต์ได้เป็นขั้นตอน
• เลือกวิดีโอแนวตั้ง 9:16 จากเครื่องและตรวจข้อมูลคลิปก่อนสร้างโพสต์
• เขียนแคปชั่นและเลือกปลายทางของงานแต่ละชิ้น
• บันทึกเทมเพลตแคปชั่นที่ใช้บ่อยแล้วนำกลับมาใช้ได้
• วางแผนวันเวลาและตรวจสถานะงานผ่านปฏิทินโพสต์

ปรับวิดีโอก่อนนำไปใช้
• ดูตัวอย่างและเลื่อนไทม์ไลน์ไปยังช่วงที่ต้องการ
• ตัดต้นท้าย แบ่งช่วง ปรับความเร็วและระดับเสียง
• เพิ่มข้อความ สติกเกอร์ ฟิลเตอร์ และปรับแสงสี
• ส่งออกคลิปที่แก้ไขแล้วเพื่อนำไปใช้ในขั้นตอนโพสต์

ออกแบบเพื่อผู้ใช้ภาษาไทย
• หน้าจอและขั้นตอนหลักใช้ภาษาไทย
• รองรับธีมสว่างและธีมมืด
• แสดงสถานะงานที่จัดคิว ตั้งเวลา กำลังทำงาน หรือไม่สำเร็จอย่างชัดเจน

ความสามารถบางส่วนต้องเข้าสู่ระบบ เชื่อมต่ออินเทอร์เน็ต หรือใช้แพ็กเกจ Starter/Pro ตามเงื่อนไขที่แสดงในแอป
```

ก่อนนำข้อความนี้ขึ้น Store ต้องทดสอบทุก bullet กับ **final release AAB** อีกครั้ง
โดยเฉพาะการส่งออกวิดีโอจริงบน Android หลายรุ่นและสถานะงานจาก production API

## 3. จุดเด่นและขอบเขตความจริงของระบบ

### ใช้เป็นจุดเด่นได้หลังตรวจ final AAB

- เลือกวิดีโอ 9:16 จาก Android Photo Picker โดยไม่ขอสิทธิ์อ่านคลังทั้งเครื่อง
- สร้างแคปชั่นและใช้เทมเพลตที่บันทึกไว้
- ปฏิทินและหน้ารายละเอียดแสดงสถานะ `QUEUED`, ตั้งเวลา, กำลังโพสต์,
  สำเร็จบางส่วน และไม่สำเร็จ โดยไม่ตีความ “เข้าคิว” ว่าเผยแพร่สำเร็จแล้ว
- เครื่องมือตัดต่อด้วยมือรองรับตัดต้นท้าย, แบ่งช่วง, ความเร็ว, ระดับเสียง,
  ข้อความ, สติกเกอร์, ฟิลเตอร์, แสงสี และส่งออกผ่าน FFmpeg ในเครื่อง
- หน้าตรวจผลงานวิดีโอมีตัวเล่น, ไทม์ไลน์, เวลาเล่น/เวลารวม และการลองใหม่เมื่อเปิดไฟล์ไม่ได้
- ผู้ใช้มีทางเริ่มลบบัญชีจากหน้าโปรไฟล์

### มี integration ในโค้ด แต่ยังห้ามใช้เป็นคำรับรอง production

| ความสามารถ | สถานะจริง | เงื่อนไขก่อนเพิ่มใน Store copy/ภาพ |
| --- | --- | --- |
| โพสต์ TikTok, YouTube Shorts, Instagram Reels และ Facebook Reels | PostPeer connection/publisher มีในโค้ด | เชื่อมบัญชีผู้ใช้จริงและทดสอบตั้งแต่อัปโหลดถึงผลสำเร็จ/ล้มเหลวบนทุกปลายทาง |
| ตั้งเวลาโพสต์บน Cloud | BullMQ/Redis adapter มีในโค้ด | เปิด Upstash + worker แยก, ใช้ Prisma และทดสอบ delayed job, restart, retry, cancel |
| Firebase Email/Google/Phone Auth | gateway มีในแอปและ API; release SHA/OAuth ตรงกับ APK ที่เซ็นแล้ว | ทดสอบ Email/Google/Phone บน Internal testing AAB และมือถือจริง |
| Starter/Pro | Paywall และ RevenueCat gateway มีในโค้ด | สร้าง Google Play products/offerings, ใส่ Android production SDK key และทดสอบซื้อ ต่ออายุ ยกเลิก คืนเงิน และ restore |
| AI แคปชั่นจากคลิป | Gemini/Groq adapters และ quota มีในโค้ด | ทดสอบ provider, โควตา, frame flow และ usage ledger ด้วยบัญชี Starter/Pro จริง |
| Pro AI ตัดต่อ | renderer จริงรองรับซับ, ตัดช่วงเงียบ, ตัดคำฟุ่มเฟือย และแสงสี | ทดสอบ Groq + upload + FFmpeg + review + post/manual editor บนอุปกรณ์จริงหลายรุ่น |
| Analytics | API/UI ใช้ข้อมูล backend และไม่สร้างตัวเลขปลอม | ต้องมีผลโพสต์จริงจาก provider และตรวจช่วงวันที่/ยอดจากบัญชีจริง |
| Push notification | FCM mobile/server code มี | เปิด Firebase sender, ทดสอบ permission, token refresh, logout/unregister และ invalid-token cleanup |
| ลบบัญชีครบทุกระบบ | มี in-app flow และ backend cleanup barrier | ตรวจ production credentials, R2/PostPeer/Firebase cleanup, RevenueCat behavior และ public deletion URL |

### ห้ามนำไปใส่ Store listing หรือ screenshots ตอนนี้

- Shopee Video และ Lazada Video ในฐานะปลายทางที่โพสต์ได้จริง
- ตัดคลิปเป็น EP อัตโนมัติ
- Hashtag Radar, ศูนย์คอมเมนต์ AI และแจ้งเตือนไวรัล
- Link in Bio ที่เผยแพร่เป็นเว็บไซต์จริง
- Team & Editor Access
- Beat sync/เพลงอัตโนมัติ และ Hook 3 วินาที
- Auto reframe, auto zoom, ลดเสียงรบกวน, แปลซับ, ป้ายราคา, CTA card
  และลายน้ำจากหน้า AI
- คาราโอเกะไฮไลต์ตามเสียง, สีซับหลายสี, พื้นหลังซับหลายแบบ หรือตำแหน่งซับกลาง
- ข้อความ “โพสต์สำเร็จทุกช่องทาง” จากเพียง response ว่า `QUEUED`

## 4. ความจริงของแพ็กเกจใน UI

ตารางนี้บันทึกข้อความปัจจุบันใน Paywall ไม่ใช่การยืนยันว่า Google Play product พร้อมขาย

| แพ็กเกจ | UI ปัจจุบัน | ข้อควรระวังสำหรับ Store |
| --- | --- | --- |
| Basic | 3 post units/เดือนหลังยืนยันเบอร์ | Phone Auth และ real publishing ต้องผ่าน production test |
| Starter | 120 post units, ตั้งเวลา/ปฏิทิน/เทมเพลต, AI แคปชั่นจากเสียง 50 ครั้ง, ลายน้ำ PostDee อัตโนมัติ | Google product/RevenueCat และ AI provider ยังไม่ผ่าน checkout-to-entitlement E2E |
| Pro | 250 post units, Starter, analytics, AI แคปชั่นเสียง+ภาพ 120 ครั้ง, AI ตัดต่อ 200 นาที | ต้องทดสอบ entitlement, quota, provider และอุปกรณ์จริงก่อนโฆษณา |

- หนึ่ง post unit นับต่อหนึ่งแพลตฟอร์ม ไม่ใช่ต่อหนึ่งวิดีโอ
- ลายน้ำที่ทำได้จริงตอนนี้เป็นโลโก้ PostDee ตำแหน่งขวาล่างคงที่ ไม่ใช่โลโก้ร้านที่อัปโหลดเอง
- อย่าใส่ราคาลง short description, icon, feature graphic หรือข้อความส่งเสริมการขาย
  ราคาควรมาจาก Google Play product metadata ตามประเทศ

## 5. Data safety working draft

นี่คือรายการสำหรับตรวจสอบ ไม่ใช่คำตอบที่อนุมัติแล้วใน Play Console ผู้เผยแพร่ต้อง
ตรวจ final AAB, production configuration, privacy policy และเอกสาร Data Safety
ของ SDK ทุกตัวก่อนตอบ Google เพราะ Google กำหนดให้รวมข้อมูลที่ third-party SDK
เก็บด้วย ([Data safety guidance](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en)).

| ประเภทข้อมูลที่อาจต้องประกาศ | ตัวอย่างใน PostDee | วัตถุประสงค์ที่คาด | ต้องยืนยันก่อนกรอก |
| --- | --- | --- | --- |
| Name | ชื่อจาก Firebase/Google, ชื่อแสดงผล | Account management, app functionality | โปรไฟล์ที่แก้ในแอปยังเป็น local draft; แยกข้อมูลที่ส่ง backend จริง |
| Email address | Email/Google sign-in | Authentication, account management, support | Firebase production flow และ retention |
| Phone number | Firebase Phone Auth สำหรับ Basic quota | Authentication, fraud/abuse prevention | เป็น optional หรือ required ต่อผู้ใช้แต่ละแพ็กเกจ |
| User IDs | Firebase UID, internal user ID, social connection IDs | Account management, cross-service linking | การส่งต่อ Firebase, RevenueCat, PostPeer และ backend |
| Purchase history | product, entitlement, renewal/cancel/refund state | Purchases, subscription entitlement | Google Play Billing และ RevenueCat Data Safety docs |
| Photos and videos | วิดีโอที่ผู้ใช้เลือก และ frames ที่ Pro อาจสกัด | Upload, publishing, AI caption/edit | retention ใน R2, Gemini/Groq และการลบหลังงานเสร็จ |
| Audio files / voice content | เสียงภายในวิดีโอที่ส่งถอดเสียง | AI caption/edit | provider, region, retention และการใช้เพื่อ train model หรือไม่ |
| Other user-generated content | แคปชั่น, template, post metadata, schedule | App functionality | store ที่ใช้จริงและระยะเก็บ |
| App interactions | เหตุการณ์ใช้งานที่ส่ง Firebase Analytics | Analytics | production เปิด monitoring อัตโนมัติเมื่อ Firebase เปิด |
| Crash logs / diagnostics | Firebase Crashlytics | App stability | SDK defaults, retention และ user association |
| Device or other IDs | FCM token, Firebase installation/analytics identifiers, RevenueCat app user ID | Push, analytics, subscriptions | ตรวจว่าจัดเป็น collected/shared อย่างไรใน SDK docs |

### ผู้ประมวลผล/บริการที่ต้องอยู่ใน privacy review

- Firebase Authentication, Analytics, Crashlytics และ Cloud Messaging
- Google Play Billing และ RevenueCat
- Render API/PostgreSQL
- Cloudflare R2
- Gemini และ/หรือ Groq ตาม production configuration
- PostPeer เมื่อเปิด social connection/publishing
- Upstash Redis เมื่อเปิด durable scheduling

อย่าตอบ “ไม่แชร์ข้อมูล” โดยอัตโนมัติ คำว่า service provider และ user-directed action
มีเงื่อนไขเฉพาะในแบบฟอร์ม ต้องให้ผู้รับผิดชอบ privacy ตรวจสัญญาและการใช้งานจริงก่อน

### Data safety / privacy TODO

- [ ] สร้าง privacy policy ภาษาไทยบน URL สาธารณะ เปิดได้โดยไม่ล็อกอิน ไม่เป็น PDF
  และแก้ไขโดยผู้เยี่ยมชมไม่ได้
- [ ] ใส่ชื่อ `PostDee` หรือชื่อ developer ที่ตรงกับ Store, ช่องทางติดต่อ,
  ประเภทข้อมูล, ผู้รับข้อมูล, ความปลอดภัย, retention และ deletion ให้ครบ
- [ ] สร้าง public account-deletion URL ที่ผู้ใช้ส่งคำขอลบได้โดยไม่ต้องติดตั้งแอปใหม่
- [ ] ทดสอบ in-app deletion ด้วย production services และระบุข้อมูลที่ต้องเก็บต่อเพราะกฎหมาย (ถ้ามี)
- [ ] ยืนยันว่า production ทุก endpoint เข้ารหัสระหว่างส่งผ่าน HTTPS/TLS ก่อนตอบ
  “Data is encrypted in transit”
- [ ] ตัดสินใจว่ามี user opt-out สำหรับ Analytics/Crashlytics หรือไม่ และทำให้คำตอบตรงกับแอป
- [ ] ดาวน์โหลด/อ่าน Data Safety guidance ของ Firebase, RevenueCat และ provider ทุกตัวตามเวอร์ชันใน final AAB
- [ ] ให้ผู้รับผิดชอบกฎหมาย/PDPA ตรวจคำตอบฉบับสุดท้าย

แอปมีการสร้างบัญชี จึงต้องมีทั้งทางลบในแอปและ web resource สำหรับขอลบบัญชี
([Google Play account deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en)).

## 6. Android permissions checklist

รายการนี้อ่านจาก packaged **release** manifest ที่สร้างในเครื่องวันที่ 14 กรกฎาคม 2026
ต้องตรวจซ้ำจาก App Bundle Explorer หลังอัปโหลด final AAB เพราะ dependency หรือ build flag
อาจทำให้รายการเปลี่ยนได้

| Permission ใน release manifest | เหตุผลที่พบ | สิ่งที่ต้องทำ |
| --- | --- | --- |
| `ACCESS_NETWORK_STATE`, `INTERNET` | API, Firebase, provider และ media upload | เก็บ; privacy policy ต้องอธิบาย network processing |
| `WAKE_LOCK`, `com.google.android.c2dm.permission.RECEIVE` | Firebase Cloud Messaging | เก็บเมื่อ push พร้อมจริง; ถ้ายังไม่เปิด pushให้พิจารณาถอด FCM ออกจาก release |
| `POST_NOTIFICATIONS` | Push notification บน Android รุ่นใหม่ | ขอเมื่อผู้ใช้เข้าใจประโยชน์ ไม่ขอทันทีโดยไม่มีบริบท; ทดสอบกรณีปฏิเสธ |
| `USE_BIOMETRIC`, `USE_FINGERPRINT` | มาจาก Google/Firebase credential dependencies | TODO: ตรวจว่า release จำเป็นจริงหรือถอดได้; UI ไม่ควรอ้าง biometric login ถ้ายังไม่มี flow |
| `com.google.android.gms.permission.AD_ID` | dependency ของ Firebase Analytics/Google services | แอปไม่มีโฆษณา แต่ยังต้องตรวจ Advertising ID/Data safety declaration หรือถอด permission หากไม่จำเป็น |
| `ACCESS_ADSERVICES_ATTRIBUTION`, `ACCESS_ADSERVICES_AD_ID` | Google measurement dependencies | ตรวจ SDK behavior และ declaration ใน Play Console |
| `BIND_GET_INSTALL_REFERRER_SERVICE`, `READ_GSERVICES` | Google/Firebase services | ตรวจ SDK disclosure และเก็บเฉพาะที่จำเป็น |
| `com.android.vending.BILLING` | Google Play Billing/RevenueCat | ต้องมีสำหรับสมาชิก; ทดสอบด้วย production product |
| `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | AndroidX internal signature permission | ไม่ใช่ข้อมูลผู้ใช้; ตรวจว่า final manifest เหมือนเดิม |

ไม่พบ `CAMERA`, `RECORD_AUDIO`, location, contacts, SMS หรือ broad storage permission
ใน release manifest snapshot นี้ การเลือกวิดีโอใช้ Photo Picker provider จึงไม่ควรเขียน
ข้อความขอสิทธิ์คลังภาพทั้งเครื่องหาก final AAB ยังเป็นเช่นนี้

- [ ] อัปโหลด final AAB ไป Internal testing แล้วตรวจ App Bundle Explorer > Manifest
- [ ] ตรวจ Play Console Permissions Declaration หลังอัปโหลด AAB; Google จะแสดงแบบฟอร์ม
  เมื่อ bundle มี permission ที่ต้องอธิบาย
  ([Permissions declaration](https://support.google.com/googleplay/android-developer/answer/9214102?hl=en-EN))
- [ ] ตรวจ runtime permission บน Android 7, 13 และรุ่น target ล่าสุด
- [ ] ทำให้คำอธิบาย permission ในแอปและ privacy policy ตรงกับ final binary

## 7. Graphics checklist

ข้อกำหนดอ้างอิงล่าสุดอยู่ที่
[Add preview assets](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en).

### App icon

- [ ] ส่งออก **32-bit PNG 512 × 512 px**, มี alpha และไม่เกิน 1,024 KB
- [ ] ใช้ `apps/mobile/assets/images/brand/postdee_launcher_icon.png` (1024 × 1024)
  เป็น source แล้ว export ไฟล์ Store แยก; ห้ามยืดไฟล์
- [ ] ตรวจ safe zone/ขอบมนตาม Play icon specification
- [ ] ห้ามใส่ราคา, คำว่า Free, อันดับ, badge หรือโลโก้ Google Play

ยังไม่มีไฟล์ 512 × 512 ที่ประกาศเป็น Google Play asset อย่างชัดเจนใน repo

### Feature graphic

- [ ] สร้าง JPEG หรือ 24-bit PNG **1024 × 500 px**, ไม่มี alpha
- [ ] สื่อว่าเป็น workflow เตรียมคลิปสำหรับครีเอเตอร์ไทย โดยใช้ UI/ฟีเจอร์ที่พร้อมจริง
- [ ] วางสาระสำคัญไว้กลางภาพเพื่อป้องกันการตัดขอบ
- [ ] ห้ามใช้คำราคา, “อันดับ 1”, “ดีที่สุด”, “ดาวน์โหลดเลย” หรือฟีเจอร์ที่ยังเป็น TODO

ยังไม่พบ feature graphic ใน repo

### Phone screenshots

Google Play กำหนดอย่างน้อย 2 ภาพ; สำหรับการแสดงผลที่ดีควรมีอย่างน้อย 4 ภาพ
ความละเอียด portrait 1080 × 1920 px (9:16) ภาพจริงของแอป ไม่มี alpha

- [ ] ภาพ 1 — Home หลังล็อกอินด้วยบัญชีทดสอบจริง; ไม่แสดงข้อมูลส่วนตัว
- [ ] ภาพ 2 — ขั้นตอนเลือกคลิป 9:16/เขียนแคปชั่น
- [ ] ภาพ 3 — เครื่องมือตัดต่อด้วยมือและ preview จริง
- [ ] ภาพ 4 — ปฏิทินและสถานะคิว/ตั้งเวลา โดยไม่อ้างว่าคิวคือโพสต์สำเร็จ
- [ ] ภาพ AI review ใช้ได้ต่อเมื่อ provider + renderer ผ่าน real-device E2E
- [ ] ภาพ Analytics ใช้ได้ต่อเมื่อเป็นข้อมูลจาก real publish ไม่ใช่ mock/demo
- [ ] ภาพ Paywall ใช้ได้ต่อเมื่อ Google products/ราคา/entitlement ตรง production
- [ ] ลบ notification, email, UID, ชื่อบัญชี, token และข้อมูลลูกค้าออกจากภาพ
- [ ] ไม่ใช้ device frame เก่า, โลโก้แพลตฟอร์มโดยไม่มีสิทธิ์ หรือข้อความ claim ที่พิสูจน์ไม่ได้
- [ ] ใส่ alt text ต่อภาพไม่เกิน 140 ตัวอักษร

ยังไม่พบชุด Store screenshots ใน repo

## 8. Play Console App content checklist

- [ ] Developer name: **TODO**
- [ ] Support email: เสนอ `support@postdee.app`; ต้องทดสอบว่าส่ง/รับได้จริง
- [ ] Support website: **TODO**
- [ ] Privacy policy URL: **TODO**
- [ ] Account deletion URL: **TODO**
- [ ] Category: เสนอ Business; เจ้าของยืนยัน
- [ ] Target audience: เสนอ 18+ และไม่ออกแบบเพื่อเด็ก; เจ้าของ/กฎหมายยืนยัน
- [ ] Ads: เสนอ “No”; ตรวจ final SDK และ manifest ก่อนตอบ
- [ ] App access: ตอบว่าบางส่วนถูกจำกัดด้วยการเข้าสู่ระบบและแพ็กเกจ
- [ ] เตรียม reviewer email/password ที่ไม่ต้องใช้ข้อมูลส่วนตัวหรือ OTP ของ reviewer
- [ ] เปิด Pro ให้ reviewer ผ่าน entitlement จริง ห้ามใช้ mock header หรือ Test Store key
- [ ] เขียนขั้นตอน reviewer ตั้งแต่ sign-in > เลือกคลิป > ตัดต่อ > review > upload/post
- [ ] ระบุถ้า social connection ต้องใช้บัญชีทดสอบหรือขั้นตอนพิเศษ
- [ ] Content rating (IARC): กรอกตาม content จริงและ user-generated video workflow
- [ ] Data safety: ใช้ checklist ในหัวข้อ 5 หลังตรวจ SDK/final AAB
- [ ] Account deletion: ใส่ web URL และทดสอบ in-app path
- [ ] Financial features: ไม่ใช่แอปการเงิน; มีเพียง in-app subscription
- [ ] News, Government, Health: เสนอ “No” ตามฟังก์ชันปัจจุบัน
- [ ] ตรวจ policy สำหรับ AI-generated content ตาม flow จริงก่อน submit

Privacy policy ต้องมี URL ทั้งใน Play Console และในแอป รวมถึงชื่อ developer/app,
ข้อมูลที่เก็บ/แชร์, คู่สัญญา, ความปลอดภัย, retention และ deletion
([Google Play User Data policy](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en)).

## 9. Release / testing checklist ก่อนคิดเรื่อง Submit

- [ ] สร้าง `.aab` ที่เซ็นด้วย production upload key และเปิด Play App Signing
- [ ] ใช้ production Dart defines: Render HTTPS, Firebase enabled, local mock auth disabled
- [x] เพิ่ม Firebase release SHA-1/SHA-256, ดาวน์โหลด `google-services.json` ใหม่ และยืนยัน SHA-1 ตรงกับ release APK ที่เซ็นจริง
- [ ] เปลี่ยน RevenueCat Test Store key เป็น Android production SDK key
- [ ] สร้างและ activate `postdee_starter_monthly` / `postdee_pro_monthly`
- [ ] ทดสอบ purchase, renewal, cancel, refund, billing issue และ restore บน Internal testing
- [ ] เปิด/test PostPeer per-user connections และ controlled publish ทุกแพลตฟอร์มที่กล่าวใน Store
- [ ] เปิด/test Upstash worker และ scheduling หลัง restart/retry
- [ ] ทดสอบ R2 multipart upload จากมือถือจริง รวม slow network และ cleanup
- [ ] ทดสอบ Firebase Email/Google/Phone Auth บน release build
- [ ] ทดสอบ account deletion ครบ R2 > database > Firebase และ public web request
- [ ] ทดสอบ AI caption/edit บน Android อย่างน้อยรุ่นต่ำ กลาง และรุ่นใหม่
- [ ] รัน `flutter analyze`, `flutter test`, release build และ Play pre-launch report
- [ ] ตรวจ crash-free flow, accessibility, dark/light theme และภาษาไทยทุกหน้าที่ถ่าย Store
- [ ] ตรวจ final manifest, native libraries, 64-bit support และ App Bundle Explorer warnings
- [ ] ตรวจประเทศที่เปิดขาย, ราคา/ภาษี, refund/support และ PDPA
- [ ] ตัดสินใจว่า developer account เป็น Personal หรือ Organization และวันที่สร้างบัญชี

ถ้าเป็น Personal account ที่สร้างหลัง 13 พฤศจิกายน 2023 ต้องทำ Closed testing
อย่างน้อย 12 คนที่ opt-in ต่อเนื่อง 14 วันก่อนขอ Production access
([Google Play testing requirements](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en)).

## 10. เงื่อนไขปลดสถานะ “ห้าม Submit”

ปลดได้เมื่อครบทุกข้อ:

1. Store copy และ screenshots ไม่มี mock, demo, prototype หรือ claim ที่ยังไม่ผ่าน E2E
2. Firebase release sign-in, RevenueCat Google Play purchase, R2 upload และ account deletion ผ่านจริง
3. ถ้าระบุ social posting ต้องผ่าน PostPeer ตั้งแต่อัปโหลดถึงผลปลายทางจริง
4. ถ้าระบุ scheduling ต้องผ่าน durable worker หลัง restart/retry
5. ถ้าระบุ AI ต้องผ่าน provider, quota และ Android renderer ด้วยวิดีโอจริง
6. Privacy policy, deletion URL, Data safety, app access และ content rating พร้อม
7. final AAB, signing, pre-launch report, permissions และ Store assets ผ่านการตรวจ
