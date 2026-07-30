# Gemini Model Separation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Use `gemini-3.5-flash-lite` for transcript and visual AI edit planning while keeping `gemini-2.5-flash-lite` as the primary caption model.

**Architecture:** Keep the existing provider boundaries and use the two existing environment variables as the source of truth. Migrate only AI edit planning to Gemini 3.5, remove sampling parameters that Gemini 3.5 no longer accepts, and stop production caption factories from trying the retired Gemini 2.0 fallback before the existing local-template fallback.

**Tech Stack:** TypeScript, Express, Vitest, Gemini GenerateContent API, Render Blueprints, Markdown

## Global Constraints

- `GEMINI_EDIT_PLAN_MODEL` must default to and be explicitly pinned as `gemini-3.5-flash-lite`.
- `GEMINI_CAPTION_MODEL` must remain `gemini-2.5-flash-lite`.
- Transcript and visual Gemini 3.5 edit-planning payloads must keep `responseMimeType: 'application/json'` and must not send `temperature`, `top_p`, or `top_k`.
- Production caption factories must not automatically try retired `gemini-2.0-flash`; after retries on the configured 2.5 primary, existing routes must fall back to the local template.
- Keep ElevenLabs Scribe v2, API contracts, Pro quota, package rules, PostDee edit guardrails, mobile UI, and FFmpeg behavior unchanged.
- Keep API keys in environment variables; no secret value may be written to Git.
- Use strict red-green TDD for every runtime or configuration behavior change.
- Do not push, deploy, or edit Render dashboard values as part of this local implementation plan.

---

### Task 1: Separate model defaults and deployment pins

**Files:**
- Modify: `apps/api/src/config/env.test.ts:5-240`
- Modify: `apps/api/src/config/renderConfig.test.ts:29-48`
- Modify: `apps/api/src/config/renderStagingConfig.test.ts:59-92`
- Modify: `apps/api/src/config/env.ts:551-580`
- Modify: `apps/api/.env.example:19-25`
- Modify: `render.yaml:64-81`
- Modify: `render.staging.yaml:68-84`

**Interfaces:**
- Consumes: `readServerConfig(env)` and the existing Render Blueprint `envVars` contract.
- Produces: `ServerConfig.geminiEditPlanModel === 'gemini-3.5-flash-lite'` by default, while `ServerConfig.geminiCaptionModel === 'gemini-2.5-flash-lite'`.

- [ ] **Step 1: Write failing default and Render contract tests**

In `apps/api/src/config/env.test.ts`, keep the caption expectation and replace
the edit expectation with these exact property values:

```ts
geminiCaptionModel: 'gemini-2.5-flash-lite',
geminiEditPlanModel: 'gemini-3.5-flash-lite',
```

Keep `reads configured service values from the environment` and
`accepts Gemini as the edit planning provider` as override tests. An explicit
environment value must still win even when it names another valid Gemini model.

In `apps/api/src/config/renderConfig.test.ts`, make the production contract
assert both pins:

```ts
expectEnvValue(source, 'CAPTION_PROVIDER', 'gemini');
expectEnvValue(source, 'GEMINI_CAPTION_MODEL', 'gemini-2.5-flash-lite');
expectEnvValue(source, 'EDIT_PLAN_PROVIDER', 'gemini');
expectEnvValue(source, 'GEMINI_EDIT_PLAN_MODEL', 'gemini-3.5-flash-lite');
```

In `apps/api/src/config/renderStagingConfig.test.ts`, add the same two model
assertions inside `requires separate provider credentials without committing values`:

