# ลูกเล่นหน้าบัญชีในแอป (2026-10-12)

สถานะ: STAGING DELIVERED — local complete; final frozen source
2B7... targeted 105/105, tests ใหม่29,
full 1,966/1,966 และ analyze no issues ผ่าน. Exact Staging x64 APK4014/8014
build/install/native safe QA ผ่านโดยคงบัญชี/ค่าเดิมและตำแหน่งเลื่อน;
positive business/mutation และ motion/accessibility guards ใช้ fixtures
ผู้ใช้สั่ง push/deploy ทั้ง Account และ Shop แล้วในวันที่2026-10-12;
feature `904a3f89c3601a1fac28eedfaf8781434b19bd49` pushed/CI ผ่านและ Render
`dep-db66eh8473hc73dabfcg` Live 11:53:11 GMT+7; health/ready/post-Live native ผ่าน

## Baseline และขอบเขต

ผู้ใช้ขอ “เพิ่มลูกเล่นในหน้า บัญชีให้หน่อย”. ทำเฉพาะ presentation ของ
`ProfileScreen` ไม่จัดเมนูใหม่ ไม่เพิ่มฟีเจอร์หรือเปลี่ยนสิทธิ์แพ็กเกจ.
Root fetch สด: HEAD `f3b45f2dbb8ce89ff7e19182885d72ca9334d666`,
`origin/main`/merge base `c4e52201a58b556f5f47529027549a2fc16af84c`,
25 ahead/0 behind บน `codex/audit-system-fixes` ที่
`C:\Users\stopp\.codex\worktrees\audit-system-fixes\PostDeeMobile`.
Prior Shop UI motion dirty complete 1,937 tests/analyze/exact x64 installed8013
คงไว้พร้อม docs/source/tests; Windows generated-plugin dirt 3 ไฟล์เดิมแยกจาก
feature. ไม่แก้ canonical `D:\PostDeeMobile` หรือ merge main

อ่าน ProfileScreen, profile draft/tests, shell, shared press feedback และ
finite Shop helper ก่อนแก้. Shell ส่ง `isActive` เฉพาะ Account tab index5
และไม่มี composer route. ProfileScreen มี observer/session listener/request
generations อยู่แล้ว; helper ใหม่เป็นของ Account ไม่เปลี่ยน Shop flow.
Shared press มี minimal disposal guard ที่จำเป็นจาก regression ด้านล่าง

## Approach และ invariants

- ใหม่ `profile_ui_motion.dart`: `AccountUiMotionScope` ใช้ `isActive`,
  lifecycle และ parent ticker. Reduced motion ให้ finite feedback จบ static
  โดยยังรักษา native control ticker; background/hidden/ticker-off หยุด effects
- `AccountUiOriginScope` ให้ Navigator overlays ฟัง origin notifier ล่าสุด
  โดย coalesce update post-frame เมื่อจำเป็น ถอด listener เมื่อ swap/dispose
  และไม่ setState ข้าม subtree ระหว่าง build
- `AccountUiPress` ครอบ header/menu/email/retry/delete entry/setting choices
  และ close/cancel/manage controls โดยไม่เปลี่ยน callbacks, gesture, semantics,
  layout หรือ hit target. Disabled/busy controls ต้องยังไม่เรียก action
- `AccountUiEntrance` fade/lift 220 ms/6 px ที่ stable main ListView key
  `profile-content-motion`: first active/explicit tab return เท่านั้น ไม่มี
  remount/outgoing duplicates/provider-rebuild replay. Setting sheet key
  `profile-setting-motion`. คง static icons ไม่เพิ่ม arrow rotation/check state
- คง account scope stable UID/email fallback และ profile/subscription/
  connection generations: session change invalidate old results. Local draft
  ต้อง UID ตรง หรือ legacy มี matching nonempty email; edit-profile/undo เดิม
- Phone verification ต้อง owner/UID ตรงทั้ง callback และ post-await.
  Email send/refresh คง busy guard, owner check และผล verification จริง;
  motion ไม่ส่งอีเมล/OTPหรืออ้างยืนยันสำเร็จเอง
- คง loading/error/retry/authoritative plan+quota, paywall, external store
  membership และ existing subscription refresh เมื่อ active tab/returnจาก
  paywall/current-route resume. Helper observer ไม่เพิ่ม network fetch
