# ลูกเล่น UI ลิงก์ร้านในแอป (2026-10-12)

สถานะ: AUTHORIZED RELEASE IN PROGRESS — local Shop complete; final SDK source
C019... ผ่าน tests ใหม่ 22/22,
full 1,937/1,937 และ analyze no issues. Exact Staging x64 APK 4013/8013 build/
install/native safe QA ผ่านโดยคงบัญชีและข้อมูลร้านเดิม; mutation paths ใช้ fixtures.
519/519 และ full 1,937/1,937 ของ source 7CDD... เป็นประวัติก่อน SDK correction.
ผู้ใช้สั่ง push/deploy ทั้ง Shop และ Account แล้วในวันที่2026-10-12;
exact feature commit/CI/Render Live ยังรอ receipt ไม่ใช้ local proof แทนผล deploy

## Baseline และขอบเขต

ผู้ใช้อนุญาตให้เพิ่มลูกเล่นหน้าลิงก์ร้านในแอปตามแนว Home/Calendar/สร้างโพสต์.
ทำเฉพาะ mobile manager และ theme/appearance controls ไม่เปลี่ยนหน้าเว็บที่แชร์
หรือ content motion ที่ผู้ใช้เลือกไว้. ณ เริ่ม implementation authorization
push/deploy ของ composer ก่อนหน้าเป็นคนละ release และยังไม่มีคำสั่ง release
ใหม่นี้; ผู้ใช้อนุญาต combined Shop/Account release ภายหลังตามสถานะด้านบน

Root fetch สด: `HEAD=f3b45f2dbb8ce89ff7e19182885d72ca9334d666`,
`origin/main`/merge base `c4e52201a58b556f5f47529027549a2fc16af84c`,
25 ahead / 0 behind บน `codex/audit-system-fixes` ใน
`C:\Users\stopp\.codex\worktrees\audit-system-fixes\PostDeeMobile`.
Windows generated-plugin dirt 3 ไฟล์เดิมคงไว้ ไม่รวม feature; ไม่แก้ canonical
worktree `D:\PostDeeMobile` หรือ merge main

ตรวจ `link_in_bio_screen.dart`, theme picker, appearance editor, preview/motion,
draft store และ tests เดิมก่อนแก้. `_markEdited()` เพิ่ม edit version และส่ง
`_persistDraft` เข้า serialized owner-scoped queue; image protection มาก่อน
disk persistence. **ระบบมี local autosave อยู่แล้ว** ตาม audit revision.
ข้อความ explicit-only ในแผน link-manager ปี 2026-10-06 เป็นประวัติก่อน audit
และไม่ใช้เป็นข้อสรุปของ current flow

## การเปลี่ยน UI และสิ่งที่คงไว้

- เพิ่ม press feedback ช่วงสั้นให้ manager actions, เพิ่ม/แก้ลิงก์, Save,
  copy/open, review และ theme controls โดยคง gesture/semantics/hit targets
  และ disabled/busy guards ของปุ่มเดิม. ไม่ใช้แอนิเมชันแทนผล Save/Publish จริง
- เปลี่ยนส่วนข้อมูลร้าน/manager/ตกแต่ง/review แบบ current-only fade/lift
  220 ms/6 px: outgoing forms/actions ถูกถอดทันที ไม่มี GlobalKey หรือ
  controller สองชุด. เปลี่ยน category ใน theme picker แบบ current-only;
  ค่า editor/controller/validation และ expanded sections ยังคงตาม flow เดิม
- เพิ่ม shadow feedback เฉพาะ drag proxy; คง stable link IDs/order/enabled/
  featured state และ gesture drag เดิม. ระหว่าง drag ต้องไม่เกิด section
  entrance หรือส่วนซ้ำที่เปลี่ยน hit geometry
- Finite effects หยุด/กลับสู่ static final state เมื่อ reduced motion,
  lifecycle ไม่ resumed, `TickerMode` ปิด, hidden tab หรือ inactive route.
  ไม่เพิ่ม ambient loop หรือ network fetch จาก presentation lifecycle
