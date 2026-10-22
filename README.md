# reels_feed

A vertical, full-screen feed of videos and pictures for Flutter, in the style of
Reels, Shorts and TikTok. It snaps one post at a time, plays only the post you
are looking at, and keeps the next ones ready so swipes feel instant.

It does not care where your data comes from or how you manage state. You give it
a count and a builder.

```dart
ReelsFeed(
  itemCount: posts.length,
  onEndReached: loadMore,
  isLoadingMore: loading,
  onItemViewed: (i) => analytics.view(posts[i].id),
  itemBuilder: (context, index) => ReelMediaCarousel(
    media: posts[index].media,
    onDoubleTap: (_) => like(posts[index]),
  ),
)
```

## Why use it

- **Smooth on real phones.** A video player holds a hardware decoder, and a feed
  that opens one per post runs out of them. `reels_feed` uses a *video pool*:
  the visible post plays, the posts around it are opened and paused, and
  everything else is released. A long scroll keeps at most four players open.
- **Instant swipes.** The next post's video is already open, with its poster
  picture showing, when you swipe to it.
- **Posts with several pictures and videos.** A post is a swipeable carousel of
  mixed media. Mute is shared, so unmuting once unmutes every video.
- **Behaves like a good citizen.** Videos stop when the app goes to the
  background, when another screen covers the feed, or when you set
  `active: false` (for example in an inactive tab).
- **Viewer gestures built in.** Tap to pause, press and hold to pause while
  held, double tap to like with a heart burst, a scrubbable progress bar, a
  mute button.
- **View tracking.** `onItemViewed` fires once per post after it has been on
  screen for a time you choose, and not for posts that were swiped past.
- **Infinite loading.** `onEndReached` asks for more shortly before the end and
  does not fire twice for the same position.
- **Ready-made overlays.** `ReelActionRail`, `ReelCaption` (expandable, with
  tappable hashtags, mentions and links), `ReelScrim`, `ReelProgressBar`.
- **Works everywhere Flutter does.** Android, iOS, web (WebAssembly compatible),
  macOS, Windows and Linux. Mouse drag, scroll wheel and keyboard shortcuts work
  on desktop and web.
- **No state-management dependency.** Plain Flutter and `video_player`.
- **Accessible.** Screen reader labels on every control, a minimum 48 pixel tap
  target, and no motion when the system asks to reduce it.

## Install

```yaml
dependencies:
  reels_feed: ^1.0.0
```

Videos are played by [`video_player`](https://pub.dev/packages/video_player), so
follow its platform setup. The one step that is easy to miss:

**Android: allow internet access in release builds.** `flutter create` adds the
`INTERNET` permission only to the debug and profile manifests, so network videos
play while you develop and then fail in a release build (the log shows
`android_getaddrinfo failed: EPERM`). Add this to
`android/app/src/main/AndroidManifest.xml`, inside `<manifest>`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

iOS needs nothing for `https` addresses; plain `http` addresses need an
`NSAppTransportSecurity` exception.

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:reels_feed/reels_feed.dart';

class ReelsPage extends StatelessWidget {
  const ReelsPage({super.key, required this.posts});

  final List<Post> posts;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ReelsFeed(
        itemCount: posts.length,
        itemBuilder: (context, index) {
          final post = posts[index];
          return Stack(
            fit: StackFit.expand,
            children: [
              ReelMediaCarousel(media: post.media),
              const ReelScrim(),
              Positioned(
                left: 16,
                right: 80,
                bottom: 40,
                child: ReelCaption(text: post.caption),
              ),
            ],
          );
        },
      ),
    );
  }
}
```

Describe media with `ReelMedia`:

```dart
ReelMedia.videoUrl('https://example.com/clip.mp4', posterUrl: 'https://example.com/clip.jpg')
ReelMedia.imageUrl('https://example.com/photo.jpg')
const ReelMedia.video(ReelSource.asset('assets/intro.mp4'))
const ReelMedia.image(ReelSource.file('/storage/photo.jpg'))   // not on web
```

Give videos a `poster`. It shows until the first frame is ready and hides the
loading gap, which is what makes a swipe feel instant.

## The pieces

### `ReelsFeed`

The snapping vertical feed.

| Parameter | What it does |
| --- | --- |
| `itemCount`, `itemBuilder` | Your posts. |
| `controller` | A `ReelsFeedController` to read and drive the feed. |
| `initialIndex` | The first post, when no controller is given. |
| `active` | `false` pauses every video (inactive tab, covered screen). |
| `preload` | `ReelsPreload(ahead: 1, behind: 1)`: how many posts around the visible one are prepared. `ReelsPreload.none()` turns it off. |
| `onPageChanged` | The visible post changed. |
| `onEndReached`, `endReachedThreshold` | Load more shortly before the end (default 3 posts before). |
| `isLoadingMore`, `loadingMoreBuilder` | Show a loading indicator and hold back `onEndReached`. |
| `onItemViewed`, `viewDuration` | A post was seen for long enough (default 1 second). Once per post. |
| `emptyBuilder` | What to show with zero posts. |
| `pool` | Your own `ReelVideoPool` (to share or customise it). |
| `physics`, `backgroundColor`, `keyboardShortcuts`, `semanticLabel` | Appearance and behaviour. |

Inside any post, `ReelItemScope.of(context)` tells you whether the post is
`active`, `preload` or `idle`, for your own widgets that should react.

### `ReelMediaCarousel`

Shows one post's pictures and videos and does the playing. Inside a `ReelsFeed`
it needs no wiring. It also works on its own: pass `active: true` or `false`.

| Parameter | What it does |
| --- | --- |
| `media` | The list of `ReelMedia`. One shows full-bleed; several swipe sideways. |
| `onTap`, `tapToPause`, `holdToPause` | Tap pauses or resumes; press and hold pauses while held. |
| `onDoubleTap` | Called with the tap position. Setting it adds the heart burst. |
| `indicator` | `ReelIndicatorStyle.dots`, `.segments` or `.none`. |
| `showMuteButton`, `muteAlignment` | The mute button. |
| `showProgressBar`, `progressPadding` | The scrubbable bar under videos. |
| `fit` | `null` fills the screen with tall media and fits wide media inside it. |
| `restartOnActive` | Videos start over each time their post is shown again. |
| `imageBuilder` | Load pictures your own way (see below). |
| `errorBuilder` | Your own "could not play" message, with a retry callback. |

### Overlays

```dart
ReelActionRail(actions: [
  ReelAction(
    icon: Icons.favorite_border,
    activeIcon: Icons.favorite,
    isActive: post.liked,
    count: post.likes,            // shown as 1.2K
    semanticLabel: 'Like',
    onTap: () => toggleLike(post),
  ),
  ReelAction(icon: Icons.chat_bubble_outline, count: post.comments, semanticLabel: 'Comments', onTap: openComments),
  ReelAction(icon: Icons.send_outlined, label: 'Share', semanticLabel: 'Share', onTap: share),
])

