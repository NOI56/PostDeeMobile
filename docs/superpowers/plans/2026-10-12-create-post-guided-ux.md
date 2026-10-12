# สร้างโพสต์: ทีละขั้นและลูกเล่นที่ช่วยให้ใช้งานง่าย (2026-10-12)

สถานะ feedback follow-up ล่าสุด: verified/installed ในเครื่องแล้ว
Final feedback 10 tests อยู่ใน targeted 86/86, full suite 1,915/1,915 และ
analysis ผ่าน. Staging APK 4012/8012 ติดตั้งแล้วโดยคงบัญชี Native caption error/
focus/keyboard ตรวจแล้วและปล่อย clean empty step two ไว้; AI/save success ใช้ fixtures
ผล 187/187, 1,914/1,914 และ native 8011 เป็นประวัติก่อน guard สุดท้าย
Receipt ต่อไปนี้เป็น guided/connector base ก่อน feedback:
Final follow-up full suite 1,905/1,905 ผ่าน, analysis ไม่มี issues และ exact
Staging APK 4010/8010 ติดตั้งแล้วโดยคง session. Native เห็นเส้น/outline และ
active circle ย้ายจากคลิปไปแคปชันโดยไม่แต่ง completion.
Base guided 1,902 tests/8009/4-step blocked path ด้านล่างเป็นประวัติก่อน follow-up;
positive account/metadata/schedule/AI และ narrow/large-text ใช้ widget fixtures
ยังไม่ได้ push/deploy ชุดนี้ ใช้ Staging server เดิมที่ไม่ได้เปลี่ยนในรอบนี้
ผลส่งมอบ Home/Calendar ก่อนหน้านี้เป็นหลักฐานคนละรอบ

## Baseline และเหตุผล

ผู้ใช้ขอให้แนะนำการปรับหน้าโพสต์และแสดงตัวอย่าง แล้วตอบ “เริ่มทำเลย”
ใช้ตัวอย่าง guided เป็นฐาน โดยปรับสิ่งที่ผู้ใช้มองเห็น ไม่เปลี่ยนการโพสต์จริง
ตัวอย่างใช้ข้อมูลจำลองจาก
`C:\Users\stopp\.codex\visualizations\2026\10\09\01a11eef-cfc7-72c1-9a62-293b6cc057e0\create-post-preview.html`.

ทำใน worktree `codex/audit-system-fixes` ที่
`C:\Users\stopp\.codex\worktrees\audit-system-fixes\PostDeeMobile`.
HEAD ก่อนแก้คือ `21f9e7e8ef14233502bb949cb7bff5cc87faa7eb`; `origin/main`
และ merge base ที่ตรวจใหม่คือ `c4e52201a58b556f5f47529027549a2fc16af84c`.
Baseline อยู่ 23 ahead / 0 behind จึงไม่ขาดระบบใหม่บน main ที่ตรวจพบ
เก็บ Windows generated-plugin edits 3 ไฟล์เดิมไว้ ไม่รวมในชุดส่งมอบ
ไม่แก้ worktree หลัก `D:\PostDeeMobile` และไม่ย้อนโค้ดจาก branch เก่า

ตรวจ composer เดิม, review summary, shell/Calendar entry, AI style/learning,
draft/media ownership, connection identities, scheduling/entitlement และ tests
ก่อนแก้ หน้าเดิมมี 4 ขั้นอยู่แล้ว; revision นี้ทำให้ AI และข้อมูลยืนยันอ่านง่ายขึ้น
พร้อมลูกเล่นแนว Home โดยเก็บ state/controller เดิมตลอด flow
ประวัติ composer เดิมอยู่ใน `2026-06-06-mobile-ui-refresh.md` และไม่ถูกแทนที่

## ขอบเขตที่ยอมรับ

1. **คลิป:** เลือกไฟล์จริง ดูคลิป/โปสเตอร์ เปลี่ยนคลิปและแต่งหน้าปกได้เหมือนเดิม
   แสดงชื่อและ metadata ที่รู้จริงเท่านั้น: dimensions, verified 9:16 และขนาดไฟล์
   ไม่ใส่ duration หรือ metadata จำลองเมื่อไม่ทราบ
   คงการตรวจ 9:16 สำหรับโพสต์และเงื่อนไขอัปโหลด AI เดิม
2. **แคปชัน:** ช่องเขียนเป็นงานหลัก พร้อมคลิปขนาดเล็ก ปุ่มให้ AI ช่วยมองเห็นได้
   guidance, style, ตัวอย่างที่เรียนรู้และตัวเลือกเพิ่มเติมอยู่ในกลุ่มพับ
   template/SEO/fallback/review notice ยังเข้าถึงได้ ไม่รัน AI จากการเปิดหน้า
3. **ช่องทาง:** แสดงบัญชี/ช่อง/เพจที่ยืนยันแล้วคู่กับแพลตฟอร์ม
   คง select/clear/retry/connect และ platform settings เดิม
   ผลอ่านไม่สำเร็จหรือ identity หายต้องเป็น unknown/error ไม่แต่งชื่อเอง
   เพิ่ม owner/request-generation guard ใน lookup เดิม เพื่อ reject คำตอบของ
   owner เก่าหรือ request เก่า และไม่ให้ `finally` ของมันจบ loading ของ request ใหม่
   ไม่แสดง review identity ระหว่าง loading/error หรือ auth-owner mismatch
4. **ตรวจทานและส่ง:** คง schedule panel กับ shared inline review, edit กลับแต่ละขั้น
   และยืนยันครั้งเดียว เพิ่มสถานะขั้น/จำนวนช่องทางแบบสั้นใน sticky action area
   วันที่/เวลายังอยู่ใน shared review และ schedule panel ไม่ย้ายไป footer
   สรุปนี้ไม่แทน readiness/account/settings/time/plan checks

คงโทนขาว/ตัวอักษรเข้ม/ปุ่มเขียว, full-screen composer และ 5-tab shell เดิม
ยึด “ทีละขั้น” จากตัวอย่าง ไม่เพิ่มแผงพร้อมกันหรือสร้าง route review ซ้ำ
ปุ่มฉบับร่างและบันทึกร่างยังเป็นการกระทำชัดเจน ไม่มี autosave ใหม่