- คง local autosave queue/owner/edit-version/image guards และ explicit Save
  เดิม. Publish/Update/Unpublish ต้อง explicit และ confirmed; copy/open ใช้
 เฉพาะ server-confirmed public URL. ไม่ยก edited slug เป็น URL ที่เผยแพร่แล้ว
- คง 100 templates/5 categories/20 ต่อหมวด, 7 legacy themes, media/logo/cover/
  background, fonts/colors, Form keys, hidden validation, link IDs/limit 20/
  disabled links/featured rules และ auto title. Public-web/preview content
  effects และ catalog ไม่เปลี่ยน

ไม่มี backend/API request/contract/schema/config/dependency/provider/package-rule
เปลี่ยน ไม่มี migration ใหม่. ไม่ใช้ CI/Render/health/migration ของ composer
ก่อนหน้าเป็นผลตรวจใหม่ของงาน mobile UI นี้

## Verification ที่ต้องส่งมอบ

| ส่วน | Acceptance | สถานะ |
| --- | --- | --- |
| Regression-first | tests ใหม่ล้มเหลวก่อนแก้ แล้วผ่านบน source สุดท้าย | RED helper/screen และ mid-drag; final SDK new tests 22/22 ผ่าน |
| Manager/section | press semantics, current-only form/action, stable edit/restore state | final SDK screen 14 cases/full 1,937 ผ่าน; native info/Add cancel/manager/navigation ผ่าน |
| Theme/editor | category replacement ไม่เก็บ outgoing actions; controller/value/100 templates คงเดิม | final SDK helper 8/full 1,937 ผ่าน; native Cute 20 candidates/preview cancel คง original theme |
| Drag | proxy/shadow guards, actual reorder/save/restore ด้วย controlled fixtures | final SDK mid-drag guards และ existing controlled data flows ผ่านใน full 1,937; ไม่ลากข้อมูลจริง |
| Motion guards | reduced motion, lifecycle, TickerMode/hidden tab, mid-transition disable และ drag interruption | final SDK screen 14/helper 8 และ full ผ่าน; native default-font safe paths ผ่าน |
| Existing flows | autosave owner/image queue, publish/update/unpublish/confirmed URLs และ auto title | final SDK full 1,937 ผ่าน; native mutation/Save/Apply/Publish ไม่ทำตามขอบเขตผู้ใช้ |
| Full/analyze/build | source สุดท้าย, package/API/Firebase/flags/signer/APK hash ตรง | full 1,937 ผ่าน 122s/analyze no issues 10.1s/x64 build 25.6s; source/APK/environment/signature/installed8013 ตรง |
| Native safe QA | read/click/theme browse/preview cancel/navigation เท่านั้น; ไม่มี Apply/edit/reorder/Save/Publish | 8013 บัญชี/ร้านเดิม retained; read/browse/cancel/navigation ผ่านและปล่อย manager clean |

บัญชีจริงของ native QA จำกัดไว้ที่ดูและลองกดโดยไม่บันทึกข้อมูล. Theme Apply,
แก้ข้อมูล/ลิงก์, visibility หรือ reorder เรียก autosave ได้ จึงใช้ controlled
widget/store fixtures ตรวจ positive mutation paths. ห้ามอ้าง fixture เป็น
native Save/Publish success. Source/APK/native receipts อยู่ด้านล่าง; ไม่มี
CI/deployment ใหม่ ณ local receipt และแยก local proof จาก external delivery ของ composer

Docs ที่ sync: `README.md`, `ROADMAP.md`, `API.md`, `ARCHITECTURE.md`,
`apps/mobile/README.md` และแผนนี้. Runtime/test inventory และผลคำสั่งอยู่ใน
final receipt ด้านล่าง; ณ local receipt ยังไม่มี commit/push/deploy ของ feature

## ผลระหว่างทำ (ยังไม่ใช่ final verification)

Regression-first receipts:

