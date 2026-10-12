# ปฏิทิน: รายการกระชับและสร้างโพสต์ตามวันที่เลือก (2026-10-11)

สถานะปัจจุบัน 2026-10-12: ผู้ใช้อนุญาต push/deploy Staging แล้ว feature SHA
`3368f4d541daafb6eaac2e2af5a93800d27831c4` pushed และ exact-source CI
`38187776818` ผ่าน Flutter 1,883 tests/analyze และ Backend checks.
แพตช์ clock follow-up ผ่าน targeted 66 และ local analyze; APK 4007/8007
build/install ผ่านโดยเก็บ data/session และ post-deploy native Home cold launch ผ่าน.
Render deploy `dep-db62jdvlot8c738l37q0` ของ exact SHA นี้ Live แล้ว
07:30:34 GMT+7; migrations/health/ready ผ่านตาม receipt ด้านล่าง.
Full native Calendar/composer
รุ่น 8006 ด้านล่างเป็นผลก่อน clock follow-up; positive queue/partial/mutations
ใช้ fixtures เพราะบัญชีจริงไม่มีโพสต์ ไม่ใช้ผล Home แทนผล Calendar

## ฐานที่ตรวจและภาพอ้างอิง

Worktree `C:\Users\stopp\.codex\worktrees\audit-system-fixes\PostDeeMobile`,
branch `codex/audit-system-fixes`. ณ เริ่มรอบ HEAD คือ
`ab56adecfdd250cce80f50ccabee601d9915fbda`, remote-main ref `c4e5220`,
18 ahead / 0 behind ตาม refs ที่ตรวจ รักษา Windows generated dirt เดิมไว้
งาน Home/runtime และ receipt ก่อนหน้านี้คงอยู่ ไม่ย้อนกลับไฟล์เก่า

ตรวจ `calendar_screen.dart`, shell/uploader, `post_schedule_policy.dart`,
`listScheduledPosts()` และแผน scheduling safety เดิมก่อนเขียนแผนนี้
API ที่ใช้อยู่คือ `GET /posts?scheduled=true`; ไม่มี `/posts/scheduled` ใหม่
Calendar เดิมเป็นเดือน มี selected-day/platform filter และ queue actions;
shell callback เดิมสร้างโพสต์โดยไม่ส่งวันที่เข้า composer; source ใหม่เพิ่ม handoff
silent refresh เดิมซ่อน failure เมื่อมีข้อมูล; source ใหม่คงเนื้อหาและแสดง error

อ้างอิง standalone preview:
`C:\Users\stopp\.codex\visualizations\2026\10\09\01a11eef-cfc7-72c1-9a62-293b6cc057e0\calendar-preview.html`.
แบบที่เลือกคือ `data-design="list"` (“รายการกระชับ”); แบบการ์ดแยกโพสต์
เป็นตัวเลือกที่ไม่ได้เลือก ข้อมูลแปดโพสต์/เวลาอัปเดต/รอจำลองหนึ่งวินาที/
เวลา 20:30 ในตัวอย่างเป็นข้อมูล demo ไม่ใช่ข้อมูลหรือเวลาบังคับของลูกค้า

## ขอบเขตที่ยอมรับและต้องรักษา

- มุมมองเริ่มต้นเป็นสัปดาห์ ใช้วันจริงเป็นฐาน และรักษา auto-select เดิม:
  ถ้าวันนี้ไม่มีรายการ เลือกรายการแรกตั้งแต่วันนี้ในเดือนปัจจุบันเมื่อยังไม่เคย
  เลือกวัน ไม่ใช่บังคับ Today ทุกครั้ง refresh. สลับสัปดาห์/เดือน เลื่อนช่วง
  ก่อน/หลังได้; “วันนี้” กลับวันจริงโดยไม่ใช้วันที่ demo สัปดาห์เริ่มจันทร์
- แสดงจำนวนโพสต์ของแต่ละวันตามข้อมูลที่อ่านและ filter ปัจจุบัน นับโพสต์
  หนึ่งครั้งแม้เลือกหลายปลายทาง ไม่ใช้จำนวนปลายทางเป็นจำนวนโพสต์