- คง language/theme persistence เมื่อผู้ใช้เลือกจริง, legal/help/security,
  delete confirmation+subscription warning+busy guard, sign out และ callbacks.
  ไม่ทำให้ press/reduced/hidden/disposal bypass confirmation หรือเรียกซ้ำ

ไม่มี backend/API/schema/config/dependency/package rule/provider/ราคาเปลี่ยน,
ไม่มี migration ใหม่. Prior composer CI/Render Live และ Shop tests/APK เป็น
หลักฐานคนละ feature ไม่ใช้แทน Account verification. ณ เริ่ม implementation
ยังไม่มีคำสั่ง push/deploy; ผู้ใช้อนุญาต combined release ภายหลังตามสถานะด้านบน

## Verification ที่ต้องส่งมอบ

| ส่วน | Acceptance | สถานะ |
| --- | --- | --- |
| Regression-first | RED ก่อน implementation แล้ว GREEN บน final source | actual behavior RED 0/16 fail; final targeted 105/105 ผ่านรวมใหม่ 29 cases |
| Press/actions | native semantics/hit target, cancel/disabled/busy/callback once | final targeted 105 ผ่าน รวม held-unmount cancel/up guards |
| Stable entrance | finite 220ms/6px, firstactive/tabreturn, ไม่ replay เมื่อ provider rebuild และไม่ remount/duplicate content | final targeted 105 ผ่าน รวม stable midrange scroll และ paint/logical-hit checks |
| Scope/overlay | reduced/lifecycle/TickerMode/isActive, mid-transition disable, latest origin/listener disposal | final screen19/helper10 ผ่านใน targeted 105 |
| Existing account flows | owner/generation, profile/undo, phone/email, billing/settings/delete/signout guards | targeted105/full1,966 ผ่าน; native read-only account/settings values retained; business mutations ไม่ทำ |
| Full/analyze/build | final source, exact Staging package/env/signer/APK/installedversion ตรง | full1,966 ผ่าน135s/analyze no issues11.7s/x64 build21.9s/installed8014 source/APK/env/signer ตรง; native safe QA ผ่าน |
| Native safe QA | browse/open-close/navigation ไม่แก้ข้อมูลหรือยืนยันคำสั่งจริง | installed8014 edit/connection/paywall browse/choice-close/help/tab-return ผ่าน; ค่าและscroll450คงเดิม |

คงข้อจำกัดผู้ใช้ “ดูและลองกดก่อน ยังไม่บันทึกข้อมูล”: native เลือก Account,
เปิด/ปิด choices/help/legal และ navigation ได้ แต่ไม่ select language/theme,
edit/Save/Done/send email/refresh verification/OTP/purchase/restore/manage
membership/delete confirm/sign out. Positive mutation/business callbacks,
reduced/hidden/large-text และ concurrency paths ใช้ controlled widget/service
fixtures; ไม่อ้างว่า native verification/purchase/delete สำเร็จ. Native actual
safe paths อยู่ใน receipt ด้านล่าง; ไม่เปิด native delete-confirm sheet

Docs sync: `README.md`, `ROADMAP.md`, `API.md`, `ARCHITECTURE.md`,
`apps/mobile/README.md` และแผนนี้. Runtime/test inventory, final source/APK
hashes และ test/build/native command receipts อยู่ด้านล่าง. ณ local receipt
ยังไม่มี external release/CI/deploy ของ Account หรือ Shop; combined release
ได้รับอนุญาตภายหลังและกำลังดำเนินการ

## Preliminary regression receipts (ยังไม่ใช่ final source)

Initial RED fixture ที่ `D:\Temp\postdee-account-motion-red-20261012.log`
พบ duplicate underscore compile error; แก้ fixture ก่อน behavior run ไม่ใช้
compile error นั้นเป็น feature regression proof. Actual behavior RED
0 pass/16 fail ใน 6s ที่
`D:\Temp\postdee-account-motion-red-behavior-20261012.log`.

Expanded Account screen ใหม่ 19 cases/helper 8 cases พร้อม existing profile/
edit/draft tests ได้ 68 pass/3 fail (71 total) ใน 10s ที่
`D:\Temp\postdee-account-motion-targeted-20261012.log`.
ยังไม่ใช้ targeted ระหว่างทำนี้เป็นผลผ่านของ source สุดท้าย