```ts
expectEnvValue(source, 'GEMINI_CAPTION_MODEL', 'gemini-2.5-flash-lite');
expectEnvValue(source, 'GEMINI_EDIT_PLAN_MODEL', 'gemini-3.5-flash-lite');
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run from `apps/api`:

```powershell
npm.cmd run test -- src/config/env.test.ts src/config/renderConfig.test.ts src/config/renderStagingConfig.test.ts
```

Expected: FAIL because the local edit default and both Render files still use
`gemini-2.5-flash-lite`, and the Render files do not explicitly declare
`GEMINI_CAPTION_MODEL`.

- [ ] **Step 3: Implement the separated defaults and pins**

In `apps/api/src/config/env.ts`, change only the edit default:

```ts
geminiCaptionModel:
  readOptional(env, 'GEMINI_CAPTION_MODEL') ?? 'gemini-2.5-flash-lite',
geminiEditPlanModel:
  readOptional(env, 'GEMINI_EDIT_PLAN_MODEL') ?? 'gemini-3.5-flash-lite',
```

In `apps/api/.env.example`, keep the values visibly separate:

```dotenv
GEMINI_CAPTION_MODEL="gemini-2.5-flash-lite"
GEMINI_EDIT_PLAN_MODEL="gemini-3.5-flash-lite"
```

In both `render.yaml` and `render.staging.yaml`, place the caption pin beside
`CAPTION_PROVIDER` and update the edit pin:

```yaml
- key: CAPTION_PROVIDER
  value: gemini
- key: GEMINI_CAPTION_MODEL
  value: gemini-2.5-flash-lite
- key: EDIT_PLAN_PROVIDER
  value: gemini
- key: GEMINI_EDIT_PLAN_MODEL
  value: gemini-3.5-flash-lite
```

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run:

```powershell
npm.cmd run test -- src/config/env.test.ts src/config/renderConfig.test.ts src/config/renderStagingConfig.test.ts
```

Expected: all three test files PASS.

- [ ] **Step 5: Commit the configuration split**

```powershell
git add apps/api/src/config/env.test.ts apps/api/src/config/renderConfig.test.ts apps/api/src/config/renderStagingConfig.test.ts apps/api/src/config/env.ts apps/api/.env.example render.yaml render.staging.yaml
git commit -m "config: separate Gemini edit and caption models"
```

---

### Task 2: Make Gemini 3.5 edit-planning requests compatible

**Files:**
- Modify: `apps/api/src/modules/aiEdits/editPlanProvider.test.ts:884-991`
- Modify: `apps/api/src/modules/aiEdits/visualEditPlanProvider.test.ts:24-116`
- Modify: `apps/api/src/modules/aiEdits/editPlanProvider.ts:1221-1307`
- Modify: `apps/api/src/modules/aiEdits/visualEditPlanProvider.ts:243-275`

**Interfaces:**
- Consumes: `createGeminiEditPlanProvider`, `createGeminiVisualEditPlanProvider`, and `ServerConfig.geminiEditPlanModel` from Task 1.
- Produces: Gemini GenerateContent requests using model `gemini-3.5-flash-lite`, structured JSON output, and provider-default sampling.

- [ ] **Step 1: Write a failing transcript-planner payload test**

In `uses Gemini to plan from the timestamped transcript`, construct the provider
with the production model:

```ts
const provider = createGeminiEditPlanProvider({
  apiKey: 'gemini-key',
  model: 'gemini-3.5-flash-lite',
  fallback: createMockEditPlanProvider(),
  fetchImpl: async (url, init) => {
    requestedUrl = url;
    requestedBody = JSON.parse(String(init.body)) as Record<string, unknown>;
    return {
      ok: true,
      json: async () => ({
        candidates: [
          {
            content: {
              parts: [
                {
                  text: JSON.stringify({
                    cuts: [{ start: 0, end: 5 }],
                    summary: 'selected complete selling moment'
                  })
                }
              ]
            }
          }
        ]
      })
    };
  }
});
```

Keep the existing complete response fixture and result assertions, then replace
the request assertions with:

```ts
expect(requestedUrl).toContain(
  '/models/gemini-3.5-flash-lite:generateContent'
);
expect(requestedUrl).toContain('key=gemini-key');
expect(requestedBody?.generationConfig).toEqual({
  responseMimeType: 'application/json'
});
expect(requestedBody?.generationConfig).not.toHaveProperty('temperature');
expect(result.model).toBe('gemini-3.5-flash-lite');
```

Also change the configured-model fixture in
`selects Gemini from config and falls back to PostDee rules` to:

```ts
GEMINI_EDIT_PLAN_MODEL: 'gemini-3.5-flash-lite'
```

- [ ] **Step 2: Write a failing visual-planner payload test**

In `uploads the whole proxy, waits for Gemini, and plans with transcript`, parse
the actual request body at the external HTTP boundary:

```ts
const successfulPlanPayload = {
  candidates: [
    {
      content: {
        parts: [
          {
            text: JSON.stringify({
              cuts: [
                { start: 0, end: 10 },
                { start: 55, end: 100 }
              ],
              summary: 'selected product and offer moments'
            })
          }
        ]
      }
    }
  ]
};

