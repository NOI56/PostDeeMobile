---
name: postdee-ui-design
description: Change or add PostDee Flutter screens, layout, copy, or translations so they match the app's current look, the owner's design preferences, and both Thai and English. Use for visual or wording changes in apps/mobile; not for API or build work.
---

# PostDee UI and copy

## Use what exists

- **Tokens:** `apps/mobile/lib/core/theme/app_theme.dart` (`AppTheme`). Use its colors, spacing scale (`spaceXs` to `spaceXl`), radii (`cardRadius`, `tileRadius`, `pillRadius`), and paddings (`screenPadding`, `tabScreenPadding`, `navOverlap` for content under the floating bottom nav). Do not hard-code a new color or spacing value when a token fits. Light and dark palettes both exist; light is the default.
- **Font:** Anuphan, bundled in the app.
- **Shared widgets:** `apps/mobile/lib/features/shared/`, for example `PostDeeCard`, `PostDeeSectionHeader`, `PostDeeSoftPill`, `PostDeeNotice`, `PostDeeSkeleton`, `PostDeePressFeedback`, `showPostDeeUndoToast`, `showPostDeeStatusSheet`, `showPostDeeTimePicker`, and the publishing motion widgets. Reuse them before writing a new one.
- **Navigation:** the bottom tabs are listed in `AGENTS.md`. Retired features get no entry point, card, or teaser.
- **Design reference:** on the owner's machine a hi-fi prototype lives at `D:\ออกแบบแอปมือถือใหม่ (2)\design_handoff_postdee` (`PostDee.dc.html` holds exact values). Use it for spacing and styling of screens it covers. Where it differs from the shipped app (navigation, removed features), the current code and `AGENTS.md` win. It may be absent on other machines.

## Owner's design preferences

- Clean and breathable: generous spacing, light cards with a soft shadow and no colored glow, fewer elements per screen.
- Remove decorative tags and pills; keep functional badges (platform, status, plan).
- No fake content: no demo names, sample metrics, or charts drawn from made-up data. Greet with the real signed-in name or no name, without emoji. If the API does not provide a number, do not show one.
- Avoid a template look: group related items into one card with rows and dividers instead of stacking identical cards.
- Plan comparisons show missing features with a neutral gray dash, never a green check (`paywall_screen.dart`).
- A small UI request is not a redesign. Do not touch billing, publishing, or account behavior while restyling.

## Copy and translations

- Thai is the default language and English is complete. Every new user-visible string needs both.
- Feature copy lives in per-feature `*_localizations.dart` files (for example `features/onboarding/onboarding_localizations.dart`, `features/uploader/channel_localizations.dart`): a Thai/English text helper and a Thai→English map. Add to the file for that feature. `core/localization/postdee_localizations.dart` holds app-wide strings and the language list.
- Leave user data, platform names, and native language names untranslated.
- Thai copy is short, friendly, and plain; avoid technical terms the seller would not use.

## Behavior to keep

- Saved drafts and in-progress input survive navigation, rebuilds, and language or theme switches.
- Loading, empty, and error states use the shared skeleton and notice widgets; errors offer a retry when one makes sense.
- Animations respect reduced motion (`MediaQuery.disableAnimationsOf`), as existing screens do.

## Verify

1. Widget tests for the changed behavior, including an English variant when copy changed (existing examples: `test/*_english_test.dart`). Run `flutter analyze` and the related tests with the workspace SDK.
2. Check light and dark themes, a small phone width, and long Thai text for overflow.
3. Show the change on a device with `postdee-android-build` and capture a screenshot. `apps/mobile/tool/account_ui_preview.dart` is an offline visual-QA entry for account screens; run it only on a separate emulator, never on the device holding the owner's app.