## ลูกเล่นและขอบเขต state

- Reuse `PostDeePressFeedback` ของ Home: press scale .97 โดยไม่เปลี่ยน
  gesture ownership, hit target, semantic tap หรือ disabled/busy behavior
- Surface ที่เลือกเปลี่ยนประมาณ 160 ms และ current step fade พร้อมเลื่อน 8 px
  ในประมาณ 180 ms; มีเฉพาะ body ขั้นปัจจุบันระหว่าง transition
  ไม่เก็บ outgoing form/actions ไว้ให้กดหรือให้ accessibility อ่าน
- Key/owner guard ต้องทำให้ late AI/media/connection response ไม่ไปทับบัญชีหรือ
  คลิปใหม่และไม่คืน widget ของขั้น/owner เก่า
- Reduced motion, disabled ancestor `TickerMode` และ app background หยุด effects
  ใช้งาน/อ่าน/เปลี่ยนขั้นได้ทันทีเมื่อไม่มี motion ไม่เพิ่ม hidden loaders/polling
  lifecycle observer สำหรับ presentation เท่านั้น ไม่ fetch ใหม่จากการ resume
  เมื่อปิด motion ระหว่าง transition ต้อง complete controller เป็น value 1
  เพื่อให้ current step แสดงครบ ไม่ค้าง opacity/ตำแหน่งกลางทาง
- สีเลือก/press/loading feedback ต้องไม่เป็นหลักฐานว่าเชื่อมต่อหรือโพสต์สำเร็จ

## ความสามารถเดิมที่ต้องคงอยู่

| Flow | ขอบเขตที่ต้องรักษา |
| --- | --- |
| AI | ผู้ใช้สั่งเอง, paid-plan/quota/entitlement reconciliation, clip-bound late-result guard, captionNeedsReview, SEO แยกจาก caption และ fallback ที่แจ้งตรงจริง |
| Style learning | profile แบบ owner-local, preset/emoji/length, learned examples สูงสุด 3; เรียนรู้เฉพาะ human-edited accepted non-fallback caption ตาม trigger เดิม |
| Draft/exit | ไฟล์ owner/device-local, explicit save, restore video/cover/caption/settings/schedule, continue/discard/save-and-exit; เปลี่ยนขั้นไม่ submit หรือ save |
| Media/cover | local player/poster และ cover editor เดิม, verified metadata, cover cleanup; ไม่เพิ่ม media upload เพื่อวาด UI |
| Destination | ชื่อจาก confirmed connection identities, loading/error/owner mismatch ไม่แสดงชื่อเก่า; owner/request-generation guard ไม่รับ late response หรือจบ loading ใหม่; missing/unknown/required settings บล็อกตามเดิม; TikTok inbox draft, YouTube Shorts, Instagram Reels, Facebook Page Video |
| Schedule | Calendar date handoff/injected local clock, ไม่ทับ restored draft, future/14-day Starter/30-day Pro/Free guard เดิม |
| Submit/result | phone/package/readiness/publisher guards, owned pre-submission receipt, stable clientRequestId replay, queue acceptance, partial/unknown/provider-draft truth และ draft cleanup เดิม |
| Ownership | stale owner/session results และ current-only actions/semantics; shell ปิด composer/child routes เมื่อบัญชีเปลี่ยน |

เป็น mobile presentation เท่านั้น ไม่มี endpoint/request/response field, database
schema/migration, provider mapping, dependency, environment flag, ราคา/แพ็กเกจ
หรือ quota ใหม่ Staging social publishing/publisher ยัง disabled ตามเดิม
ไม่โฆษณา Facebook Reels/Shopee Video/Lazada Video ว่าโพสต์ได้จาก revision นี้

## ผลตรวจ base guided รุ่น 8009 (ก่อน connector follow-up)

| การตรวจ | เกณฑ์ | สถานะรอบนี้ |
| --- | --- | --- |
| Test-first | guided controls/identity/known metadata/sticky summary + owner/refresh late-connection guard + press/cancel/step transition/reduced/background/semantics | guided 11/11 ผ่าน; หลังแก้ fold รัน app 15 + guided 11 = 26/26 ผ่าน 8s |
| Targeted regressions | uploader/AI style-learning/draft/review/shell/Calendar date handoff และ guards เดิม | existing 170 + guided 11 = 181/181 ผ่าน 43s ก่อนปรับ fold gap; fold regressions 26/26 ผ่านหลังแก้ |
| Full Flutter suite / analysis | ใช้ source รวมสุดท้าย ไม่มี count จาก Home/Calendar มาแทน | final full 1,902/1,902 ผ่าน 3m50s; analysis ไม่มี issues 13.2s; exit 0 ทั้งสอง |
| Diff review | ไม่มี deletion/unrelated rewrite/API/schema/env/dependency/settings lost | final read-only guard review ไม่มี material finding; diff --check ผ่าน |
| Exact Staging APK | package/signature/API/Firebase/flags ตรง source; ติดตั้งไม่ล้างบัญชี/ข้อมูล | helper build 4009/installed 8009 ผ่าน 21.8s, same signer, install -r สำเร็จ; session คงเดิม |
| Native/visual | 4 ขั้น, compact AI/options, actual identity/metadata states; ระบุ account/clip ที่ตรวจจริง | default-font 4 ขั้นผ่าน; no-destination confirm disabled; positive/narrow/large-text/motion ใช้ widget fixtures |
| Delivery | แยก push/CI/Render Live/health/migration receipt เมื่อได้รับอนุญาตและทำจริง | local source/APK/native ส่งมอบแล้ว; ไม่ได้ push/CI/Render deploy ชุดนี้ |