const fetchImpl = vi.fn(async (url: string, init: RequestInit = {}) => {
  if (url.includes(':generateContent')) {
    const body = JSON.parse(String(init.body)) as {
      generationConfig?: Record<string, unknown>;
      contents?: unknown[];
    };

    expect(url).toContain(
      '/models/gemini-3.5-flash-lite:generateContent'
    );
    expect(body.generationConfig).toEqual({
      responseMimeType: 'application/json'
    });
    expect(body.generationConfig).not.toHaveProperty('temperature');
    expect(String(init.body)).toContain('fileUri');
    expect(String(init.body)).toContain('ราคา 99 บาท');

    return response(successfulPlanPayload);
  }
  throw new Error(`Unexpected request: ${init.method ?? 'GET'} ${url}`);
});
```

Construct the provider with:

```ts
model: 'gemini-3.5-flash-lite'
```

Keep the existing upload, polling, transcript, result, and cleanup assertions.

- [ ] **Step 3: Run both provider tests and verify RED**

Run:

```powershell
npm.cmd run test -- src/modules/aiEdits/editPlanProvider.test.ts src/modules/aiEdits/visualEditPlanProvider.test.ts
```

Expected: FAIL because both actual `generationConfig` objects still contain
`temperature: 0.2`.

- [ ] **Step 4: Remove only the deprecated edit-planning parameter**

In `createGeminiEditPlanProvider` and
`createGeminiVisualEditPlanProvider`, make the two request bodies use:

```ts
generationConfig: {
  responseMimeType: 'application/json'
}
```

Do not change the caption providers' Gemini 2.5 `temperature: 0.8`, the system
prompts, transcript filtering, visual Files API upload, JSON parsing, cut
guardrails, or fallback logic.

- [ ] **Step 5: Run both provider tests and verify GREEN**

Run:

```powershell
npm.cmd run test -- src/modules/aiEdits/editPlanProvider.test.ts src/modules/aiEdits/visualEditPlanProvider.test.ts
```

Expected: both test files PASS, including the existing PostDee fallback and
visual-file cleanup tests.

- [ ] **Step 6: Commit the Gemini 3.5 request migration**

```powershell
git add apps/api/src/modules/aiEdits/editPlanProvider.test.ts apps/api/src/modules/aiEdits/visualEditPlanProvider.test.ts apps/api/src/modules/aiEdits/editPlanProvider.ts apps/api/src/modules/aiEdits/visualEditPlanProvider.ts
git commit -m "fix: migrate AI edit requests to Gemini 3.5"
```

---

### Task 3: Remove the retired caption fallback from production factories

**Files:**
- Modify: `apps/api/src/modules/captions/captionGeneratorFactory.test.ts:27-320`
- Modify: `apps/api/src/modules/captions/realClipCaptionProvider.test.ts:1-176`
- Modify: `apps/api/src/modules/captions/captionGeneratorFactory.ts:7-12,318-361`
- Modify: `apps/api/src/modules/captions/realClipCaptionProvider.ts:289-312`
- Verify: `apps/api/src/modules/captions/captionRoutes.test.ts:31-50,671-690`

**Interfaces:**
- Consumes: `createCaptionGeneratorFromConfig`, `createRealClipCaptionProviderFromConfig`, and the existing route-level local-template fallbacks.
- Produces: production-configured caption providers that call only `config.geminiCaptionModel` (`gemini-2.5-flash-lite`) before throwing to the route fallback.

- [ ] **Step 1: Write a failing keyword-caption factory test**

Add this behavior test under `describe('createCaptionGeneratorFromConfig')`:

```ts
it('uses only the configured Gemini model before the route fallback', async () => {
  const requestedUrls: string[] = [];
  const fetchImpl = vi.fn(async (url: string) => {
    requestedUrls.push(url);
    return { ok: false, status: 400, json: async () => ({}) };
  });
  const generator = createCaptionGeneratorFromConfig({
    config: {
      captionProvider: 'gemini',
      openAiApiKey: undefined,
      geminiApiKey: 'gemini-key',
      openAiCaptionModel: 'gpt-4o-mini',
      geminiCaptionModel: 'gemini-2.5-flash-lite'
    },
    fetchImpl
  });

  await expect(generator.generate(['skincare'])).rejects.toThrow('status 400');
  expect(requestedUrls).toEqual([
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=gemini-key'
  ]);
});
```

This catches the current bug because the config factory presently makes a
second request to retired `gemini-2.0-flash`.

- [ ] **Step 2: Write a failing real-clip factory test**

Import both public factories:

```ts
import {
  createGeminiRealClipCaptionProvider,
  createRealClipCaptionProviderFromConfig
} from './realClipCaptionProvider.js';
```

Add:

```ts
it('uses only the configured Gemini model before the route fallback', async () => {
  const requestedUrls: string[] = [];
  const provider = createRealClipCaptionProviderFromConfig({
    config: {
      captionProvider: 'gemini',
      geminiApiKey: 'gemini-key',
      geminiCaptionModel: 'gemini-2.5-flash-lite'
    },
    fetchImpl: async (url) => {
      requestedUrls.push(url);
      return { ok: false, status: 400, json: async () => ({}) };
    }
  });

  expect(provider).toBeDefined();
  await expect(
    provider!.generate({
      request: { videoS3Key: 'uploads/u/clip.mp4', selectedFrameKeys: [] },
      mode: 'AUDIO_ONLY',
      audio
    })
  ).rejects.toThrow('status 400');
  expect(requestedUrls).toEqual([
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=gemini-key'
  ]);
});
```

Keep lower-level optional fallback coverage, but rename its test model fixture
from `gemini-2.0-flash` to the neutral `gemini-secondary`. The reusable helper
may still accept an explicitly supplied fallback; production factories must not
supply one.

- [ ] **Step 3: Run caption tests and verify RED**

Run:

```powershell
npm.cmd run test -- src/modules/captions/captionGeneratorFactory.test.ts src/modules/captions/realClipCaptionProvider.test.ts src/modules/captions/captionRoutes.test.ts
```

Expected: the two new factory tests FAIL because each current factory attempts
`gemini-2.0-flash`. Existing route tests should continue to prove that a thrown
provider error returns `local-template` or `local-real-clip-template`.

- [ ] **Step 4: Remove the retired automatic fallback wiring**

In `captionGeneratorFactory.ts`, delete:

```ts
const defaultGeminiFallbackModels = ['gemini-2.0-flash'];
```

Build the configured generator without `fallbackModels`:

```ts
return createGeminiCaptionGenerator({
  apiKey: config.geminiApiKey,
  model: config.geminiCaptionModel,
  fetchImpl
});
```

In `realClipCaptionProvider.ts`, build the configured provider without
`fallbackModels`:

```ts
return createGeminiRealClipCaptionProvider({
  apiKey: config.geminiApiKey,
  model: config.geminiCaptionModel,
  fetchImpl
});
```

Update nearby comments to say the provider retries the configured primary and
then lets the route use the local template. Do not alter retry budgets,
authentication-error handling, caption output schemas, quota, or route code.

- [ ] **Step 5: Run caption tests and verify GREEN**

Run:

```powershell
npm.cmd run test -- src/modules/captions/captionGeneratorFactory.test.ts src/modules/captions/realClipCaptionProvider.test.ts src/modules/captions/captionRoutes.test.ts
```

Expected: all three test files PASS; configured factories request only
`gemini-2.5-flash-lite`, and route-level local fallback tests remain green.

- [ ] **Step 6: Confirm the retired production model ID is gone**

Run from the repository root:

```powershell
rg -n "gemini-2\.0-flash" apps/api/src render.yaml render.staging.yaml
```

Expected: no matches.

- [ ] **Step 7: Commit the caption fallback cleanup**

```powershell
git add apps/api/src/modules/captions/captionGeneratorFactory.test.ts apps/api/src/modules/captions/realClipCaptionProvider.test.ts apps/api/src/modules/captions/captionGeneratorFactory.ts apps/api/src/modules/captions/realClipCaptionProvider.ts
git commit -m "fix: retire Gemini 2.0 caption fallback"
```

---

### Task 4: Synchronize source-of-truth documentation and run the full gate

**Files:**
- Modify: `README.md:51-57,856-864`
- Modify: `ROADMAP.md:100-101,349-357`
- Modify: `API.md:30-34,689-696,1085-1103,1661-1668`
- Modify: `ARCHITECTURE.md:263,503-508,553-583,644-657`
- Modify: `docs/GO_LIVE.md:46-50,184-200`
- Modify: `docs/RENDER_ENVIRONMENT_KEYS.md:101-111`
- Modify: `docs/STAGING.md:72-80`
- Modify: `docs/superpowers/plans/2026-07-20-subtitle-studio-plan.md:67-72`
- Modify: `docs/superpowers/plans/2026-07-23-ai-edit-whole-video-proxy-plan.md:3-35,50-64`

**Interfaces:**
- Consumes: the tested runtime behavior from Tasks 1-3.
- Produces: one consistent operator/developer description of the model split, Gemini 3.5 payload rules, and local caption fallback.

- [ ] **Step 1: Update the current runtime source-of-truth text**

Use these exact facts in `README.md`, `ROADMAP.md`, `API.md`, and
`ARCHITECTURE.md`:

```text
AI edit planning:
  GEMINI_EDIT_PLAN_MODEL=gemini-3.5-flash-lite
  Transcript and visual requests use structured JSON and provider-default
  sampling; they do not send an explicit temperature.

