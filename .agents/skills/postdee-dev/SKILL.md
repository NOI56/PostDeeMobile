---
name: postdee-dev
description: Locate the PostDee code, contracts, and tests affected by a change to the Flutter app, Express/Prisma API, or admin console, and route to the matching PostDee workflow skill. Use when starting a PostDee feature, bug fix, or code question; not for unrelated projects.
---

# PostDee development map

`AGENTS.md` is the rulebook and is already loaded: baseline and no-regression policy, retired features, the Facebook Page Reels rule, language rules, and the completion summary. Do not restate it. This skill adds only where things live, which specialized skill fits, and the local facts that are easy to get wrong.

## Pick the workflow skill

| Task | Skill |
| --- | --- |
| Build or install the app on an Android device or emulator | `postdee-android-build` |
| Change an API route, payload, Prisma model, or migration | `postdee-api-schema-change` |
| Change a screen, theme, copy, or translation | `postdee-ui-design` |
| Deploy or inspect the Staging API on Render | `postdee-staging-deploy` |
| Post for real through a connected social account | `postdee-publish-e2e` |
| Decide whether a candidate is ready for Production or a store | `postdee-release-check` |

Use several when a task spans them, for example a schema change that ends in a Staging deploy.

## Find the affected code

Read [the project map](references/project-map.md) for the area, then trace the flow end to end: screen → Mobile service and `PostDeeApiClient` → API route → store (memory and Prisma) → provider adapter → tests on both sides.

`rg` respects `.gitignore`, so sibling worktrees under `.worktrees/` and `.claude/worktrees/` are skipped automatically. `artifacts/` and `output/` in the root checkout are untracked scratch output, not source; exclude them from searches.

## Facts that are easy to get wrong

- **Two stores per persisted feature.** Most API features have a memory store (default for tests and local runs) and a Prisma repository, chosen by a `*_STORE` variable through a factory, for example `postStore.ts`, `prismaPostRepository.ts`, and `postStoreFactory.ts`. Change both and test both.
- **Flutter SDK.** Use the workspace SDK at `.tools/flutter/bin/flutter.bat` in the root checkout. It is gitignored, so a linked worktree does not contain it; find the root with `git rev-parse --path-format=absolute --git-common-dir`. A global Flutter install on the machine may be a different version; do not switch silently.
- **Node.** The API pins its Node version in `apps/api/package.json` `engines`. On Windows use `npm.cmd` and `npx.cmd`. `npm.cmd run typecheck` exists in addition to the commands in `AGENTS.md`.
- **Generated Windows files.** `flutter pub get` on Windows rewrites `apps/mobile/windows/flutter/generated_plugin_registrant.cc` and `generated_plugins.cmake`. Leave them out of commits unless the task changes plugins.
- **Large Mobile suite.** The full `flutter test` run can exhaust PowerShell memory on the owner's machine. If it stops early, report the partial count and rely on the GitHub CI run for the same commit, naming the run. Do not call a partial run a pass.
- **Opt-in database tests skip silently.** A green API suite does not prove Prisma behavior; see `postdee-api-schema-change`.
- **Commit messages on `main` carry `[skip render]`.** The Production Render service auto-deploys from `main`; the marker keeps a merge from deploying it. Keep the marker on merge commits unless the owner asks for a Production deploy.
- **Admin console UI** is plain HTML/CSS/JS in `apps/api/src/modules/admin/web/`, copied into `dist` by the build. Preview it locally with `npm.cmd run admin:preview`.