Runtime ที่แก้คือ `apps/mobile/lib/features/uploader/uploader_screen.dart`;
เพิ่ม `uploader_guided_ux_test.dart` และปรับ helpers/assertions ที่สัมพันธ์โดยตรง
ใน uploader, wizard, AI race, AI entitlement และ caption-style tests เดิม
เอกสารที่ sync คือ README, ROADMAP, API, ARCHITECTURE, Mobile README และ plan นี้
Commands/logs, final source, counts, APK/native และข้อจำกัดบันทึกด้านล่าง
Agent ไม่ทำ Save/Post/OAuth/ซื้อแพ็กเกจ/real AI/upload เพื่อพิสูจน์หน้าตา
Positive cases ใช้ fixture แยกจาก native empty/unknown state;
คลิปที่ผู้ใช้เลือกเองระหว่างตรวจและ review form ปัจจุบันไม่ถูกแก้หรือทิ้ง

### ไฟล์ที่เปลี่ยนและคำสั่งตรวจของ base guided รุ่น 8009

Runtime 1 ไฟล์:
`apps/mobile/lib/features/uploader/uploader_screen.dart`.
Test ใหม่ 1 ไฟล์: `apps/mobile/test/uploader_guided_ux_test.dart`.
Test เดิมที่ปรับ helpers/expectations ตรงกับ compact presentation 5 ไฟล์:

- `apps/mobile/test/uploader_ai_entitlement_resync_test.dart`
- `apps/mobile/test/uploader_caption_style_test.dart`
- `apps/mobile/test/uploader_screen_test.dart`
- `apps/mobile/test/uploader_wizard_ai_race_test.dart`
- `apps/mobile/test/uploader_wizard_test.dart`

เอกสาร 6 ไฟล์: `README.md`, `ROADMAP.md`, `API.md`, `ARCHITECTURE.md`,
`apps/mobile/README.md` และ plan นี้.
`app_test.dart` fold assertion เดิมไม่ได้เปลี่ยน;
Windows generated-plugin edits 3 ไฟล์เดิมไม่ได้เป็นส่วนหนึ่งของ guided revision

คำสั่งตรวจใช้ Flutter SDK `C:\Users\stopp\flutter\bin\flutter.bat`:

- `flutter.bat test`: baseline, test-first red, guided/targeted/fold regressions
  และ final full suite; ดู counts/source/logs ของแต่ละรอบด้านล่าง
- `flutter.bat analyze`: final source ไม่มี issues
- `apps/mobile/tool/postdee-staging.ps1 -Command build-apk` พร้อม
  `--target-platform android-x64 --split-per-abi --build-number=4009`:
  helper ตรวจ environment และสร้าง exact Staging debug APK
- `adb -s emulator-5556 install -r <app-x86_64-debug.apk>`: อัปเดตแอปโดยไม่ล้างข้อมูล
- `git diff --check` และ read-only guard/diff review: ขอบเขตไฟล์/guards/ไม่มี deletion

ไม่รัน backend suite หรือ Prisma migration ใหม่จาก mobile presentation นี้
เพราะไม่มี backend/API/schema เปลี่ยน และไม่ใช้ผลชุดเก่าอ้างว่ารันใหม่

### ผลตรวจและการแก้ fold ก่อน freeze source สุดท้าย

Baseline regressions ก่อนแก้ผ่าน 170/170 ใน 35s ที่
`D:\Temp\postdee-composer-guided-baseline-20261012.log`.
Initial test-first guided cases 10 กรณีไม่ผ่านตามที่คาดก่อน implement
(`+0 -10`) ที่ `D:\Temp\postdee-composer-guided-red-20261012.log`.
ต่อมาเพิ่มกรณีปิด motion กลาง transition จึงเป็น 11 กรณีในชุดสุดท้าย

Source `uploader_screen.dart` ก่อน follow-up fold มี SHA-256
`8741137F27069C1E2FBE280F2334A924309AA2C590A830D320A9BEBE7DE0914A`.
Guided tests 11/11 ผ่านใน 5s ที่
`D:\Temp\postdee-composer-guided-final-20261012.log`; targeted suite เดิม 170
รวม guided ใหม่ 11 เป็น 181/181 ผ่านใน 43s ที่
`D:\Temp\postdee-composer-guided-regressions-final-20261012.log`.
รวม compact AI/options, latest confirmed account names, owner/refresh late-result
guards, current-only controls/semantics, press cancel, reduced motion/TickerMode/
background และ disable-motion กลาง transition, 320 dp large text และ metadata
ที่รู้จริง

Full suite รอบแรกผ่าน 1,901 กรณีและ fail 1 ใน 3m49s ที่
`app_test.dart: keeps upload video preview compact on a phone viewport`.
Log คือ `D:\Temp\postdee-composer-guided-full-tests-20261012.log`.
Metadata/footer ที่เพิ่มทำให้ empty clip card ต่ำกว่า footer ใน viewport 393×698
จึงลดช่องว่างก่อนคลิปเฉพาะขั้นคลิปจาก 20 เป็น 12 logical px; ขั้นอื่นยัง 20
เก็บ assertion เดิมไว้ ไม่ลดเงื่อนไขการตรวจหรือย้าย footer เพื่อให้ test ผ่าน
App 15 + guided 11 รวม 26/26 ผ่านหลังแก้ใน 8s ที่
`D:\Temp\postdee-composer-guided-fold-regressions-20261012.log`.
Source hash ใหม่ที่ freeze และตรวจซ้ำคือ
`6BA75570326A0A857C69E3F8C0AB82E005220C35F7D944848ACFF3BA24186C11`.
Final analysis ของ hash นี้ไม่มี issues ใน 13.2s, exit 0 ที่
`D:\Temp\postdee-composer-guided-analyze-final-20261012.log`.
Final full Flutter suite ของ hash นี้ผ่าน 1,902/1,902 ใน 3m50s, exit 0 ที่
`D:\Temp\postdee-composer-guided-full-tests-final-20261012.log`.
Frozen runtime และ APK hash ตรงหลังการตรวจสุดท้าย ไม่มี runtime patch หลัง build

### Exact Staging APK และการติดตั้ง

