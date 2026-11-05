export type LinkInBioLanguage = 'th' | 'en';

export const linkInBioLocalizations = {
  th: {
    defaultDescription: 'เลือกช่องทางที่ต้องการได้เลย',
    footer: 'สร้างหน้าเว็บร้านค้าด้วย PostDee',
    openLink: 'เปิดลิงก์',
    coverAlt: (storeName: string) => `ภาพปกของ ${storeName}`,
    logoAlt: (storeName: string) => `โลโก้ ${storeName}`,
    notFound: 'ไม่พบหน้าเว็บร้านค้า'
  },
  en: {
    defaultDescription: 'Choose a channel below',
    footer: 'Create your store page with PostDee',
    openLink: 'Open link',
    coverAlt: (storeName: string) => `Cover image for ${storeName}`,
    logoAlt: (storeName: string) => `Logo for ${storeName}`,
    notFound: 'Store page not found'
  }
} as const;
