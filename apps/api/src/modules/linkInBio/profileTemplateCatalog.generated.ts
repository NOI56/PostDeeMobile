// Generated from shared/profile-templates.json by scripts/generate-profile-templates.mjs.
// Do not edit; maintain the authored source catalog and regenerate both clients.

export type ProfileTemplateCategoryId = 'minimal' | 'cute' | 'nature' | 'luxury' | 'creative';
export type ProfileTemplateLayout = {
  header: 'centered' | 'left' | 'split' | 'cover' | 'badge';
  links: 'list' | 'grid';
  button: 'solid' | 'outline' | 'soft' | 'raised';
  decoration: 'none' | 'line' | 'dots' | 'frame' | 'stripe';
  avatar: 'circle' | 'rounded' | 'square';
};
export type ProfileTemplatePalette = { background: string; gradient: string; surface: string; button: string; name: string; description: string; category: string; buttonText: string; brand: string };
export type ProfileTemplateDefinition = {
  id: string; name: string; category: ProfileTemplateCategoryId;
  themeId: 'minimal' | 'shop' | 'pastel' | 'dark' | 'pink' | 'garden' | 'cards';
  layout: ProfileTemplateLayout; palette: ProfileTemplatePalette;
  font: 'anuphan' | 'prompt' | 'system'; buttonRadius: 'rounded' | 'pill' | 'square';
  effects: { background: boolean; entrance: boolean; featured: boolean; stickers: 'none' | 'hearts' | 'flowers' | 'sparkles' };
};

export const profileTemplateCategories: readonly { id: ProfileTemplateCategoryId; name: string }[] = [
  {
    "id": "minimal",
    "name": "เรียบง่าย"
  },
  {
    "id": "cute",
    "name": "น่ารัก / พาสเทล"
  },
  {
    "id": "nature",
    "name": "ธรรมชาติ / อบอุ่น"
  },
  {
    "id": "luxury",
    "name": "หรูหรา / พรีเมียม"
  },
  {
    "id": "creative",
    "name": "สดใส / ครีเอทีฟ"
  }
];