พบ real bug เมื่อกดค้างใน modal แล้ว unmount: gesture cancel ทำให้ shared
`PostDeePressFeedback._release` เรียก setState หลัง dispose. Scope จึงรวม
minimal mounted/dispose guard ใน shared helper พร้อม primitive regression
tests-first; คง native actions/hit target/business callbacks และ motion เดิม.
Candidate runtime 3: `apps/mobile/lib/features/profile/profile_screen.dart`,
ใหม่ `apps/mobile/lib/features/profile/profile_ui_motion.dart` และ
`apps/mobile/lib/features/shared/postdee_press_feedback.dart`.
New test files: `apps/mobile/test/profile_ui_motion_test.dart` และ
`apps/mobile/test/profile_ui_motion_primitives_test.dart`; specific shared guard
cases และ final receipt อยู่ด้านล่าง

อีก 2 failures มาจาก test measurement: paint rect ถูก scale แต่ logical hit
layout ต้องคงเดิม และ scroll ที่ bottom max ถูก clamp ตาม existing loading
status height. ปรับ measurement ที่ wrapper/layout และใช้ stable midrange 200
โดยไม่ลด assertions หรือแก้ runtime loader เพื่อหลบ failure

ก่อน Account patch root ยืนยัน prior 125-file mobile manifest C019... ของ Shop
เดิมยังครบ (`relative mobile path:SHA` เรียงและ join LF). ณ preliminary receipt
นี้ new final source/full/analyze/APK/native ยังรอผล; ไม่ใช้ Shop 1,937/8013 แทน Account

## Final frozen source และ targeted GREEN

Runtime 3 ไฟล์และ new test files 2 freeze แล้ว. Shared press mounted/dispose
guard และ held-unmount cancel/up primitive regression รวม helper10 + screen19
= 29 new cases. Expanded existing profile/edit/draft, Shop22 และ uploader feedback
พร้อม Account cases ผ่าน 105/105 ใน 14s, exit0:
`D:\Temp\postdee-account-motion-targeted-green-20261012.log`.

Second targeted ก่อน GREEN ได้ 104 pass/1 fail (105 total) ใน 17s ที่
`D:\Temp\postdee-account-motion-targeted-final-20261012.log`: test คาด exact
semantics label แต่ native merged label มีข้อความประกอบ. ใช้
`tester.getSemantics(edit)`, `flagsCollection.isButton` และ label contains
ข้อความเดิม โดยยังตรวจ semantics button/label; ไม่ลด assertions.
Header wrapper bounds/getSize, actual paint shrink/original hit edge และ stable
scroll offset200 tests คงไว้. Existing loader/status-height/bottom clamp ไม่เปลี่ยน

Final manifest ของ mobile lib Dart 126 ไฟล์ (`Windows relative mobile path:SHA`
เรียงแล้ว join LF) มี SHA-256:
`2B7E4D05D08AE00099F97288A28C5F2751A248F32EFC70EFAC72CA942B992403`.
นี่เป็น source manifest ไม่ใช่ APK hash. Final full 1,966/1,966 ผ่านใน 135s,
exit0 ที่ `D:\Temp\postdee-account-motion-full-final-20261012.log`.
Final analyze no issues ใน 11.7s, exit0:
`D:\Temp\postdee-account-motion-analyze-final-20261012.log`.
SDK Flutter3.44.1/Dart3.12.1 เดิม. Build/install/native safe QA รุ่นใหม่ผ่าน
ตาม receipt ด้านล่าง; source manifest ไม่เปลี่ยนหลังตรวจสุดท้าย

Existing Staging `/health` และ `/ready` HTTP200 ทั้งคู่จริงที่
`2026-10-12T11:29:53.4107319+07:00`. Native ก่อน patch ยัง installed8013 /
`0.1.0-staging`, account Free0/3/connections0/4. ผลนี้เป็น existing-server/
previous-app baseline ไม่ใช่ Account build/CI/deployment proof. ไม่มี backend/
schema/config change, migration ใหม่ หรือ backend/CI suite ใหม่ในงานนี้

## Exact Staging build/install 4014/8014 และ native safe QA

Staging helper build ผ่าน 21.9s, exit0:
`D:\Temp\postdee-account-motion-build-staging-x64-4014-20261012.log`.
ใช้ `--build-number=4014 --split-per-abi --target-platform=android-x64`.
Delivered `apps/mobile/build/app/outputs/flutter-apk/app-x86_64-debug.apk`
มี SHA-256:
`7E6585C09471DB9CAE3909A068FB13117FF67C67EE1A7E7E27109F7E3B90F640`.
Package `com.postdee.postdee_mobile.staging`, versionCode8014,
versionName `0.1.0-staging`, label `PostDee Staging`, min24/target36,
signer เดิม `014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`.
Final126-file source manifest 2B7... ตรงก่อนและหลัง build