AI caption generation:
  GEMINI_CAPTION_MODEL=gemini-2.5-flash-lite
  The configured primary retries transient failures, then the route falls back
  directly to the local template. No secondary Gemini model is attempted.
```

Specific corrections:

- Change the `ROADMAP.md` AI editing stack from Gemini 2.5 Flash-Lite to
  Gemini 3.5 Flash-Lite.
- Change the `ROADMAP.md` caption row from “model fallback + local template”
  to configured-primary retries followed directly by local template.
- Keep the caption response/config examples in `API.md` and `ARCHITECTURE.md`
  at `gemini-2.5-flash-lite`.
- Change only the `GEMINI_EDIT_PLAN_MODEL` environment-table value in
  `API.md` to `gemini-3.5-flash-lite`.
- Add Gemini 3.5 to the AI edit sequence/flow without changing the documented
  ElevenLabs, PostDee rule, or FFmpeg roles.

- [ ] **Step 2: Update deployment and staging guidance**

In `docs/GO_LIVE.md`, `docs/RENDER_ENVIRONMENT_KEYS.md`, and
`docs/STAGING.md`, document:

```env
GEMINI_CAPTION_MODEL=gemini-2.5-flash-lite
GEMINI_EDIT_PLAN_MODEL=gemini-3.5-flash-lite
```

Rename `Defaults Not Needed In Render Unless Overriding` in
`docs/RENDER_ENVIRONMENT_KEYS.md` to:

```markdown
## Model Defaults and Explicit Blueprint Pins
```

Explain that both values are explicitly pinned in Production and Staging;
Gemini 3.5 edit requests omit `temperature`; caption failures go directly to
the existing local template after primary retries.

- [ ] **Step 3: Mark relevant historical plans with the current baseline**

In `docs/superpowers/plans/2026-07-20-subtitle-studio-plan.md`, replace the
line that calls Gemini 2.5 the current AI edit baseline with Gemini 3.5.

In `docs/superpowers/plans/2026-07-23-ai-edit-whole-video-proxy-plan.md`, add
this current-runtime note near the top and the matching verification item:

```markdown
> Current runtime update (2026-07-30): transcript and visual planning use
> `gemini-3.5-flash-lite`. Both GenerateContent payloads keep structured JSON
> output and omit `generationConfig.temperature`.
```

- [ ] **Step 4: Check documentation consistency**

Run:

```powershell
rg -n "GEMINI_EDIT_PLAN_MODEL.*gemini-2\.5-flash-lite|AI auto editing.*Gemini 2\.5 Flash-Lite|retry \+ model fallback|secondary model, then local template" README.md ROADMAP.md API.md ARCHITECTURE.md docs/GO_LIVE.md docs/RENDER_ENVIRONMENT_KEYS.md docs/STAGING.md docs/superpowers/plans/2026-07-20-subtitle-studio-plan.md docs/superpowers/plans/2026-07-23-ai-edit-whole-video-proxy-plan.md
```

Expected: no stale AI-edit model or secondary-caption-fallback matches.

Run:

```powershell
rg -n "gemini-3\.5-flash-lite|gemini-2\.5-flash-lite" README.md ROADMAP.md API.md ARCHITECTURE.md docs/GO_LIVE.md docs/RENDER_ENVIRONMENT_KEYS.md docs/STAGING.md
```

Expected: AI edit references resolve to 3.5 and caption references resolve to
2.5 in their respective sections.

- [ ] **Step 5: Run the full API test suite**

Run from `apps/api`:

```powershell
npm.cmd run test
```

Expected: all API test files PASS with zero failures.

- [ ] **Step 6: Build the API**

Run:

```powershell
npm.cmd run build
```

Expected: TypeScript compilation exits successfully.

- [ ] **Step 7: Validate the Prisma schema**

Run:

```powershell
$env:DATABASE_URL='postgresql://postdee:postdee_password@localhost:5432/postdee?schema=public'
npm.cmd run prisma:validate
```

Expected: Prisma reports that `schema.prisma` is valid. This command validates
the schema and does not require the database server to be running.

- [ ] **Step 8: Commit documentation and verified behavior**

```powershell
git add README.md ROADMAP.md API.md ARCHITECTURE.md docs/GO_LIVE.md docs/RENDER_ENVIRONMENT_KEYS.md docs/STAGING.md docs/superpowers/plans/2026-07-20-subtitle-studio-plan.md docs/superpowers/plans/2026-07-23-ai-edit-whole-video-proxy-plan.md
git commit -m "docs: record Gemini model separation"
```

- [ ] **Step 9: Confirm the branch is clean and ready for review**

Run:

```powershell
git status --short --branch
git log --oneline -5
```

Expected: no modified or untracked files remain. The branch contains separate
commits for config, edit request compatibility, caption fallback cleanup, and
documentation.

## Deployment handoff

After this plan passes locally, pushing and deploying are separate operational
actions. Staging acceptance must then confirm:

1. The deployed environment reports the two explicit model pins.
2. A Thai clip reaches transcript and visual planning with Gemini 3.5.
3. The caption flow still reports Gemini 2.5 on success.
4. An induced Gemini edit failure still reaches deterministic PostDee rules.
5. An induced caption failure still returns the local template.
