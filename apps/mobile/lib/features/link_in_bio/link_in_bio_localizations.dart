import 'package:flutter/material.dart';

import '../../core/localization/postdee_localizations.dart';

bool linkInBioUsesThai(BuildContext context) =>
    (Localizations.of<PostDeeLocalizations>(context, PostDeeLocalizations)
            ?.locale
            .languageCode ??
        'th') ==
    'th';

String linkInBioText(BuildContext context, String thai, String english) =>
    linkInBioUsesThai(context) ? thai : english;

/// Use only for app-owned copy. Store names, link labels and other customer
/// content must be rendered directly, even when they match a translation key.
String localizeLinkInBioMessage(BuildContext context, String message) {
  if (linkInBioUsesThai(context)) return message;
  final translated = _englishMessages[message];
  if (translated != null) return translated;
  final addition = RegExp(
    r'^แพ็กเกจนี้เพิ่มได้สูงสุด (\d+) ลิงก์ รวมลิงก์ที่ปิดไว้ หากต้องการเพิ่ม ให้ลบลิงก์เดิมหรืออัปเกรดแพ็กเกจ$',
  ).firstMatch(message);
  if (addition != null) {
    return 'Your plan allows up to ${addition[1]} links, including hidden links. Delete an existing link or upgrade your plan to add another.';
  }
  final publishLimit = RegExp(
    r'^แพ็กเกจนี้เปิดใช้ได้สูงสุด (\d+) ลิงก์ กรุณาปิดลิงก์ส่วนเกินก่อนเผยแพร่ ข้อมูลเดิมยังอยู่$',
  ).firstMatch(message);
  if (publishLimit != null) {
    return 'Your plan allows up to ${publishLimit[1]} active links. Disable extra links before publishing. Your existing data has been kept.';
  }
  final enableLimit = RegExp(
    r'^แพ็กเกจนี้เปิดใช้ได้สูงสุด (\d+) ลิงก์ กรุณาปิดลิงก์อื่นก่อน$',
  ).firstMatch(message);
  if (enableLimit != null) {
    return 'Your plan allows up to ${enableLimit[1]} active links. Disable another link first.';
  }
  return message;
}

class LinkInBioText extends StatelessWidget {
  const LinkInBioText(
    this.message, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.softWrap,
    this.overflow,
  });

  final String message;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final bool? softWrap;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) => Text(
        localizeLinkInBioMessage(context, message),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        softWrap: softWrap,
        overflow: overflow,
      );
}

