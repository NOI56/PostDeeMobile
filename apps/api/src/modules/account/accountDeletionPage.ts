// Public account deletion request page required by Google Play. It must be
// reachable without the app, name the app, show the request steps, and say
// which data is deleted or kept. Keep the labels in sync with the Mobile UI.
export const accountDeletionSupportEmail = 'postdee.support@gmail.com';

const mailtoHref = `mailto:${accountDeletionSupportEmail}?subject=${
  encodeURIComponent('ขอลบบัญชี PostDee / PostDee account deletion request')
}`;

export const renderAccountDeletionPage = (nonce: string): string => `<!doctype html>
<html lang="th">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="index, follow">
<title>ขอลบบัญชี PostDee</title>
<style nonce="${nonce}">
:root { --bg: #f6f8f7; --card: #ffffff; --text: #101812; --muted: #4b5a52;
  --line: #dfe6e2; --accent: #087f5b; --warn-bg: #fff7ed; --warn: #9a3412; }
@media (prefers-color-scheme: dark) {
  :root { --bg: #0e1411; --card: #16201b; --text: #f5f5f5; --muted: #a7b3ad;
    --line: #26342d; --accent: #36d6a0; --warn-bg: #2a1c10; --warn: #fdba74; }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text);
  font: 16px/1.65 system-ui, -apple-system, "Segoe UI", "Noto Sans Thai", sans-serif; }
main { max-width: 720px; margin: 0 auto; padding: 32px 16px 48px; }
h1 { font-size: 1.75rem; line-height: 1.3; margin: 0 0 8px; }
h2 { font-size: 1.2rem; margin: 0 0 12px; }
h3 { font-size: 1rem; margin: 20px 0 8px; }
p { margin: 0 0 12px; }
.lead { color: var(--muted); margin-bottom: 24px; }
section { background: var(--card); border: 1px solid var(--line); border-radius: 16px;
  padding: 20px; margin-bottom: 16px; }
ol, ul { margin: 0 0 12px; padding-left: 1.4em; }
li { margin-bottom: 6px; }
a { color: var(--accent); font-weight: 600; overflow-wrap: anywhere; }
.button { display: inline-block; background: var(--accent); color: #ffffff; text-decoration: none;
  padding: 10px 18px; border-radius: 999px; margin: 4px 0 12px; }
@media (prefers-color-scheme: dark) { .button { color: #0e1411; } }
.note { background: var(--warn-bg); color: var(--warn); border-radius: 12px; padding: 12px 14px; }
.muted { color: var(--muted); font-size: 0.9rem; }
</style>
</head>
<body>
<main>
<h1>ขอลบบัญชี PostDee</h1>
<p class="lead">หน้านี้อธิบายวิธีลบบัญชีแอป PostDee และข้อมูลที่เกี่ยวข้อง
คุณลบได้เองในแอป หรือส่งคำขอทางอีเมลโดยไม่ต้องติดตั้งแอป</p>

<section>
<h2>วิธีที่ 1: ลบในแอป (เร็วที่สุด)</h2>
<ol>
<li>เปิดแอป PostDee และเข้าสู่ระบบด้วยบัญชีที่ต้องการลบ</li>
<li>ไปที่แท็บ <strong>บัญชี</strong> แล้วกด <strong>ลบบัญชี</strong></li>
<li>อ่านคำเตือน แล้วกด <strong>ลบบัญชีถาวร</strong> หากเข้าสู่ระบบไว้นานแล้ว
แอปจะให้เข้าสู่ระบบใหม่ก่อนเพื่อยืนยันว่าเป็นเจ้าของบัญชี</li>
</ol>
<p>เมื่อลบสำเร็จ แอปจะออกจากระบบให้ทันที</p>
</section>

<section>
<h2>วิธีที่ 2: ขอลบทางอีเมล (ไม่ต้องติดตั้งแอป)</h2>
<p>ส่งอีเมลถึง <a href="${mailtoHref}">${accountDeletionSupportEmail}</a></p>
<a class="button" href="${mailtoHref}">ส่งอีเมลขอลบบัญชี</a>
<ol>
<li>ส่งจากอีเมลที่ใช้เข้าสู่ระบบ PostDee หากเข้าสู่ระบบด้วยเบอร์โทร ให้ระบุเบอร์นั้น</li>
<li>ใช้หัวข้อ “ขอลบบัญชี PostDee” และบอกวิธีที่ใช้เข้าสู่ระบบ
(อีเมล, Google, Apple หรือเบอร์โทร)</li>
<li>เราจะตรวจสอบว่าคุณเป็นเจ้าของบัญชี แล้วลบบัญชีและแจ้งผลกลับภายใน 30 วัน</li>
</ol>
<p class="note">ห้ามส่งรหัสผ่านหรือรหัส OTP ทีมงานจะไม่ขอข้อมูลเหล่านี้</p>
</section>

<section>
<h2>ข้อมูลที่ถูกลบ</h2>
<ul>
<li>บัญชีและการเข้าสู่ระบบ PostDee (Firebase Authentication)</li>
<li>โพสต์ โพสต์ที่ตั้งเวลาไว้ ผลการโพสต์ และเทมเพลตแคปชั่น</li>
<li>วิดีโอและรูปหน้าปกที่อัปโหลดไว้บนเซิร์ฟเวอร์ของ PostDee</li>
<li>หน้าเว็บร้านค้า (Link in Bio) และรูปภาพของหน้านั้น</li>
<li>การเชื่อมต่อบัญชีโซเชียล ระบบจะยกเลิกการเชื่อมต่อทุกบัญชีและลบโปรไฟล์ของคุณที่ผู้ให้บริการโพสต์ (PostPeer)</li>
<li>สถานะแพ็กเกจ โควตา และเครดิตคงเหลือในระบบ PostDee</li>
<li>ข้อมูลอุปกรณ์สำหรับส่งการแจ้งเตือน</li>
</ul>
</section>

<section>
<h2>ข้อมูลที่อาจเก็บไว้</h2>
<ul>
<li><strong>หลักฐานการลบ:</strong> รหัสบัญชีภายใน เวลาที่ยืนยันการลบ
และกรณีขอลบทางอีเมล บันทึกว่าทีมงานคนใดดำเนินการและเหตุผล
เก็บไว้ต่อไปเพื่อยืนยันว่าลบครบและกันการทำรายการซ้ำ ไม่มีอีเมล ชื่อ หรือเนื้อหาของคุณ</li>
<li><strong>เลขรายการซื้อเครดิตเพิ่ม:</strong> เก็บไว้โดยไม่ผูกกับบัญชี
เพื่อกันไม่ให้นำใบเสร็จเดิมมาใช้ซ้ำ</li>
<li><strong>ชื่อลิงก์ร้านค้าเดิม:</strong> ถูกกันไว้ 30 วันหลังลบ เพื่อไม่ให้ผู้อื่นนำลิงก์ที่คุณเคยแชร์ไปใช้</li>
<li><strong>การซื้อแพ็กเกจ:</strong> Google Play, App Store และ RevenueCat
เก็บประวัติการซื้อตามนโยบายของตน การลบบัญชี <strong>ไม่ยกเลิกสมาชิก</strong>
กรุณายกเลิกในร้านค้าของอุปกรณ์ก่อน</li>
<li><strong>โพสต์ที่เผยแพร่แล้ว</strong> บน TikTok, YouTube, Instagram หรือ Facebook
ไม่ถูกลบ ลบได้ที่แพลตฟอร์มนั้นโดยตรง</li>
<li><strong>ข้อมูลในเครื่อง:</strong> ฉบับร่างและไฟล์ในมือถือไม่ถูกลบจากเซิร์ฟเวอร์
ให้ลบฉบับร่าง ล้างข้อมูลแอป หรือลบแอป</li>
<li><strong>สำเนาสำรองและบันทึกระบบ:</strong> สำเนาสำรองของฐานข้อมูล บันทึกระบบ
และรายงานข้อผิดพลาดของผู้ให้บริการอาจคงอยู่ช่วงหนึ่ง จนถูกเขียนทับหรือหมดอายุตามรอบของผู้ให้บริการ</li>
</ul>
</section>

<section lang="en">
<h2>Delete your PostDee account</h2>
<h3>In the app</h3>
<p>Sign in to PostDee, open the <strong>บัญชี (Account)</strong> tab, tap
<strong>ลบบัญชี (Delete account)</strong>, then <strong>ลบบัญชีถาวร (Delete permanently)</strong>.
You may be asked to sign in again first.</p>
<h3>Without the app</h3>
<p>Email <a href="${mailtoHref}">${accountDeletionSupportEmail}</a> from the address you
sign in with (or include your phone number), with the subject “PostDee account deletion
request” and your sign-in method. We verify ownership and delete the account within
30 days. Never send a password or OTP code.</p>
<h3>Deleted</h3>
<p>Your account and sign-in identity, posts, schedules, publishing results, templates,
uploaded videos and covers, Link in Bio page and images, social account connections
(including your profile at our publishing provider PostPeer), plan, quota and credit
balances, and push notification tokens.</p>
<h3>Kept</h3>
<p>An internal account ID and deletion timestamp as proof of deletion (for email requests,
also which team member processed it and why); add-on purchase
transaction IDs, unlinked from you, to prevent receipt reuse; your old store link name,
reserved for 30 days; purchase records held by Google Play, the App Store and
RevenueCat under their policies (deleting the account does not cancel a subscription);
posts already published on social platforms; drafts and files on your device; and
provider backups, logs and error reports until they expire on the provider's schedule.</p>
</section>

<p class="muted">PostDee · ติดต่อ <a href="mailto:${accountDeletionSupportEmail}">${accountDeletionSupportEmail}</a></p>
</main>
</body>
</html>
`;
