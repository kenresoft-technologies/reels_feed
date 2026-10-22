/// A vertical, full-screen feed of videos and pictures for Flutter, in the style
/// of Reels, Shorts and TikTok.
///
/// Start with [ReelsFeed] and [ReelMediaCarousel]; add [ReelActionRail],
/// [ReelCaption] and [ReelScrim] for the usual overlays.
library;

export 'src/media/reel_image_view.dart' show ReelImageBuilder;
export 'src/media/reel_media.dart' show ReelMedia, ReelMediaType;
export 'src/media/reel_media_carousel.dart' show ReelIndicatorStyle, ReelMediaCarousel;
export 'src/media/reel_source.dart'
    show ReelAssetSource, ReelFileSource, ReelNetworkSource, ReelSource, createReelVideoController;
export 'src/media/reel_video_cache.dart' show ReelVideoCache;
export 'src/media/reel_video_pool.dart'
    show ReelVideoControllerFactory, ReelVideoEntry, ReelVideoPool, ReelVideoStatus;
export 'src/media/reel_video_view.dart' show ReelErrorBuilder;
export 'src/reel_item_state.dart' show ReelItemPhase, ReelItemScope, ReelItemState, ReelsFeedScope;
export 'src/reels_feed.dart' show ReelsFeed, ReelsPreload;
export 'src/reels_feed_controller.dart' show ReelsFeedController;
export 'src/widgets/format_count.dart' show formatReelCount;
export 'src/widgets/reel_action_rail.dart' show ReelAction, ReelActionRail;
export 'src/widgets/reel_caption.dart' show ReelCaption;
export 'src/widgets/reel_heart_burst.dart' show ReelHeartBurst, ReelHeartBurstState;
export 'src/widgets/reel_progress_bar.dart' show ReelProgressBar;
export 'src/widgets/reel_scrim.dart' show ReelScrim;
export 'src/widgets/reel_shadows.dart' show reelCheapShadow;