Helper ใช้ base `staging.local.example.json`: Staging API/Firebase Auth true/
local mock false/Staging badge/project `project-798caf7e-85b8-45e3-af7`, พร้อม
validated ignored canonical RevenueCat Test Store overlay เดิม. ไม่เปิดเผย
SDK key ไม่ copy credentials หรือเปลี่ยน config/dependencies

`adb install -r` สำเร็จ ไม่มี downgrade/data clear; เปิด exact MainActivity และ
dumpsys ยืนยัน8014. firstInstallTime คง `2026-10-05 06:30:36`, lastUpdate
`2026-10-12 04:34:20` UTC /11:34:20 GMT+7.
Actual native รุ่นใหม่คง signed-in account/Home Free0/3/connections0/4;
Accountชื่อเดิม/email verified/Free0/3/phone unverified. Edit profile open →
header Back ไม่ edit/Save ตรวจแล้ว. Connections route 0/4 มี CTA เดิมทั้ง4
โดยไม่ OAuth และกลับได้. Paywall เปิดอ่าน Basic current/Test Store catalog
แล้วกลับ โดยไม่
purchase/restore/manage. Settings เลื่อน450: Language sheet Thai checked/
English option แล้วปิด X ไม่เลือก; Theme sheet Light checked/Dark option
แล้วปิด X ไม่เลือก. Help open/back กลับตำแหน่งเดิม และ Home ↔ Account
คืน scroll450/list/settings/account values เดิม. จบที่ Account top พร้อมใช้งาน

ไม่มี typing/Save/settings selection/send email/OTP/refresh verification/
OAuth/manage/purchase/restore/sign out/delete actions. Native delete-confirm
sheet ไม่ได้เปิด; guards ของ destructive/positive callbacks ตรวจด้วย controlled
fixtures. Reduced/background/ticker/large-text/mid-transition/disposal และ
business-positive paths ใช้ fixtures แยกจาก native default-font browse checks

Critical PID10537 logs200 lines ตรวจ
`2026-10-12T11:38:17.8196771+07:00`: Critical0 สำหรับ E/flutter/FATAL/
overflow/Unhandled/EXCEPTION. Paywall เป็น Test Store prices ไม่ใช่ผลตรวจ
production pricing/purchase/entitlement จากการซื้อจริง
Actual new-app raw JPEG originals 390x895 ไม่ปรับภาพ:

- `C:\Users\stopp\.codex\visualizations\2026\10\12\01a12dc1-f51c-7ec2-9a95-f89a5069c32c\account-ui-motion-top-8014.jpg` — 37,366 bytes
- `C:\Users\stopp\.codex\visualizations\2026\10\12\01a12dc1-f51c-7ec2-9a95-f89a5069c32c\account-ui-motion-language-8014.jpg` — 26,806 bytes
- `C:\Users\stopp\.codex\visualizations\2026\10\12\01a12dc1-f51c-7ec2-9a95-f89a5069c32c\account-ui-motion-theme-8014.jpg` — 27,438 bytes

Final source manifest126/SDK/APK/signature/environment ตรงกับ buildและinstalled
8014 ตามด้านบน. `git diff --check` ผ่าน ไม่มี unexpected/deleted config/source
files; previous Shop changes และ Windows dirt3 คงไว้. ไม่มี backend/config/
schema/dependency/package changes, migration ใหม่หรือ backend suite ใหม่;
mobile UI-only ไม่มี backend change ที่ต้อง rollout. ณ local receipt Account/
Shop ยังไม่ได้ commit/push/deploy; คำสั่ง combined release ภายหลังอยู่ด้านล่าง
existing-server health checksไม่ใช่ new deployment proof

## Final Account scope inventory และคำสั่ง

Runtime3:

- `apps/mobile/lib/features/profile/profile_screen.dart`
- ใหม่ `apps/mobile/lib/features/profile/profile_ui_motion.dart`
- `apps/mobile/lib/features/shared/postdee_press_feedback.dart` (minimal mounted/dispose guard)

New tests2:

- `apps/mobile/test/profile_ui_motion_test.dart` — 19 cases
- `apps/mobile/test/profile_ui_motion_primitives_test.dart` — 10 cases