export const profileTemplates: readonly ProfileTemplateDefinition[] = [
  {
    "id": "minimal-white-editorial",
    "name": "บทบรรณาธิการ",
    "category": "minimal",
    "themeId": "minimal",
    "layout": {
      "header": "left",
      "links": "list",
      "button": "outline",
      "decoration": "line",
      "avatar": "circle"
    },
    "palette": {
      "background": "#ffffff",
      "gradient": "#f1f3f2",
      "surface": "#ffffff",
      "button": "#d4dad7",
      "name": "#17201f",
      "description": "#65716e",
      "category": "#17201f",
      "buttonText": "#17201f",
      "brand": "#65716e"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "minimal-white-paper",
    "name": "กระดาษขาว",
    "category": "minimal",
    "themeId": "minimal",
    "layout": {
      "header": "centered",
      "links": "list",
      "button": "solid",
      "decoration": "none",
      "avatar": "circle"
    },
    "palette": {
      "background": "#ffffff",
      "gradient": "#f2f4f3",
      "surface": "#ffffff",
      "button": "#243d35",
      "name": "#17201f",
      "description": "#626d69",
      "category": "#243d35",
      "buttonText": "#ffffff",
      "brand": "#626d69"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "minimal-fine-lines",
    "name": "เส้นบาง",
    "category": "minimal",
    "themeId": "minimal",
    "layout": {
      "header": "centered",
      "links": "list",
      "button": "outline",
      "decoration": "line",
      "avatar": "rounded"
    },
    "palette": {
      "background": "#fafafa",
      "gradient": "#ebeeee",
      "surface": "#ffffff",
      "button": "#3e504b",
      "name": "#222b29",
      "description": "#646d69",
      "category": "#3e504b",
      "buttonText": "#222b29",
      "brand": "#646d69"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "minimal-pebble-tiles",
    "name": "ก้อนหิน",
    "category": "minimal",
    "themeId": "minimal",
    "layout": {
      "header": "centered",
      "links": "grid",
      "button": "soft",
      "decoration": "dots",
      "avatar": "square"
    },
    "palette": {
      "background": "#f5f5f0",
      "gradient": "#e6e8df",
      "surface": "#ffffff",
      "button": "#e6e8df",
      "name": "#283226",
      "description": "#61695d",
      "category": "#4e5e49",
      "buttonText": "#283226",
      "brand": "#61695d"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "minimal-light-cards",
    "name": "การ์ดเบา",
    "category": "minimal",
    "themeId": "minimal",
    "layout": {
      "header": "centered",
      "links": "grid",
      "button": "raised",
      "decoration": "frame",
      "avatar": "circle"
    },
    "palette": {
      "background": "#ffffff",
      "gradient": "#e9eef0",
      "surface": "#ffffff",
      "button": "#355466",
      "name": "#20313b",
      "description": "#5e6e76",
      "category": "#355466",
      "buttonText": "#ffffff",
      "brand": "#5e6e76"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "minimal-daily-studio",
    "name": "สตูดิโอประจำวัน",
    "category": "minimal",
    "themeId": "minimal",
    "layout": {
      "header": "left",
      "links": "list",
      "button": "solid",
      "decoration": "stripe",
      "avatar": "rounded"
    },
    "palette": {
      "background": "#fcfcfa",
      "gradient": "#eaece6",
      "surface": "#ffffff",
      "button": "#3e5142",
      "name": "#1c2820",
      "description": "#5e6b62",
      "category": "#3e5142",
      "buttonText": "#ffffff",
      "brand": "#5e6b62"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "minimal-pocket-board",
    "name": "บอร์ดพกพา",
    "category": "minimal",
    "themeId": "minimal",
    "layout": {
      "header": "left",
      "links": "grid",
      "button": "soft",
      "decoration": "line",
      "avatar": "circle"
    },
    "palette": {
      "background": "#f4f7f6",
      "gradient": "#e0eae7",
      "surface": "#ffffff",
      "button": "#e0eae7",
      "name": "#263c33",
      "description": "#5a6a61",
      "category": "#2f5a4b",
      "buttonText": "#263c33",
      "brand": "#5a6a61"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "minimal-layered-note",
    "name": "โน้ตซ้อน",
    "category": "minimal",
    "themeId": "minimal",
    "layout": {
      "header": "left",
      "links": "grid",
      "button": "raised",
      "decoration": "dots",
      "avatar": "rounded"
    },
    "palette": {
      "background": "#faf8f5",
      "gradient": "#eee5d9",
      "surface": "#ffffff",
      "button": "#66513f",
      "name": "#352a24",
      "description": "#726257",
      "category": "#66513f",
      "buttonText": "#ffffff",
      "brand": "#726257"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "minimal-mono-pair",
    "name": "ขาวดำคู่กัน",
    "category": "minimal",
    "themeId": "minimal",
    "layout": {
      "header": "split",
      "links": "list",
      "button": "solid",
      "decoration": "frame",
      "avatar": "square"
    },
    "palette": {
      "background": "#f5f5f5",
      "gradient": "#e6e6e6",
      "surface": "#ffffff",
      "button": "#242424",
      "name": "#171717",
      "description": "#656565",
      "category": "#242424",
      "buttonText": "#ffffff",
      "brand": "#656565"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "minimal-side-lines",
    "name": "เส้นข้าง",
    "category": "minimal",
    "themeId": "minimal",
    "layout": {
      "header": "split",
      "links": "list",
      "button": "outline",
      "decoration": "stripe",
      "avatar": "circle"
    },
    "palette": {
      "background": "#fafbfc",
      "gradient": "#e8edf4",
      "surface": "#ffffff",
      "button": "#3e4b65",
      "name": "#252c3a",
      "description": "#606b7f",
      "category": "#3e4b65",
      "buttonText": "#252c3a",
      "brand": "#606b7f"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "minimal-easy-grid",
    "name": "ตารางสบายตา",
    "category": "minimal",
    "themeId": "minimal",
    "layout": {
      "header": "split",
      "links": "grid",
      "button": "soft",
      "decoration": "none",
      "avatar": "rounded"
    },
    "palette": {
      "background": "#f3f5f4",
      "gradient": "#dfe5e2",
      "surface": "#ffffff",
      "button": "#dfe5e2",
      "name": "#283a30",
      "description": "#59675e",
      "category": "#435a4d",
      "buttonText": "#283a30",
      "brand": "#59675e"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "minimal-quiet-blocks",
    "name": "บล็อกเรียบ",
    "category": "minimal",
    "themeId": "minimal",
    "layout": {
      "header": "split",
      "links": "grid",
      "button": "raised",
      "decoration": "line",
      "avatar": "square"
    },
    "palette": {
      "background": "#f7f6f2",
      "gradient": "#e7e5db",
      "surface": "#ffffff",
      "button": "#5b5845",
      "name": "#2e2c23",
      "description": "#686655",
      "category": "#5b5845",
      "buttonText": "#ffffff",
      "brand": "#686655"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "minimal-clean-cover",
    "name": "ภาพปกสะอาด",
    "category": "minimal",
    "themeId": "minimal",
    "layout": {
      "header": "cover",
      "links": "list",
      "button": "solid",
      "decoration": "dots",
      "avatar": "circle"
    },
    "palette": {
      "background": "#ffffff",
      "gradient": "#edf2f4",
      "surface": "#ffffff",
      "button": "#3c5967",
      "name": "#1f323b",
      "description": "#5d7078",
      "category": "#3c5967",
      "buttonText": "#ffffff",
      "brand": "#5d7078"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "minimal-picture-frame",
    "name": "กรอบภาพ",
    "category": "minimal",
    "themeId": "minimal",
    "layout": {
      "header": "cover",
      "links": "list",
      "button": "outline",
      "decoration": "frame",
      "avatar": "rounded"
    },
    "palette": {
      "background": "#fbfaf8",
      "gradient": "#ece7df",
      "surface": "#ffffff",
      "button": "#665440",
      "name": "#322a21",
      "description": "#726555",
      "category": "#665440",
      "buttonText": "#322a21",
      "brand": "#726555"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "minimal-open-shelf",
    "name": "ชั้นวางโปร่ง",
    "category": "minimal",
    "themeId": "minimal",
    "layout": {
      "header": "cover",
      "links": "grid",
      "button": "soft",
      "decoration": "stripe",
      "avatar": "square"
    },
    "palette": {
      "background": "#f2f5f3",
      "gradient": "#dce7df",
      "surface": "#ffffff",
      "button": "#dce7df",
      "name": "#24392c",
      "description": "#5a6a5f",
      "category": "#3b5b47",
      "buttonText": "#24392c",
      "brand": "#5a6a5f"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "minimal-stacked-paper",
    "name": "กระดาษซ้อน",
    "category": "minimal",
    "themeId": "minimal",
    "layout": {
      "header": "cover",
      "links": "grid",
      "button": "raised",
      "decoration": "none",
      "avatar": "circle"
    },
    "palette": {
      "background": "#f8f8f8",
      "gradient": "#e9eceb",
      "surface": "#ffffff",
      "button": "#3c5049",
      "name": "#273c33",
      "description": "#606d68",
      "category": "#3c5049",
      "buttonText": "#ffffff",
      "brand": "#606d68"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "minimal-studio-seal",
    "name": "ตราประจำร้าน",
    "category": "minimal",
    "themeId": "minimal",
    "layout": {
      "header": "badge",
      "links": "list",
      "button": "solid",
      "decoration": "line",
      "avatar": "rounded"
    },
    "palette": {
      "background": "#fbfbfb",
      "gradient": "#eceeee",
      "surface": "#ffffff",
      "button": "#394744",
      "name": "#202c28",
      "description": "#636d69",
      "category": "#394744",
      "buttonText": "#ffffff",
      "brand": "#636d69"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "minimal-simple-ring",
    "name": "วงแหวนเรียบ",
    "category": "minimal",
    "themeId": "minimal",
    "layout": {
      "header": "badge",
      "links": "list",
      "button": "outline",
      "decoration": "dots",
      "avatar": "square"
    },
    "palette": {
      "background": "#f5f7f6",
      "gradient": "#e3eae6",
      "surface": "#ffffff",
      "button": "#41624e",
      "name": "#243a2d",
      "description": "#5c6a5f",
      "category": "#41624e",
      "buttonText": "#243a2d",
      "brand": "#5c6a5f"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "minimal-little-spaces",
    "name": "ช่องเล็ก",
    "category": "minimal",
    "themeId": "minimal",
    "layout": {
      "header": "badge",
      "links": "grid",
      "button": "soft",
      "decoration": "frame",
      "avatar": "circle"
    },
    "palette": {
      "background": "#f7f8fa",
      "gradient": "#e5e9f0",
      "surface": "#ffffff",
      "button": "#e5e9f0",
      "name": "#26334a",
      "description": "#5c6779",
      "category": "#425470",
      "buttonText": "#26334a",
      "brand": "#5c6779"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "minimal-signature-cards",
    "name": "การ์ดลายเซ็น",
    "category": "minimal",
    "themeId": "minimal",
    "layout": {
      "header": "badge",
      "links": "grid",
      "button": "raised",
      "decoration": "stripe",
      "avatar": "rounded"
    },
    "palette": {
      "background": "#fffdf8",
      "gradient": "#eee8da",
      "surface": "#ffffff",
      "button": "#6b5639",
      "name": "#392d1c",
      "description": "#73674e",
      "category": "#6b5639",
      "buttonText": "#ffffff",
      "brand": "#73674e"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "cute-cherry-cream",
    "name": "เชอร์รี่ครีม",
    "category": "cute",
    "themeId": "pink",
    "layout": {
      "header": "centered",
      "links": "list",
      "button": "solid",
      "decoration": "frame",
      "avatar": "circle"
    },
    "palette": {
      "background": "#fff1f6",
      "gradient": "#f9dce9",
      "surface": "#fff9fc",
      "button": "#ad426a",
      "name": "#61364b",
      "description": "#7a5b6a",
      "category": "#a94067",
      "buttonText": "#ffffff",
      "brand": "#7a5b6a"
    },
    "font": "anuphan",
    "buttonRadius": "pill",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "hearts"
    }
  },
  {
    "id": "cute-paper-hearts",
    "name": "หัวใจบนกระดาษ",
    "category": "cute",
    "themeId": "pink",
    "layout": {
      "header": "centered",
      "links": "list",
      "button": "outline",
      "decoration": "stripe",
      "avatar": "circle"
    },
    "palette": {
      "background": "#fff8fa",
      "gradient": "#fbe1e8",
      "surface": "#ffffff",
      "button": "#9e4b65",
      "name": "#5c3745",
      "description": "#805f6d",
      "category": "#9e4b65",
      "buttonText": "#5c3745",
      "brand": "#805f6d"
    },
    "font": "anuphan",
    "buttonRadius": "pill",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "hearts"
    }
  },
  {
    "id": "cute-candy-box",
    "name": "กล่องขนม",
    "category": "cute",
    "themeId": "pink",
    "layout": {
      "header": "centered",
      "links": "grid",
      "button": "soft",
      "decoration": "none",
      "avatar": "circle"
    },
    "palette": {
      "background": "#faf2ff",
      "gradient": "#eadcf6",
      "surface": "#fffaff",
      "button": "#eadcf6",
      "name": "#4d345b",
      "description": "#6f5c78",
      "category": "#80519a",
      "buttonText": "#4d345b",
      "brand": "#6f5c78"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "hearts"
    }
  },
  {
    "id": "cute-marshmallow-cards",
    "name": "การ์ดมาร์ชเมลโลว์",
    "category": "cute",
    "themeId": "pink",
    "layout": {
      "header": "centered",
      "links": "grid",
      "button": "raised",
      "decoration": "line",
      "avatar": "circle"
    },
    "palette": {
      "background": "#fff5ed",
      "gradient": "#f8ddc9",
      "surface": "#fffaf4",
      "button": "#a45a3d",
      "name": "#633b2b",
      "description": "#7b5c4d",
      "category": "#945137",
      "buttonText": "#ffffff",
      "brand": "#7b5c4d"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "hearts"
    }
  },
  {
    "id": "cute-pink-notebook",
    "name": "สมุดชมพู",
    "category": "cute",
    "themeId": "pink",
    "layout": {
      "header": "left",
      "links": "list",
      "button": "solid",
      "decoration": "dots",
      "avatar": "circle"
    },
    "palette": {
      "background": "#fceef4",
      "gradient": "#f3d4e3",
      "surface": "#fff8fb",
      "button": "#a74370",
      "name": "#633449",
      "description": "#7a5365",
      "category": "#9a3e68",
      "buttonText": "#ffffff",
      "brand": "#7a5365"
    },
    "font": "anuphan",
    "buttonRadius": "pill",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "hearts"
    }
  },
  {
    "id": "cute-thin-ribbon",
    "name": "ริบบิ้นบาง",
    "category": "cute",
    "themeId": "pink",
    "layout": {
      "header": "left",
      "links": "list",
      "button": "outline",
      "decoration": "frame",
      "avatar": "circle"
    },
    "palette": {
      "background": "#fff5fb",
      "gradient": "#f4deee",
      "surface": "#ffffff",
      "button": "#95517d",
      "name": "#563447",
      "description": "#7c5c70",
      "category": "#914f7a",
      "buttonText": "#563447",
      "brand": "#7c5c70"
    },
    "font": "anuphan",
    "buttonRadius": "pill",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "hearts"
    }
  },
  {
    "id": "cute-pastel-picnic",
    "name": "ปิกนิกพาสเทล",
    "category": "cute",
    "themeId": "pink",
    "layout": {
      "header": "left",
      "links": "grid",
      "button": "soft",
      "decoration": "stripe",
      "avatar": "circle"
    },
    "palette": {
      "background": "#f1f7ff",
      "gradient": "#d7e5f7",
      "surface": "#fbfdff",
      "button": "#d7e5f7",
      "name": "#354862",
      "description": "#56667d",
      "category": "#4c6691",
      "buttonText": "#354862",
      "brand": "#56667d"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "hearts"
    }
  },
  {
    "id": "cute-sticker-layers",
    "name": "สติกเกอร์ซ้อน",
    "category": "cute",
    "themeId": "pink",
    "layout": {
      "header": "left",
      "links": "grid",
      "button": "raised",
      "decoration": "none",
      "avatar": "circle"
    },
    "palette": {
      "background": "#fdf0f3",
      "gradient": "#f3d3df",
      "surface": "#fff8fa",
      "button": "#ab4c68",
      "name": "#673c4b",
      "description": "#785561",
      "category": "#9a445e",
      "buttonText": "#ffffff",
      "brand": "#785561"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "hearts"
    }
  },
  {
    "id": "cute-tiny-friends",
    "name": "เพื่อนตัวจิ๋ว",
    "category": "cute",
    "themeId": "pink",
    "layout": {
      "header": "split",
      "links": "list",
      "button": "solid",
      "decoration": "line",
      "avatar": "circle"
    },
    "palette": {
      "background": "#f4efff",
      "gradient": "#e4d8f7",
      "surface": "#fcfaff",
      "button": "#79579d",
      "name": "#4b365d",
      "description": "#6b5978",
      "category": "#735395",
      "buttonText": "#ffffff",
      "brand": "#6b5978"
    },
    "font": "anuphan",
    "buttonRadius": "pill",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "hearts"
    }
  },
  {
    "id": "cute-love-letter",
    "name": "จดหมายรัก",
    "category": "cute",
    "themeId": "pink",
    "layout": {
      "header": "split",
      "links": "list",
      "button": "outline",
      "decoration": "dots",
      "avatar": "circle"
    },
    "palette": {
      "background": "#fff1f1",
      "gradient": "#f8dcdc",
      "surface": "#fffbfb",
      "button": "#a14e58",
      "name": "#633a40",
      "description": "#7f5c61",
      "category": "#9d4c56",
      "buttonText": "#633a40",
      "brand": "#7f5c61"
    },
    "font": "anuphan",
    "buttonRadius": "pill",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "hearts"
    }
  },
  {
    "id": "cute-bow-box",
    "name": "กล่องโบว์",
    "category": "cute",
    "themeId": "pink",
    "layout": {
      "header": "split",
      "links": "grid",
      "button": "soft",
      "decoration": "frame",
      "avatar": "circle"
    },
    "palette": {
      "background": "#fff6e9",
      "gradient": "#f3e0b8",
      "surface": "#fffcf5",
      "button": "#f3e0b8",
      "name": "#5c432b",
      "description": "#736249",
      "category": "#825e2f",
      "buttonText": "#5c432b",
      "brand": "#736249"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "hearts"
    }
  },
  {
    "id": "cute-soft-bakery",
    "name": "ขนมอบนุ่ม",
    "category": "cute",
    "themeId": "pink",
    "layout": {
      "header": "split",
      "links": "grid",
      "button": "raised",
      "decoration": "stripe",
      "avatar": "circle"
    },
    "palette": {
      "background": "#f8f0ed",
      "gradient": "#ecd9ce",
      "surface": "#fffaf6",
      "button": "#9c674e",
      "name": "#644637",
      "description": "#755c4c",
      "category": "#815540",
      "buttonText": "#ffffff",
      "brand": "#755c4c"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "hearts"
    }
  },
  {
    "id": "cute-cotton-clouds",
    "name": "เมฆฝ้าย",
    "category": "cute",
    "themeId": "pink",
    "layout": {
      "header": "cover",
      "links": "list",
      "button": "solid",
      "decoration": "none",
      "avatar": "circle"
    },
    "palette": {
      "background": "#f2f6ff",
      "gradient": "#dbe4fa",
      "surface": "#fcfdff",
      "button": "#6173a5",
      "name": "#3a4768",
      "description": "#5c667e",
      "category": "#556590",
      "buttonText": "#ffffff",
      "brand": "#5c667e"
    },
    "font": "anuphan",
    "buttonRadius": "pill",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "hearts"
    }
  },
  {
    "id": "cute-sweet-postcard",
    "name": "โปสต์การ์ดหวาน",
    "category": "cute",
    "themeId": "pink",
    "layout": {
      "header": "cover",
      "links": "list",
      "button": "outline",
      "decoration": "line",
      "avatar": "circle"
    },
    "palette": {
      "background": "#fff0f8",
      "gradient": "#f4d7e9",
      "surface": "#fffbfd",
      "button": "#a34d7d",
      "name": "#673c55",
      "description": "#735969",
      "category": "#974774",
      "buttonText": "#673c55",
      "brand": "#735969"
    },
    "font": "anuphan",
    "buttonRadius": "pill",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "hearts"
    }
  },
  {
    "id": "cute-doll-cabinet",
    "name": "ตู้ตุ๊กตา",
    "category": "cute",
    "themeId": "pink",
    "layout": {
      "header": "cover",
      "links": "grid",
      "button": "soft",
      "decoration": "dots",
      "avatar": "circle"
    },
    "palette": {
      "background": "#f7eeff",
      "gradient": "#e9d8f8",
      "surface": "#fdfaff",
      "button": "#e9d8f8",
      "name": "#53325e",
      "description": "#73587b",
      "category": "#7d4e8f",
      "buttonText": "#53325e",
      "brand": "#73587b"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "hearts"
    }
  },
  {
    "id": "cute-candy-pop",
    "name": "แคนดี้ป๊อป",
    "category": "cute",
    "themeId": "pink",
    "layout": {
      "header": "cover",
      "links": "grid",
      "button": "raised",
      "decoration": "frame",
      "avatar": "circle"
    },
    "palette": {
      "background": "#fff4ee",
      "gradient": "#f8decd",
      "surface": "#fffaf5",
      "button": "#a25942",
      "name": "#603a2b",
      "description": "#7e5e4d",
      "category": "#96523d",
      "buttonText": "#ffffff",
      "brand": "#7e5e4d"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "hearts"
    }
  },
  {
    "id": "cute-heart-seal",
    "name": "ตราหัวใจ",
    "category": "cute",
    "themeId": "pink",
    "layout": {
      "header": "badge",
      "links": "list",
      "button": "solid",
      "decoration": "stripe",
      "avatar": "circle"
    },
    "palette": {
      "background": "#fff3f6",
      "gradient": "#f5dfe5",
      "surface": "#fffafd",
      "button": "#a44a67",
      "name": "#63384b",
      "description": "#7e5c6c",
      "category": "#a04864",
      "buttonText": "#ffffff",
      "brand": "#7e5c6c"
    },
    "font": "anuphan",
    "buttonRadius": "pill",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "hearts"
    }
  },
  {
    "id": "cute-flower-petals",
    "name": "กลีบดอกไม้",
    "category": "cute",
    "themeId": "pink",
    "layout": {
      "header": "badge",
      "links": "list",
      "button": "outline",
      "decoration": "none",
      "avatar": "circle"
    },
    "palette": {
      "background": "#fcf2ff",
      "gradient": "#ecdff5",
      "surface": "#fffbff",
      "button": "#935e9b",
      "name": "#633a68",
      "description": "#775c7a",
      "category": "#815288",
      "buttonText": "#633a68",
      "brand": "#775c7a"
    },
    "font": "anuphan",
    "buttonRadius": "pill",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "hearts"
    }
  },
  {
    "id": "cute-sugar-gems",
    "name": "เพชรน้ำตาล",
    "category": "cute",
    "themeId": "pink",
    "layout": {
      "header": "badge",
      "links": "grid",
      "button": "soft",
      "decoration": "line",
      "avatar": "circle"
    },
    "palette": {
      "background": "#f2f5ff",
      "gradient": "#dce2f8",
      "surface": "#fcfdff",
      "button": "#dce2f8",
      "name": "#414665",
      "description": "#5e6279",
      "category": "#586292",
      "buttonText": "#414665",
      "brand": "#5e6279"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "hearts"
    }
  },
  {
    "id": "cute-gift-cards",
    "name": "การ์ดของขวัญ",
    "category": "cute",
    "themeId": "pink",
    "layout": {
      "header": "badge",
      "links": "grid",
      "button": "raised",
      "decoration": "dots",
      "avatar": "circle"
    },
    "palette": {
      "background": "#fff5f0",
      "gradient": "#f4ded2",
      "surface": "#fffaf8",
      "button": "#a4604c",
      "name": "#673e31",
      "description": "#785f53",
      "category": "#905443",
      "buttonText": "#ffffff",
      "brand": "#785f53"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "hearts"
    }
  },
  {
    "id": "nature-olive-garden",
    "name": "สวนมะกอก",
    "category": "nature",
    "themeId": "garden",
    "layout": {
      "header": "centered",
      "links": "list",
      "button": "outline",
      "decoration": "line",
      "avatar": "rounded"
    },
    "palette": {
      "background": "#fffaf0",
      "gradient": "#ece7d5",
      "surface": "#fffef8",
      "button": "#718852",
      "name": "#35472c",
      "description": "#626b56",
      "category": "#596d45",
      "buttonText": "#35472c",
      "brand": "#626b56"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "flowers"
    }
  },
  {
    "id": "nature-morning-garden",
    "name": "สวนเช้า",
    "category": "nature",
    "themeId": "garden",
    "layout": {
      "header": "centered",
      "links": "list",
      "button": "solid",
      "decoration": "line",
      "avatar": "circle"
    },
    "palette": {
      "background": "#fffaf0",
      "gradient": "#eee8d8",
      "surface": "#fffef9",
      "button": "#5b7448",
      "name": "#34452c",
      "description": "#616a57",
      "category": "#566e44",
      "buttonText": "#ffffff",
      "brand": "#616a57"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "flowers"
    }
  },
  {
    "id": "nature-clay-pots",
    "name": "กระถางดิน",
    "category": "nature",
    "themeId": "garden",
    "layout": {
      "header": "centered",
      "links": "grid",
      "button": "soft",
      "decoration": "frame",
      "avatar": "square"
    },
    "palette": {
      "background": "#f7efe4",
      "gradient": "#e4d2ba",
      "surface": "#fffaf1",
      "button": "#e4d2ba",
      "name": "#543b29",
      "description": "#675847",
      "category": "#7f5235",
      "buttonText": "#543b29",
      "brand": "#675847"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "flowers"
    }
  },
  {
    "id": "nature-leaf-cards",
    "name": "การ์ดใบไม้",
    "category": "nature",
    "themeId": "garden",
    "layout": {
      "header": "centered",
      "links": "grid",
      "button": "raised",
      "decoration": "stripe",
      "avatar": "circle"
    },
    "palette": {
      "background": "#f2f5e9",
      "gradient": "#dfe7cb",
      "surface": "#fcfff6",
      "button": "#5b7142",
      "name": "#344a2b",
      "description": "#5c684f",
      "category": "#566b3f",
      "buttonText": "#ffffff",
      "brand": "#5c684f"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "flowers"
    }
  },
  {
    "id": "nature-craft-studio",
    "name": "งานคราฟต์",
    "category": "nature",
    "themeId": "garden",
    "layout": {
      "header": "left",
      "links": "list",
      "button": "solid",
      "decoration": "none",
      "avatar": "rounded"
    },
    "palette": {
      "background": "#f7efe2",
      "gradient": "#e6d8bf",
      "surface": "#fffaf2",
      "button": "#87633e",
      "name": "#4f3f2c",
      "description": "#665b4a",
      "category": "#7a5938",
      "buttonText": "#ffffff",
      "brand": "#665b4a"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "flowers"
    }
  },
  {
    "id": "nature-paper-fibers",
    "name": "เส้นใยกระดาษ",
    "category": "nature",
    "themeId": "garden",
    "layout": {
      "header": "left",
      "links": "list",
      "button": "outline",
      "decoration": "line",
      "avatar": "square"
    },
    "palette": {
      "background": "#f9f5ea",
      "gradient": "#e9e2cf",
      "surface": "#fffdf6",
      "button": "#756847",
      "name": "#473f2d",
      "description": "#6a6453",
      "category": "#6f6343",
      "buttonText": "#473f2d",
      "brand": "#6a6453"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "flowers"
    }
  },
  {
    "id": "nature-wooden-desk",
    "name": "โต๊ะไม้",
    "category": "nature",
    "themeId": "garden",
    "layout": {
      "header": "left",
      "links": "grid",
      "button": "soft",
      "decoration": "dots",
      "avatar": "circle"
    },
    "palette": {
      "background": "#f3eee5",
      "gradient": "#dfd1bd",
      "surface": "#fffbf4",
      "button": "#dfd1bd",
      "name": "#443725",
      "description": "#635848",
      "category": "#6f5534",
      "buttonText": "#443725",
      "brand": "#635848"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "flowers"
    }
  },
  {
    "id": "nature-pressed-notebook",
    "name": "สมุดแห้ง",
    "category": "nature",
    "themeId": "garden",
    "layout": {
      "header": "left",
      "links": "grid",
      "button": "raised",
      "decoration": "frame",
      "avatar": "rounded"
    },
    "palette": {
      "background": "#f0f3e7",
      "gradient": "#d9e1c7",
      "surface": "#fcfff7",
      "button": "#5f7548",
      "name": "#3d4d31",
      "description": "#5b6250",
      "category": "#53663f",
      "buttonText": "#ffffff",
      "brand": "#5b6250"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "flowers"
    }
  },
  {
    "id": "nature-leaf-pair",
    "name": "ใบไม้ข้างชื่อ",
    "category": "nature",
    "themeId": "garden",
    "layout": {
      "header": "split",
      "links": "list",
      "button": "solid",
      "decoration": "stripe",
      "avatar": "square"
    },
    "palette": {
      "background": "#f5f9ed",
      "gradient": "#e1eccb",
      "surface": "#fcfff8",
      "button": "#567a41",
      "name": "#35542c",
      "description": "#5b6a56",
      "category": "#50713c",
      "buttonText": "#ffffff",
      "brand": "#5b6a56"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "flowers"
    }
  },
  {
    "id": "nature-grass-lines",
    "name": "ก้านหญ้า",
    "category": "nature",
    "themeId": "garden",
    "layout": {
      "header": "split",
      "links": "list",
      "button": "outline",
      "decoration": "none",
      "avatar": "circle"
    },
    "palette": {
      "background": "#faf8ed",
      "gradient": "#e9e5ce",
      "surface": "#fffef7",
      "button": "#7a7540",
      "name": "#4b482b",
      "description": "#67654d",
      "category": "#6b6638",
      "buttonText": "#4b482b",
      "brand": "#67654d"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "flowers"
    }
  },
  {
    "id": "nature-garden-basket",
    "name": "ตะกร้าสวน",
    "category": "nature",
    "themeId": "garden",
    "layout": {
      "header": "split",
      "links": "grid",
      "button": "soft",
      "decoration": "line",
      "avatar": "rounded"
    },
    "palette": {
      "background": "#f2f5ed",
      "gradient": "#dfe8d5",
      "surface": "#fcfff9",
      "button": "#dfe8d5",
      "name": "#384d30",
      "description": "#5b6a56",
      "category": "#576d4b",
      "buttonText": "#384d30",
      "brand": "#5b6a56"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "flowers"
    }
  },
  {
    "id": "nature-wood-layers",
    "name": "แผ่นไม้ซ้อน",
    "category": "nature",
    "themeId": "garden",
    "layout": {
      "header": "split",
      "links": "grid",
      "button": "raised",
      "decoration": "dots",
      "avatar": "square"
    },
    "palette": {
      "background": "#f8efe5",
      "gradient": "#e9d7c1",
      "surface": "#fffaf3",
      "button": "#926644",
      "name": "#5c422d",
      "description": "#6b5b47",
      "category": "#7c573a",
      "buttonText": "#ffffff",
      "brand": "#6b5b47"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "flowers"
    }
  },
  {
    "id": "nature-garden-veranda",
    "name": "ระเบียงสวน",
    "category": "nature",
    "themeId": "garden",
    "layout": {
      "header": "cover",
      "links": "list",
      "button": "solid",
      "decoration": "frame",
      "avatar": "circle"
    },
    "palette": {
      "background": "#f7fbef",
      "gradient": "#e3eed0",
      "surface": "#fdfff7",
      "button": "#56783f",
      "name": "#38562e",
      "description": "#606d54",
      "category": "#52723c",
      "buttonText": "#ffffff",
      "brand": "#606d54"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "flowers"
    }
  },
  {
    "id": "nature-linen-frame",
    "name": "กรอบลินิน",
    "category": "nature",
    "themeId": "garden",
    "layout": {
      "header": "cover",
      "links": "list",
      "button": "outline",
      "decoration": "stripe",
      "avatar": "rounded"
    },
    "palette": {
      "background": "#faf6ec",
      "gradient": "#eae1ce",
      "surface": "#fffdf8",
      "button": "#7c7051",
      "name": "#4f4836",
      "description": "#6b6454",
      "category": "#6d6247",
      "buttonText": "#4f4836",
      "brand": "#6b6454"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "flowers"
    }
  },
  {
    "id": "nature-flower-shelf",
    "name": "ชั้นดอกไม้",
    "category": "nature",
    "themeId": "garden",
    "layout": {
      "header": "cover",
      "links": "grid",
      "button": "soft",
      "decoration": "none",
      "avatar": "square"
    },
    "palette": {
      "background": "#fcf8ed",
      "gradient": "#eee4c9",
      "surface": "#fffdf6",
      "button": "#eee4c9",
      "name": "#4c482b",
      "description": "#696550",
      "category": "#6c673f",
      "buttonText": "#4c482b",
      "brand": "#696550"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "flowers"
    }
  },
  {
    "id": "nature-forest-postcard",
    "name": "โปสต์การ์ดป่า",
    "category": "nature",
    "themeId": "garden",
    "layout": {
      "header": "cover",
      "links": "grid",
      "button": "raised",
      "decoration": "line",
      "avatar": "circle"
    },
    "palette": {
      "background": "#eef5ed",
      "gradient": "#d1e2cc",
      "surface": "#fafff8",
      "button": "#4d7048",
      "name": "#2f492b",
      "description": "#536450",
      "category": "#496a44",
      "buttonText": "#ffffff",
      "brand": "#536450"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "flowers"
    }
  },
  {
    "id": "nature-leaf-seal",
    "name": "ตราใบไม้",
    "category": "nature",
    "themeId": "garden",
    "layout": {
      "header": "badge",
      "links": "list",
      "button": "solid",
      "decoration": "dots",
      "avatar": "rounded"
    },
    "palette": {
      "background": "#f3f7e9",
      "gradient": "#dfebca",
      "surface": "#fcfff7",
      "button": "#657d40",
      "name": "#3c4d29",
      "description": "#5d6a51",
      "category": "#586d38",
      "buttonText": "#ffffff",
      "brand": "#5d6a51"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "flowers"
    }
  },
  {
    "id": "nature-little-wreath",
    "name": "พวงดอกเล็ก",
    "category": "nature",
    "themeId": "garden",
    "layout": {
      "header": "badge",
      "links": "list",
      "button": "outline",
      "decoration": "frame",
      "avatar": "square"
    },
    "palette": {
      "background": "#fbf6eb",
      "gradient": "#eee1c7",
      "surface": "#fffdf7",
      "button": "#816d42",
      "name": "#55472c",
      "description": "#6b614d",
      "category": "#74623b",
      "buttonText": "#55472c",
      "brand": "#6b614d"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "flowers"
    }
  },
  {
    "id": "nature-greenhouse",
    "name": "เรือนกระจก",
    "category": "nature",
    "themeId": "garden",
    "layout": {
      "header": "badge",
      "links": "grid",
      "button": "soft",
      "decoration": "stripe",
      "avatar": "circle"
    },
    "palette": {
      "background": "#edf6f1",
      "gradient": "#cfe5d9",
      "surface": "#f8fffb",
      "button": "#cfe5d9",
      "name": "#2c5042",
      "description": "#51685c",
      "category": "#426a57",
      "buttonText": "#2c5042",
      "brand": "#51685c"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "flowers"
    }
  },
  {
    "id": "nature-herbal-tea",
    "name": "การ์ดชาสมุนไพร",
    "category": "nature",
    "themeId": "garden",
    "layout": {
      "header": "badge",
      "links": "grid",
      "button": "raised",
      "decoration": "none",
      "avatar": "rounded"
    },
    "palette": {
      "background": "#f5f3e6",
      "gradient": "#e2dfc3",
      "surface": "#fffdf5",
      "button": "#75763f",
      "name": "#484927",
      "description": "#5e614a",
      "category": "#636436",
      "buttonText": "#ffffff",
      "brand": "#5e614a"
    },
    "font": "anuphan",
    "buttonRadius": "rounded",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "flowers"
    }
  },
  {
    "id": "luxury-gold-seal",
    "name": "ตราทอง",
    "category": "luxury",
    "themeId": "dark",
    "layout": {
      "header": "badge",
      "links": "list",
      "button": "outline",
      "decoration": "frame",
      "avatar": "square"
    },
    "palette": {
      "background": "#151619",
      "gradient": "#29282b",
      "surface": "#1c1e23",
      "button": "#bd9b5d",
      "name": "#f6eedf",
      "description": "#b7a68c",
      "category": "#bd9b5d",
      "buttonText": "#f6eedf",
      "brand": "#b7a68c"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "luxury-emerald-room",
    "name": "ห้องมรกต",
    "category": "luxury",
    "themeId": "dark",
    "layout": {
      "header": "centered",
      "links": "list",
      "button": "solid",
      "decoration": "frame",
      "avatar": "square"
    },
    "palette": {
      "background": "#10201c",
      "gradient": "#213a31",
      "surface": "#172c25",
      "button": "#aecd98",
      "name": "#eef5e7",
      "description": "#b4c4b5",
      "category": "#aecd98",
      "buttonText": "#18201b",
      "brand": "#b4c4b5"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "luxury-gold-lines",
    "name": "เส้นทอง",
    "category": "luxury",
    "themeId": "dark",
    "layout": {
      "header": "centered",
      "links": "list",
      "button": "outline",
      "decoration": "stripe",
      "avatar": "square"
    },
    "palette": {
      "background": "#171717",
      "gradient": "#302b22",
      "surface": "#20201f",
      "button": "#c9a56a",
      "name": "#f5eddf",
      "description": "#b6ad9d",
      "category": "#c9a56a",
      "buttonText": "#f5eddf",
      "brand": "#b6ad9d"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "luxury-gem-box",
    "name": "กล่องอัญมณี",
    "category": "luxury",
    "themeId": "dark",
    "layout": {
      "header": "centered",
      "links": "grid",
      "button": "soft",
      "decoration": "none",
      "avatar": "square"
    },
    "palette": {
      "background": "#111d2b",
      "gradient": "#25364e",
      "surface": "#1c2b3d",
      "button": "#25364e",
      "name": "#f0f5fc",
      "description": "#a6b7cc",
      "category": "#a3bddb",
      "buttonText": "#f0f5fc",
      "brand": "#a6b7cc"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "luxury-velvet-cards",
    "name": "การ์ดกำมะหยี่",
    "category": "luxury",
    "themeId": "dark",
    "layout": {
      "header": "centered",
      "links": "grid",
      "button": "raised",
      "decoration": "line",
      "avatar": "square"
    },
    "palette": {
      "background": "#281522",
      "gradient": "#4c2b43",
      "surface": "#351d2e",
      "button": "#d1a4c1",
      "name": "#fcf0f8",
      "description": "#bda4b8",
      "category": "#d1a4c1",
      "buttonText": "#18201b",
      "brand": "#bda4b8"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "luxury-black-studio",
    "name": "แบล็กสตูดิโอ",
    "category": "luxury",
    "themeId": "dark",
    "layout": {
      "header": "left",
      "links": "list",
      "button": "solid",
      "decoration": "dots",
      "avatar": "square"
    },
    "palette": {
      "background": "#141519",
      "gradient": "#2b2e35",
      "surface": "#1e2026",
      "button": "#c5bdab",
      "name": "#f4f1e9",
      "description": "#aca99f",
      "category": "#c5bdab",
      "buttonText": "#18201b",
      "brand": "#aca99f"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "luxury-silver-signature",
    "name": "ลายเซ็นเงิน",
    "category": "luxury",
    "themeId": "dark",
    "layout": {
      "header": "left",
      "links": "list",
      "button": "outline",
      "decoration": "frame",
      "avatar": "square"
    },
    "palette": {
      "background": "#161b21",
      "gradient": "#2b3440",
      "surface": "#202832",
      "button": "#bcc9d5",
      "name": "#edf2f7",
      "description": "#a1b0be",
      "category": "#bcc9d5",
      "buttonText": "#edf2f7",
      "brand": "#a1b0be"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "luxury-wine-grid",
    "name": "ตารางไวน์",
    "category": "luxury",
    "themeId": "dark",
    "layout": {
      "header": "left",
      "links": "grid",
      "button": "soft",
      "decoration": "stripe",
      "avatar": "square"
    },
    "palette": {
      "background": "#261319",
      "gradient": "#48212c",
      "surface": "#341b23",
      "button": "#48212c",
      "name": "#fcf0f1",
      "description": "#c0a0a7",
      "category": "#d3a0ab",
      "buttonText": "#fcf0f1",
      "brand": "#c0a0a7"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "luxury-ink-cards",
    "name": "การ์ดน้ำหมึก",
    "category": "luxury",
    "themeId": "dark",
    "layout": {
      "header": "left",
      "links": "grid",
      "button": "raised",
      "decoration": "none",
      "avatar": "square"
    },
    "palette": {
      "background": "#111a27",
      "gradient": "#253249",
      "surface": "#1b2738",
      "button": "#b1bed4",
      "name": "#edf2fa",
      "description": "#9daec5",
      "category": "#b1bed4",
      "buttonText": "#18201b",
      "brand": "#9daec5"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "luxury-paired-monogram",
    "name": "โมโนแกรมคู่",
    "category": "luxury",
    "themeId": "dark",
    "layout": {
      "header": "split",
      "links": "list",
      "button": "solid",
      "decoration": "line",
      "avatar": "square"
    },
    "palette": {
      "background": "#181b18",
      "gradient": "#32382d",
      "surface": "#232821",
      "button": "#c1bc9f",
      "name": "#f2f1e7",
      "description": "#acaf9f",
      "category": "#c1bc9f",
      "buttonText": "#18201b",
      "brand": "#acaf9f"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "luxury-champagne-lines",
    "name": "เส้นแชมเปญ",
    "category": "luxury",
    "themeId": "dark",
    "layout": {
      "header": "split",
      "links": "list",
      "button": "outline",
      "decoration": "dots",
      "avatar": "square"
    },
    "palette": {
      "background": "#211b14",
      "gradient": "#403627",
      "surface": "#2c261d",
      "button": "#cfb584",
      "name": "#fcf5e7",
      "description": "#bdb19b",
      "category": "#cfb584",
      "buttonText": "#fcf5e7",
      "brand": "#bdb19b"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "luxury-pearl-box",
    "name": "กล่องไข่มุก",
    "category": "luxury",
    "themeId": "dark",
    "layout": {
      "header": "split",
      "links": "grid",
      "button": "soft",
      "decoration": "frame",
      "avatar": "square"
    },
    "palette": {
      "background": "#f6f1e8",
      "gradient": "#e7dcc9",
      "surface": "#fffdf8",
      "button": "#e7dcc9",
      "name": "#403628",
      "description": "#6d604e",
      "category": "#725d40",
      "buttonText": "#403628",
      "brand": "#6d604e"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "luxury-marble-shelf",
    "name": "ชั้นหินอ่อน",
    "category": "luxury",
    "themeId": "dark",
    "layout": {
      "header": "split",
      "links": "grid",
      "button": "raised",
      "decoration": "stripe",
      "avatar": "square"
    },
    "palette": {
      "background": "#eae7e2",
      "gradient": "#d5cec2",
      "surface": "#f8f6f2",
      "button": "#625c50",
      "name": "#312e28",
      "description": "#5d584f",
      "category": "#5d574c",
      "buttonText": "#ffffff",
      "brand": "#5d584f"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "luxury-black-gallery",
    "name": "แกลเลอรีดำ",
    "category": "luxury",
    "themeId": "dark",
    "layout": {
      "header": "cover",
      "links": "list",
      "button": "solid",
      "decoration": "none",
      "avatar": "square"
    },
    "palette": {
      "background": "#111214",
      "gradient": "#26282d",
      "surface": "#1b1d21",
      "button": "#bcae93",
      "name": "#f6f1e8",
      "description": "#aaa293",
      "category": "#bcae93",
      "buttonText": "#18201b",
      "brand": "#aaa293"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "luxury-brass-frame",
    "name": "กรอบทองเหลือง",
    "category": "luxury",
    "themeId": "dark",
    "layout": {
      "header": "cover",
      "links": "list",
      "button": "outline",
      "decoration": "line",
      "avatar": "square"
    },
    "palette": {
      "background": "#1b1915",
      "gradient": "#393124",
      "surface": "#27221b",
      "button": "#c6a36e",
      "name": "#faf1e2",
      "description": "#b8ab94",
      "category": "#c6a36e",
      "buttonText": "#faf1e2",
      "brand": "#b8ab94"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "luxury-jewel-cabinet",
    "name": "ตู้เครื่องประดับ",
    "category": "luxury",
    "themeId": "dark",
    "layout": {
      "header": "cover",
      "links": "grid",
      "button": "soft",
      "decoration": "dots",
      "avatar": "square"
    },
    "palette": {
      "background": "#162021",
      "gradient": "#2e3d3d",
      "surface": "#21302f",
      "button": "#2e3d3d",
      "name": "#edf6f1",
      "description": "#a1b5ac",
      "category": "#acc3bb",
      "buttonText": "#edf6f1",
      "brand": "#a1b5ac"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "luxury-premium-album",
    "name": "อัลบั้มพรีเมียม",
    "category": "luxury",
    "themeId": "dark",
    "layout": {
      "header": "cover",
      "links": "grid",
      "button": "raised",
      "decoration": "frame",
      "avatar": "square"
    },
    "palette": {
      "background": "#1d1825",
      "gradient": "#383045",
      "surface": "#292233",
      "button": "#bdb0d1",
      "name": "#f5effb",
      "description": "#aaa0b8",
      "category": "#bdb0d1",
      "buttonText": "#18201b",
      "brand": "#aaa0b8"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "luxury-premium-seal",
    "name": "ตราร้านพรีเมียม",
    "category": "luxury",
    "themeId": "dark",
    "layout": {
      "header": "badge",
      "links": "list",
      "button": "solid",
      "decoration": "stripe",
      "avatar": "square"
    },
    "palette": {
      "background": "#151b18",
      "gradient": "#303b32",
      "surface": "#212c24",
      "button": "#b6c5a4",
      "name": "#f2f6e9",
      "description": "#a6b3a0",
      "category": "#b6c5a4",
      "buttonText": "#18201b",
      "brand": "#a6b3a0"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "luxury-onyx-seal",
    "name": "ตรานิล",
    "category": "luxury",
    "themeId": "dark",
    "layout": {
      "header": "badge",
      "links": "grid",
      "button": "soft",
      "decoration": "line",
      "avatar": "square"
    },
    "palette": {
      "background": "#15171c",
      "gradient": "#292e37",
      "surface": "#20252d",
      "button": "#292e37",
      "name": "#f0f4fb",
      "description": "#a0adbf",
      "category": "#b9c6da",
      "buttonText": "#f0f4fb",
      "brand": "#a0adbf"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "luxury-platinum-cards",
    "name": "การ์ดแพลทินัม",
    "category": "luxury",
    "themeId": "dark",
    "layout": {
      "header": "badge",
      "links": "grid",
      "button": "raised",
      "decoration": "dots",
      "avatar": "square"
    },
    "palette": {
      "background": "#1b1c20",
      "gradient": "#34363d",
      "surface": "#26282e",
      "button": "#c3c8d1",
      "name": "#f4f5f7",
      "description": "#b0b4bc",
      "category": "#c3c8d1",
      "buttonText": "#18201b",
      "brand": "#b0b4bc"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": false,
      "entrance": true,
      "featured": false,
      "stickers": "none"
    }
  },
  {
    "id": "creative-yellow-pop",
    "name": "เหลืองป๊อป",
    "category": "creative",
    "themeId": "shop",
    "layout": {
      "header": "left",
      "links": "grid",
      "button": "raised",
      "decoration": "line",
      "avatar": "rounded"
    },
    "palette": {
      "background": "#fff09d",
      "gradient": "#ffe15d",
      "surface": "#fff7c8",
      "button": "#f0ce37",
      "name": "#242522",
      "description": "#6e643f",
      "category": "#72621a",
      "buttonText": "#242522",
      "brand": "#6e643f"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "sparkles"
    }
  },
  {
    "id": "creative-pop-sunday",
    "name": "ป๊อปซันเดย์",
    "category": "creative",
    "themeId": "shop",
    "layout": {
      "header": "centered",
      "links": "list",
      "button": "solid",
      "decoration": "stripe",
      "avatar": "circle"
    },
    "palette": {
      "background": "#fff4c4",
      "gradient": "#ffe484",
      "surface": "#fffbe5",
      "button": "#c13b1b",
      "name": "#2d2218",
      "description": "#795c38",
      "category": "#b7381a",
      "buttonText": "#ffffff",
      "brand": "#795c38"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "sparkles"
    }
  },
  {
    "id": "creative-vivid-lines",
    "name": "เส้นสีจัด",
    "category": "creative",
    "themeId": "shop",
    "layout": {
      "header": "centered",
      "links": "list",
      "button": "outline",
      "decoration": "none",
      "avatar": "rounded"
    },
    "palette": {
      "background": "#f2efff",
      "gradient": "#d9d0ff",
      "surface": "#faf8ff",
      "button": "#6441a3",
      "name": "#30234d",
      "description": "#65577a",
      "category": "#6441a3",
      "buttonText": "#30234d",
      "brand": "#65577a"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "sparkles"
    }
  },
  {
    "id": "creative-play-blocks",
    "name": "บล็อกขี้เล่น",
    "category": "creative",
    "themeId": "shop",
    "layout": {
      "header": "centered",
      "links": "grid",
      "button": "soft",
      "decoration": "line",
      "avatar": "square"
    },
    "palette": {
      "background": "#edfff8",
      "gradient": "#c9f4e0",
      "surface": "#f7fffc",
      "button": "#c9f4e0",
      "name": "#173c33",
      "description": "#4b6f64",
      "category": "#206b59",
      "buttonText": "#173c33",
      "brand": "#4b6f64"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "sparkles"
    }
  },
  {
    "id": "creative-stacked-posters",
    "name": "โปสเตอร์ซ้อน",
    "category": "creative",
    "themeId": "shop",
    "layout": {
      "header": "centered",
      "links": "grid",
      "button": "raised",
      "decoration": "dots",
      "avatar": "circle"
    },
    "palette": {
      "background": "#fff0ee",
      "gradient": "#ffc9bd",
      "surface": "#fff8f6",
      "button": "#b94637",
      "name": "#48291f",
      "description": "#7a5446",
      "category": "#9d3c2f",
      "buttonText": "#ffffff",
      "brand": "#7a5446"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "sparkles"
    }
  },
  {
    "id": "creative-yellow-studio",
    "name": "สตูดิโอเหลือง",
    "category": "creative",
    "themeId": "shop",
    "layout": {
      "header": "left",
      "links": "list",
      "button": "solid",
      "decoration": "frame",
      "avatar": "rounded"
    },
    "palette": {
      "background": "#fff1a1",
      "gradient": "#ffdc4e",
      "surface": "#fff8d6",
      "button": "#e9c62d",
      "name": "#242522",
      "description": "#686244",
      "category": "#6f5e15",
      "buttonText": "#242522",
      "brand": "#686244"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "sparkles"
    }
  },
  {
    "id": "creative-marker-notes",
    "name": "โน้ตปากกา",
    "category": "creative",
    "themeId": "shop",
    "layout": {
      "header": "left",
      "links": "list",
      "button": "outline",
      "decoration": "stripe",
      "avatar": "square"
    },
    "palette": {
      "background": "#f3f4ff",
      "gradient": "#d6ddff",
      "surface": "#fafbff",
      "button": "#4860aa",
      "name": "#283358",
      "description": "#57627c",
      "category": "#465ea6",
      "buttonText": "#283358",
      "brand": "#57627c"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "sparkles"
    }
  },
  {
    "id": "creative-collage-grid",
    "name": "ตารางคอลลาจ",
    "category": "creative",
    "themeId": "shop",
    "layout": {
      "header": "left",
      "links": "grid",
      "button": "soft",
      "decoration": "none",
      "avatar": "circle"
    },
    "palette": {
      "background": "#fff4ee",
      "gradient": "#ffdec8",
      "surface": "#fffaf6",
      "button": "#ffdec8",
      "name": "#542f1c",
      "description": "#825e4a",
      "category": "#a24d29",
      "buttonText": "#542f1c",
      "brand": "#825e4a"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "sparkles"
    }
  },
  {
    "id": "creative-blue-pair",
    "name": "คู่สีฟ้า",
    "category": "creative",
    "themeId": "shop",
    "layout": {
      "header": "split",
      "links": "list",
      "button": "solid",
      "decoration": "dots",
      "avatar": "square"
    },
    "palette": {
      "background": "#e9f7ff",
      "gradient": "#bce3ff",
      "surface": "#f4fbff",
      "button": "#2869ac",
      "name": "#193c65",
      "description": "#4d637a",
      "category": "#2664a3",
      "buttonText": "#ffffff",
      "brand": "#4d637a"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "sparkles"
    }
  },
  {
    "id": "creative-ink-frame",
    "name": "กรอบหมึก",
    "category": "creative",
    "themeId": "shop",
    "layout": {
      "header": "split",
      "links": "list",
      "button": "outline",
      "decoration": "frame",
      "avatar": "circle"
    },
    "palette": {
      "background": "#fff3ec",
      "gradient": "#f5c7a2",
      "surface": "#fffbf7",
      "button": "#914b28",
      "name": "#4c2d1a",
      "description": "#6a5341",
      "category": "#8a4726",
      "buttonText": "#4c2d1a",
      "brand": "#6a5341"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "sparkles"
    }
  },
  {
    "id": "creative-comic-panels",
    "name": "ช่องคอมิก",
    "category": "creative",
    "themeId": "shop",
    "layout": {
      "header": "split",
      "links": "grid",
      "button": "soft",
      "decoration": "stripe",
      "avatar": "rounded"
    },
    "palette": {
      "background": "#f8edff",
      "gradient": "#e6c9fa",
      "surface": "#fdf8ff",
      "button": "#e6c9fa",
      "name": "#462357",
      "description": "#6f4e7e",
      "category": "#7e39a6",
      "buttonText": "#462357",
      "brand": "#6f4e7e"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "sparkles"
    }
  },
  {
    "id": "creative-neon-blocks",
    "name": "บล็อกนีออน",
    "category": "creative",
    "themeId": "shop",
    "layout": {
      "header": "split",
      "links": "grid",
      "button": "raised",
      "decoration": "none",
      "avatar": "square"
    },
    "palette": {
      "background": "#e8fbf2",
      "gradient": "#a9edcc",
      "surface": "#f4fff9",
      "button": "#225c42",
      "name": "#1d3a2b",
      "description": "#4a6557",
      "category": "#225c42",
      "buttonText": "#ffffff",
      "brand": "#4a6557"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "sparkles"
    }
  },
  {
    "id": "creative-retro-cover",
    "name": "หน้าปกเรโทร",
    "category": "creative",
    "themeId": "shop",
    "layout": {
      "header": "cover",
      "links": "list",
      "button": "solid",
      "decoration": "line",
      "avatar": "circle"
    },
    "palette": {
      "background": "#fff0c8",
      "gradient": "#edcb6e",
      "surface": "#fffae8",
      "button": "#a3592b",
      "name": "#493016",
      "description": "#6a5236",
      "category": "#824722",
      "buttonText": "#ffffff",
      "brand": "#6a5236"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "sparkles"
    }
  },
  {
    "id": "creative-fun-frame",
    "name": "เฟรมสีสนุก",
    "category": "creative",
    "themeId": "shop",
    "layout": {
      "header": "cover",
      "links": "list",
      "button": "outline",
      "decoration": "dots",
      "avatar": "rounded"
    },
    "palette": {
      "background": "#ffeaf0",
      "gradient": "#f7b8d0",
      "surface": "#fff5f8",
      "button": "#aa356e",
      "name": "#57223d",
      "description": "#71465c",
      "category": "#912d5e",
      "buttonText": "#57223d",
      "brand": "#71465c"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "sparkles"
    }
  },
  {
    "id": "creative-color-cabinet",
    "name": "ตู้สีสด",
    "category": "creative",
    "themeId": "shop",
    "layout": {
      "header": "cover",
      "links": "grid",
      "button": "soft",
      "decoration": "frame",
      "avatar": "square"
    },
    "palette": {
      "background": "#e8f5ff",
      "gradient": "#b6d7f4",
      "surface": "#f6fbff",
      "button": "#b6d7f4",
      "name": "#254360",
      "description": "#4a5c6d",
      "category": "#385e83",
      "buttonText": "#254360",
      "brand": "#4a5c6d"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "sparkles"
    }
  },
  {
    "id": "creative-modern-layers",
    "name": "ปกซ้อนยุคใหม่",
    "category": "creative",
    "themeId": "shop",
    "layout": {
      "header": "cover",
      "links": "grid",
      "button": "raised",
      "decoration": "stripe",
      "avatar": "circle"
    },
    "palette": {
      "background": "#f2f1e9",
      "gradient": "#d7d49a",
      "surface": "#fffef6",
      "button": "#6f7128",
      "name": "#393b19",
      "description": "#595a3b",
      "category": "#5c5d21",
      "buttonText": "#ffffff",
      "brand": "#595a3b"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "sparkles"
    }
  },
  {
    "id": "creative-orange-seal",
    "name": "ตราสีส้ม",
    "category": "creative",
    "themeId": "shop",
    "layout": {
      "header": "badge",
      "links": "list",
      "button": "solid",
      "decoration": "none",
      "avatar": "rounded"
    },
    "palette": {
      "background": "#fff0e5",
      "gradient": "#f6b890",
      "surface": "#fff8f1",
      "button": "#b54c1f",
      "name": "#5c301b",
      "description": "#654b39",
      "category": "#883917",
      "buttonText": "#ffffff",
      "brand": "#654b39"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "sparkles"
    }
  },
  {
    "id": "creative-pop-ring",
    "name": "วงแหวนป๊อป",
    "category": "creative",
    "themeId": "shop",
    "layout": {
      "header": "badge",
      "links": "list",
      "button": "outline",
      "decoration": "line",
      "avatar": "square"
    },
    "palette": {
      "background": "#edf5ff",
      "gradient": "#b5d3fa",
      "surface": "#f7fbff",
      "button": "#356bb3",
      "name": "#233e68",
      "description": "#475a70",
      "category": "#2c5894",
      "buttonText": "#233e68",
      "brand": "#475a70"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "sparkles"
    }
  },
  {
    "id": "creative-color-patches",
    "name": "แพตช์หลากสี",
    "category": "creative",
    "themeId": "shop",
    "layout": {
      "header": "badge",
      "links": "grid",
      "button": "soft",
      "decoration": "dots",
      "avatar": "circle"
    },
    "palette": {
      "background": "#f5edff",
      "gradient": "#d5bafb",
      "surface": "#fcf8ff",
      "button": "#d5bafb",
      "name": "#47285e",
      "description": "#60476f",
      "category": "#6b3c96",
      "buttonText": "#47285e",
      "brand": "#60476f"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "sparkles"
    }
  },
  {
    "id": "creative-contrast-cards",
    "name": "การ์ดสีตัด",
    "category": "creative",
    "themeId": "shop",
    "layout": {
      "header": "badge",
      "links": "grid",
      "button": "raised",
      "decoration": "frame",
      "avatar": "rounded"
    },
    "palette": {
      "background": "#fff5d8",
      "gradient": "#ead169",
      "surface": "#fffcf0",
      "button": "#88612b",
      "name": "#423017",
      "description": "#67563c",
      "category": "#745225",
      "buttonText": "#ffffff",
      "brand": "#67563c"
    },
    "font": "prompt",
    "buttonRadius": "square",
    "effects": {
      "background": true,
      "entrance": true,
      "featured": false,
      "stickers": "sparkles"
    }
  }
];

const templatesById = new Map(profileTemplates.map((template) => [template.id, template]));
export const getProfileTemplate = (id: string | null | undefined): ProfileTemplateDefinition | undefined => typeof id === 'string' ? templatesById.get(id) : undefined;
