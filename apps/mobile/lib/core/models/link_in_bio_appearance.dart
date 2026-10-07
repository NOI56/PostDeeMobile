import 'profile_platform_catalog.generated.dart';
import 'profile_template_catalog.generated.dart';

const linkInBioFonts = {'anuphan', 'prompt', 'system'};
const linkInBioIcons = {
  'auto',
  'link',
  ...profilePlatformIds,
  'website',
  'email',
  'phone',
};
const _unset = Object();
final _hexColor = RegExp(r'^#[0-9a-fA-F]{6}$');
final _imageKey = RegExp(
  r'^uploads/[^/\\\s]+/[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}/profile-(?:logo|cover|background)\.png$',
);

bool isSafeLinkInBioImageKey(String value) {
  if (value.length > 512 ||
      !_imageKey.hasMatch(value) ||
      value.split('/').any((segment) => segment == '.' || segment == '..') ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    return false;
  }
  try {
    final owner = Uri.decodeComponent(value.split('/')[1]);
    return owner.isNotEmpty && !RegExp(r'[\x00-\x1f\x7f]').hasMatch(owner);
  } on FormatException {
    return false;
  }
}

String _readColor(Object? value) {
  if (value is! String || !_hexColor.hasMatch(value)) {
    throw const FormatException('Invalid profile color');
  }
  return value.toLowerCase();
}

String _readText(Object? value, int maximum) {
  if (value is! String || value.length > maximum) {
    throw const FormatException('Invalid profile text');
  }
  return value;
}

String? _readImageKey(Object? value) {
  if (value == null) return null;
  if (value is! String || !isSafeLinkInBioImageKey(value)) {
    throw const FormatException('Invalid profile image key');
  }
  return value;
}

Map<String, Object?> _readObject(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Invalid profile style');
  }
  return value;
}

void validateLinkInBioLinkOptions({
  String category = '',
  String icon = 'auto',
  String? font,
  String? textColor,
  String? buttonColor,
}) {
  _readText(category, 60);
  if (!linkInBioIcons.contains(icon) ||
      (font != null && !linkInBioFonts.contains(font))) {
    throw const FormatException('Invalid link icon or font');
  }
  if (textColor != null) _readColor(textColor);
  if (buttonColor != null) _readColor(buttonColor);
}

class LinkInBioTextStyle {
  const LinkInBioTextStyle({this.color = '#253529', this.font = 'anuphan'});
  final String color;
  final String font;

  factory LinkInBioTextStyle.fromJson(Map<String, Object?> json) {
    final font = json['font'];
    if (font is! String || !linkInBioFonts.contains(font)) {
      throw const FormatException('Invalid profile font');
    }
    return LinkInBioTextStyle(color: _readColor(json['color']), font: font);
  }

  Map<String, Object?> toJson() {
    if (!linkInBioFonts.contains(font)) {
      throw const FormatException('Invalid profile font');
    }
    return {'color': _readColor(color), 'font': font};
  }

  LinkInBioTextStyle copyWith({String? color, String? font}) =>
      LinkInBioTextStyle(
        color: color ?? this.color,
        font: font ?? this.font,
      );
}

class LinkInBioBackground {
  const LinkInBioBackground({
    this.mode = 'solid',
    this.color = '#fff8ef',
    this.gradientColor = '#f4e3c7',
    this.imageKey,
    this.overlay = 30,
  });
  final String mode;
  final String color;
  final String gradientColor;
  final String? imageKey;
  final int overlay;

  factory LinkInBioBackground.fromJson(Map<String, Object?> json) {
    final mode = json['mode'];
    final overlay = json['overlay'];
    if (mode is! String ||
        !const {'solid', 'gradient', 'image'}.contains(mode) ||
        overlay is! int ||
        overlay < 0 ||
        overlay > 80) {
      throw const FormatException('Invalid profile background');
    }
    return LinkInBioBackground(
        mode: mode,
        color: _readColor(json['color']),
        gradientColor: _readColor(json['gradientColor']),
        imageKey: _readImageKey(json['imageKey']),
        overlay: overlay);
  }

  Map<String, Object?> toJson() {
    if (!const {'solid', 'gradient', 'image'}.contains(mode) ||
        overlay < 0 ||
        overlay > 80) {
      throw const FormatException('Invalid profile background');
    }
    return {
      'mode': mode,
      'color': _readColor(color),
      'gradientColor': _readColor(gradientColor),
      'imageKey': _readImageKey(imageKey),
      'overlay': overlay
    };
  }