ReelCaption(
  text: post.caption,
  onHashtagTap: (tag) => openTag(tag),
  onMentionTap: (name) => openProfile(name),
  onLinkTap: (url) => launch(url),
)
```

`ReelScrim` darkens an edge so white text stays readable on bright video.
`ReelProgressBar` and `ReelHeartBurst` are exported for custom layouts, and
`formatReelCount(1234)` gives `1.2K`.

### `ReelsFeedController`

```dart
final controller = ReelsFeedController();

controller.currentIndex.addListener(() => print(controller.currentIndex.value));
controller.animateToIndex(5);
controller.next();
controller.toggleMute();      // shared by every video
controller.togglePause();
```

A controller you create is yours to `dispose`. A feed without one makes and
disposes its own.

## Customising

### Your own image loader or cache

Pictures use Flutter's in-memory image cache by default, which keeps this package
free of extra dependencies. For a disk cache, placeholders and error handling,
pass an `imageBuilder`. With [`any_source_image`](https://pub.dev/packages/any_source_image):

```dart
ReelMediaCarousel(
  media: post.media,
  imageBuilder: (context, source, fit) => AppImage(
    source.key,                    // the address of a network picture
    fit: fit,
    width: double.infinity,
    height: double.infinity,
  ),
)
```

The example app does exactly this. Any other loader works the same way, for
example `CachedNetworkImage(imageUrl: (source as ReelNetworkSource).url, fit: fit)`.

### Your own video player setup (caching, headers)

Videos come from a `ReelVideoPool`. Replace how players are built, for example
to play from a disk cache:

```dart
final pool = ReelVideoPool(
  maxIdle: 1,
  controllerFactory: (source) => VideoPlayerController.file(
    cachedFileFor(source),
  ),
);

ReelsFeed(pool: pool, ...);   // you dispose a pool you pass in
```

For request headers, use `ReelSource.network(url, headers: {...})`.

### Tuning preload

```dart
ReelsFeed(preload: const ReelsPreload(ahead: 2, behind: 0), ...)
```

More `ahead` makes fast swiping smoother and uses more memory and data. Each
prepared video holds a decoder, so go above 2 only on purpose.

## Platform notes

- **Web:** browsers only autoplay muted video, so the feed starts muted there
  (`startMuted` on the controller overrides it). `ReelSource.file` is not
  available in a browser. Playing video cross-origin needs the server to send
  CORS headers.
- **Desktop and web:** drag with the mouse, scroll with the wheel, arrow keys or
  `J`/`K` to move, `Space` to pause, `M` to mute. Turn this off with
  `keyboardShortcuts: false`.
- **Android and iOS:** `mixWithOthers` on the pool lets videos play alongside
  other apps' audio.
- **Bottom navigation:** wrap the feed so it sits above the bar, and set
  `active` to whether its tab is selected.

## Performance notes

On a mid-range Android phone (profile mode) scrolling the example feed with videos, captions and the
action rail renders 90% of frames in about 20 ms, against about 9 ms for a bare `PageView` of
images. Blurred text and icon shadows were the biggest cost, so the overlays here use a cheap hard
shadow (`reelCheapShadow`). If you add your own overlays, prefer a `ReelScrim` for legibility over
blurred shadows.

- Give videos a `poster` and `aspectRatio` where you know them.
- Keep `itemBuilder` cheap and avoid rebuilding the whole list on every like;
  update only the post that changed.
- Prefer `ReelsFeedController` over `setState` for things like mute and pause,
  which already update only the widgets that show them.

## Testing

`ReelVideoPool` takes a `controllerFactory`, and `video_player` can be faked with
`VideoPlayerPlatform.instance`. The package's own tests do this to check that a
long scroll never keeps more than four players open, so you can do the same for
your screens.

## License

BSD 3-Clause. Copyright (c) 2026 Kenresoft Technologies Ltd.