- Filter “ทั้งหมด” และสี่ปลายทางที่รองรับจริง ไม่เพิ่ม Shopee/Lazada routes
- รายการวันเลือกเป็นแถวกระชับ: เวลา แคปชัน ช่องทาง และสถานะจริง ใช้ helper
  ผลส่งเดิมเพื่อรักษา partial/unknown และเปิด terminal detail แบบ read-only
- วันที่ผ่านมาดูได้ แต่ปุ่มสร้างตามวันนั้นต้องไม่ส่ง schedule ย้อนหลัง
  วันปัจจุบัน/อนาคตส่ง local date-only เข้า composer เดิม ให้ผู้ใช้เลือกคลิป/
  เวลาและตรวจทานต่อ ไม่ auto-save/submit และไม่ทับ schedule ของร่างที่ restore
- เวลาแสดง/group ใช้ local time; `PUBLISHED`/`PARTIAL_PUBLISHED` ใช้
  `publishedAt` จริงก่อน fallback `scheduledAt` เช่นระบบเดิม ส่ง schedule UTC
  ผ่าน conversion เดิมหลังมีทั้งวันที่และเวลา
- Future-only, Starter 14 วัน/Pro 30 วัน, latest subscription และ publishing
  readiness/kill switch เดิมยังบังคับ ไม่มีการขยายสิทธิ์เพราะเลือกวันใน Calendar
- Queue reschedule/cancel, mutation generation และ completed-result routes
  คงเดิม ไม่มี provider/API/schema/dependency/configuration หรือกฎแพ็กเกจใหม่
- Refresh คงข้อมูลที่ยืนยันแล้วรวม known-empty และ selected date/view/filter;
  failure บอก error/retry ไม่อ้างอ่านสำเร็จ ไม่รับผลเก่าหลัง owner เปลี่ยนหรือ
  หลัง cancel/reschedule. Poll QUEUED/PUBLISHING ทุก 30 วินาทีเฉพาะ visible/
  foreground; inactive/background หยุด timer

## จุดเชื่อมและ regression ที่ต้องตรวจ

| จุด | เกณฑ์ |
| --- | --- |
| วัน/ช่วง | Today, สัปดาห์ข้ามเดือน/ปี, เดือนสั้น/วันอธิกสุรทิน และ selection อยู่ในช่วงที่แสดง |
| จำนวน/filters | ตรงรายการจริง ไม่ duplicate multi-platform และ empty/error แยกกัน |
| สถานะ/เวลา | published time, partial, unknown, publishing non-interactive และ queue-only actions คงเดิม |
| Date handoff | Calendar → shell → composer รับวันเดียวกันใน local date; ไม่ทับ draft และไม่ bypass future/plan checks |
| Refresh/owner | stale content/retry, coalesced reads, late owner/mutation results และ polling lifecycle |
| Layout/accessibility | ไทย 390/320 logical px, large text, wrap/scroll, selected semantics, touch target และ reduced motion; ระบุ scale ของหลักฐานจริงแยกกัน |

ไฟล์ runtime ที่เกี่ยวข้องคือ Calendar, shell และ uploader; regression ใช้
Calendar/shell/uploader tests เดิมและ tests สำหรับ behavior ใหม่ เอกสารที่ sync
คือ README/API/ARCHITECTURE/ROADMAP, mobile README และแผนนี้

## Verification และ fidelity ledger (Staging delivered; native ตามขอบเขต)

| การตรวจ | สถานะปัจจุบัน |
| --- | --- |
| Targeted Calendar/date-handoff regressions | Calendar 45 เดิม; clock follow-up 66 ผ่าน (date-handoff 8, uploader 57, app schedule panel 1) |
| Full Flutter suite และ analyze | exact-source CI 1,883 tests ผ่าน/analyze no issues 12.9s; local final analyze no issues 14.6s |
| Diff/backend contract | Read-only diff ใน API/pubspec/lock ว่าง; ไม่มี schema/environment/provider change |
| Actual Flutter renders | 1/1 ผ่าน 4s; week/month ที่ 390/text 1.0 และ 320/text 1.8 ดูแล้วไม่ overflow; เป็น fixture data |
| Staging exact-source APK/environment | helper build 4007/installed 8007, Gradle 144.2s; package/environment/signature ตาม receipt ใหม่ด้านล่าง |
| Native install/package | รุ่น 8007 install-r สำเร็จ, signature/firstInstallTime เดิม, shared_prefs XML fingerprints diff 0, session คืนได้และ post-deploy Home cold launch ผ่าน |
| Native Calendar/composer | receipt รุ่น 8006 ก่อน clock follow-up: week/month/date handoff, Free guard, retained refresh และ past-date/Today ผ่านโดยไม่ Save; ไม่อ้างว่าทำ interactive Calendar ซ้ำบน 8007 |
| Push/deploy/CI | authorized/pushed SHA 3368f4d; CI 38187776818 ผ่านทั้งสอง jobs; exact-source Render dep-db62jdvlot8c738l37q0 Live, 16 migrations/no pending และ health/ready HTTP 200 |