Staging helper build 4009 ผ่าน `assembleDebug` ใน 21.8s ที่
`D:\Temp\postdee-composer-guided-apk-20261012.log`.
ใช้ runtime hash `6BA75570326A0A857C69E3F8C0AB82E005220C35F7D944848ACFF3BA24186C11`
และ APK `apps/mobile/build/app/outputs/flutter-apk/app-x86_64-debug.apk` มี SHA-256
`E28B205A5E333A1547EAB23C717BB20A94695843443C5D16BC9DA6D94D7E0ED2`.
Package คือ `com.postdee.postdee_mobile.staging`, installed versionCode 8009,
versionName `0.1.0-staging`, x86_64. Signer SHA-256
`014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`
ตรงกับรุ่นก่อน 8008. Helper ตรวจ Staging API
`https://postdee-api-staging.onrender.com`, Firebase auth เปิด/local mock ปิด,
validated RevenueCat Test Store overlay และ feature flags เดิม โดยไม่แสดง key

ก่อนติดตั้ง เครื่องจำลอง `emulator-5556` อยู่หน้า Home ที่ล็อกอินแล้ว,
Free 0/3, channels 0/4, posts 0 และไม่มี form เปิดค้าง.
`adb install -r` สำเร็จโดยไม่ uninstall/clear data;
package dump แสดง firstInstallTime เดิม `2026-10-05 06:30:36`
และ lastUpdateTime `2026-10-12 02:10:14` (ค่าดิบจาก device ไม่ใช้เป็นเวลาท้องถิ่น
ของผู้ใช้). เปิดแล้ว Home คงบัญชีที่ล็อกอิน, Free 0/3, channels 0/4 และ posts 0

### Native และ actual screenshots รุ่น 8009

ตรวจบนเครื่องจำลองที่มองเห็นด้วย default font ข้อมูลจริงของบัญชีนี้ไม่มี
ช่องทางเชื่อมและไม่มีโพสต์ จึงแยก native blocked/empty path ออกจาก positive fixtures

| ขั้นที่เห็นจริง | ผลและข้อจำกัด |
| --- | --- |
| คลิป | เริ่ม empty picker เห็น card ทั้งใบเหนือ sticky footer; ไม่เลือกคลิปแทนผู้ใช้ |
| แคปชัน | ปุ่ม AI มองเห็นทันทีและ options พับอยู่; เปิดดู style settings แบบอ่านอย่างเดียว ไม่บันทึกหรือเรียก AI จริง |
| ช่องทาง | no-channel state และจำนวนที่เลือก 0; ไม่อ้างว่าตรวจชื่อบัญชีที่เชื่อมบน native |
| ตรวจทาน | หลังผู้ใช้เลือกคลิปเองระหว่างการตรวจ เห็น thumbnail/file `100000099.mp4`, caption ว่าง, destinations 0, warning และ native confirmation `ยืนยันส่ง 0 ช่องทาง` disabled |

พบ user interaction ระหว่าง observations จึงอ่าน state ใหม่และปล่อย review form
ที่มีคลิปของผู้ใช้ไว้ตามเดิม ไม่แก้, Save, discard หรือปิดเพื่อให้ทำ QA ต่อ
ไม่มี agent Save/Post/OAuth/ซื้อแพ็กเกจ/real AI/upload.
Positive confirmed account identities, known dimensions/filesize, schedules,
real-clip AI trigger และ style learning ใช้ widget fixtures; ไม่อ้างว่า provider
publishing/real AI สำเร็จบน native. Narrow/large-text, press intermediates และ
reduced motion/TickerMode/background ใช้ widget tests ไม่ใช่ native default-font capture

Actual screenshots ที่ export จาก native observations:

- `C:\Users\stopp\.codex\visualizations\2026\10\12\01a12dc1-f51c-7ec2-9a95-f89a5069c32c\create-post-clip.png`
- `C:\Users\stopp\.codex\visualizations\2026\10\12\01a12dc1-f51c-7ec2-9a95-f89a5069c32c\create-post-caption.png`
- `C:\Users\stopp\.codex\visualizations\2026\10\12\01a12dc1-f51c-7ec2-9a95-f89a5069c32c\create-post-destinations.png`
- `C:\Users\stopp\.codex\visualizations\2026\10\12\01a12dc1-f51c-7ec2-9a95-f89a5069c32c\create-post-review.png`

Final native error log
`D:\Temp\postdee-composer-guided-native-errors-final-20261012.log` มี 0 bytes,
ไม่พบ Flutter/Android runtime error ในการตรวจนี้

### ขอบเขตส่งมอบและสิ่งที่ยังไม่ได้ยืนยัน

รอบนี้ส่งมอบ local source/tests/docs และ installed Staging APK เท่านั้น
ไม่มี push, remote CI หรือ Render deploy ของ guided revision; backend server
เดิมไม่ได้เปลี่ยน. ไม่มี database/schema/API/backend files เปลี่ยน จึงไม่ต้องมี
migration และไม่อ้าง fresh migration/database/deployment checks จากการทำ mobile UI
ผล backend/Render Live ของ Calendar ก่อนหน้าเป็นประวัติแยก ไม่ใช้แทนผลรอบนี้
ยังต้องขออนุญาตแยกสำหรับการโพสต์จริง/ซื้อแพ็กเกจหรือใช้บัญชีเชื่อมเพื่อ
native end-to-end ที่มี side effects; revision นี้ไม่มีการทดสอบการส่งออกโซเชียลจริง

## Follow-up: เส้นเชื่อมวงกลมขั้นตอน (2026-10-12, verified/installed ในเครื่อง)

หลังส่งมอบ local guided รุ่น 8009 ผู้ใช้ขอให้ progress เหมือนภาพอ้างอิง:
เพิ่มเส้นบาง 3 ช่วงเชื่อมวงกลมทั้ง 4 และให้วงกลมขั้นที่ยังไม่เสร็จมีเส้นขอบ
เป็นการปรับ presentation เฉพาะส่วนเดิม ไม่เปลี่ยนลำดับขั้นหรือเงื่อนไขสำเร็จ
หลักฐาน 1,902 tests, APK 4009/8009 และ native ข้างต้นเป็น receipt ก่อน follow-up
ไม่ใช้แทนผลของ source ใหม่

### ขอบเขตและ baseline

