import 'profile_platform_catalog.generated.dart';

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

class LinkInBioAppearance {
  const LinkInBioAppearance({
    this.version = 1,
    this.themeId = 'minimal',
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
  });
  const LinkInBioAppearance.defaults() : this();

  final int version;
  final String themeId;
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
        _ => throw const FormatException('Invalid profile theme'),
      };
  factory LinkInBioAppearance.fromTheme(String themeId) =>
      LinkInBioAppearance.forTheme(themeId);

  factory LinkInBioAppearance.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    final theme = json['themeId'];
    final radius = json['buttonRadius'];
    final featured = json['featuredLinkId'];
    if (version != 1 ||
        version is! int ||
        theme is! String ||
        !const {'minimal', 'shop', 'pastel', 'dark'}.contains(theme) ||
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
        featuredLabel: _readText(json['featuredLabel'], 40));
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'version': version,
      'themeId': themeId,
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
      'featuredLabel': featuredLabel
    };
    // Const constructors keep old call sites compatible; validate when encoding
    // a network request or saving a draft so invalid style values never persist.
    LinkInBioAppearance.fromJson(json);
    return json;
  }

  LinkInBioAppearance copyWith(
          {int? version,
          String? themeId,
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
          String? featuredLabel}) =>
      LinkInBioAppearance(
        version: version ?? this.version,
        themeId: themeId ?? this.themeId,
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
      );
}