### Prior local verification และ APK receipt (2026-10-11, รุ่น 8006)

Full `flutter test --concurrency=2 --reporter compact` ผ่าน 1,882/1,882 ใน
2m40s; full `flutter analyze` no issues 13.1s. Logs:
`D:\Temp\postdee-calendar-full-suite-20261011.log` และ
`D:\Temp\postdee-calendar-analyze-20261011.log`.
Targeted Calendar 45/45 และ uploader date-handoff 7/7 ผ่าน รวม midnight
ที่ไม่มีเวลาภายในวันและ error ต้องเลื่อนมาให้เห็น โดยไม่ activate schedule

Actual Calendar fixture capture 1/1 ผ่าน 4s; ตรวจ week/month ที่ logical width
390/text scale 1.0 และ 320/text scale 1.8 แล้วไม่มี overflow. ภาพอยู่ใน
`D:\Temp\postdee-calendar-ux-20261011`: `calendar-week-390.png`,
`calendar-month-390.png`, `calendar-week-320.png`, `calendar-month-320.png`.
Capture log: `D:\Temp\postdee-calendar-visual-qa-20261011.log`.
ข้อมูลตัวอย่างแยกจากบัญชีจริง; text-scale-2 controller regressions ที่
360/393 ผ่านใน full suite ไม่ใช่ claim ว่า render 320 ใช้ scale 2

| Fidelity จุดตรวจ | หลักฐานที่ยืนยันแล้ว |
| --- | --- |
| Hierarchy/palette | compact rows, week/month/Today, ขาว/มิ้นต์/เขียว เทียบ selected list preview |
| Period/selection | สัปดาห์เริ่มจันทร์, month grid และ day selected; auto-select เดิมกับ Today มี regressions |
| Counts/filter | จำนวน post หนึ่งครั้งต่อวันและ all/four-logo filters แสดงจาก fixture/ทดสอบ |
| Row/status | เวลาอยู่ซ้าย, caption/status/channels กระชับ; partial/unknown/published time ผ่าน regressions |
| Narrow/Thai | ภาพ 390/1.0 และ 320/1.8 ไม่มี overflow; filter wrap/short count เป็น adaptation เพื่อให้อ่านได้ |
| Refresh/guards | known-empty/stale content + error/retry, owner/mutation/polling cases ผ่าน tests; native known-empty คงวันที่ 13/filter TikTok หลัง refresh |
| Composer handoff | native แสดงวัน 13 แต่เลือกโพสต์เลยอยู่, Free ถูกปิดตั้งเวลา; draft schedule เดิม/future/paid-policy ผ่าน tests |

Staging helper build number 4006 สร้าง split x86_64 debug APK ใน 21.1s,
package `com.postdee.postdee_mobile.staging`, installed version code 8006,
version name `0.1.0-staging`, min SDK 24/target SDK 36. SHA-256:
`E5FD9C795E24817683E484244B0586046919E65F7E63CADC0D81B1A1282B981E`.
Signature ตรงกับรุ่น 8005 ที่ติดตั้งเดิม certificate SHA-256
`014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`.
Build log: `D:\Temp\postdee-calendar-staging-build-20261011.log`.
ตรวจ API `https://postdee-api-staging.onrender.com`, Firebase project
`project-798caf7e-85b8-45e3-af7`, auth true/local mock false และ Test Store
overlay ผ่านโดยไม่พิมพ์ค่า key ไม่มี environment/flag เปลี่ยน