ใช้ HEAD `21f9e7e8ef14233502bb949cb7bff5cc87faa7eb` เดิมใน worktree เดิม;
fetch ใหม่ยืนยัน `origin/main`/merge base `c4e52201a58b556f5f47529027549a2fc16af84c`,
23 ahead / 0 behind. เก็บ pending guided source/tests/docs และ Windows edits
ทั้งหมดไว้ ไม่ reset, commit, push หรือข้ามงานก่อนหน้า

- เพิ่ม connector สี border ของ theme สูง 2 logical px จำนวน 3 ช่วง
  `LayoutBuilder` คำนวณระยะจากความกว้างจริงและวางเส้นระหว่างขอบวงกลมขนาด 26 px
- เส้นเป็นของตกแต่ง: `IgnorePointer`/`ExcludeSemantics` ไม่ขวางปุ่ม/เพิ่ม focus
  หรือ semantic action; ปุ่ม 4 ขั้นและ short-cut navigation ยังเป็นของเดิม
- ขั้นปัจจุบันยังสีเขียว, completed ยังขึ้น check จากข้อมูลที่ครบจริง
  ขั้นที่ยังไม่ current/complete เพิ่ม border; การข้ามขั้นที่ input ว่างไม่ทำให้ครบ
- คง captions/style learning, drafts, cover, connection owner/request guards,
  scheduling, publisher/entitlement และ current-only motion guards ของ guided
  ไม่เพิ่ม API/schema/dependency/environment/product rule หรือ migration

Runtime เปลี่ยนเฉพาะ progress ใน `uploader_screen.dart`; เพิ่ม 3 regression
cases ใน `apps/mobile/test/uploader_wizard_navigation_cues_test.dart`.
Source SHA-256 ที่ freeze คือ
`FB4158707E4B68BD08AA142F9ADD2E9B3B4C0DE5BB627444793483CF265EFFA1`.

### ผลตรวจที่เกิดขึ้นจริง

- Test-first connectors 3 กรณี fail ก่อน implement (`+0 -3`) ที่
  `D:\Temp\postdee-composer-connectors-red-20261012.log`.
- Nav cues 9 + guided 11 + app 15 รวม 35/35 ผ่านใน 12s ที่
  `D:\Temp\postdee-composer-connectors-targeted-20261012.log`.
  ตรวจตำแหน่งเส้นระหว่างขอบวงกลม/กึ่งกลาง/ความสูงที่ 320 dp/text 1.0,
  320 dp/text 2.0 และ 393 dp/text 1.0 รวม native-button semantics และ no submission
  outline ตรวจจาก read-only source review ไม่ใช่ assertion ใหม่ใน geometry tests
- Analysis ไม่มี issues ใน 11.6s ที่
  `D:\Temp\postdee-composer-connectors-analyze-20261012.log`.
- Read-only review ผ่านและ `git diff --check` ไม่มีปัญหา; hit/semantics และ
  completion guards เดิมยังคงอยู่

Helper build 4010 ผ่าน `assembleDebug` ใน 16.9s ที่
`D:\Temp\postdee-composer-connectors-apk-20261012.log` จาก source hash
`FB4158707E4B68BD08AA142F9ADD2E9B3B4C0DE5BB627444793483CF265EFFA1`.
APK `apps/mobile/build/app/outputs/flutter-apk/app-x86_64-debug.apk` มี SHA-256
`00D52A98ACE12243A4C793A10A26E733C89A055501B806F154A0A60C44392CFF`.
Package `com.postdee.postdee_mobile.staging`, versionCode 8010, x86_64,
same signer `014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`.
Final full suite ของ source ใหม่ผ่าน 1,905/1,905 ใน 3m14s, exit 0 ที่
`D:\Temp\postdee-composer-connectors-full-20261012.log`.
Source/APK hash ไม่เปลี่ยนหลัง build และ final checks

ตอนเตรียมติดตั้งครั้งแรก native 8009 มีคลิปผู้ใช้ `100000099.mp4` ใน form
ที่ยังไม่บันทึก จึงยังไม่ติดตั้งในตอนนั้น. Fresh pre-install state ภายหลังพบว่า
ผู้ใช้กลับ Calendar week วันที่ 12/All แล้วและไม่มี form เปิดค้าง
agent ไม่ได้ Save/discard/ปิด form นี้ จึงติดตั้งต่อได้โดยไม่เสี่ยงทิ้ง form เปิดอยู่
`adb install -r` สำเร็จ รุ่น 8010; package dump คง firstInstallTime
`2026-10-05 06:30:36`, lastUpdateTime `2026-10-12 02:28:04` เป็น raw device values
Native หลังติดตั้งเปิด Home โดยคงบัญชีเดิม จากนั้นเปิด Create Post แบบ empty
และกดขั้น 2 “แคปชัน”: เห็นเส้นบาง 3 ช่วงและ pending borders ในขั้นคลิป/แคปชัน,
active circle สีเขียวย้ายถูกขั้น. เมื่อข้ามจากคลิปว่าง ขั้นคลิปยังแสดงเลข 1
ไม่แสดง check ว่าครบแล้ว. ไม่มี overflow ที่ default font
ไม่มี clip selection, AI generation, Save/Post/OAuth/ซื้อแพ็กเกจโดย agent
Narrow/large text และ geometry ใช้ widget fixtures; ไม่อ้าง native text scale อื่น
Actual native screenshot ของขั้นแคปชันที่ active circle เป็น 2:
`C:\Users\stopp\.codex\visualizations\2026\10\12\01a12dc1-f51c-7ec2-9a95-f89a5069c32c\create-post-connectors.png`.
ตรวจ current-process `flutter:E`/`AndroidRuntime:E` สำเร็จ exit 0;
`D:\Temp\postdee-composer-connectors-native-errors-20261012.log` มี 0 bytes
ไม่พบ error. ปล่อยแอปที่ขั้นแคปชันให้ผู้ใช้เห็น; runtime hash สุดท้ายยัง FB415... ข้างต้น
ผล native 8009 ก่อนหน้าเป็นประวัติแยก; ไม่มี push/CI/Render deploy follow-up นี้

