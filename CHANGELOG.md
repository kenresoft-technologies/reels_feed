## 1.0.0

First release.

- `ReelsFeed`: a snapping vertical feed with preloading, `onEndReached`, view tracking
  (`onItemViewed`), pause when the app is in the background or covered, and mouse and
  keyboard support on desktop and web.
- `ReelMediaCarousel`: pictures and videos of one post, with tap to pause, hold to pause, a shared
  mute button, a scrubbable progress bar, a double-tap heart burst and page indicators.
- `ReelVideoPool`: opens, shares and recycles video players so a long scroll keeps only a few open.
- `ReelsFeedController`: current post, moving between posts, shared mute and pause.
- Overlays: `ReelActionRail`, `ReelCaption`, `ReelScrim`, `ReelProgressBar`, `ReelHeartBurst`,
  `formatReelCount`.
- Network, asset and file sources for pictures and videos; custom image loading through `imageBuilder`.
- Never opens more than `ReelVideoPool.maxPlayers` (3) players, because phones have few hardware
  decoders and the system takes one from a paused player when an app asks for too many. Extra videos
  wait for a slot; the video on screen borrows one from a preloaded neighbour.
- `ReelVideoCache`: network videos are saved to disk in the background (`ReelsFeed.cacheVideos`,
  on by default) so a revisit plays from the device without the network.
- Scrolling past a video and back resumes it instantly instead of reloading it. `restartOnActive`
  starts videos over if you want that.
- Quietly reopens a video that fails once (`ReelVideoPool.autoRetries`) before showing the error, and
  a player that breaks after opening can be retried too.
- Overlays use a cheap hard shadow instead of a blurred one (`reelCheapShadow`), which keeps scrolling
  smooth on mid-range GPUs.
- Compiles to WebAssembly.
