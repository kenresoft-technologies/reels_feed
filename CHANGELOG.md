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
- Compiles to WebAssembly.