คำสั่ง follow-up ใช้ `flutter.bat test` (red/targeted/full), `flutter.bat analyze`,
Staging helper `-Command build-apk` พร้อม x64/split ABI/`--build-number=4010`,
`adb install -r` และ `git diff --check` ตาม receipts จริงข้างต้น
เพิ่ม navigation-cues tests เดิม 1 ไฟล์จาก base จึงรวมทั้งรอบเป็น runtime 1,
new guided test 1, existing tests 6 และ docs 6; Windows generated-plugin edits
เดิม 3 ไฟล์ยังไม่รวมในชุดนี้ ไม่มี backend/schema/API/env/dependency เปลี่ยน

## Follow-up: feedback แคปชัน, รอ AI และบันทึกร่าง (2026-10-12, verified/installed ในเครื่อง)

ผู้ใช้อนุญาตให้เริ่ม implement 3 ลูกเล่นจาก interactive prototype
`C:\Users\stopp\.codex\visualizations\2026\10\12\01a12dc1-f51c-7ec2-9a95-f89a5069c32c\create-post-interactions.html`.
Prototype ใช้ข้อความ/เวลา/ผลบันทึกจำลอง; runtime ต้องผูกกับ validation,
existing AI response และ draft save จริง ไม่ย้าย fake timers/results เข้าแอป
ผล 1,905 tests, build 4010/installed 8010 และ native connectors ด้านบนเป็น
base history ก่อน feedback follow-up นี้ ไม่ใช่ผลตรวจของ source ใหม่

### ขอบเขตและ baseline ของรอบนี้

ทำใน worktree `codex/audit-system-fixes` เดิมและเก็บ pending source/tests/docs
ทั้งหมด รวม Windows generated-plugin edits เดิมไว้ ไม่มี reset หรือทับงานก่อนหน้า
Fresh `git fetch origin` สำเร็จ; HEAD ของรอบนี้คือ
`21f9e7e8ef14233502bb949cb7bff5cc87faa7eb`, `origin/main`/merge base คือ
`c4e52201a58b556f5f47529027549a2fc16af84c`, 23 ahead / 0 behind.
Runtime ก่อน feedback patch มี SHA-256
`FB4158707E4B68BD08AA142F9ADD2E9B3B4C0DE5BB627444793483CF265EFFA1`;
เป็น source ก่อนรอบนี้ ไม่ใช่ final feedback hash หรือผล test ใหม่
ไม่มี push/deploy authorization ของ feedback รอบนี้

1. **แคปชันว่าง:** เมื่อกดไปต่อจากขั้นแคปชันโดยไม่มีข้อความที่ trim แล้ว
   ต้องคงขั้นเดิม แสดง inline error คู่ช่องแคปชันและย้าย focus ให้แก้ได้
   อ่าน error ได้ด้วย accessibility; แก้ข้อความแล้วต้องไม่ทิ้ง error เก่าค้าง
   ไม่ save, upload, เรียนรู้ style หรือ submit จาก failed validation
2. **กำลังรอ AI:** indicator แสดงเฉพาะช่วงที่ existing AI operation กำลังทำงาน
   และหยุดตามผลสำเร็จ/ล้มเหลว/ยกเลิก/owner หรือ clip เปลี่ยน ตาม guards เดิม
   เมื่อได้รับผลจริง แสดง caption ทั้งข้อความที่ใช้จริงพร้อมกันและ feedback สั้น
   ไม่จำลองพิมพ์ทีละตัวหรือแสดง caption ตัวอย่างว่าเป็นผล AI
   คง manual-edit protection, clip/owner late-result guards, paid-plan/quota,
   actual fallback/review notices, SEO และ human-edited style-learning trigger เดิม
3. **บันทึกแล้ว ✓:** แสดง feedback ชั่วคราวเมื่อ explicit Save สำเร็จจาก store จริง
   ไม่แสดงก่อน receipt, เมื่อ fail, หรือจาก navigation/publish pre-submission
   บอกว่าเก็บ draft ในเครื่อง ไม่แสดงเหมือนโพสต์หรือ cloud save สำเร็จ
   เมื่อหมดเวลา/แก้ form/เปลี่ยน owner ต้องไม่ค้าง success ของข้อมูลเก่า

คง 4 ขั้น, progress connectors/outlines, compact AI/options, cover/drafts,
verified connection identities, Calendar date handoff, scheduling/entitlements
และ existing publish/retry/result truth. Motion/feedback ต้องคง touch targets,
focus/semantics และทำงานทันทีเมื่อ reduced motion, disabled `TickerMode`
หรือ app background. ไม่เพิ่ม autosave/persistence trigger, provider request,
API/request field, backend/schema/migration, dependency หรือ environment flag

### แผนตรวจและสถานะจริง

| การตรวจ | เกณฑ์ | สถานะ feedback รอบนี้ |
| --- | --- | --- |
| Test-first feedback | required caption focus/inline error, real-operation AI wait/result, verified explicit save/failure/reset | ก่อน guard feedback 9/9 ผ่าน; final feedback 10 cases รวมใน save suite 86/86 ผ่าน |
| Existing regressions | manual edits/AI race, style learning/fallback, explicit draft save/failure/ownership, review/schedule/shell และ connectors | ก่อน guard 65/65 และ 187/187 ผ่าน; หลัง guard feedback/draft/exit/uploader 86/86 ผ่าน 31s |
| Full suite / analysis | source รวมสุดท้ายของ feedback ไม่ใช้ count 1,905 มาแทน | source D531 final full 1,915/1,915 ผ่าน 3m47s และ analysis ผ่าน 12.5s; source F1E6 full 1,914 เป็นก่อน guard |
| Read-only diff/guard review | เก็บ existing side effects/guards, ไม่มี deletion/unrelated changes | rapid Save guard แก้แล้ว; final static reviewer ไม่พบ blocker |
| Exact APK/native | ตรวจ source/environment/signature/installed version จริงและประเมิน form ก่อนติดตั้ง | build 4012/installed 8012 ผ่าน 21.8s; retained account/native error-focus-keyboard ผ่าน; final filtered error log 0 hits |
| Delivery | แยก local proof จาก push/CI/Render Live เมื่อมี authorization และทำจริง | local implementation/tests/docs/APK/native ส่งมอบแล้ว; ไม่ได้ push/CI/Render deploy ชุดนี้ |