- Helper RED import classes ยังไม่มี exit 1:
  `D:\Temp\postdee-bio-ui-primitives-red-20261012.log`
- Screen RED compile exit 1, 0 pass/10 fail ใน 5s:
  `D:\Temp\postdee-shop-link-motion-red-20261012.log`
- Helper/template/editor GREEN 135/135 ผ่าน 11s, exit 0:
  `D:\Temp\postdee-bio-ui-primitives-green2-20261012.log`

ระหว่าง regression พบ native `ExpansionTile` ต้องใช้ Ticker ทำงานจนจบแม้
reduced motion. แยก native active ticker เป็น `enabled && resumed && parentTicker`
และส่ง reduced ผ่าน `MediaQuery.disableAnimations`; finite helper ใช้ static
final state เมื่อ reduced. ไม่ปิด native ticker เพียงเพราะ reduced จน disclosure
ค้างหรือเปิดไม่ครบ. ผลนี้เป็น source ระหว่างทำ ไม่ใช้แทน full/final source checks

Candidate runtime 4 ไฟล์: `link_in_bio_screen.dart`,
`link_in_bio_theme_picker.dart`, `link_in_bio_appearance_editor.dart` และใหม่
`apps/mobile/lib/features/link_in_bio/link_in_bio_ui_motion.dart`.
New tests: `apps/mobile/test/link_in_bio_ui_motion_test.dart` และ
`apps/mobile/test/link_in_bio_ui_motion_primitives_test.dart`.
ณ preliminary receipt นี้ Screen/mid-drag/full/analyze/APK/native ยังรอผล;
ผล final source ระบุแยกด้านล่าง

Native baseline เป็นแอปเดิม 8012: บัญชีจริง `noikub` มี 2 ลิงก์ เผยแพร่และ
local saved clean. เปิด theme ดูอย่างเดียว ไม่มี Apply/Save/ข้อมูลเปลี่ยน.
Staging `/health` และ `/ready` ตอบ HTTP 200 จริงที่
`2026-10-12T10:55:37+07:00`; ไม่ใช่ fresh deployment/backend-suite receipt.
Environment ใช้ Staging API, Firebase Auth true, local mock false และ Firebase
project `project-798caf7e-85b8-45e3-af7` เดิม. ไม่มี backend/schema/config/dependency
เปลี่ยนหรือ migration ใหม่ และยังไม่ได้รัน backend checks ใหม่ในงานนี้

## Pre-SDK source และ targeted regression (ประวัติก่อน SDK correction)

Mobile `lib` Dart files 125 ไฟล์ ใช้ manifest SHA-256 ต่อ relative path เรียงชื่อ
แล้ว join ด้วย LF (`relativepath:sha`):
`7CDD5BFC84E2736AB3355A50E7A53A2858FA82AB100A3A3C030792008DC699E4`.
นี่เป็น pre-SDK source manifest hash ไม่ใช่ final source/APK hash

Screen tests ใหม่ 14/14 ผ่านใน 6s, exit 0:
`D:\Temp\postdee-shop-link-motion-green-origin-final-20261012.log`.
Helper มี 8 tests รวม disposal และ swap origin-notifier listener; รวมใหม่
22 cases. All link-in-bio tests และ profile-template catalog ผ่าน 519/519 ใน
37s, exit 0: `D:\Temp\postdee-shop-link-targeted-final-20261012.log`.

Mid-drag regression ก่อนแก้ได้ 12 pass/2 fail ใน 7s: origin `TickerMode` หรือ
`isActive` เปลี่ยน แต่ overlay shadow ยังมีค่า 6.2838. Direct
`ValueListenableBuilder` รอบแรกทำให้เกิด cross-overlay setState during build
(11 pass/3 fail ใน 7s). Final `BioUiOriginScope` ฟัง origin notifier,
coalesce ไป post-frame เมื่ออยู่ `persistentCallbacks`, อ่านค่าล่าสุดและถอด
listener เมื่อ swap/dispose; screen ทั้ง 14 cases จึงผ่าน. ไม่ลด assertions
หรือเปลี่ยน data flow เพื่อหลบ regression. ผลระหว่างทำด้านบนเป็นประวัติแยก
ไม่ใช้ 135 ผ่านมาแทน 519 หรือ final SDK receipts ที่ระบุแยกด้านล่าง

