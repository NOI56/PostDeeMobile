# AI Edit Subtitle Review Flow Design

## Context

After AI analysis, the current mobile flow opens Subtitle Studio automatically
whenever automatic captions are enabled. This interrupts the one-tap AI edit
flow and shows the full transcript before a preview has been rendered.

## Desired flow

1. The user selects a clip and taps the AI edit button.
2. AI prepares the edit recipe and caption cues.
3. The app creates an in-memory `SubtitleProject` from those cues without
   navigating away. Its initial font size and position match the subtitle
   settings selected on the AI setup screen.
4. The preview is rendered with the AI captions and the app opens the existing
   result review screen.
5. Subtitle Studio opens only when the user explicitly taps the edit-subtitles
   action on the review screen.
6. Saving edited subtitles re-renders the preview. Canceling keeps the current
   preview unchanged.

## Scope

- Keep the existing AI analysis, quota, caption generation, rendering, draft
  store, and review UI.
- Do not change API contracts or subscription rules.
- Do not remove Subtitle Studio or its explicit review action.
- Change only the automatic navigation that occurs between preparation and
  preview rendering.

## Verification

- A widget regression test must prove that processing does not launch Subtitle
  Studio, renders a captioned preview, and reaches the review screen.
- The same test must prove that the review action launches Subtitle Studio and
  applies the edited text and style to a second render.
- Run Flutter analyze, the full Flutter test suite, and an Android debug build.