Runtime/tests อยู่ในส่วน composer ที่สัมพันธ์โดยตรง: `uploader_screen.dart`
และ new `apps/mobile/test/uploader_interaction_feedback_test.dart`.
เอกสาร summary 5 ไฟล์ระบุ final feedback verified/installed ตามผลจริง
และคง prior 1,905/8010 กับ pre-guard 1,914/8011 เป็น history แยก
ไม่เรียก AI จริงหรือ Save/Post/OAuth/ซื้อแพ็กเกจบนบัญชีผู้ใช้เพื่อวาด UI
positive outcomes ใช้ widget fixtures และต้องแยกจาก native account state

### Source/build/targeted/native รุ่น 8011 (ประวัติก่อน rapid-save guard)

Runtime candidate `uploader_screen.dart` มี SHA-256
`F1E6B8C311F2168512BD776BD9339237079CA2B39C5773689809644546273654`.
Static reviewer ไม่พบ blocker และ analyzer ไม่มี issues ใน 12.1s
เป็น analysis ก่อนแก้ test helpers/rapid-save guard; source F1E6 full 1,914
ผ่านภายหลังตาม receipt ด้านล่าง ไม่ใช้แทน source guard รุ่น 8012

Staging helper build 4011 ใช้ debug/android-x64/split ABI ผ่าน `assembleDebug`
ใน 22.6s ที่ `D:\Temp\postdee-composer-feedback-apk-20261012.log`.
Helper ใช้ Staging base example และ ignored RevenueCat Test Store overlay
ที่ตรวจ SDK configuration แล้ว ไม่แสดง SDK key; environment เดิมไม่เปลี่ยน
APK `apps/mobile/build/app/outputs/flutter-apk/app-x86_64-debug.apk` มี SHA-256
`7379D489B5F86C24EDCF594FEA3C21CE08EFEA7253723FC14688615B07DE5528`.
Package `com.postdee.postdee_mobile.staging`, versionCode 8011,
versionName `0.1.0-staging`, x86_64; signer
`014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`
ตรงกับรุ่นก่อน. Runtime และ APK hash ไม่เปลี่ยนหลังแก้ test helpers
`adb install -r` สำเร็จโดยไม่ล้างบัญชี; package dump คง firstInstallTime
`2026-10-05 06:30:36`, lastUpdateTime `2026-10-12 03:11:00` เป็น raw device values

Save feedback runtime เป็น 2.2-second timer หลัง verified explicit save;
ตรวจ current form snapshot/owner/generation และ foreground ก่อนโชว์
success ของ operation เก่าจะไม่มาค้างบน form ที่เปลี่ยน; regression proof ด้านล่าง
AI wait text เป็น live region พร้อม indicator ที่ static เมื่อ motion ถูกปิด
ผล caption แสดงครบข้อความจาก response จริงในแอป; widget response เป็น mock fixture
จึงไม่ใช้ widget result ยืนยันคุณภาพหรือความสำเร็จของ actual AI provider

### Targeted และ test-helper follow-up

Feedback tests 9/9 ผ่าน 7s ที่
`D:\Temp\postdee-composer-feedback-green4-20261012.log`.
Pending-AI regressions 3 ไฟล์รวม 65/65 ผ่าน 22s ที่
`D:\Temp\postdee-composer-feedback-pending-regressions-20261012.log`.
Targeted suite ก่อน final guard รวม 187/187 ผ่าน 1m01s ที่
`D:\Temp\postdee-composer-feedback-targeted-final-20261012.log`.
ปรับเฉพาะตัวช่วยรอ AI ใน `uploader_wizard_ai_race_test.dart`,
`uploader_caption_style_test.dart`, `uploader_ai_entitlement_resync_test.dart`
เพราะ indicator จริงวนระหว่าง completer ยังรอ; ไม่ใช้ `pumpAndSettle` รอ spinner
ที่ยังไม่จบ และไม่ลด assertion ของ manual-edit/late AI/style/entitlement guards
ในรอบก่อน rapid-save guard runtime ยัง hash F1E6... และ APK 8011 hash 7379...
ที่แสดงเต็มข้างต้น
ไม่มี rebuild runtime หลัง test-helper changes เหล่านี้

### Native รุ่น 8011: validation ที่ตรวจจริง

Home คงบัญชีเดิม Free 0/3, connected 0/4 และไม่มีโพสต์.
เปิดขั้นแคปชันว่างแล้วกด Next: เห็น inline red error, auto focus และ keyboard
ใส่ตัวทดสอบ `t` ด้วย onscreen keyboard: notice หายตามเงื่อนไข
ลบตัวทดสอบและซ่อน keyboard แล้วเหลือ field ว่าง ปล่อยแอปไว้ที่ขั้นแคปชัน
ไม่ Save, AI generation, upload, post, purchase หรือ OAuth บนบัญชีผู้ใช้
AI wait/full-response และ verified Save success/failure/reset เป็น mock-widget
fixtures ไม่ใช่ actual AI/provider หรือ native local-save success

Actual screenshots:

- `C:\Users\stopp\.codex\visualizations\2026\10\12\01a12dc1-f51c-7ec2-9a95-f89a5069c32c\create-post-caption-focus-8011.png`
- `C:\Users\stopp\.codex\visualizations\2026\10\12\01a12dc1-f51c-7ec2-9a95-f89a5069c32c\create-post-feedback-8011.png`

Current-process relevant fatal/layout/asset/disposed errors ไม่พบ;
`D:\Temp\postdee-composer-feedback-native-errors-20261012.log` มี 0 bytes
ผล native นี้เป็นของรุ่น 8011 ก่อน rapid-save guard ไม่ใช่รุ่นส่งมอบสุดท้าย
ไม่มี push/remote CI/Render deploy หรือ backend/schema/env change ของรอบนี้

### Rapid Save callback guard (verified)