## Final SDK source และ verification ที่ยืนยันแล้ว

Initial analyze พบ 8 issues ใหม่จาก deprecated `TickerMode.of/getNotifier`,
protected `hasListeners` และ deprecated `hasFlag`. แก้ให้ใช้ API ของ Flutter
3.44 ปัจจุบันโดยไม่ suppression; `BioUiOriginScope` ใช้
`ValueListenable<TickerModeData>` และ `.value.enabled`, ใช้
`TickerMode.valuesOf(context)` / `getValuesNotifier` ใน current scopes.
ไม่มี package/dependency/network API หรือ behavior contract เปลี่ยน

Final 125-file mobile Dart manifest SHA-256 ตามวิธี relative-path/hash เดิม:
`C019FA9D020D0347DC45C58E9710E4CEC075D2292D2E11010D62922D8C99E82E`.
New tests 22/22 ผ่านใน 7s, exit 0:
`D:\Temp\postdee-shop-link-motion-sdk-final-20261012.log`.
Final analyze no issues ใน 10.1s, exit 0:
`D:\Temp\postdee-shop-link-analyze-sdk-final-20261012.log`.

Pre-SDK full 1,937/1,937 ผ่าน 136s, exit 0 ที่
`D:\Temp\postdee-shop-link-full-final-20261012.log` เป็นประวัติของ source
7CDD... เท่านั้น. Final full ของ C019... ผ่าน 1,937/1,937 ใน 122s, exit 0:
`D:\Temp\postdee-shop-link-full-sdk-final-20261012.log`.
ผล pre-SDK เป็นประวัติแยก ไม่ใช้แทน final source checks

## Exact build/install และ native safe QA 8013

Staging helper x64 build ผ่านใน 25.6s, exit 0:
`D:\Temp\postdee-shop-link-build-staging-x64-4013-20261012.log`.
ใช้ `--build-number=4013 --split-per-abi --target-platform=android-x64`.
Initial universal 4013 ไม่ใช่ artifact ที่ส่งมอบหรือติดตั้ง; delivered
`apps/mobile/build/app/outputs/flutter-apk/app-x86_64-debug.apk` มี SHA-256
`21F42D9E06856523CE33A9B531516CD743BC47A4A457DA939D1E202BE5263D07`.
Package `com.postdee.postdee_mobile.staging`, versionCode 8013,
versionName `0.1.0-staging`, signer เดิม
`014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`.
All-125-file source manifest C019... ตรงก่อนและหลัง build

ใช้ actual defines จาก `staging.local.example.json`: Staging API/Firebase Auth
true/local mock false/project `project-798caf7e-85b8-45e3-af7` เดิม. Ignored
RevenueCat Test Store overlay จาก canonical ถูก helper validate โดยไม่เปิดเผย
SDK keyหรือ copy credentials. `adb install -r` สำเร็จ ไม่มี downgrade/data clear;
เปิด MainActivity รุ่น 8013. firstInstallTime คง `2026-10-05 06:30:36`,
lastUpdateTime `2026-10-12 04:12:45` device UTC / 11:12:45 GMT+7

Native actual installed 8013 คง session: Home Free 0/3, connected 0/4,
ไม่มีโพสต์. Shop `noikub` มี 2/20 ลิงก์ เผยแพร่และ local saved clean พร้อม
original URL/theme. ตรวจ Info open/back ไม่แก้ข้อมูล, Add sheet ว่าง open/close,
Theme Cute มี 20 candidates/preview Cherry Frame/close โดยไม่ Apply,
Review preview/full modal close และ Home ↔ Shop ยังคง 2 ลิงก์/state.
จบที่ manager สถานะ published/saved clean และ original grid theme ไม่เปลี่ยน

