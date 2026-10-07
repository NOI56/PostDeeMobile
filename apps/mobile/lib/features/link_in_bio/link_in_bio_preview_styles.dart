import 'package:flutter/material.dart';
import '../../core/models/link_in_bio_appearance.dart';

Color bioColor(String value) =>
    Color(int.parse('ff${value.substring(1)}', radix: 16));
String? bioFont(String value) => switch (value) {
      'anuphan' => 'Anuphan',
      'prompt' => 'Prompt',
      _ => null,
    };
TextStyle bioTextStyle(LinkInBioTextStyle value,
        {double size = 16, FontWeight weight = FontWeight.w400}) =>
    TextStyle(
        inherit: false,
        color: bioColor(value.color),
        fontFamily: bioFont(value.font),
        fontSize: size,
        fontWeight: weight,
        height: 1.6);