const _englishMessages = <String, String>{
  'กำลังบันทึกแบบร่างในเครื่อง...': 'Saving draft on this device...',
  'มีการแก้ไขที่ยังไม่ได้บันทึก': 'Unsaved changes',
  'บันทึกแบบร่างในเครื่องแล้ว': 'Draft saved on this device',
  'แบบร่างยังไม่ได้บันทึก': 'Draft not saved yet',
  'ระบบคุ้มครองรูปแบบร่างยังไม่พร้อมใช้งาน กรุณาลองใหม่ภายหลัง':
      'Draft image protection is not available yet. Please try again later.',
  'บันทึกแบบร่างไม่สำเร็จ กรุณาลองใหม่':
      'Could not save the draft. Please try again.',
  'บัญชีเปลี่ยนแล้ว กรุณาเปิดหน้าลิงก์ร้านอีกครั้ง':
      'Your account has changed. Please reopen Store link.',
  'โหลดรูปตัวอย่างไม่สำเร็จ กรุณาตรวจสถานะเว็บไซต์เพื่อลองใหม่':
      'Could not load the preview image. Check website status to try again.',
  'ยังคุ้มครองรูปแบบร่างไม่ได้ กรุณาลองใหม่ก่อนเปลี่ยนรูป':
      'Could not protect draft images yet. Please try again before changing an image.',
  'โหลดสถานะหน้าโปรไฟล์ไม่สำเร็จ กรุณาลองใหม่':
      'Could not load website status. Please try again.',
  'บันทึกแบบร่างในเครื่องแล้ว ยังไม่ได้อัปเดตเว็บไซต์':
      'Draft saved on this device. The website has not been updated.',
  'คำแนะนำร้านยาวเกิน 280 ตัวอักษร':
      'Your store description must be no longer than 280 characters.',
  'กรอกชื่อร้าน 1–80 ตัวอักษร': 'Enter a store name with 1–80 characters.',
  'ชื่อ URL ต้องเป็น a-z, 0-9 หรือขีดกลางภายในชื่อ ความยาว 3–40 ตัวอักษร':
      'Use 3–40 characters for the URL name: a–z, 0–9 and hyphens between words.',
  'เพิ่มและเปิดใช้งานอย่างน้อย 1 ลิงก์ก่อนเผยแพร่':
      'Add and enable at least one link before publishing.',
  'เปิดใช้ได้สูงสุด 20 ลิงก์': 'You can enable up to 20 links.',
  'เพิ่มภาพพื้นหลัง หรือเปลี่ยนพื้นหลังเป็นสีเดียวก่อนเผยแพร่':
      'Add a background image or choose a solid background before publishing.',
  'ข้อมูลลิงก์ไม่ถูกต้อง กรุณาลบแล้วเพิ่มใหม่':
      'This link is invalid. Please remove it and add it again.',
  'ยังตรวจสอบสิทธิ์ลิงก์ไม่ได้ กรุณาลองใหม่ คุณยังแก้ไขแบบร่างเดิมได้':
      'Could not check your link allowance. Please try again. You can still edit your existing draft.',
  'เผยแพร่แล้ว แต่บันทึกแบบร่างในเครื่องไม่สำเร็จ กรุณาบันทึกแบบร่างอีกครั้ง':
      'Published, but the draft could not be saved on this device. Please save the draft again.',
  'เผยแพร่หน้าโปรไฟล์แล้ว คัดลอกลิงก์ส่งให้ลูกค้าได้':
      'Website published. You can copy the link and share it with customers.',
  'ชื่อ URL นี้มีคนใช้แล้ว กรุณาเลือกชื่อใหม่':
      'This URL name is already taken. Please choose another.',
  'ยังไม่ทราบผลการเผยแพร่ กรุณาตรวจสถานะก่อนลองอีกครั้ง':
      'The publishing result is unknown. Check website status before trying again.',
  'เผยแพร่หน้าโปรไฟล์ไม่สำเร็จ กรุณาลองใหม่':
      'Could not publish the website. Please try again.',
  'หยุดเผยแพร่หน้าโปรไฟล์?': 'Unpublish this website?',
  'ลูกค้าจะเปิดลิงก์หน้านี้ไม่ได้จนกว่าจะเผยแพร่อีกครั้ง แบบร่างของคุณยังอยู่':
      'Customers will not be able to open this website until you publish it again. Your draft will be kept.',
  'ยกเลิก': 'Cancel',
  'หยุดเผยแพร่': 'Unpublish',
  'หยุดเผยแพร่แล้ว แบบร่างของคุณยังอยู่':
      'Website unpublished. Your draft has been kept.',
  'ยังไม่ทราบผลการหยุดเผยแพร่ กรุณาตรวจสถานะก่อนลองอีกครั้ง':
      'The unpublishing result is unknown. Check website status before trying again.',
  'คัดลอกลิงก์แล้ว วางในแชตหรือหน้าโปรไฟล์ได้เลย':
      'Link copied. You can paste it in a chat or profile.',
  'คัดลอกลิงก์ไม่สำเร็จ กรุณาลองใหม่':
      'Could not copy the link. Please try again.',
  'เปิดเว็บไซต์ไม่สำเร็จ กรุณาคัดลอกลิงก์แล้วเปิดในเบราว์เซอร์':
      'Could not open the website. Copy the link and open it in your browser.',
  'เปิดเว็บไซต์ไม่สำเร็จ กรุณาลองใหม่':
      'Could not open the website. Please try again.',
  'ตัวอย่างก่อนเผยแพร่': 'Preview before publishing',
  'ปิดตัวอย่าง': 'Close preview',
  'เลิกทำ': 'Undo',
  'อัปโหลดโลโก้ไม่สำเร็จ กรุณาลองใหม่ รูปเดิมยังอยู่':
      'Could not upload the logo. Please try again. Your previous image has been kept.',
  'ตั้งชื่อและ URL ในข้อมูลร้าน': 'Set your store name and URL in Store info',
  'คัดลอกลิงก์': 'Copy link',
  'เปิดเว็บไซต์': 'Open website',
  'ข้อมูลร้าน': 'Store info',
  'ตกแต่ง': 'Customize',
  'ดูตัวอย่าง': 'Preview',
  'เพิ่มลิงก์': 'Add link',
  'ลิงก์ของร้าน': 'Store links',
  'กำลังตรวจสอบสิทธิ์ลิงก์...': 'Checking your link allowance...',
  'ลองตรวจสอบสิทธิ์อีกครั้ง': 'Check link allowance again',
  'เพิ่มลิงก์แรกของร้าน': 'Add your store\'s first link',
  'เช่น ร้านค้า สินค้า หรือช่องทางติดต่อ':
      'For example, a store, product or contact link.',
  'เผยแพร่อีกครั้งเพื่ออัปเดตหน้าเว็บจริง':
      'Publish again to update your live website.',
  'โลโก้ร้าน': 'Store logo',
  'รูปที่ลูกค้าเห็นบนหน้าเว็บ': 'The image customers see on your website',
  'เพิ่มโลโก้': 'Add logo',
  'เปลี่ยนโลโก้': 'Change logo',
  'ลบโลโก้': 'Remove logo',
  'ลบรูป': 'Remove image',
  'ชื่อร้าน': 'Store name',
  'เช่น ร้านมินาขายดี': 'For example, Mina Shop',
  'แนะนำร้านสั้น ๆ': 'Short store description',
  'ไม่บังคับ': 'Optional',
  'ร้านของคุณขายอะไร มีอะไรน่าสนใจ':
      'What does your store sell? What makes it special?',
  'ย่อ': 'Collapse',
  'แก้ไข': 'Edit',
  'ลิงก์ร้านของคุณ': 'Your store link',
  'ตั้งชื่อ URL ร้าน': 'Choose your store URL',
  'ชื่อ URL': 'URL name',
  'a-z, 0-9 และขีดกลาง ความยาว 3–40 ตัวอักษร':
      '3–40 characters: a–z, 0–9 and hyphens',
  'ตัวเลือกลิงก์': 'Link options',
  'ยกเลิกโปรโมชันเด่น': 'Remove featured promotion',
  'เลือกเป็นโปรโมชันเด่น': 'Set as featured promotion',
  'เลื่อนขึ้น': 'Move up',
  'เลื่อนลง': 'Move down',
  'ลบลิงก์': 'Delete link',
  'ลากเพื่อย้าย หรือใช้เมนูเลื่อนขึ้นและเลื่อนลง':
      'Drag to reorder, or use Move up and Move down in the menu',
  'เลือกธีมที่ชอบ': 'Choose a theme',
  'ปรับสี รูป และตัวอักษร': 'Customize colors, images and text',
  'ตรวจแบบร่างก่อนเผยแพร่ เมื่อพร้อมกดเผยแพร่ให้ลูกค้าเห็น':
      'Review your draft before publishing. Publish when you are ready for customers to see it.',
  'ดูตัวอย่างเต็มหน้า': 'Full-screen preview',
  'แก้ไขข้อมูลร้านและ URL': 'Edit store info and URL',
  'ตัวเลือกเพิ่มเติม': 'More options',
  'บันทึกแบบร่าง': 'Save draft',
  'ตรวจสถานะเว็บไซต์': 'Check website status',
  'บันทึกเป็นแบบร่าง ต้องเผยแพร่เพื่ออัปเดตเว็บจริง':
      'Saved as a draft. Publish to update your live website.',
  'บันทึกแล้วกลับ': 'Save and return',
  'เสร็จสิ้น': 'Done',
  'กลับไปที่ลิงก์': 'Back to links',
  'กำลังดำเนินการ...': 'Please wait...',
  'ตรวจและเผยแพร่': 'Review and publish',
  'อัปเดตหน้าเว็บไซต์': 'Update website',
  'เผยแพร่หน้าเว็บไซต์': 'Publish website',
  'ยังไม่ทราบผล กรุณาตรวจสถานะ': 'Result unknown. Check website status.',
  'กำลังตรวจสถานะ...': 'Checking website status...',
  'เผยแพร่แล้ว': 'Published',
  'ยังไม่ได้เผยแพร่': 'Not published',
  'ยังตรวจสถานะเว็บไซต์ไม่ได้': 'Could not check website status',
  'กลับ': 'Back',
  'ตกแต่งหน้าเว็บ': 'Customize website',
  'ลิงก์ร้าน': 'Store link',
  'ตรวจสถานะอีกครั้ง': 'Check status again',
  'มีการแก้ไขที่ยังไม่ได้เผยแพร่ เว็บไซต์ยังใช้ข้อมูลที่เผยแพร่ครั้งล่าสุด':
      'You have unpublished changes. Your website still shows the last published version.',
  'เมื่อเผยแพร่ชื่อ URL ใหม่ ลิงก์เดิมจะเปิดไม่ได้ ต้องส่งลิงก์ใหม่ให้ลูกค้า':
      'Publishing a new URL name will make the old link unavailable. Share the new link with your customers.',
  'แก้ไขลิงก์': 'Edit link',
  'ซ่อนอยู่': 'Hidden',
  'เพิ่มลิงก์ใหม่': 'Add link',
  'ปิด': 'Close',
  'ชื่อปุ่ม': 'Button label',
  'เว้นว่างเพื่อใช้ชื่อจากลิงก์': 'Leave blank to use a label from the link',
  'ลิงก์หรือช่องทางติดต่อ': 'Link or contact',
  'วางลิงก์เว็บไซต์ อีเมล หรือเบอร์โทร':
      'Paste a website link, email address or phone number',
  'หมวดหมู่ยาวเกิน 60 ตัวอักษร':
      'The category must be no longer than 60 characters.',
  'หมวดหมู่': 'Category',
  'เช่น ช้อปสินค้า หรือ ติดต่อ': 'For example, Shop or Contact',
  'โลโก้': 'Logo',
  'ปรับปุ่มนี้แยกจากธีมได้ หรือเว้นว่างเพื่อใช้ค่าของธีม':
      'Customize this button, or leave these settings empty to use the theme.',
  'ฟอนต์ปุ่มนี้': 'Button font',
  'สีข้อความปุ่มนี้': 'Button text color',
  'สีพื้นปุ่มนี้': 'Button background color',
  'บันทึกลิงก์': 'Save link',
  'กรอกชื่อปุ่ม 1–80 ตัวอักษร': 'Enter a button label with 1–80 characters.',
  'ใช้ URL เต็มที่ขึ้นต้นด้วย https:// หรือ http:// และไม่มีชื่อผู้ใช้หรือรหัสผ่าน หรือใช้ mailto:อีเมล / tel:เบอร์โทร':
      'Use a full https:// or http:// URL without a username or password, or use mailto:email / tel:phone.',
  'ส่งอีเมล': 'Send email',
  'โทรหาร้าน': 'Call the store',
  'ดำเนินการไม่สำเร็จ กรุณาลองใหม่อีกครั้ง':
      'Could not complete the action. Please try again.',
  'ระบบตอบกลับช้าเกินไป กรุณาลองใหม่อีกครั้ง':
      'The request took too long. Please try again.',
  'เชื่อมต่อ PostDee ไม่ได้ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่':
      'Cannot connect to PostDee. Check your internet connection and try again.',
  'ระบบ PostDee ไม่พร้อมใช้งานชั่วคราว กรุณาลองใหม่ภายหลัง':
      'PostDee is temporarily unavailable. Please try again later.',
  'กรุณาเข้าสู่ระบบใหม่ แล้วลองอีกครั้ง': 'Please sign in again and retry.',
  'มีคำขอมากเกินไป กรุณารอสักครู่แล้วลองใหม่':
      'Too many requests. Wait a moment and try again.',
  'เลือกรูปที่มีขนาดไม่เกิน 20 MB': 'Choose an image no larger than 20 MB.',
  'รูปนี้มีรายละเอียดมากเกินไป กรุณาเลือกรูปอื่น':
      'This image is too detailed. Please choose another.',
  'อัปโหลดรูปไม่สำเร็จ กรุณาลองใหม่ รูปเดิมยังอยู่':
      'Could not upload the image. Please try again. Your previous image has been kept.',
  'เปิดรูปนี้ไม่ได้ กรุณาเลือกรูปอื่น':
      'Could not open this image. Please choose another image.',
  'บันทึกโลโก้ไม่สำเร็จ กรุณาลองใหม่':
      'Could not save the logo. Please try again.',
  'ตัวอักษรและเส้นบาง': 'Type and fine lines',
  'แถบลาเวนเดอร์': 'Lavender bands',
  'ภาพเด่นเรียบง่าย': 'Simple featured image',
  'สมุดกระดาษขาว': 'White paper notebook',
  'รางเส้นบาง': 'Fine line rails',
  'ช่องกริดก้อนหิน': 'Pebble grid',
  'แกลเลอรีโปร่ง': 'Airy gallery',
  'โปสเตอร์ประจำวัน': 'Daily poster',
  'หน้าต่างพกพา': 'Pocket window',
  'โน้ตคอลลาจ': 'Note collage',
  'ริบบิ้นเส้นข้าง': 'Side ribbons',
  'ขั้นบันไดเรียบ': 'Simple steps',
  'ตั๋วกระดาษเรียบ': 'Plain paper ticket',
  'ซุ้มกรอบภาพ': 'Picture frame arch',
  'ชั้นกระจกโปร่ง': 'Open glass shelves',
  'กระดาษฉีกซ้อน': 'Layered torn paper',
  'ตราสตูดิโอ': 'Studio seal',
  'กิ่งไม้เส้นบาง': 'Fine branches',
  'ขอบหยักเรียบ': 'Simple scalloped edge',
  'ป้ายลายเซ็น': 'Signature card',
  'เรียบง่าย': 'Minimal',
  'น่ารัก / พาสเทล': 'Cute / Pastel',
  'ธรรมชาติ / อบอุ่น': 'Nature / Warm',
  'หรูหรา / พรีเมียม': 'Luxury / Premium',
  'สดใส / ครีเอทีฟ': 'Bright / Creative',
  'ร้านค้า': 'Shop',
  'พาสเทล': 'Pastel',
  'เข้ม': 'Dark',
  'ชมพูพาสเทล': 'Pastel pink',
  'สวนดอกไม้': 'Flower garden',
  'ร้านค้าแบบการ์ด': 'Shop cards',
  'กรอบหยักเชอร์รี่': 'Cherry scalloped frame',
  'สมุดสติกเกอร์': 'Sticker notebook',
  'หน้าต่างลูกกวาด': 'Candy window',
  'จดหมายหัวใจ': 'Heart letter',
  'บันไดมาร์ชเมลโลว์': 'Marshmallow steps',
  'สมุดชมพู': 'Pink notebook',
  'ริบบิ้นบาง': 'Thin ribbons',
  'ช่องปิกนิกพาสเทล': 'Pastel picnic grid',
  'เพื่อนคู่สี': 'Color pair friends',
  'จดหมายฉีกขอบ': 'Torn edge letter',
  'ป้ายกล่องโบว์': 'Bow gift card',
  'ตั๋วเบเกอรี': 'Bakery ticket',
  'กระจกเมฆฝ้าย': 'Cotton cloud mirror',
  'ภาพโปสต์การ์ดหวาน': 'Sweet postcard',
  'แกลเลอรีตุ๊กตา': 'Doll gallery',
  'โปสเตอร์แคนดี้': 'Candy poster',
  'ตราหัวใจ': 'Heart seal',
  'สวนกลีบดอกไม้': 'Flower petal garden',
  'ซุ้มเพชรน้ำตาล': 'Sugar gem arch',
  'รางการ์ดของขวัญ': 'Gift card rails',
  'สวนมะกอก': 'Olive garden',
  'เรือนกระจก': 'Greenhouse',
  'กระดาษเส้นใย': 'Fiber paper',
  'ภาพสวนเช้า': 'Morning garden picture',
  'ป้ายกระถางดิน': 'Clay pot card',
  'แกลเลอรีใบไม้': 'Leaf gallery',
  'บทบันทึกงานคราฟต์': 'Craft journal',
  'คู่สีโต๊ะไม้': 'Wooden desk colors',
  'สมุดใบไม้แห้ง': 'Pressed leaf notebook',
  'คอลลาจใบไม้': 'Leaf collage',
  'รางก้านหญ้า': 'Grass stem rails',
  'ขอบหยักตะกร้าสวน': 'Garden basket scallops',
  'ขั้นไม้ซ้อน': 'Layered wooden steps',
  'ซุ้มระเบียงสวน': 'Garden veranda arch',
  'หน้าต่างลินิน': 'Linen window',
  'ช่องชั้นดอกไม้': 'Flower shelf grid',
  'โปสเตอร์ป่า': 'Forest poster',
  'ตราใบไม้': 'Leaf seal',
  'ริบบิ้นพวงดอกไม้': 'Wreath ribbon',
  'ตั๋วชาสมุนไพร': 'Herbal tea ticket',
  'ตราประทับทอง': 'Gold seal',
  'ป้ายลายเซ็นเงิน': 'Silver signature card',
  'แกลเลอรีขาวดำ': 'Monochrome gallery',
  'ภาพห้องมรกต': 'Emerald room picture',
  'บทบรรณาธิการทอง': 'Gold editorial',
  'ช่องกล่องอัญมณี': 'Jewel box grid',
  'ขั้นกำมะหยี่': 'Velvet steps',
  'โปสเตอร์แบล็กสตูดิโอ': 'Black studio poster',
  'คู่สีไวน์': 'Wine color pair',
  'คอลลาจน้ำหมึก': 'Ink collage',
  'รางโมโนแกรม': 'Monogram rails',
  'ริบบิ้นแชมเปญ': 'Champagne ribbons',
  'ขอบหยักไข่มุก': 'Pearl scallops',
  'กระดาษฉีกลายหินอ่อน': 'Torn marble paper',
  'ซุ้มทองเหลือง': 'Brass arch',
  'หน้าต่างเครื่องประดับ': 'Jewelry window',
  'กระจกอัลบั้มพรีเมียม': 'Premium album mirror',
  'สมุดพรีเมียม': 'Premium notebook',
  'สวนราตรีนิล': 'Onyx night garden',
  'ตั๋วแพลทินัม': 'Platinum ticket',
  'โปสเตอร์เหลืองป๊อป': 'Yellow pop poster',
  'หน้าต่างบล็อกสี': 'Color block window',
  'ตั๋วเรโทร': 'Retro ticket',
  'คู่สีป๊อปซันเดย์': 'Sunday pop colors',
  'ตัวอักษรสีจัด': 'Vivid typography',
  'ขั้นโปสเตอร์ซ้อน': 'Stacked poster steps',
  'รางสตูดิโอเหลือง': 'Yellow studio rails',
  'สมุดปากกามาร์กเกอร์': 'Marker notebook',
  'คอลลาจสีสนุก': 'Playful color collage',
  'ภาพเด่นสีฟ้า': 'Blue featured image',
  'กระดาษฉีกกรอบหมึก': 'Torn paper ink frame',
  'หน้าต่างคอมิก': 'Comic window',
  'กระจกนีออน': 'Neon mirror',
  'ซุ้มสีสนุก': 'Playful color arch',
  'แกลเลอรีสีสด': 'Vivid color gallery',
  'ขอบหยักยุคใหม่': 'Modern scalloped edge',
  'ตราสีส้ม': 'Orange seal',
  'สวนวงแหวนป๊อป': 'Pop ring garden',
  'ริบบิ้นแพตช์สี': 'Color patch ribbon',
  'ป้ายสีตัด': 'Contrast color card',
};
