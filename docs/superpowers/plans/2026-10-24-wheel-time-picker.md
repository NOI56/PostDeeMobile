# Looping wheel time picker — 2026-10-24

## Request and baseline

The user approved implementing a native-style wheel time selector. Replace the
uploader and Calendar reschedule time dialogs with one shared Flutter component;
keep their scheduling behavior and limits intact.

The root task verified fresh `main` at
`4f2242000d0b49bae9bdbfaa04a27be107474991`. The active worktree is
`C:\Users\stopp\.codex\worktrees\platform-consent-preserve\PostDeeMobile`,
branch `codex/platform-captions`. HEAD/tracking `origin/main` share this merge
base and have 0 ahead/0 behind at the start. Preserve the three pre-existing
generated Windows plugin changes and unrelated work in other checkouts.

Reviewed the existing uploader/Calendar time entry points,
`post_schedule_policy.dart`, downstream UTC serialization, `API.md`'s rolling
schedule rules and earlier Calendar notes before documenting the change.

## Approved behavior

- Add `apps/mobile/lib/features/shared/postdee_time_picker.dart`, using
  Flutter `CupertinoPicker` wheels in a shared 24-hour presentation. This is a
  Flutter component, not a new operating-system picker or plugin.
- Replace the uploader and Calendar reschedule `showTimePicker` calls only.
  Keep date selection, selected-day handoff and other scheduling controls.
- Hours loop `23 → 00 → 01`; minutes loop `59 → 00 → 01`. The two columns
  are independent: wrapping minutes does not increment hours, and wrapping
  hours does not advance/reverse the selected date.
- Start at the caller's existing selected time. A new uploader schedule retains
  the current **18:30** fallback; Calendar retains the post's current local time.
- Stage wheel changes inside the dialog. Only confirmation returns a new
  `TimeOfDay`; Cancel or dismissal leaves the caller's previous value intact.
- Preserve device-local display/composition with the supplied date. The existing
  API client converts the composed instant to UTC for requests. Do not add a
  fixed Bangkok offset, change the date silently or round to larger intervals.
- Maintain light/dark readability, tappable confirmation/cancellation controls,
  selected-value semantics and usability on narrow screens/enlarged text.

## Existing boundaries

The dialog chooses a time; it does not publish, reschedule or save on its own.
The uploader keeps its draft and review flow. Calendar keeps its owner-scoped,
still-queued reschedule validation and stale-result/auth boundaries. Switching
account or leaving a screen must not let a late picker result change another
owner's state. The uploader captures its auth session and draft generation
before loading policy/opening the picker, then checks both before applying a
result. Returning to the original account after an A-to-B-to-A switch does not
make the older session current again.

Future-time validation and current-plan limits stay unchanged. Starter permits
14 days and Pro 30 days, measured as rolling real instants/24-hour durations,
with the existing inclusive upper boundary and server validation authoritative.
Do not substitute a number of visible calendar dates or extend the window when
a wheel wraps. Existing accepted schedules, monthly post/AI quota rules,
publishing readiness, queue safeguards and provider behavior remain unchanged.

`API.md` was checked and needs no edit: schedule creation/rescheduling already
accept RFC 3339 instants, normalize offsets to UTC and enforce the existing
future/paid-plan/14–30-day guards. No API contract, backend runtime, database,
migration, dependency, provider, credential or environment change is introduced.

## Files and verification

Runtime scope is the shared picker and its two existing callers, with regression
tests owned by the implementation task. Documentation scope is `README.md`,
`ARCHITECTURE.md`, `ROADMAP.md` and this record; preserve previous release notes.

Verification is specific to this candidate; earlier caption-release results are
not reused as proof:

- Test-first shared-component and uploader checks failed before implementation.
  The responsive Cancel regression also failed before its layout fix. Evidence:
  `component-red.log`, `uploader-time-red.log`, `component-responsive-red.log`.
- Shared picker: **14 passed**, including real hour/minute drag across zero in
  both directions, multiple cycles/negative indices, independent columns/date,
  initial 23:59, exact nearest-center confirmation during movement, Cancel,
  system Back, reopening, adjustable semantics and reduced-motion selection.
