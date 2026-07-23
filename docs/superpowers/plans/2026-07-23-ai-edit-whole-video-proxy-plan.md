# AI Edit Whole-Video Proxy Plan

**Status:** Implemented locally on `main`; real Gemini/R2 device E2E is still a release gate.

**Goal:** Let the edit planner see the complete clip timeline, hear its audio,
and use the timestamped Thai transcript before choosing a target-length story
window. Do not rely on a sparse set of still images.

## Architecture

1. Groq transcription remains the metered first pass and audio-only fallback.
2. When the requested result is shorter than the transcript, Flutter creates a
   whole-duration proxy with `fps=1,scale=360:-2`, MPEG-4 video, mono 16 kHz AAC,
   and no duration cap.
3. The proxy is uploaded as `purpose=ai-edit-visual-proxy`, limited to 50 MiB,
   and scoped to the authenticated user's storage prefix.
4. `POST /ai-edits/plan` downloads that proxy and sends it through Gemini Files
   API together with timestamped transcript segments.
5. Gemini returns absolute cut ranges. Existing validation and target trimming
   remain the final safety boundary.
6. If proxy extraction, upload, download, Gemini processing, or generation
   fails, planning falls back to the existing audio/transcript provider.
7. Flutter caches one local proxy for the current source across duration-only
   replans and removes it when the source changes or the screen closes. R2 and
   Gemini copies are cleaned best-effort per request. The original full-resolution
   video remains on the phone and is used for every render.
8. Gemini suggestions are normalized into one continuous target-length window.
   A soft Thai continuation-fragment penalty may move the opening to a nearby
   complete transcript boundary without hard-blocking a stronger hook.
9. Gemini file upload, processing-state polling, and deletion use Google's
   official `@google/genai` server SDK. This replaced the hand-written resumable
   request after real Staging runs continued to receive upload-start HTTP 400
   responses and fall back to audio-only planning.

Gemini's normal video understanding samples visual frames at roughly 1 fps, so
the proxy keeps the complete time axis while avoiding a wasteful 30 fps upload.
Its full audio track and the transcript preserve speech context between frames.

## Safety boundaries

- Accept only `.mp4` + `video/mp4` + `purpose=ai-edit-visual-proxy`.
- Reject proxy uploads above 50 MiB or with client-supplied dimensions.
- Reject non-MP4 plan keys and keys outside the authenticated user namespace.
- Never return provider errors, API keys, signed URLs, or raw storage metadata
  to the mobile client.
- Visual failure must not replace a valid audio plan with an empty plan.

## Verification

- API provider test: whole byte payload upload, Files API polling, transcript +
  file URI request, target trim, and Gemini file deletion.
- API route tests: owned proxy, fallback, foreign-key rejection, and R2 cleanup.
- Upload tests: accepted shape plus extension, MIME, dimensions, and 50 MiB cap.
- Flutter extractor tests: no `-t`, full-duration FFmpeg arguments, empty output,
  and local cleanup.
- Flutter screen test: audio prepare, proxy upload, local proxy reuse across a
  duration change, cleanup on disposal, and result review.
- Reproducible real-media preprocessing smoke test:
  `scripts/test-ai-edit-visual-proxy.ps1`.
- Release gate: run the licensed Thai fixture set through deployed R2 + Gemini,
  have a Thai reviewer score hook, coherence, visual relevance, speech cuts, and
  duration accuracy for at least three target lengths.
