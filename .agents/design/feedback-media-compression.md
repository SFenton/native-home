# Feedback media compression

> **What:** Where and how Feedback (Report an Issue, Request a Feature) shrinks an oversized video so it can be attached. **Read when:** touching `FeedbackMediaFitter`, `FeedbackMovieEncoder` or the Feedback media limit. Policy details: [Media compression in feedback.md](../pages/settings/feedback.md#media-compression-owner-delegated-decision-2026-11-05).

## Goal

A long video attached to Feedback is compressed to fit the 10 MiB limit instead of being refused. Today `FeedbackMediaFitter` (HassCore) only steps through four fixed `AVAssetExportSession` presets (HEVC 1080p, 720p, 540p, 480p). Presets carry their own bitrates, so any clip longer than about 40-60 s ends over the limit at every step and is refused as "too large". Photos already step down fine. Nothing drawn or worded changes: the existing preparing state and the existing too-large copy stay.

## Options judged

- **Option A: local, bitrate-targeted encode.** An `AVAssetReader` to `AVAssetWriter` path in HassCore (hardware encoder, no new dependency) sizes the video bitrate from the duration. Long clips attach instead of being refused; the upload is at most 10 MiB.
- **Option B: server transcode in an integration** (`ha-fenton-feedback`, which files reports). Slower sends, since originals (often 100 MB+ from a 4K iPhone clip) go up over cellular; the integration needs ffmpeg and CPU on the Home Assistant host, a raised request limit, async job status and a second repo released through HACS. More moving parts, worse on mobile data.
- **Option C: local presets plus truncation** (`fileLengthLimit`). Cuts the end of the clip and loses the part of the bug that may matter.

Decision: 2026-11-05, judged Option A, B and C; picked Option A, because the app already owns compression and location scrubbing, so this makes it reliable rather than moving it; B is heavier and worse on mobile data, C loses the clip's end (owner-delegated).

Gate: app_wide=no

## Rung 0 (system API first)

System API on iOS 17, 18 and 26: `AVAssetExportSession` presets have no bitrate or size target and `fileLengthLimit` truncates, so they are not enough. `AVAssetWriter` with `AVVideoAverageBitRateKey` is the system API for a size target. Precedent: Telegram, Signal and WhatsApp size videos by bitrate from duration.

## Policy and amendments

Target 92% of the limit; video bitrate = budget x 8 / duration minus audio (AAC 64 kbps stereo, or none). Resolution from bitrate: >= 3.5 Mbps keeps up to 1920 on the long edge, >= 1.8 Mbps 1280, >= 0.9 Mbps 960, else 640; aspect and orientation kept; HDR tone-mapped to SDR Rec.709 H.264. Floor 200 kbps video: below that (a clip of about 6 minutes or more) it is still refused as too large. Files already under the limit are left byte for byte.

- **During build.** Rate control alone hit an encoder quality floor at small sizes. On overshoot each retry also drops one resolution rung (1920, 1280, 960, 640, 480, 320) at 80% bitrate: at most 3 attempts, then refused as too large.
- **Review round 1.** Frames above 30 fps are dropped. An import in progress is cancelled when the media is removed or the sheet closes. A source whose audio cannot be read or downmixed encodes video only rather than being refused.

## Unmeasured

Encode time on an older iPhone for a several-minute 4K clip (expected seconds to tens of seconds on the hardware encoder); quality at the floor.