การติดตั้งครั้งแรกติด insufficient storage; คืนพื้นที่เฉพาะ runtime/compiler
caches ด้วย `pm trim-caches`/`delete-dexopt` และ reboot ปล่อยไฟล์ที่เปิดอยู่
จนมีพื้นที่ประมาณ 1 GB โดยไม่ล้าง app data/shared preferences หรือ uninstall.
`adb install -r` สำเร็จรุ่น 8006; package/signature ตรง และ firstInstallTime
2026-10-05 คงเดิม เปิดแอปครั้งแรกหลัง install แสดง login; ผู้ใช้ล็อกอินให้แล้ว
จึงตรวจ Calendar/composer ต่อ ขนาดข้อมูล sharedprefs/files/databases/
app_flutter ก่อนและหลัง install คงเดิม ไม่สมมติสาเหตุที่ session ไม่ restore
มี FCM registration failure ตอน startup แรก แยกจาก scoped error log ของ
Calendar หลังล็อกอินด้านล่าง ไม่อ้างว่าผล Calendar ยืนยัน push notification

### Native receipt หลังผู้ใช้ล็อกอิน (รุ่น 8006)

เครื่อง `emulator-5556` ใช้ package/version/environment ตรง APK ข้างต้น
Home แสดง Free เหลือ 0/3 และไม่มีร่าง/โพสต์ ไม่สร้างข้อมูลลูกค้าเพื่อเติม QA

| ขั้นตอนจริง | ผล |
| --- | --- |
| Week/month | เริ่มสัปดาห์วันที่ 11 ต.ค.; เดือน selected=true และมีวัน 1–31 |
| วันเลือก | เลือก 13 ต.ค. แล้วกลับ week แสดง 12–18 และยังเลือก 13 |
| Filter | TikTok selected=true; empty copy ระบุว่าไม่มีโพสต์สำหรับช่องทางนี้ |
| Create/date handoff | เปิด composer แล้ว review ขั้น 4 แสดง “วันที่จากปฏิทิน: 13 ต.ค. 2026”; “โพสต์เลย” ยัง selected ไม่มี implicit schedule |
| Free guard | กดตั้งเวลาแล้วแสดงต้องใช้ Starter 199/Pro 299; ไม่ activate/persist schedule |
| กลับ/refresh | ปิด composer ว่างโดยไม่ Save/discard prompt; กลับ Calendar คง 13/TikTok และ refresh known-empty ยังรักษาค่าเดิม |
| Past/Today | Today+All แล้วเลือก 7 ต.ค.: dated-create header disabled มี “กลับไปวันนี้”; กดแล้วกลับ 11/week/All |

ภาพใน `D:\Temp\postdee-calendar-ux-20261011`: `calendar-native-final.png`,
`calendar-native-month.png`, `calendar-native-date-handoff.png`,
`calendar-native-free-guard.png` และ `calendar-native-week.png`.
XML อยู่ใน `D:\Temp`: `postdee-calendar-native-{week,month,selected,filter,review,free-guard,return,refresh,past,final}.xml`.
PID-restricted Flutter/AndroidRuntime error log ว่าง:
`D:\Temp\postdee-calendar-native-error-check-20261011.log`.
ไม่มี Save/Publish/OAuth connect/ซื้อแพ็กเกจโดย agent. ทุก native Calendar row
ของบัญชีนี้เป็น empty state; positive queue/partial/reschedule/cancel และ owner
race ใช้ fixture/regression tests ไม่อ้างเป็น native connected-account mutation

ผลชุดนี้ต้องแยกจาก Home CI `38125004499`/Staging feature `ce89a0e` ซึ่งเป็น
receipt ของ runtime ก่อน Calendar ห้ามเติม counts/SHA/Live หรืออ้าง native
positive queue/mutation โดยยังไม่ตรวจด้วยข้อมูลจริงหรือ fixture ที่ระบุชัด

## Release validation follow-up (2026-10-12, Staging delivered)

ผู้ใช้อนุญาต push/deploy Staging แล้วในวันที่ 12 ต.ค.; receipt รุ่น 8006
ด้านบนเป็นผลก่อน clock follow-up แยกจาก CI/build/native startup รอบใหม่

