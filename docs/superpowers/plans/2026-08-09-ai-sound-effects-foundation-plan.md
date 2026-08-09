# แผนระบบ AI เลือกและใส่เอฟเฟกต์เสียงอัตโนมัติ

วันที่: 2026-08-10
สถานะ: พัฒนาและตรวจอัตโนมัติแล้ว; รอทดสอบการฟัง Preview/full export และ A/V sync
บน Android กับ iPhone หลัง Staging transcription provider กลับมาใช้งานได้

## เป้าหมาย

ผู้ขายเปิด `AI ใส่เอฟเฟกต์เสียงให้` เพียงสวิตช์เดียว จากนั้น AI วิเคราะห์เนื้อหา
คำพูด และจังหวะของคลิป แล้วเลือกเสียงจากคลัง PostDee พร้อมตำแหน่งเวลาให้อัตโนมัติ
ผู้ใช้ไม่ต้องเลือกไฟล์เสียงหรือวางตำแหน่งเอง

## สัญญาความปลอดภัย

- ใช้เฉพาะเสียง procedural 10 เสียงที่ PostDee สร้างและ bundle ในแอป
- ไม่ส่งไฟล์ WAV, asset path หรือ URL เข้าโมเดล และไม่ดาวน์โหลดเสียงจากภายนอก
- AI คืนได้เฉพาะ `soundId + sourceSeconds` จาก allowlist และ trusted transcript anchor
- API ตรวจผลทั้งก้อนแบบ atomic จำกัดไม่เกิน 8 จุด; ข้อมูลผิดเพียงจุดเดียวทำให้รอบ SFX
  เป็น unavailable และไม่ส่งรายการที่เหลือให้ renderer
- โมเดลควบคุมความดังไม่ได้; Mobile กำหนดความดังคงที่ 25%
- Mobile แปลง source timeline ผ่านช่วงตัดจริงก่อน render และทิ้งเอฟเฟกต์ที่อยู่ในช่วงถูกตัด
- Preview, Review rerender และ full export ต้องอ่าน recipe ชุดเดียวกัน
- SFX-only เป็นงาน AI จริง: วิเคราะห์สำเร็จรวมกรณีเลือก 0 จุดจึงคิด AI minutes;
  provider/timing/parse unavailable เพียงอย่างเดียวไม่คิดนาที

## ขอบเขตที่เก็บไว้

- catalog/model/validation และหลักฐานสิทธิ์ของไฟล์เสียง
- procedural WAV 48 kHz stereo, manifest และ SHA-256
- FFmpeg input materialization, delay, mix, limiter, AAC output, cleanup และ cache signature
- guard สำหรับวิดีโอไม่มีเสียง, asset หาย, ค่าผิด, render ล้ม และเกินจำนวน

## สิ่งที่นำออก

- การ์ด `เพิ่มเอฟเฟกต์เสียงเอง`
- Sound Effect Studio, ปุ่มทดลองฟัง, slider เวลา/ความดัง และปุ่มแก้เสียงใน Review
- manual-only local recipe/media strategy, QA dart-define และ `just_audio`
- state/preset/cache ที่เป็นรายการ manual แยกจาก recipe

## ลำดับงาน

1. [x] คง catalog 10 เสียงและ renderer ที่ตรวจสิทธิ์/asset แบบ fail closed
2. [x] เพิ่ม Mobile recipe parser แบบ all-or-nothing สำหรับ `soundEffects`
3. [x] เพิ่ม pure mapper จาก source timeline ไป output timelineหลังตัด
4. [x] เพิ่ม AI sound-effect planner พร้อม allowlist/anchor parser และ quota outcome
5. [x] เปิดการ์ด AI SFX และส่ง `capabilities.sfx=true` เข้า prepare
6. [x] เชื่อมผล AI เข้ากับ Preview/Review/Export และรองรับช่วงตัดจริง
7. [x] ลบ manual UI/path/dependency/tests ทั้งหมด
8. [x] รัน full API/Mobile tests, build/analyze และซิงก์เอกสาร
9. [ ] ฟัง Preview/full export และตรวจระดับเสียง/A-V sync บน Android กับ iPhone

ผลตรวจอัตโนมัติรอบ 2026-08-10: API 938/938 และ TypeScript build ผ่าน;
Mobile 792/792 และ Flutter analyze ผ่านโดยไม่พบปัญหา; `git diff --check` ผ่าน
โดยมีเพียงคำเตือนรูปแบบบรรทัด LF/CRLF ของ Windows

## เกณฑ์ก่อน Production

- AI เลือกได้เฉพาะ ID และ timestamp ที่ server อนุญาต
- เสียงที่ตกในช่วงถูกตัดต้องไม่รั่วเข้า output และเวลาที่เหลือต้องเลื่อนตรงกับคลิปหลังตัด
- ปิด SFX แล้วต้องไม่มี asset input/filter ของเสียงใน FFmpeg
- provider ล้ม/ข้อมูลเสียต้องไม่สุ่มเสียงทดแทนและไม่คิด AI minutes
- render ล้มต้องเก็บผลลัพธ์เดิมไว้
- output มี video+audio stream, ไม่ clip เกิน limiter และเสียงพูดยังชัด
- ต้องมี device evidence แยก Preview กับ full export; automated tests ไม่แทนการฟังจริง
- Staging ที่ยังมี ElevenLabs quota ไม่พอต้องคงสถานะ blocked และห้ามอ้างว่า E2E ผ่าน

## แนวทางสิทธิ์

ใช้เสียงที่ PostDee สร้างเองด้วย oscillator/noise/foley พร้อมเก็บ script, SHA-256,
duration และวันที่สร้างต่อไฟล์ หากเพิ่มเสียงภายนอกภายหลังต้องตรวจ commercial use,
redistribution-in-app และ AI use แยกทุกไฟล์ ห้ามใช้เสียงแจ้งเตือนของแพลตฟอร์ม/แบรนด์
หรือดาวน์โหลดคลังเสียงมาใส่แอปโดยไม่มีสิทธิ์แจกไฟล์ภายในแอปอย่างชัดเจน