Docs6: `README.md`, `ROADMAP.md`, `API.md`, `ARCHITECTURE.md`,
`apps/mobile/README.md` และแผนนี้. Account scope11ไฟล์; prior Shop scope12
และ Windows generated-plugin dirt3 เป็นงานก่อนหน้า ไม่รวม Account runtime/tests.
Docs5หลักเป็น shared history files ซึ่งเก็บ receipt ของทั้งสองงานครบ

คำสั่ง: `flutter.bat test` new/targeted/full, `flutter.bat analyze`, Staging
helper `-Command build-apk` พร้อม `--build-number=4014 --split-per-abi
--target-platform=android-x64`, `adb install -r`, MainActivity launch และ
`git diff --check`. Local implementation/tests/docs/build/install/native safe QA
เสร็จแล้ว; ณ local receipt ยังไม่มี external release ของงานนี้

## Authorized combined release (2026-10-12, Staging delivered)

ผู้ใช้อนุญาต push/deploy Shop-link และ Account UI motion พร้อมกัน.
Fresh fetch ก่อน release ยืนยัน HEAD
`f3b45f2dbb8ce89ff7e19182885d72ca9334d666`, origin/main/merge base
`c4e52201a58b556f5f47529027549a2fc16af84c`, 25ahead/0behind และ remote
feature ref ตรง baseline. Combined18-file scope ไม่รวม Windows dirt3เดิม
Final126-file runtime manifest ยังเป็น
`2B7E4D05D08AE00099F97288A28C5F2751A248F32EFC70EFAC72CA942B992403`.
คง source/APK8014/native/fixtures receipts ข้างต้น. Combined18-file feature
`904a3f89c3601a1fac28eedfaf8781434b19bd49` commit/push ไป
`origin/codex/audit-system-fixes` สำเร็จ; ไม่ merge main, Windows dirt3ไม่รวม

Exact-source CI [38205149761](https://github.com/NOI56/PostDeeMobile/actions/runs/38205149761)
created `2026-10-12 04:46:26Z`, completed success `04:50:27Z` ทั้งสอง jobs.
Backend 1,781 tests/109 files, build, Prisma schema validation, shared catalog
generator check/tests และ high-threshold production audit ผ่าน; ยังมี4moderate
findings เดิม ไม่ใช่ audit0. Mobile analyze no issues10.7s และ1,966 testsผ่านจบ
`04:50:22Z`. Checkout/head SHA ทั้งสองงานตรง full feature SHA ข้างต้น.
`build_staging_apk=false` ข้าม CI APK build/uploadโดยตั้งใจ; local installed8014
source126 manifest2B7.../APK7E6585... เดิมคงไว้ ไม่มี reinstall หรือ artifactใหม่

Render service `postdee-api-staging` / `srv-d9bb72ojs32c739osa5g` ใช้ specific
commit exactSHA:
[dep-db66eh8473hc73dabfcg](https://dashboard.render.com/web/srv-d9bb72ojs32c739osa5g/deploys/dep-db66eh8473hc73dabfcg).
`Deploy succeeded | Live`, duration1m55s: start11:51:17 GMT+7,
checkout11:51:22, build successful11:51:57, Prisma16existing migrations/
`No pending migrations to apply`11:52:18, startup11:53:08 port10000 และ
service Live11:53:11. Publishing mode/publisher `disabled`, queue `memory`
คงเดิม; ไม่มี API/schema/config/dependency หรือ migration ใหม่

`/health` และ `/ready` HTTP200 ทั้งคู่จริงที่
`2026-10-12T11:53:49.0454574+07:00`; health statusok, readiness databaseok/queueok.
Source identity มาจาก exact CI/Render checkout ไม่ใช่ health response
Post-Live native Home → Shop → Account safe navigation ผ่าน: AccountFree0/3,
connected0/4; Shopnoikub published/savedclean2/20 คงสองลิงก์ enabledเดิม/
confirmedURL. ไม่มี Save/Publish/purchase/OAuth/delete/signout.
PID10537 recent206lines Critical0 ที่ `2026-10-12T11:54:49.0090913+07:00`.
Positive business/mutation และ motion/accessibility pathsยังเป็นfixturesตามขอบเขต

Raw Render proof JPEG:
`C:\Users\stopp\.codex\visualizations\2026\10\12\01a12dc1-f51c-7ec2-9a95-f89a5069c32c\release-live-904a3f8.jpg`.
Receipt follow-up จะเป็น docs-only ไม่มี runtime delta; ไม่ใช้ SHA เอกสารที่ยัง
ไม่สร้างมาอ้างเป็น deployed feature source
