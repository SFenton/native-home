# Image cache

> **What:** how remote images load, cache and update. **Read when:** drawing any remote image (camera snapshots, recipe photos, media artwork, app icons).

- **Components:**
  - `ImagePipeline` (`HassDesign/Images/ImagePipeline.swift`) loads and caches.
  - `CachedImage(url:contentMode:placeholder:)` (`HassDesign/Images/CachedImage.swift`) draws.
  - `RemoteImage` and `ImageCard` use `CachedImage`.
  - Never use `AsyncImage` or decode with `UIImage(data:)` / `CGImageSourceCreateImageAtIndex` in a view. Those decode at full size on the main thread at first draw, which was a scroll hitch per cell.
- **Why not `AsyncImage`:**
  - The deployment target is iOS 17. `AsyncImage` only honors HTTP caching on iOS 27.
  - Home Assistant's proxies send no caching headers and rotate tokens, so URL-keyed HTTP caching misses on every rotation.
  - Scrolling also needs decoded, downsampled images in memory and a disk copy for cold launches.
- **Layers:**
  - Memory: decoded images at draw size, so a cell scrolling back into view draws on its first frame.
  - Disk: `Caches/FentonImages`, original bytes plus `ETag` / `Last-Modified` / max age. A cold launch shows the last images offline.
  - Decoding: `CGImageSourceCreateThumbnailAtIndex` at the view's pixel size (bucketed to 128 px), off the main thread.
- **Cache key:** the URL without `token`, `authSig` or `access_token`. A rotated Home Assistant token still finds the image on disk. Other query items, such as a media player's `cache=` artwork hash, stay in the key.
- **How changed images update:**
  - **Same URL, within max age:** served from cache, no request. The max age is the server's `Cache-Control: max-age`, else 5 min. Home Assistant's proxies send none.
  - **Same URL, past max age:** the cached image shows at once. A conditional request (`If-None-Match` / `If-Modified-Since`) follows. A `304` only refreshes the timestamp; a `200` replaces the bytes and the view swaps to the new image.
  - **Same key, different URL** (Home Assistant rotated the camera token, or the artwork changed): the previous image stays up while the new URL is fetched, then the new one replaces it. A new key cross-fades; a same-key refresh swaps without animation, so snapshots don't flicker.
  - Failures leave the cached image in place. With nothing cached, the placeholder shows.
- **Budget:** the memory cache holds 96 MB and is evicted by the system under pressure. The disk store holds 200 MB, trimmed oldest-first at launch (`trimDisk`). Settings → Performance shows usage and has **Clear Image Cache**.
- **Gate:** `CachedImage` reports readiness to an enclosing `ContentGate`.
- **Telemetry:** `ImageFetch` and `ImageDecode` signposts, plus the counters `image.memoryHits`, `image.diskHits`, `image.fetches`, `image.notModified`, `image.changed` and `image.failures`.
- **Not for people's photos:** a person's Home Assistant photo is not in `ImagePipeline` (purgeable Caches, size trim, URL-keyed, no delete-when-the-server-drops-it, no sign-out wipe). It has its own store and fade: [avatar](avatar.md). It reuses this pattern's key rule (`token` / `authSig` / `access_token` dropped) and the ImageIO thumbnail decode.
- **Tests:** `Tests/HassDesignTests/ImagePipelineTests.swift` (stub `URLProtocol` for 200/304/rotation/failure; temp directory).

## Guards

Checked by `python3 tools/pattern_guard.py` against `contracts/patterns.json` (comment lines are ignored).

- `image-cache/no-async-image`: Remote images load through ImagePipeline / CachedImage, never AsyncImage (image-cache). Scans `**/*.swift`.
- `image-cache/no-uiimage-data-in-features`: Views do not decode images with UIImage(data:); decode through ImagePipeline (image-cache). Scans `HassUI/Features/**/*.swift`.

### Known debt

Each file below still breaks its guard and is allowed until it is fixed; remove the row and the registry `debt` entry together.

| File | Guard | What to do |
|---|---|---|
| `apple/Sources/HassUI/Features/Inventory/ScanCamera.swift` | `image-cache/no-uiimage-data-in-features` | downsizes a captured frame with `UIImage(data:)` (a one-shot capture, not a scrolling cell); route through `ImagePipeline` or move into `HassCore` |