ไม่มี typing/link edit/visibility toggle/reorder/Save/Done/Apply/Publish หรือ
native positive data writes. Positive mutations/Save/publish contracts ใช้
controlled widget/store fixtures ไม่อ้างว่า native data-save/publish ผ่านจริง.
Reduced/hidden/lifecycle/mid-drag/large-text acceptance ใช้ fixtures แยกจาก
native default-font observations. Critical PID 9263 logs 154 lines ตรวจ
11:16:55 GMT+7: 0 E/flutter/FATAL/overflow/Unhandled hits

Actual new-app screenshots (raw JPEG):

- `C:\Users\stopp\.codex\visualizations\2026\10\12\01a12dc1-f51c-7ec2-9a95-f89a5069c32c\shop-link-motion-manager-8013.jpg` — 41,648 bytes
- `C:\Users\stopp\.codex\visualizations\2026\10\12\01a12dc1-f51c-7ec2-9a95-f89a5069c32c\shop-link-motion-theme-8013.jpg` — 45,283 bytes

ไม่มี backend source/API/schema/config/dependency change หรือ migration ใหม่;
ณ local verification ไม่มี fresh backend full/Prisma migration execution/CI/Render deploy.
Health/ready HTTP 200 เวลา 10:55:37 เป็น existing-server check ไม่ใช่ new
deployment proof. Mobile UI-only ไม่มี backend change ที่ต้อง rollout; ณ local
verification ยังไม่มีคำสั่ง push ซึ่งได้รับอนุญาต combined release ภายหลัง.
Final `git diff --check` ผ่าน และไม่มี deleted/unexpected files;
Windows dirt 3 ไฟล์เดิมคงไว้และแยกจาก feature

## Final inventory และคำสั่งตรวจ

Runtime 4 ไฟล์ใน `apps/mobile/lib/features/link_in_bio/`:

- `link_in_bio_screen.dart`
- `link_in_bio_theme_picker.dart`
- `link_in_bio_appearance_editor.dart`
- ใหม่ `link_in_bio_ui_motion.dart`

New tests 2: `apps/mobile/test/link_in_bio_ui_motion_test.dart` (14 cases) และ
`apps/mobile/test/link_in_bio_ui_motion_primitives_test.dart` (8 cases).
Docs 6: `README.md`, `ROADMAP.md`, `API.md`, `ARCHITECTURE.md`,
`apps/mobile/README.md` และแผนนี้. รวม feature inventory 12 ไฟล์; Windows
generated-plugin dirt 3 ไฟล์เดิมไม่รวม. ไม่แก้ runtime/tests อื่นหรือ public renderer

คำสั่ง: `flutter.bat test` ชุดใหม่/targeted/full, `flutter.bat analyze`,
Staging helper `-Command build-apk` พร้อม x64/split ABI/build-number 4013,
`adb install -r`, MainActivity launch และ `git diff --check`.
งานส่งมอบในเครื่องเสร็จแล้ว; ณ local receipt external release ยังไม่ได้ทำ

## Authorized combined release (2026-10-12, in progress)

ผู้ใช้อนุญาต push/deploy Shop-link และ Account UI motion พร้อมกัน.
Fresh fetch ก่อน release ยืนยัน HEAD
`f3b45f2dbb8ce89ff7e19182885d72ca9334d666`, origin/main/merge base
`c4e52201a58b556f5f47529027549a2fc16af84c`, 25ahead/0behind และ remote
feature ref ตรง baseline. Combined18-file scope ไม่รวม Windows dirt3เดิม
Current combined126-file runtime manifest เป็น
`2B7E4D05D08AE00099F97288A28C5F2751A248F32EFC70EFAC72CA942B992403`.
Shop C019.../8013 เป็น local history; combined source/APK8014/native Account
receipts อยู่ใน `2026-10-12-account-ui-motion.md`. Exact feature commit,
push/CI/Render Live/health/migration receipts จะบันทึกเมื่อยืนยันจริง
