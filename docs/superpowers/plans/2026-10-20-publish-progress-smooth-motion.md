# Smooth activity feedback during publishing

สถานะ: IMPLEMENTING — selected the first (เรียบเนียน) full-screen mockup.

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

Verification results and delivery limits will be recorded here.