  LinkInBioBackground copyWith(
          {String? mode,
          String? color,
          String? gradientColor,
          Object? imageKey = _unset,
          int? overlay}) =>
      LinkInBioBackground(
        mode: mode ?? this.mode,
        color: color ?? this.color,
        gradientColor: gradientColor ?? this.gradientColor,
        imageKey:
            identical(imageKey, _unset) ? this.imageKey : imageKey as String?,
        overlay: overlay ?? this.overlay,
      );
}

const linkInBioThemeNames = {
  'minimal': 'เรียบง่าย',
  'shop': 'ร้านค้า',
  'pastel': 'พาสเทล',
  'dark': 'เข้ม',
  'pink': 'ชมพูพาสเทล',
  'garden': 'สวนดอกไม้',
  'cards': 'ร้านค้าแบบการ์ด',
};

class LinkInBioEffects {
  const LinkInBioEffects(
      {this.background = false,
      this.entrance = false,
      this.featured = false,
      this.stickers = 'none'});
  final bool background;
  final bool entrance;
  final bool featured;
  final String stickers;
  bool get enabled => background || entrance || featured || stickers != 'none';
  factory LinkInBioEffects.fromJson(Map<String, Object?> json) {
    for (final field in ['background', 'entrance', 'featured']) {
      if (json.containsKey(field) && json[field] is! bool) {
        throw const FormatException('Invalid profile motion');
      }
    }
    final stickers = json.containsKey('stickers') ? json['stickers'] : 'none';
    if (!const {'none', 'hearts', 'flowers', 'sparkles'}.contains(stickers)) {
      throw const FormatException('Invalid profile stickers');
    }
    return LinkInBioEffects(
        background: json['background'] as bool? ?? false,
        entrance: json['entrance'] as bool? ?? false,
        featured: json['featured'] as bool? ?? false,
        stickers: stickers as String);
  }
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'background': background,
      'entrance': entrance,
      'featured': featured,
      'stickers': stickers
    };
    LinkInBioEffects.fromJson(json);
    return json;
  }

  LinkInBioEffects copyWith(
          {bool? background,
          bool? entrance,
          bool? featured,
          String? stickers}) =>
      LinkInBioEffects(
          background: background ?? this.background,
          entrance: entrance ?? this.entrance,
          featured: featured ?? this.featured,
          stickers: stickers ?? this.stickers);
}

class LinkInBioAppearance {
  const LinkInBioAppearance({
    this.version = 1,
    this.themeId = 'minimal',
    this.templateId,
    this.description = '',
    this.logoKey,
    this.coverKey,
    this.background = const LinkInBioBackground(),
    this.surfaceColor = '#ffffff',
    this.buttonColor = '#305d36',
    this.buttonRadius = 'rounded',
    this.nameStyle = const LinkInBioTextStyle(),
    this.descriptionStyle = const LinkInBioTextStyle(color: '#687065'),
    this.categoryStyle = const LinkInBioTextStyle(color: '#537844'),
    this.buttonStyle = const LinkInBioTextStyle(color: '#ffffff'),
    this.brandStyle = const LinkInBioTextStyle(color: '#687065'),
    this.featuredLinkId,
    this.featuredLabel = 'โปรวันนี้',
    this.effects = const LinkInBioEffects(),
  });
  const LinkInBioAppearance.defaults() : this();

  final int version;
  final String themeId;
  final String? templateId;
  final String description;
  final String? logoKey;
  final String? coverKey;
  final LinkInBioBackground background;
  final String surfaceColor;
  final String buttonColor;
  final String buttonRadius;
  final LinkInBioTextStyle nameStyle;
  final LinkInBioTextStyle descriptionStyle;
  final LinkInBioTextStyle categoryStyle;
  final LinkInBioTextStyle buttonStyle;
  final LinkInBioTextStyle brandStyle;
  final String? featuredLinkId;
  final String featuredLabel;
  final LinkInBioEffects effects;