CI `38187274274` ของ Calendar SHA
`591ddb721a014222e92ba6f836af0350c77ef3b8` ผ่าน Flutter 1,878 tests และไม่ผ่าน
4 tests ใน `uploader_calendar_schedule_test.dart`: fixture ตรึง `now` เป็น
11 ต.ค. แต่ `_SchedulePanel` อ่านวันที่เครื่องจริงซึ่งเป็น 12 ต.ค. จึงแสดง
“วันนี้/พรุ่งนี้” ไม่ตรงกับวันที่จำลองของ policy ทั้งสี่ assertions ยังรักษาไว้
เพื่อยืนยันวันและเวลาที่เลือก ไม่ลดเกณฑ์ทดสอบให้ผ่าน

ขอบเขตแพตช์คือส่ง callback `widget.now` เข้า `_SchedulePanel` และ normalize
เวลาที่อ่านเป็น local ให้ตรงกับ date seed/policy เดิม โดยค่า default ของ
`UploaderScreen.now` ยังเป็น `DateTime.now`. ไม่มี API/schema/provider/
environment หรือกฎแพ็กเกจเปลี่ยน เพิ่ม UTC-clock regression ที่ derive local
day/time โดยไม่สมมติ timezone ไทย และรักษา assertions เดิมครบ

### Exact-source CI และ APK/native startup receipt

SHA `3368f4d541daafb6eaac2e2af5a93800d27831c4` pushed ไป
`origin/codex/audit-system-fixes`. CI `38187776818` ผ่าน Backend API และ
Flutter Mobile; head SHA และ checkout logs ของทั้งสอง jobs ตรง full SHA นี้
Flutter 1,883 tests ผ่าน/analyze no issues 12.9s. Backend 1,781 tests/109 files,
generator 22/22, build, Prisma validate และ production dependency audit ที่
threshold high ผ่าน โดยยังมี 4 moderate/0 high findings ไม่ใช่ zero findings
Targeted local follow-up 66 ผ่าน; final local analyze no issues 14.6s
CI completed 2026-10-12 00:27:09 UTC / 07:27:09 GMT+7. Optional APK build/upload
ใน CI ถูก skip ตามที่เลือก; APK signed/Test Store รุ่น 8007 เป็น local artifact
ที่สร้างและติดตั้งจริง ไม่ใช่ CI APK

Official Staging helper build 4007 สร้าง split x86_64 debug APK; Gradle 144.2s,
127,583,210 bytes; local builder ใช้ Flutter 3.44.1/Dart 3.12.1.
Package `com.postdee.postdee_mobile.staging`, installed
versionCode 8007, min SDK 24/target SDK 36. SHA-256:
`F41156646D3204B0329BCA1B7A7483C4B28DE96CCEB0F8213FECF3C315A942B6`.
Certificate SHA-256 ตรงกับรุ่นเดิม
`014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`.
API Staging/Firebase project `project-798caf7e-85b8-45e3-af7`, auth/local-mock
flags และ validated RevenueCat Test Store overlay คงเดิม ไม่พิมพ์ SDK key

`adb install -r` สำเร็จ; before/after `shared_prefs/*.xml` fingerprints diff 0 และ
firstInstallTime 2026-10-05 คงเดิม. Session คืนได้และ Home อ่านข้อมูลจริง Free
เหลือ 0/3, ไม่มีโพสต์, social 0/4, ลิงก์ร้านเผยแพร่แล้ว. Current-PID scoped
error log 0 bytes. การตรวจรุ่น 8007 รอบนี้เป็น startup/Home smoke เท่านั้น
ไม่ได้กด interactive Calendar/composer ซ้ำ และไม่แทน receipt รุ่น 8006

### Exact-source Render receipt

Render specific-commit deploy `dep-db62jdvlot8c738l37q0` ใช้ full SHA
`3368f4d541daafb6eaac2e2af5a93800d27831c4` ตรง CI; ตรวจ identity จาก
Render checkout/UI ไม่ใช่ response ของ health endpoint. Page/start timestamp
2026-10-12 07:28:39 GMT+7; Live/Deploy succeeded 07:30:34 GMT+7 ใช้ 1m55s
Build สำเร็จ; pre-deploy 07:29:41 พบ 16 existing migrations และ
“No pending migrations to apply” ไม่มี migration ใหม่ใน Calendar

