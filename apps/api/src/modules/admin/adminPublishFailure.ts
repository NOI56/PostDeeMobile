// Only translate known, fixed public worker messages. Never return raw provider payloads.
const known: Record<string, string> = {
  'TikTok rejected this video because its frame rate validation failed. Export the video again before retrying.': 'TikTok ไม่รับอัตราเฟรมของคลิป ให้ส่งออกไฟล์ใหม่ก่อนลองอีกครั้ง',
  'Publishing result could not be confirmed. Check the platform before trying again.': 'ยังยืนยันผลไม่ได้ ตรวจคลิปบนช่องทางก่อนส่งซ้ำ',
  'TikTok publishing options changed. Review the account and publishing settings before trying again.': 'การตั้งค่า TikTok เปลี่ยน ให้ตรวจบัญชีและการตั้งค่าโพสต์อีกครั้ง',
  'TikTok publishing options could not be checked. No video was sent to TikTok. Review the settings before trying again.': 'ตรวจสิทธิ์ TikTok ไม่สำเร็จ ยังไม่ได้ส่งคลิป ให้ตรวจการเชื่อมต่อและการตั้งค่า',
  'Publishing to this platform failed. Please try again later.': 'ช่องทางส่งไม่สำเร็จ ตรวจสถานะช่องทางและผลเดิมก่อนลองใหม่'
};
export const adminPublishFailure = (message: string | null) => message && known[message] || 'ไม่มีสาเหตุที่ยืนยันได้จากข้อมูลที่บันทึก ตรวจผลในแอปและช่องทางก่อนส่งซ้ำ';