  factory LinkInBioAppearance.forTheme(String themeId) => switch (themeId) {
        'minimal' => const LinkInBioAppearance(),
        'shop' => const LinkInBioAppearance(
            themeId: 'shop',
            background:
                LinkInBioBackground(color: '#fff5e8', gradientColor: '#ffe0b2'),
            buttonColor: '#e85d24',
            nameStyle: LinkInBioTextStyle(color: '#3a2418', font: 'prompt'),
            descriptionStyle: LinkInBioTextStyle(color: '#765a49'),
            categoryStyle: LinkInBioTextStyle(color: '#c44918'),
            brandStyle: LinkInBioTextStyle(color: '#765a49')),
        'pastel' => const LinkInBioAppearance(
            themeId: 'pastel',
            background:
                LinkInBioBackground(color: '#f8f0fc', gradientColor: '#e6f1ff'),
            buttonColor: '#8b5fbf',
            buttonRadius: 'pill',
            nameStyle: LinkInBioTextStyle(color: '#473258'),
            descriptionStyle: LinkInBioTextStyle(color: '#766185'),
            categoryStyle: LinkInBioTextStyle(color: '#8b5fbf'),
            brandStyle: LinkInBioTextStyle(color: '#766185')),
        'dark' => const LinkInBioAppearance(
            themeId: 'dark',
            background:
                LinkInBioBackground(color: '#111827', gradientColor: '#263449'),
            surfaceColor: '#1f2937',
            buttonColor: '#34d399',
            nameStyle: LinkInBioTextStyle(color: '#f9fafb', font: 'prompt'),
            descriptionStyle: LinkInBioTextStyle(color: '#cbd5e1'),
            categoryStyle: LinkInBioTextStyle(color: '#a7f3d0'),
            buttonStyle: LinkInBioTextStyle(color: '#102a22'),
            brandStyle: LinkInBioTextStyle(color: '#cbd5e1')),
        'pink' => const LinkInBioAppearance(
            themeId: 'pink',
            background: LinkInBioBackground(
                mode: 'gradient', color: '#fff1f6', gradientColor: '#fde6ee'),
            surfaceColor: '#fff9fc',
            buttonColor: '#b94f78',
            buttonRadius: 'pill',
            nameStyle: LinkInBioTextStyle(color: '#67364d'),
            descriptionStyle: LinkInBioTextStyle(color: '#8d6576'),
            categoryStyle: LinkInBioTextStyle(color: '#67364d'),
            brandStyle: LinkInBioTextStyle(color: '#8d6576'),
            effects: LinkInBioEffects(
                background: true, entrance: true, stickers: 'hearts')),
        'garden' => const LinkInBioAppearance(
            themeId: 'garden',
            background:
                LinkInBioBackground(color: '#fffaf0', gradientColor: '#f5f0dc'),
            surfaceColor: '#fffef8',
            buttonColor: '#718852',
            nameStyle: LinkInBioTextStyle(color: '#35472c'),
            descriptionStyle: LinkInBioTextStyle(color: '#68765d'),
            categoryStyle: LinkInBioTextStyle(color: '#35472c'),
            brandStyle: LinkInBioTextStyle(color: '#68765d'),
            effects: LinkInBioEffects(entrance: true, stickers: 'flowers')),
        'cards' => const LinkInBioAppearance(
            themeId: 'cards',
            background: LinkInBioBackground(
                mode: 'gradient', color: '#eee8f7', gradientColor: '#e4d8f5'),
            surfaceColor: '#f7f3fc',
            buttonColor: '#ffffff',
            nameStyle: LinkInBioTextStyle(color: '#40364e'),
            descriptionStyle: LinkInBioTextStyle(color: '#796b87'),
            categoryStyle: LinkInBioTextStyle(color: '#40364e'),
            buttonStyle: LinkInBioTextStyle(color: '#40364e'),
            brandStyle: LinkInBioTextStyle(color: '#796b87'),
            effects: LinkInBioEffects(
                background: true, entrance: true, stickers: 'sparkles')),
        _ => throw const FormatException('Invalid profile theme'),
      };
  factory LinkInBioAppearance.fromTheme(String themeId) =>
      LinkInBioAppearance.forTheme(themeId);

  factory LinkInBioAppearance.forTemplate(String templateId) {
    final template = getProfileTemplate(templateId);
    if (template == null) {
      throw const FormatException('Invalid profile template');
    }
    final palette = template.palette;
    return LinkInBioAppearance.forTheme(template.themeId).copyWith(
      templateId: template.id,
      background: LinkInBioBackground(
        mode: template.effects['background'] == true ? 'gradient' : 'solid',
        color: palette.background,
        gradientColor: palette.gradient,
      ),
      surfaceColor: palette.surface,
      buttonColor: palette.button,
      buttonRadius: template.buttonRadius,
      nameStyle: LinkInBioTextStyle(color: palette.name, font: template.font),
      descriptionStyle:
          LinkInBioTextStyle(color: palette.description, font: template.font),
      categoryStyle:
          LinkInBioTextStyle(color: palette.category, font: template.font),
      buttonStyle:
          LinkInBioTextStyle(color: palette.buttonText, font: template.font),
      brandStyle: LinkInBioTextStyle(color: palette.brand, font: template.font),
      effects: LinkInBioEffects.fromJson(template.effects),
    );
  }

