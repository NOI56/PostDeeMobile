# Smooth activity feedback during publishing

สถานะ: VERIFYING ANDROID DELIVERY — selected the first (เรียบเนียน)
full-screen mockup; focused and full Mobile tests pass.

## Baseline and scope

- Fresh `origin/main`: `644fea90bb4b0b70078cf2f3642514d57a434447` on 2026-10-20.
- Start from `777db096ecbab93dcaa228c9aa0d18c3c86bd94f`, which contains the
  locally verified remembered-settings feature. Keep that feature and the three
  unrelated Windows generated-plugin metadata changes intact.
- Work on `codex/publish-flow-smooth-motion`; no merge, push or deployment is
  part of this selection.
- The selected mockup is the full publishing-progress screen, rather than the
  previous Home/Calendar post-card animation. Change only its presentation.

## Intended behavior

Keep the real reported stage/fraction, stage-progress semantics, error/retry,
back-navigation guards and truthful accepted/queued/provider outcomes. Add an
upload emblem with one gently orbiting dot, a light clipped inside the filled
portion of the real progress rail, destination labels and a compact three-step
summary (preparing, uploading, creating a queue). Do not advance percentages or
report publication merely because an animation completes.

Use one retained animation clock for the dot and light. Pause/reset it for
background lifecycle, disabled TickerMode and reduced motion; dispose it when
the pending view ends. Stage updates must not repeat publishing or restart the
clock unnecessarily. The layout must fit a narrow screen and enlarged text.

No dependency, API contract, schema, entitlement, provider configuration or
feature-flag change. README/ROADMAP/ARCHITECTURE/Mobile README will reflect the
final local status. API.md was checked and requires no contract update.

## Verification plan

Write regression tests first, including fixed progress while the activity loops,
one publish operation, motion guards, truthful completion/error and small-screen
layout. Run the focused tests, complete Mobile suite and analysis on the exact
source, then build Staging Android x86_64. Prefer a controlled local render for
the pending screen so verification does not create a real social post. Verify
the installed Staging package/environment and retain the user's data.

## Verification receipt

- Runtime/test candidate: `a5aefac4f421e26293cdaab1e6ac09138aacb4d6`.
- Tests-first RED: 17 existing cases pass and eight new cases fail because the
  orbit, steps and destination chips do not exist yet. The implemented focused
  batch passes **51/51**, including the draft-flow and owner-change preflight
  checks. Only six deliberately pending waits switch to bounded pumps; their
  original assertions and post-completion settlement remain intact.
- Full Mobile suite: **2,488 passed / 3 optional preview skips**, exit 0 in
  171.8 seconds. Real progress does not advance with elapsed animation time;
  publishing is called once. Lifecycle/reduced-motion/TickerMode, outcome
  disposal, all nine stages and 320dp / 200% text coverage pass.
- Full-suite runtime and all non-preview tests match delivery candidate
  `a5aefac` byte-for-byte. After that run, only the skipped optional render
  harness and documentation changed; the final harness is explicitly run
  separately. See `tested-to-delivery-comparison.json`.
- Use a local production-widget render fixture, not a real post. The initial
  harness omitted the app's global theme synchronization; it was corrected to
  match the real Light/Dark palettes. Outcome button fonts fall back to Ahem
  in the widget tester, so final PNG captures cover the pending screen only;
  outcome behavior remains asserted without changing its production UI.

Evidence is under
`D:\PostDeeMobile\artifacts\smooth-publish-progress-20261020`.
Final analysis, render and Android build/install receipts will be added here.
