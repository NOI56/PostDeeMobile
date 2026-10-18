import { expect, it } from 'vitest';
import { adminPublishFailure } from './adminPublishFailure.js';
it('translates only known safe worker messages and never exposes arbitrary provider credentials', () => {
  expect(adminPublishFailure('Publishing result could not be confirmed. Check the platform before trying again.')).toContain('ก่อนส่งซ้ำ');
  expect(adminPublishFailure('PostPeer token=secret https://signed.example/video?key=secret')).not.toContain('secret');
  expect(adminPublishFailure(null)).toContain('ไม่มีสาเหตุที่ยืนยันได้');
});
