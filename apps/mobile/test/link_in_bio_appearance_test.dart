import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';

void main() {
  test('legacy defaults preserve the existing cream and green profile page',
      () {
    const appearance = LinkInBioAppearance();
    expect(appearance.themeId, 'minimal');
    expect(appearance.background.color, '#fff8ef');
    expect(appearance.background.gradientColor, '#f4e3c7');
    expect(appearance.background.overlay, 30);
    expect(appearance.buttonColor, '#305d36');
    expect(appearance.buttonStyle.color, '#ffffff');
    expect(appearance.featuredLabel, 'โปรวันนี้');
    expect(LinkInBioAppearance.fromJson(appearance.toJson()).toJson(),
        appearance.toJson());
  });

  test('theme presets match the backend and keep fonts allowlisted', () {
    final shop = LinkInBioAppearance.forTheme('shop');
    final pastel = LinkInBioAppearance.forTheme('pastel');
    final dark = LinkInBioAppearance.fromTheme('dark');
    expect(shop.background.color, '#fff5e8');
    expect(shop.buttonColor, '#e85d24');
    expect(shop.nameStyle.font, 'prompt');
    expect(pastel.background.gradientColor, '#e6f1ff');
    expect(pastel.buttonRadius, 'pill');
    expect(dark.surfaceColor, '#1f2937');
    expect(dark.buttonColor, '#34d399');
    expect(dark.nameStyle.font, 'prompt');
    expect(
        () => LinkInBioAppearance.forTheme('unknown'), throwsFormatException);
  });

  test(
      'custom appearance round trips and nullable copyWith clears media and featured links',
      () {
    const key =
        'uploads/seller/11111111-1111-4111-8111-111111111111/profile-logo.png';
    final original = LinkInBioAppearance.forTheme('pastel').copyWith(
      description: 'สินค้าที่เราเลือกมาให้คุณ',
      logoKey: key,
      coverKey: key,
      background:
          const LinkInBioBackground(mode: 'image', imageKey: key, overlay: 55),
      nameStyle: const LinkInBioTextStyle(color: '#663399', font: 'system'),
      featuredLinkId: 'shop',
      featuredLabel: 'โปรโมชั่นวันนี้',
    );
    expect(LinkInBioAppearance.fromJson(original.toJson()).toJson(),
        original.toJson());
    final cleared = original.copyWith(
        logoKey: null,
        coverKey: null,
        featuredLinkId: null,
        background:
            original.background.copyWith(mode: 'solid', imageKey: null));
    expect(cleared.logoKey, isNull);
    expect(cleared.coverKey, isNull);
    expect(cleared.featuredLinkId, isNull);
    expect(cleared.background.imageKey, isNull);
    expect(original.logoKey, key);
  });

  for (final change in <Map<String, Object?>>[
    {'version': 2},
    {'themeId': 'evil'},
    {'description': 'x' * 281},
    {'surfaceColor': 'red'},
    {'buttonColor': '#fff'},
    {'buttonRadius': 'script'},
    {'featuredLabel': 'x' * 41},
    {'logoKey': 'https://evil.example/logo.png'},
    {'coverKey': 'uploads/seller/../other/logo.png'},
    {'logoKey': 'uploads/seller/a\n.png'},
    {
      'nameStyle': {'color': '#253529', 'font': 'url(https://evil.example)'}
    },
    {
      'buttonStyle': {'color': 'white;display:none', 'font': 'anuphan'}
    },
    {
      'background': {
        'mode': 'solid',
        'color': '#fff8ef',
        'gradientColor': '#f4e3c7',
        'imageKey': null,
        'overlay': 81
      }
    },
    {
      'background': {
        'mode': 'video',
        'color': '#fff8ef',
        'gradientColor': '#f4e3c7',
        'imageKey': null,
        'overlay': 30
      }
    },
    {
      'background': {
        'mode': 'solid',
        'color': '#fff8ef',
        'gradientColor': '#f4e3c7',
        'imageKey': null,
        'overlay': 1.5
      }
    },
  ]) {
    test('rejects malformed appearance ${change.keys.single}', () {
      expect(
          () => LinkInBioAppearance.fromJson(
              {...const LinkInBioAppearance().toJson(), ...change}),
          throwsFormatException);
    });
  }

  test('provided appearance cannot silently lose required style fields', () {
    final json = const LinkInBioAppearance().toJson()..remove('nameStyle');
    expect(() => LinkInBioAppearance.fromJson(json), throwsFormatException);
    expect(() => LinkInBioAppearance.fromJson({}), throwsFormatException);
  });

  test('image keys reject traversal segments but allow all owned image roles',
      () {
    const id = '11111111-1111-4111-8111-111111111111';
    for (final owner in ['.', '..']) {
      expect(isSafeLinkInBioImageKey('uploads/$owner/$id/profile-logo.png'),
          isFalse);
    }
    for (final slot in ['logo', 'cover', 'background']) {
      expect(isSafeLinkInBioImageKey('uploads/seller/$id/profile-$slot.png'),
          isTrue);
    }
  });
}
