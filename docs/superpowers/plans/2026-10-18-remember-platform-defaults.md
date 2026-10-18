# Remember publishing settings per connected channel

สถานะ: VERIFYING — targeted tests pass; local branch only, not merged, pushed,
deployed or installed.

## Request and baseline

จำการตั้งค่าที่ใช้ซ้ำ เพื่อไม่ต้องกรอกใหม่เมื่อสร้างคลิปครั้งถัดไป
โดยร่างคลิปเดิมยังใช้ค่าของร่าง และการกดยกเลิกไม่เปลี่ยนค่าที่จำไว้

- Canonical `main` and fresh `origin/main`: `644fea90bb4b0b70078cf2f3642514d57a434447`,
  initially 0 ahead / 0 behind; branch `codex/remember-platform-defaults`.
- Reuse the attached `admin-usage-accuracy/PostDeeMobile` worktree. Preserve its
  three pre-existing Windows generated-plugin metadata changes and unrelated work.
- Existing platform settings are initialized per composer; local publish drafts
  already preserve same-clip choices and reset current capability/consent proof.

## Reusable settings and fresh clip declarations

| Platform | Remember for the next new clip | Review per clip |
| --- | --- | --- |
| TikTok | Inbox / Direct mode | Manual privacy and interactions, commercial/AI disclosure, music/policy confirmation, creator capabilities |
| YouTube | Visibility and explicit audience choice | Title, synthetic-media answer, community certification |
| Instagram | Share to feed | AI disclosure and cover |
| Facebook Page Video | Publish / Page draft | AI disclosure and cover |

TikTok explicitly requires no default privacy value and interactions initially
off: [Content Sharing Guidelines](https://developers.tiktok.com/docs/en/content-sharing-guidelines).
YouTube allows a channel audience default with per-video overrides:
[audience settings](https://support.google.com/youtube/answer/9527654?hl=en).
PostDee saves its own editable local preference; it does not fetch or modify
YouTube Studio defaults. Studio's browser-upload defaults do not automatically
apply to mobile/editor uploads:
[upload defaults](https://support.google.com/youtube/answer/2660027?hl=en).

## Implementation boundary

- Allowlisted SharedPreferences data only, scoped by API endpoint, stable owner
  and verified connection identity/revision; never use the display name as a key.
- Load when opening a fresh platform form and before entering review, including
  the progress-control shortcut. This honors optional Instagram choices and does
  not silently replace remembered TikTok Direct with Inbox when a sheet is skipped.
  Keep same-form saved choices and restored drafts ahead of defaults. Distinguish
  an actual restored draft from a new form that has merely been saved locally;
  saving early or selecting another platform after saving cannot skip defaults.
  Loading is cancellable in the sheet and bounded to eight seconds before review;
  stale owner, connection or form results cannot replace current intent.
- Persist only after explicit platform Save. Storage errors leave the current
  clip usable and explain that remembering did not succeed. Cancel/dismiss does
  not write. Explicit saved preferences can finish persisting after the
  composer closes when its auth lifecycle is still current. Account deletion
  clears the deleted owner's local defaults.
- Serialize writes, guard auth lifecycles and invalidate pending reads/writes
  during owner cleanup. Corrupt or unsupported stored values fail closed.
- Clip replacement carries only reusable choices with their source-channel
  binding and resets clip-specific declarations. Replacing the clip of a restored
  legacy draft reads current channel preferences afresh, because that draft has
  no stored channel-default provenance. Do not auto-select destinations or send anything.
- No dependency, API field, server behavior, database, plan, entitlement,
  feature-flag or environment change; no migration or API deployment required.

## Verification

Tests were written before runtime changes. The initial widget compile RED records
the missing Uploader constructor dependency, not a functional storage failure.
The first targeted run found an immediate failed-future handling bug, which was
fixed by consuming storage errors before the modal's first frame. Separate new
draft regressions reproduced remembered Instagram `false` becoming `true` before
the restored-draft provenance fix. Independent source reviews covered the
allowlist, owner/channel isolation, async writes and optional-sheet paths.

Final targeted tests pass **131**, with one optional visual-preview case skipped,
including **23** new widget cases and **20** store cases. The existing unified
settings and shell/account-deletion tests also pass in this batch. Evidence:
`D:\PostDeeMobile\artifacts\remember-settings-tooling-20261018\remembered-widget-targeted-final.log`;
the eight relevant source/test files match their D: verification copies by SHA-256.

The first full run passes 2,479 with two optional skips and finds one old recovery
test that confirms a replacement video without re-answering its declarations.
The updated test first proves confirmation is disabled, then explicitly answers
the new clip's fields and retains every existing assertion: same request ID,
changed media fingerprint/key, retained draft and server 409 rejection. Runtime
recovery is unchanged. The expanded targeted batch then passes **144**, with one
optional preview skipped. Evidence: `remembered-recovery-targeted-final.log`.

Pending repeat full Mobile suite, analysis and Staging build.
Use the D: verification snapshot and temp/cache locations because C: has little
free space. Existing installed Staging APK12026 and live API remain untouched.
No native or real provider publication has been tested for this change yet.
