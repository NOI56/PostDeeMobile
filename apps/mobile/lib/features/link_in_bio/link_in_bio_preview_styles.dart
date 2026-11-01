import 'package:flutter/material.dart';
import '../../core/models/link_in_bio_appearance.dart';

Color bioColor(String value) =>
    Color(int.parse('ff${value.substring(1)}', radix: 16));
String? bioFont(String value) => switch (value) {
      'anuphan' => 'Anuphan',
      'prompt' => 'Prompt',
      _ => null,
    };
// Most Thai shop names start with "ร้าน" and a lone ร reads like a Latin S in
// loopless fonts, so the initial comes from the name itself. A leading vowel
// (เ แ โ ใ ไ) is skipped in favor of the consonant it belongs to.
final _initialLetter = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _leadingThaiVowel = RegExp('[\u0e40-\u0e44]');
String bioAvatarInitial(String storeName) {
  final name = storeName.trim();
  final stripped = name.replaceFirst(RegExp(r'^ร้าน\s*'), '');
  final characters =
      (stripped.isEmpty ? name : stripped).runes.map(String.fromCharCode);
  return characters.firstWhere(
      (character) =>
          _initialLetter.hasMatch(character) &&
          !_leadingThaiVowel.hasMatch(character),
      orElse: () => characters.isEmpty ? 'ร' : characters.first);
}

// Phone numbers wrap as one unit: word joiners and no-break spaces stop the
// line breaker from splitting them at a hyphen or space.
final _phoneNumber = RegExp(r'\+?\d[\d -]{6,}\d');
String bioKeepNumbersTogether(String text) => text.replaceAllMapped(
    _phoneNumber,
    (match) => match[0]!.replaceAll('-', '-\u2060').replaceAll(' ', '\u00a0'));

TextStyle bioTextStyle(LinkInBioTextStyle value,
        {double size = 16, FontWeight weight = FontWeight.w400}) =>
    TextStyle(
        inherit: false,
        color: bioColor(value.color),
        fontFamily: bioFont(value.font),
        fontSize: size,
        fontWeight: weight,
        height: 1.6);