  factory LinkInBioAppearance.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    final theme = json['themeId'];
    final templateId = json['templateId'];
    if (templateId != null && templateId is! String) {
      throw const FormatException('Invalid profile template');
    }
    final template = getProfileTemplate(templateId as String?);
    if (templateId != null && (template == null || template.themeId != theme)) {
      throw const FormatException('Invalid profile template');
    }
    final radius = json['buttonRadius'];
    final featured = json['featuredLinkId'];
    if (version != 1 ||
        version is! int ||
        theme is! String ||
        !linkInBioThemeNames.containsKey(theme) ||
        radius is! String ||
        !const {'rounded', 'pill', 'square'}.contains(radius) ||
        (featured != null &&
            (featured is! String ||
                featured.trim().isEmpty ||
                featured.length > 80))) {
      throw const FormatException('Invalid profile appearance');
    }
    return LinkInBioAppearance(
        version: version,
        themeId: theme,
        templateId: templateId,
        description: _readText(json['description'], 280),
        logoKey: _readImageKey(json['logoKey']),
        coverKey: _readImageKey(json['coverKey']),
        background:
            LinkInBioBackground.fromJson(_readObject(json['background'])),
        surfaceColor: _readColor(json['surfaceColor']),
        buttonColor: _readColor(json['buttonColor']),
        buttonRadius: radius,
        nameStyle: LinkInBioTextStyle.fromJson(_readObject(json['nameStyle'])),
        descriptionStyle:
            LinkInBioTextStyle.fromJson(_readObject(json['descriptionStyle'])),
        categoryStyle:
            LinkInBioTextStyle.fromJson(_readObject(json['categoryStyle'])),
        buttonStyle:
            LinkInBioTextStyle.fromJson(_readObject(json['buttonStyle'])),
        brandStyle:
            LinkInBioTextStyle.fromJson(_readObject(json['brandStyle'])),
        featuredLinkId: featured as String?,
        featuredLabel: _readText(json['featuredLabel'], 40),
        effects: json.containsKey('effects')
            ? LinkInBioEffects.fromJson(_readObject(json['effects']))
            : const LinkInBioEffects());
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'version': version,
      'themeId': themeId,
      'templateId': templateId,
      'description': description,
      'logoKey': logoKey,
      'coverKey': coverKey,
      'background': background.toJson(),
      'surfaceColor': _readColor(surfaceColor),
      'buttonColor': _readColor(buttonColor),
      'buttonRadius': buttonRadius,
      'nameStyle': nameStyle.toJson(),
      'descriptionStyle': descriptionStyle.toJson(),
      'categoryStyle': categoryStyle.toJson(),
      'buttonStyle': buttonStyle.toJson(),
      'brandStyle': brandStyle.toJson(),
      'featuredLinkId': featuredLinkId,
      'featuredLabel': featuredLabel,
      'effects': effects.toJson(),
    };
    // Const constructors keep old call sites compatible; validate when encoding
    // a network request or saving a draft so invalid style values never persist.
    LinkInBioAppearance.fromJson(json);
    return json;
  }

  LinkInBioAppearance copyWith(
          {int? version,
          String? themeId,
          Object? templateId = _unset,
          String? description,
          Object? logoKey = _unset,
          Object? coverKey = _unset,
          LinkInBioBackground? background,
          String? surfaceColor,
          String? buttonColor,
          String? buttonRadius,
          LinkInBioTextStyle? nameStyle,
          LinkInBioTextStyle? descriptionStyle,
          LinkInBioTextStyle? categoryStyle,
          LinkInBioTextStyle? buttonStyle,
          LinkInBioTextStyle? brandStyle,
          Object? featuredLinkId = _unset,
          String? featuredLabel,
          LinkInBioEffects? effects}) =>
      LinkInBioAppearance(
        version: version ?? this.version,
        themeId: themeId ?? this.themeId,
        templateId: identical(templateId, _unset)
            ? this.templateId
            : templateId as String?,
        description: description ?? this.description,
        logoKey: identical(logoKey, _unset) ? this.logoKey : logoKey as String?,
        coverKey:
            identical(coverKey, _unset) ? this.coverKey : coverKey as String?,
        background: background ?? this.background,
        surfaceColor: surfaceColor ?? this.surfaceColor,
        buttonColor: buttonColor ?? this.buttonColor,
        buttonRadius: buttonRadius ?? this.buttonRadius,
        nameStyle: nameStyle ?? this.nameStyle,
        descriptionStyle: descriptionStyle ?? this.descriptionStyle,
        categoryStyle: categoryStyle ?? this.categoryStyle,
        buttonStyle: buttonStyle ?? this.buttonStyle,
        brandStyle: brandStyle ?? this.brandStyle,
        featuredLinkId: identical(featuredLinkId, _unset)
            ? this.featuredLinkId
            : featuredLinkId as String?,
        featuredLabel: featuredLabel ?? this.featuredLabel,
        effects: effects ?? this.effects,
      );
}
