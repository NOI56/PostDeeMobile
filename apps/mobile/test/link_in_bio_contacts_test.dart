import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_link_defaults.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_platform_logo.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_validation.dart';

void main() {
  test('contact links select the correct logo and suggested button name', () {
    const cases = {
      'https://m.me/shop': ('messenger', 'Messenger'),
      'https://www.messenger.com/t/shop': ('messenger', 'Messenger'),
      'https://facebook.com/messages/t/shop': ('messenger', 'Messenger'),
      'https://wa.me/66812345678': ('whatsapp', 'WhatsApp'),
      'https://api.whatsapp.com/send?phone=66812345678': (
        'whatsapp',
        'WhatsApp'
      ),
      'https://maps.app.goo.gl/shop': ('google_maps', 'Google Maps'),
      'https://goo.gl/maps/shop': ('google_maps', 'Google Maps'),
      'https://www.google.com/maps/place/shop': ('google_maps', 'Google Maps'),
      'https://maps.google.co.th/?q=shop': ('google_maps', 'Google Maps'),
      'https://example.com/shop': ('website', 'example.com'),
      'mailto:shop+sales@example.com': ('email', 'ส่งอีเมล'),
      'tel:+66812345678': ('phone', 'โทรหาร้าน'),
    };
    for (final entry in cases.entries) {
      expect(linkInBioLinkError('ติดต่อ', entry.key), isNull,
          reason: entry.key);
      expect(bioPlatformId(entry.key), entry.value.$1, reason: entry.key);
      expect(suggestedBioLinkTitle(entry.key), entry.value.$2,
          reason: entry.key);
      expect(linkInBioIcons, contains(entry.value.$1));
    }
  });

  test('lookalike domains and unrelated Google paths stay websites', () {
    for (final url in [
      'https://m.me.evil.example/shop',
      'https://notwhatsapp.com/shop',
      'https://maps.app.goo.gl.evil.example/shop',
      'https://google.com/search?q=maps',
      'https://google.com/mapshop',
      'https://goo.gl/other',
      'https://sub.goo.gl/maps/shop',
      'https://docs.google.com/maps/shop'
    ]) {
      expect(bioPlatformId(url), 'website', reason: url);
    }
  });

  test('unsupported or malformed contacts remain invalid and have no title',
      () {
    for (final url in [
      'mailto',
      'mailto:',
      'mailto://shop@example.com',
      'mailto:a@example.com,b@example.com',
      'mailto:shop@example.com?subject=hi',
      'mailto:shop%0d%0abcc@example.com',
      'mailto:a..b@example.com',
      'mailto:a@-example.com',
      'mailto:a@example.com#fragment',
      'tel',
      'tel:',
      'tel:+123',
      'tel:+66812345678;ext=1',
      'tel:*123#',
      'tel:%2B66812345678',
      'sms:+66812345678',
      'javascript:alert(1)',
      'data:text/html,x'
    ]) {
      expect(linkInBioLinkError('ติดต่อ', url), isNotNull, reason: url);
      expect(suggestedBioLinkTitle(url), isNull, reason: url);
    }
  });

  test('simple contact destinations retain their original safe address', () {
    for (final url in [
      'MAILTO:shop@example.com',
      'mailto:sales+shop@example.co.th',
      'tel:0812345678',
      'TEL:+66812345678',
    ]) {
      expect(linkInBioLinkError('ติดต่อร้าน', url), isNull, reason: url);
    }
  });

  test('plain email and phone inputs become safe contact destinations', () {
    expect(normalizeBioLinkInput('  shop@example.com  '),
        'mailto:shop@example.com');
    expect(normalizeBioLinkInput('0812345678'), 'tel:0812345678');
    expect(normalizeBioLinkInput('+66812345678'), 'tel:+66812345678');
    expect(normalizeBioLinkInput('  https://example.com/shop  '),
        'https://example.com/shop');
    expect(normalizeBioLinkInput('mailto:shop@example.com'),
        'mailto:shop@example.com');
    expect(normalizeBioLinkInput('tel:+66812345678'), 'tel:+66812345678');
  });

  test('incomplete and unsafe plain inputs are never promoted to contacts', () {
    for (final input in [
      'www.example.com',
      '123',
      '*123#',
      'shop@example.com,other@example.com',
      'shop@example.com?subject=hello',
      'shop%0d%0abcc@example.com',
      'a..b@example.com',
      '081 234 5678',
      'shop\n@example.com',
      'https://user:password@example.com',
    ]) {
      expect(normalizeBioLinkInput(input), input, reason: input);
      expect(
          linkInBioLinkError('ติดต่อ', normalizeBioLinkInput(input)), isNotNull,
          reason: input);
    }
  });

  for (final icon in ['messenger', 'whatsapp', 'google_maps']) {
    testWidgets('$icon loads a bundled brand mark in a 40px slot',
        (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: Center(child: BioPlatformLogo(icon: icon))));
      await tester.pumpAndSettle();
      expect(bioPlatformLogoAsset(icon), 'assets/images/platforms/$icon.png');
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.color, isNull);
      expect(tester.getSize(find.byType(BioPlatformLogo)), const Size(40, 40));
      expect(tester.takeException(), isNull);
    });
  }

  for (final entry in {
    'website': Icons.language,
    'email': Icons.mail_outline,
    'phone': Icons.phone_outlined
  }.entries) {
    testWidgets('${entry.key} has its own generic contact symbol',
        (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: Center(child: BioPlatformLogo(icon: entry.key))));
      expect(find.byIcon(entry.value), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  }
}