- Uploader scheduling: **13 passed**, including selected-date retention,
  Cancel/reopen, A-to-B-to-A rejection and a fixture draft-save request whose UTC
  instant equals the chosen local date and time. No upload/publication is used
  for that draft check.
- Calendar/cover/shared schedule policy: **66 passed**. Existing date-picker
  confirmations stay unchanged; seven time-confirmation taps use the new wheel
  key. Added tests change the minute before Cancel and verify no PATCH, retained
  queue/action availability, plus rejecting an old owner session while open.
  Existing downgrade, real rolling 14/30-day limits, past-time rejection, cover
  retention, busy feedback and stale reload checks remain green.
- Validated Staging configuration: **93 passed** across shared picker, uploader,
  Calendar, cover mutations and shared schedule policy.
- Real Anuphan/Material Icons rendering: **2 passed**, with inspected captures
  at light 430x900 and dark 320x900 / 1.7x text. Enlarged text uses full-width
  stacked actions so `ยกเลิก` stays on one line, without shrinking fonts. Shared
  component tests also cover 320x600 with a 120px keyboard inset.
- Full Mobile suite: **2,819 passed / 6 skipped**, no failures, in 5m38s
  (`flutter test --concurrency=4 --reporter expanded`). Full `flutter analyze`
  passes with no issues; the explicit mounted check satisfies async-context
  analysis alongside the session/draft guard.
- Exact-source debug Staging APK **12046** built successfully (161.4s), package
  `com.postdee.postdee_mobile.staging`, version name `0.1.0-staging`. Its complete
  embedded shared-picker, uploader and Calendar sources match the final files.
  API remains `https://postdee-api-staging.onrender.com`, Firebase auth is enabled
  with the existing matching debug project, local mock auth is disabled and the
  unchanged helper validates the existing RevenueCat Test Store configuration.
  Sentry release is `postdee-mobile@wheel-time-picker+12046`.
- APK SHA-256:
  `c8b7136cff233674af3d62379fa789c1c457b0487997a3d66352ec993d5e9b08`
  (292,746,425 bytes). Package, launcher and safe environment metadata are
  recorded in `wheel-build-result.json`.
- Evidence is under `D:\PostDeeMobile\artifacts\wheel-time-picker-20261024`:
  `component-tests.log`, `uploader-time-final.log`, `calendar-wheel-tests.log`,
  `staging-schedule-tests.log`, `mobile-full-tests.log`,
  `mobile-analyze-final.log`, `staging-build.log`, `visual-final.log` and
  `visual-final/wheel-light.png` / `wheel-dark-large.png`.
- One earlier parallel capture lost an OS temporary compiler output and was
  stopped; its log is retained as `visual-attempt-temp-failure.log`. Final
  capture/full-suite/Staging verification uses a task-owned temporary directory
  and passes. That interrupted attempt is not final verification evidence.
- Final diff/whitespace and a separate read-only functional review pass. Only
  the shared component, two callers, five test files and four documentation
  files belong to this task. No API/schema/dependency/CI/Render change exists;
  unrelated generated Windows edits remain excluded.
- Installed/native smoke: **not performed for this candidate**. Real-handset,
  actual scheduled publication and signed iOS/store delivery are not established
  by widget checks or the APK build.

Automated tests may use fixtures. No real post, queue mutation, AI credit spend
or purchase is required to verify the picker. A widget or build result does not
establish actual scheduled publication.

## Delivery boundary

The implementation handoff completed without merge, push, deployment or
installation. The user subsequently requested `main/push`, authorizing Git
integration of the twelve intended runtime/test/documentation files. An
independent pre-push review rechecked all three runtime SHA-256 values against
the verified APK, the final full-suite/Staging/analyzer logs and the fresh
`4f22420` main baseline; no source changed after verification.

Keep unrelated generated Windows files and work in other checkouts excluded.
The Git delivery does not install or restart the app, mutate queued posts or
deploy a backend. Preserve the existing app, account, storage and data. APK
12046 remains available for a later update/native acceptance. The existing API
supports the UI, so this picker requires no backend deployment or migration.