ตรวจ 07:31:15 GMT+7: `/health` และ `/ready` HTTP 200/status ok. Startup
07:30:28 ยืนยัน social-publishing mode/publisher `disabled` และ
`PUBLISH_QUEUE=memory` คงเดิม ผลนี้ยืนยัน service/database/queue readiness
ตาม endpoint ไม่ใช่การส่งโพสต์โซเชียลจริง. Screenshot:
`D:\Temp\postdee-calendar-release-render-live-20261012.png`.

Fresh fetch ก่อนส่งมอบยังพบ `main`/merge base `c4e5220`, feature 20 ahead /
0 behind; runtime API/schema/native-platform/configuration diff เทียบ Live
ก่อนหน้า `ce89a0e` ว่าง ยกเว้น mobile feature ที่ระบุ ไม่ merge main หรือ
เปลี่ยน Production และรักษา Windows generated dirt เดิมสามไฟล์ไว้

### Post-deploy native smoke (รุ่น 8007)

หลัง Render Live force-stop/start รุ่น 8007 เดิม แล้ว cold launch สำเร็จ 7.4s;
auth session คืนและ Home อ่าน Free เหลือ 0/3, social 0/4, ไม่มีโพสต์ และ
ลิงก์ร้านเผยแพร่แล้ว. UI XML:
`D:\Temp\postdee-calendar-release-native-live-20261012.xml`.
Current-PID Flutter/AndroidRuntime error log 0 bytes:
`D:\Temp\postdee-calendar-release-native-live-errors-20261012.log`.
ไม่มี interactive Calendar/composer ซ้ำหรือ Save/Publish/OAuth/ซื้อแพ็กเกจ
ในการตรวจรอบนี้; full Calendar native รุ่น 8006 และ positive fixtures ยังคง
เป็น receipt แยกตามขอบเขตข้างต้น การเทียบ fingerprints ครอบคลุมเฉพาะ
shared preferences XML ไม่ใช่ hash ของ files directory

## Motion follow-up (2026-10-12, local)

ผู้ใช้ขอให้หน้าปฏิทินมีลูกเล่นเหมือนหน้าหลัก รอบนี้เพิ่มเฉพาะ mobile presentation
ต่อจาก HEAD `78ee597183b8b27e3954f68023ac85ee73b49da2` บน
`codex/audit-system-fixes`; verified `origin/main` และ merge base ยังเป็น
`c4e52201a58b556f5f47529027549a2fc16af84c` ก่อนแก้ 21 ahead / 0 behind
รักษา generated Windows dirt เดิมสามไฟล์ไว้

### ขอบเขต runtime

- ใช้ `PostDeePressFeedback` เดิมจาก Home: ย่อ .97 ขณะกดแล้วคืนขนาด
  คง gesture/semantics/hit target ของ control เดิม ทั้งเลือกวัน ปุ่มช่วงเวลา
  Today, week/month/platform filter, refresh, create และแถวโพสต์ที่กดได้
- สีวันที่เลือกและ view/platform filters เปลี่ยนใน 160 ms; grid ปรับความสูง
  week/month ใน 220 ms โดยคง initial week view และ selection เดิม
- รายการปัจจุบันค่อยปรากฏ/เลื่อนขึ้น 8 px ใน 180 ms โดย key รวม owner
  generation/day/platform/initial-load state และ unmount รายการก่อนหน้าทันที
  ไม่เก็บ outgoing post controls ระหว่าง transition
- Initial load ใช้ `PostDeeSkeleton` เดิม พร้อม accessible loading label;
  silent refresh คงข้อมูลที่ยืนยันแล้วและวันที่/filter เดิม
- Reduced motion, inactive tab, app background และ disabled `TickerMode`
  หยุด effects; grid ใช้ static layout แทน `AnimatedSize` เมื่อปิด animation
  เพื่อหลีกเลี่ยง Flutter 3.44 layout assertion ตอนเปลี่ยนความสูง
  owner/request/mutation guards และ visible-only polling คงเดิม

ไม่เปลี่ยน API/backend/schema/provider/plan rules, date handoff หรือ publishing
kill switch และไม่เพิ่ม migration/environment setting/dependency. Runtime scope
คือ `apps/mobile/lib/features/calendar/calendar_screen.dart`; ตรวจและ sync
README, ROADMAP, ARCHITECTURE, API และ mobile README เฉพาะเรื่องนี้

