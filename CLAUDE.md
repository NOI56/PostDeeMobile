# CLAUDE.md

Claude Code อ่านไฟล์นี้อัตโนมัติทุกครั้งที่เริ่มงาน ใช้เป็น "ความจำหลัก" ของโปรเจค

## คู่มือการทำงาน (สำคัญ)

แนวทางการทำงาน รายละเอียด stack การ verify และกฎการแก้ไฟล์ทั้งหมด อยู่ใน **[AGENTS.md](AGENTS.md)** — อ่านและทำตามไฟล์นั้นเป็นหลัก

@AGENTS.md

## เอกสารอ้างอิงหลัก

- [README.md](README.md) — ภาพรวมโปรเจคและวิธีเริ่มต้น
- [ARCHITECTURE.md](ARCHITECTURE.md) — โครงสร้างสถาปัตยกรรม
- [API.md](API.md) — สัญญา API (API contract)
- [ROADMAP.md](ROADMAP.md) — แผนงานและทิศทางผลิตภัณฑ์
- [FIREBASE_SETUP.md](FIREBASE_SETUP.md) — การตั้งค่า Firebase

> เมื่อแก้แผนผลิตภัณฑ์ กฎ package, API contract หรือทิศทางสถาปัตยกรรม ให้ sync เอกสารด้านบนให้ตรงกันด้วย

## ทิศทางผลิตภัณฑ์: ใช้ได้หลายประเทศ

PostDee ตั้งใจให้ใช้ได้หลายประเทศ โดยไทยเป็นตลาดแรก แอปรองรับไทย/อังกฤษและจำภาษาที่เลือก งานใหม่ต้องไม่ผูกกับไทยอย่างเดียว เช่น ราคาบาทตายตัว เบอร์ `+66` อย่างเดียว เวลา Bangkok หรือข้อความภาษาไทยอย่างเดียว กฎเต็มอยู่ในหัวข้อ "Multi-Country Direction" ของ [AGENTS.md](AGENTS.md)

## Language

- **Chat with the user in Thai** — all conversation, explanations, and summaries should be in Thai.
- **Write code, comments, docs, and commit messages in English.**
- Keep explanations simple and clear — the user may not have a coding background.

## คำสั่งที่ใช้บ่อย

### Backend (`apps/api`)

```powershell
cd apps/api
npm.cmd run test     # รันเทสต์
npm.cmd run build    # build TypeScript
$env:DATABASE_URL='postgresql://postdee:postdee_password@localhost:5432/postdee?schema=public'; npm.cmd run prisma:validate
```

### Mobile (`apps/mobile`)

```powershell
cd apps/mobile
flutter pub get
flutter analyze
flutter test
```

> หมายเหตุ: Flutter อาจยังไม่อยู่ใน PATH — อย่าอ้างว่า `flutter analyze`/`flutter test` ผ่าน ถ้ายังไม่ได้รันจริง

## สภาพแวดล้อม

- OS: Windows — ใช้ PowerShell เป็น shell หลัก (`npm.cmd`, `npx.cmd`)
- เริ่มต้นค้นหาไฟล์/ข้อความด้วย `rg` (ripgrep) ก่อนเสมอ