Source F1E6... และ APK 8011 ผ่าน full suite 1,914/1,914 ใน 3m48s แล้ว
ที่ `D:\Temp\postdee-composer-feedback-full-final-20261012.log`.
เป็นผลก่อน guard สุดท้าย ไม่ใช่ final feedback delivery receipt
ตรวจเพิ่มเติมพบว่า callback Save ครั้งที่สองก่อน toolbar rebuild สามารถเข้า
`_saveDraft` แล้ว clear feedback generation ของครั้งแรก แม้ persistence path
จะปฏิเสธงานซ้ำ จึงเสี่ยงไม่แสดง check หลังงานแรกบันทึกสำเร็จจริง

Regression test ก่อนแก้ไม่ผ่านเพราะ check หาย (`+0 -1`) ที่
`D:\Temp\postdee-composer-feedback-double-save-red-20261012.log`.
เพิ่ม early guard
`_formBusy || _isGeneratingCaption` ให้ตรง disabled state ของ toolbar เดิม
เพื่อไม่ให้ callback ที่ไม่ควรเริ่มงานไป clear generation ของ operation ที่กำลังทำ
ไม่มี persistence request/auto-save/provider/API ใหม่ และไม่มี backend/schema/env เปลี่ยน
หลังแก้ final static reviewer ไม่พบ blocker และ feedback 10 + draft/exit/uploader
รวม 86/86 ผ่าน 31s ที่ `D:\Temp\postdee-composer-feedback-save-final-20261012.log`.
Final analyzer ไม่มี issues ใน 12.5s ที่
`D:\Temp\postdee-composer-feedback-analyze-final-20261012.log`.
Source หลัง guard ผ่าน final full suite และ native รุ่น 8012 ตาม receipt ด้านล่าง
ไม่ใช้ผล full/native รุ่น 8011 แทน source ที่เพิ่ม guard นี้

### Final-guard build 4012/installed 8012 และ local delivery

Runtime `uploader_screen.dart` ที่ freeze หลัง guard มี SHA-256
`D531005E8E9C4DA79440AEA27092092F2319D858821638A6D59F8C85718FF547`.
Staging helper build 4012 ผ่าน `assembleDebug` ใน 21.8s ที่
`D:\Temp\postdee-composer-feedback-apk-final-20261012.log`.
APK SHA-256
`F59D8693B4F5BBA3A076C221189F569781F1C116320AC5A820D335767FF2D539`.
Package `com.postdee.postdee_mobile.staging`, versionCode 8012,
versionName `0.1.0-staging`, x86_64 และ signer
`014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb` เดิม
API/Firebase/auth flags/validated ignored RevenueCat Test Store overlay เดิม
ไม่มี SDK key เปิดเผยหรือ environment/dependency เปลี่ยน

`adb install -r` สำเร็จโดยไม่ล้างบัญชี; firstInstallTime คง
`2026-10-05 06:30:36`, lastUpdateTime `2026-10-12 03:21:20` เป็น raw device values.
Native Home คงบัญชีเดิม Free 0/3, connected 0/4 และไม่มีโพสต์
Final full delivery suite ผ่าน 1,915/1,915 ใน 3m47s ที่
`D:\Temp\postdee-composer-feedback-full-delivery-20261012.log`.
Runtime hash D531... และ APK hash F59... ข้างต้นไม่เปลี่ยนหลัง build/ตรวจสุดท้าย

Native รุ่นสุดท้าย 8012 ที่ขั้นแคปชันว่าง: กด Next แล้วเห็น inline red warning,
focused caret และ keyboard. Reset โดยกด progress ขั้นแคปชัน แล้วปล่อย clean
empty step two เปิดไว้ โดยไม่เขียนข้อมูล, Save, AI generation, upload, post,
purchase หรือ OAuth. ไม่อ้าง native Save Draft success/actual AI provider invocation;
AI wait/full-response และ verified Save success/failure/reset/rapid callback ใช้
controlled widget/store fixtures. Narrow/large-text/motion guards ใช้ widgets
แยกจาก native default-font observations

Final filtered fatal/unhandled/layout/asset/disposed error log ไม่มี hits และมี 0 bytes:
`D:\Temp\postdee-composer-feedback-native-errors-delivery-20261012.log`.
Actual final screenshots:

- `C:\Users\stopp\.codex\visualizations\2026\10\12\01a12dc1-f51c-7ec2-9a95-f89a5069c32c\create-post-caption-focus-8012.png`
- `C:\Users\stopp\.codex\visualizations\2026\10\12\01a12dc1-f51c-7ec2-9a95-f89a5069c32c\create-post-feedback-8012.png`

รอบนี้ไม่มี push/remote CI/Render deploy หรือ backend/schema/API/env/dependency
เปลี่ยน จึงไม่มี migration หรือ fresh database/deployment receipt
Staging server เดิมไม่เปลี่ยน. คำสั่งของ source สุดท้ายคือ `flutter.bat test`,
`flutter.bat analyze`, Staging helper `-Command build-apk` พร้อม x64/split ABI/
`--build-number=4012`, `adb install -r` และ `git diff --check`.

### Final combined change inventory

Runtime 1 ไฟล์:
`apps/mobile/lib/features/uploader/uploader_screen.dart`.
New widget-test files 2:

- `apps/mobile/test/uploader_guided_ux_test.dart`
- `apps/mobile/test/uploader_interaction_feedback_test.dart` (final feedback 10 cases)

Existing test files 6:

- `apps/mobile/test/uploader_ai_entitlement_resync_test.dart`
- `apps/mobile/test/uploader_caption_style_test.dart`
- `apps/mobile/test/uploader_screen_test.dart`
- `apps/mobile/test/uploader_wizard_ai_race_test.dart`
- `apps/mobile/test/uploader_wizard_navigation_cues_test.dart`
- `apps/mobile/test/uploader_wizard_test.dart`

Docs 6: `README.md`, `ROADMAP.md`, `API.md`, `ARCHITECTURE.md`,
`apps/mobile/README.md` และ `docs/superpowers/plans/2026-10-12-create-post-guided-ux.md`.
รวม 15 ไฟล์ที่สัมพันธ์โดยตรง; Windows generated-plugin dirt 3 ไฟล์เดิมยังเก็บไว้
และไม่รวมใน feature inventory. Base app fold assertions คงเดิม ไม่มี backend/
API/schema/config/dependency changes หรือ unrelated deletions
