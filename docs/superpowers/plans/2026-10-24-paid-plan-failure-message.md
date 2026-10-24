# Thai reason for scheduled posts stopped by an expired plan

Baseline: `origin/main` at `fc1ddd38` (2026-10-24). Branch:
`claude/mobile-paid-plan-failure-message`. Companion to PR #29, where the API
fails a due scheduled post with platform reason `PAID_PLAN_REQUIRED` when the
owner is back on Basic.

## Problem

Post detail shows each failed platform's `errorMessage` as `สาเหตุ: …`, mapping
only known messages to Thai. Without this change it would show the raw code
`PAID_PLAN_REQUIRED`. It would also offer "ทบทวนช่องทางนี้" (review the
channel), which opens account-connection guidance that cannot fix an expired
plan.

## Change

`apps/mobile/lib/features/posts/post_detail_screen.dart`:
- `PAID_PLAN_REQUIRED` maps to "แพ็กเกจหมดอายุก่อนถึงเวลาโพสต์
  จึงยังไม่ได้ส่งโพสต์นี้ ต่ออายุแพ็กเกจ Starter หรือ Pro แล้วสร้างโพสต์ใหม่".
- The channel-review button is hidden for that reason only. Other failures
  keep it.

No API, schema or dependency change. The app does not open the paywall from
this screen; renewing stays in the existing billing flow.

## Reproduction before the fix

`test/post_detail_paid_plan_failure_test.dart` was pushed alone first (commit
`da6b5f86`), and CI ran it against the unchanged app. CI Flutter Mobile failed
on exactly the new case: the Thai reason was not found, because the raw code
was shown. The guard that keeps channel review for other failures passed.
Locally, Flutter was blocked by another session's long-running `flutter test`.

## Verification

- Fix commit `1db86a14`: CI Flutter Mobile passed (`flutter analyze` "No issues
  found" and the full `flutter test` suite), and Backend API passed.
- Not verified: a real device.
