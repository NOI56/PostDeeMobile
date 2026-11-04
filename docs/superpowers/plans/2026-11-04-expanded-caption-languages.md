# Full documented caption language list — 2026-11-04

Status: isolated local candidate; no publication, merge, deployment or device update.

## Scope and baseline

The owner asked to include the full set of languages AI can read after reviewing
the initial 17-language caption picker. This candidate adds the 109 named entries
in Google's published general-use text-language list, plus Automatic. It does not
claim every possible human language or guarantee speech/audio accuracy.

Verified GitHub `main`: `927a302002841aab770aeba30cc6302f89783261`.
Branch: `codex/expanded-caption-languages`. This base already includes PR #60 and
the separately integrated clip-duration PR #61; preserve both. The earlier local
Staging-record commit `905ebc86` remains on its original branch and is excluded.
Open PR discovery was empty at the start. Source edits are restricted to the
language catalog/generation, caption request/provider/picker, tests and contracts.

## Evidence and boundaries

- [Google supported languages](https://firebase.google.com/docs/ai-logic/models?hl=en#supported-languages),
  updated 2026-11-03 UTC and checked 2026-11-04, names 109 unique general-use
  text-language entries. Chinese `zh` covers simplified/traditional as one entry.
- Google's current examples describe newer general-use models. The configured
  app stays on `gemini-2.5-flash-lite`; its
  [exact model card](https://aistudio.google.com/docs/models/gemini-2.5-flash-lite)
  confirms text/audio input and text output, but does not certify all catalog
  languages or equal quality. No provider/model migration is included.
- The [audio guide](https://aistudio.google.com/docs/audio) has no exhaustive
  audio input-language list/count for this path. Keep speech detection distinct
  from the user's output choice and do not advertise 109 certified audio languages.
- [Unicode CLDR aliases](https://raw.githubusercontent.com/unicode-org/cldr/main/common/supplemental/supplementalMetadata.xml)
  supply `iw` → `he` and the product-compatible `tl` → `fil` mapping.
  [CLDR script data](https://raw.githubusercontent.com/unicode-org/cldr/main/common/supplemental/supplementalData.xml)
  guides permissive writing-system checks; it is not evidence of Gemini quality.
  Google's `mni-Mtei` remains specific to Meitei Mayek; `mni` is a product alias.

## Implementation and rollout

One versioned JSON catalog generates static API and Mobile data, with no runtime
catalog fetch or new dependency. A generator check/test runs in CI. Preserve all
17 prior codes, Automatic, unknown old-draft fallback and existing data. Known
aliases canonicalize before generation. Reject invalid requests before costs.

The searchable picker keeps Automatic easy to reach and supports Thai/English
UI, native names, codes, aliases, empty results, keyboard access and cancellation.
Preserve owner/draft/generation guards so a late modal selection cannot overwrite
a newer form. Writing/audit use the requested language while retaining original
media evidence and source-language context. Script-family checks accept legitimate
multi-script languages but cannot distinguish languages sharing a script.

No schema/migration, entitlement, pricing, queue, model, environment or clip-duration
change. **API before Mobile**: new codes require the new API, while installed older
clients continue using their old codes or Automatic. Existing captions, platform
previews, billing, quotas, refunds and publishing behavior remain intact.

## Validation

- Node 22.23.3: generator parity check and all 24 generator tests passed.
- API full suite: 206 files passed, 15 skipped; 3,997 tests passed, 80 skipped.
  The skipped real-database suites remain opt-in; no schema or persisted-store
  change is included. Typecheck, build, Prisma validation and seed/config
  TypeScript checks passed.
- Mobile targeted regression tests: 66 passed, covering all catalog values,
  aliases, draft restoration, requests, disabled states, owner changes, search,
  cancellation, Thai/English, light/dark, 2x text and short-window keyboards.
- Independent final diff review and `git diff --check` passed. PR #61 duration
  wiring, configuration, schema and release files remain intact.
- Mobile full suite passed: 5,268 tests, 10 skipped. `flutter analyze --no-pub`
  passed with no issues. Analysis first identified a deprecated assertion in the
  new widget test; after replacing it with the current semantics API, all 16
  picker tests and analysis passed again. No application behavior changed.
- `flutter build web --debug --no-pub
  --dart-define-from-file=staging.local.example.json` passed, including its Wasm
  dry run. This is a local build with the repository's Staging example defines;
  it has not been hosted or used to call the live API with new language codes.
- Two actual-widget preview capture tests passed for light/dark. Search for
  Russian by Thai/English name, selection and the serialized `ru` request were
  verified with local test doubles. The primary review image is saved privately
  in the owner's Library.
  Captures and evidence JSON remain outside the repository at
  `D:\codex\2026-11-04\task\caption-language-109-review`.
- There is no connected device for a physical-device check. Complete installed
  font coverage and real Gemini quality across all 109 languages remain untested.

Tests use controlled provider responses; no real Gemini multilingual accuracy or
paid generation is claimed. No Staging or Production mutation is part of this
local candidate.
