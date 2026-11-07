# Settings: Report an Issue and Request a Feature

> **What:** the Settings list's Feedback section and the feedback form it opens, as built: files, HIG decisions, filing and tests. **Read when:** changing `HassUI/Features/Settings/Feedback/` or `HassCore/Feedback/`. The issues it files are worked by the [triage agent](../../workflow/triage-agent.md).

## Source

Ported from FestivalNativeApps' in-app feedback form (`.agents/controls/feedback-form/{spec,ios}.md` and `FestivalUI/Features/Settings/Feedback/` there). The web dashboard has no equivalent (it runs inside Home Assistant), so this is a native-only section.

**Filing goes through Home Assistant** (owner, 2026-10-14: "Yes, relay"), the way Festival's app files through its service: the [Fenton Home Feedback](https://github.com/SFenton/ha-fenton-feedback) integration holds the GitHub token, and the app never has one. Differences from Festival:

| Festival | Here | Why |
|---|---|---|
| The app posts to its own service | The app posts to the integration on the signed-in Home Assistant, with its Home Assistant access token | Home Assistant is the app's only server; a token shipped in the app is forbidden (AGENTS.md) |
| Public tracker, anonymous bodies | Private request repo `SFenton/request-repo`; the integration names the Home Assistant user who sent it | Screenshots show the house; the household is trusted |
| Service transcodes media | `FeedbackMediaFitter` shrinks each file to GitHub's 10 MB attachment limit on the device; each file goes in its own request | Home Assistant's request body limit |
| Rows hidden until `/api/features` says so | Rows always shown; the form shows a setup notice when the integration is missing | Discoverable for the owner who installs it |
| Polls a job for the issue number | Synchronous: uploads, then files, then shows `#N` with View on GitHub | The integration answers directly |

## Native

| Piece | File | Notes |
|---|---|---|
| Kinds, prefix rule, validation | `HassCore/Feedback/FeedbackKind.swift`, `FeedbackDraft.swift`, `FeedbackValidationIssue.swift` | `[Bug] `/`[Feature] ` kept by `setTitle`; lengths in UTF-16 |
| Report | `FeedbackReport` | The JSON `POST /api/fenton_feedback/report` takes: kind, platform, title, boxes, `[label, value]` diagnostics, uploaded media. The integration composes the issue (sections, inline media, diagnostics, reporter, `<!-- fenton-feedback:v1 -->`, labels) |
| Client | `HomeAssistantFeedbackClient` over `FeedbackHTTPTransport` | `GET …/status`, `POST …/media` (one raw file), `POST …/report`, each with the app's access token; a 404 means the integration isn't installed. Errors map from the integration's `code` to fixed copy in `FeedbackFilingError` (never its text) |
| Diagnostics | `FeedbackDiagnostics`, `HassUI/.../FeedbackDiagnosticsCollector.swift` | App version and build date, OS, device family + hardware id, window size/size class/orientation, Home Assistant version and connection, text size/VoiceOver/Reduce Motion/appearance, locale. Never a token, password or server address |
| Media | `FeedbackLocationScrubber` (ported), `FeedbackMediaFitter`, `FeedbackPickedMedia` | Copy → strip location → fit to 10 MB (JPEG steps, then export presets) → count limit (4). Private copies in `tmp/fenton-feedback-media/<uuid>/`, purged when the sheet goes away |
| Form | `FeedbackFormModel`, `FeedbackFormSheet`, `FeedbackAttachmentStrip`/`Tile`, `FeedbackFieldHeader`, `SheetDismissAttemptObserver` | As Festival's sheet; checks availability on open; progress "Uploading media n of m…" then "Filing your report on GitHub…"; Stop Sending only while media uploads |
| Entry | `FeedbackSettingsSection` in `SettingsScreen` | Its own section (no header, since the list sits on the house backdrop) after Performance; `.feedbackFormSheet(item:)` builds the services from the session and presents with `.hassSheet(.form)`; the form uses `.modalChrome()` |
| Fixture | `FeedbackFixtureFiler` (Debug only), `FENTON_FEEDBACK_FIXTURE=1` (set up) / `unavailable` | Titles with `fixture-failed` fail as a GitHub problem, `fixture-limited` as rate limited |

## Decisions (HIG via `apple-hig`)

- **Cancel leading, Submit trailing**, discard confirmation on Cancel and swipe (HIG Sheets; HIG Modality: "If either a dismiss gesture or button could lose user-generated content, get confirmation before closing").
- **Visible explanations, not placeholders** (HIG Text fields), **Submit disabled with the reason shown** (HIG Entering data), including "Reporting isn't set up in Home Assistant yet."
- **Setup notice leads the form** when the integration is missing (the shared `InfoBox`, neutral tone), saying who can add it, so nobody types a report that can't be sent.
- **Quick Look** for tapped media; no photo-library permission (`PhotosPicker` runs out of process; HIG Privacy).

## Test IDs

`settings.feedback.bug|feature`; `feedback.field.title|description|repro|expected`, `.close`, `.submit`, `.attach`, `.attach.media|files|progress`, `.attachments`, `.attachment.N[.remove]`, `.attachments.notice`, `.validation`, `.progress`, `.stop`, `.done`, `.view`, `.discard.confirm|cancel`, `.setup`.

## Tests

- Unit (`HassCoreTests`): `FeedbackTests` (prefix, validation, platform, attachment policy and names, report encoding, diagnostics, Home Assistant client requests and error mapping over a stub transport, fixture), `FeedbackLocationScrubberTests` (ported), `FeedbackMediaFitterTests`. `HassUITests`: `FeedbackFormModelTests` (availability, admit/refuse, submit → filed, failures, cancel, staging purge, hosted renders).
- Journeys (`FeedbackJourneyTests`, fixture only, never a real issue): rows, bug and feature form audits with AX5 relaunch, discard confirmation then filing #1, the setup notice, failed filing keeps the form, screenshot capture.
- The integration's own tests (validation, composition, GitHub client, config flow and endpoints inside Home Assistant) live in `SFenton/ha-fenton-feedback`.