### ผลตรวจและการส่งมอบรอบ motion

Targeted regressions ผ่าน 119/119 ใน 26s: motion ใหม่ 8, Calendar เดิม 45,
shell 53, date handoff 8 และ Home shared primitives 5. Log:
`D:\Temp\postdee-calendar-motion-targeted-final-20261012.log`.
Runtime source `calendar_screen.dart` SHA-256 ที่ freeze สำหรับตรวจ:
`4D1281880605AB18A844F9A70BEC8EE1EA6678068ABB7BCB66D068BD588C7CCA`.
Diff check ผ่าน ไม่มี tracked deletion; runtime API, pubspec/lock, Android,
shared widgets, shell และ uploader ไม่เปลี่ยนจาก HEAD ที่ระบุ

Full Flutter suite ของ frozen source ผ่าน 1,891/1,891 ใน 3m19s (exit 0);
`flutter analyze` ไม่พบปัญหาใน 17.3s (exit 0). Logs:
`D:\Temp\postdee-calendar-motion-full-20261012.log` และ
`D:\Temp\postdee-calendar-motion-analyze-final-20261012.log`.

Staging helper build 4008 ผ่าน Gradle `assembleDebug` 18.3s. APK
`apps/mobile/build/app/outputs/flutter-apk/app-x86_64-debug.apk` ขนาด
127,586,142 bytes มี SHA-256
`32EEC7945BC0736AF2D153419EC39162A22815C5EAFFBF70C8EA1F5B2CAFBF28`.
Package `com.postdee.postdee_mobile.staging`, installed versionCode 8008,
versionName `0.1.0-staging`, min SDK 24/target SDK 36, x86_64.
Signer SHA-256
`014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`
ตรงกับรุ่น 8007; frozen runtime hash ตรงก่อนติดตั้ง. Build log:
`D:\Temp\postdee-calendar-motion-build-20261012.log`.

Environment ใช้ API `https://postdee-api-staging.onrender.com` และ Firebase
`project-798caf7e-85b8-45e3-af7`, Firebase auth เปิด/local mock ปิด,
validated RevenueCat Test Store overlay และ feature flags เดิม.
`adb install -r` สำเร็จ, firstInstallTime เดิม 2026-10-05; cold launch 5.092s.
Visible native Home คืนบัญชี A, Free 0/3, social 0/4 และข้อมูลไม่มีโพสต์

Native รุ่น 8008 ตรวจผ่านบนเครื่องจำลองที่มองเห็น โดยไม่ Save/Publish/OAuth
หรือซื้อแพ็กเกจ:

- Calendar เริ่ม week วันที่ 12; เลือก 13 แล้ว footer แสดงวันที่เดียวกัน
- สลับ month เห็น 1–31 และยังเลือก 13; กลับ week ยังรักษา 13
- เลือก TikTok แสดง empty copy ของช่องทางนั้น; refresh แสดงกำลังอัปเดต
  พร้อมคงข้อมูลเดิม แล้วเวลาอัปเดต 00:51 ยังรักษา 13/TikTok
- Today คืนวันที่ 12 โดยคง TikTok; All คืนตัวกรองทั้งหมด ปล่อยแอปเปิดไว้ที่
  Calendar week วันที่ 12/All

Current-PID Flutter/AndroidRuntime error log 0 bytes:
`D:\Temp\postdee-calendar-motion-native-errors-20261012.log`.
บัญชีจริงไม่มีโพสต์ จึงตรวจ native empty path; positive current-post actions,
reduced motion/background guards และ intermediate shrink ใช้ fixtures.
ไม่ใช้ tool highlight เป็นหลักฐานลูกเล่นของแอป

รุ่น 8007, CI `38187776818` และ Render Live ข้างต้นเป็น receipt ก่อน motion
follow-up จึงไม่ใช้ยืนยัน effects ใหม่นี้ ไม่มี API/schema/migration ใหม่และ
ไม่ได้รัน backend/health/Render/CI ใหม่รอบนี้ เพราะ runtime backend ไม่เปลี่ยน
รอบนี้ตรวจและติดตั้ง local รุ่น 8008 แล้ว ยังไม่ push/deploy
