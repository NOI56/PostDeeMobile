# PostDee procedural sound effects

ไฟล์ WAV ในโฟลเดอร์นี้สร้างจาก oscillator และ noise generator ด้วย
`scripts/generate_ai_sound_effects.ps1` โดยไม่มี sample, melody, brand sound
หรือไฟล์เสียงจากบุคคลที่สาม

- รูปแบบ: PCM signed 16-bit little-endian, 48 kHz, stereo
- การใช้งาน: ฝังในวิดีโอที่ PostDee เรนเดอร์
- ห้ามเปลี่ยนไฟล์โดยตรง ให้แก้ script แล้วสร้างใหม่เพื่อให้ตรวจสอบที่มาได้
- SHA-256 เก็บใน `manifest.sha256` และระยะเวลา/รูปแบบเก็บใน `manifest.csv`
- Script กำหนด seed ของ noise ทุกเสียงและเขียน manifest ใหม่อัตโนมัติ เพื่อให้
  การรันซ้ำด้วย FFmpeg รุ่นเดียวกันได้ไฟล์และ hash ชุดเดิม
- Script กำหนด seed ของ noise ทุกเสียงและเขียน manifest ใหม่อัตโนมัติ เพื่อให้
  การรันซ้ำด้วย FFmpeg รุ่นเดียวกันได้ไฟล์และ hash ชุดเดิม

เสียงชุดนี้เป็นทรัพย์สินที่สร้างขึ้นภายใน repository สำหรับผลิตภัณฑ์ PostDee
และยังไม่เปิดเป็นคลังไฟล์ดาวน์โหลดหรือแจกจ่ายแบบ standalone
