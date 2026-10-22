import 'package:any_source_image/any_source_image.dart';
import 'package:flutter/material.dart';
import 'package:reels_feed/reels_feed.dart';

// Used by the performance test to compare builds: full, media, images or raw.
const String perfMode = String.fromEnvironment('PERF', defaultValue: 'full');

void main() => runApp(const ExampleApp());

/// A small demo of `reels_feed`: a feed of videos and picture carousels with the
/// usual overlays, a like that bursts a heart, and endless loading.
class ExampleApp extends StatelessWidget {
  /// Creates the demo app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'reels_feed example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const FeedPage(),
    );
  }
}

/// One post in the demo. Real apps would use their own model.
class Post {
  /// Creates a post.
  Post({
    required this.id,
    required this.author,
    required this.caption,
    required this.media,
    this.likes = 0,
    this.comments = 0,
  });

  /// A unique id.
  final int id;

  /// Who posted it.
  final String author;

  /// The text under the post.
  final String caption;

  /// The pictures and videos.
  final List<ReelMedia> media;

  /// How many likes.
  int likes;

  /// How many comments.
  int comments;

  /// Whether the viewer liked it.
  bool liked = false;

  /// Whether the viewer saved it.
  bool saved = false;
}

const _bee =
    'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4';
const _butterfly =
    'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4';

/// Makes demo posts: videos, a carousel mixing pictures and a video, and a
/// single picture, repeating.
List<Post> makePosts(int start, int count) {
  return List.generate(count, (i) {
    final id = start + i;
    switch (id % 3) {
      case 0:
        return Post(
          id: id,
          author: 'bee_keeper_$id',
          caption: 'Busy bees on a sunny day #nature #bees @flutterdev',
          likes: 1200 + id * 37,
          comments: 48 + id,
          media: [
            ReelMedia.videoUrl(
              _bee,
              posterUrl: 'https://picsum.photos/seed/bee$id/720/1280',
            ),
          ],
        );
      case 1:
        return Post(
          id: id,
          author: 'photo_walks',
          caption:
              'A little tour in three parts. Swipe sideways to see them all, and tap the video to '
              'pause it. #travel #photography #carousel https://example.com/tour',
          likes: 89000 + id,
          comments: 1204,
          media: [
            ReelMedia.imageUrl(
              'https://picsum.photos/seed/a$id/720/1280',
              aspectRatio: 9 / 16,
            ),
            ReelMedia.imageUrl(
              'https://picsum.photos/seed/b$id/1280/720',
              aspectRatio: 16 / 9,
            ),
            ReelMedia.videoUrl(
              _butterfly,
              posterUrl: 'https://picsum.photos/seed/c$id/720/1280',
            ),
          ],
        );
      default:
        return Post(
          id: id,
          author: 'quiet_corners',
          caption: 'Double tap to like. #still',
          likes: 310,
          comments: 7,
          media: [
            ReelMedia.imageUrl(
              'https://picsum.photos/seed/d$id/720/1280',
              aspectRatio: 9 / 16,
            ),
          ],
        );
    }
  });
}

/// The demo screen.
class FeedPage extends StatefulWidget {
  /// Creates the demo screen.
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final ReelsFeedController _controller = ReelsFeedController();
  final List<Post> _posts = makePosts(0, 6);
  bool _loadingMore = false;
  int _viewed = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    // Stand-in for a network request.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() {
      _posts.addAll(makePosts(_posts.length, 6));
      _loadingMore = false;
    });
  }

  void _toggleLike(Post post) {
    setState(() {
      post.liked = !post.liked;
      post.likes += post.liked ? 1 : -1;
    });
  }

  void _note(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (perfMode == 'raw') {
      return Scaffold(
        body: PageView.builder(
          scrollDirection: Axis.vertical,
          itemBuilder: (context, i) => Image.network(
            'https://picsum.photos/seed/raw$i/720/1280',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
        ),
      );
    }
    if (perfMode == 'media' || perfMode == 'images') {
      final posts = perfMode == 'images'
          ? List.generate(
              40,
              (i) => Post(
                id: i,
                author: 'x',
                caption: '',
                media: [
                  ReelMedia.imageUrl(
                    'https://picsum.photos/seed/raw$i/720/1280',
                    aspectRatio: 9 / 16,
                  ),
                ],
              ),
            )
          : _posts;
      return Scaffold(
        body: ReelsFeed(
          itemCount: posts.length,
          itemBuilder: (context, i) => ReelMediaCarousel(media: posts[i].media),
        ),
      );
    }
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Reels',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 56),
            child: Center(
              child: Text(
                '$_viewed viewed',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: ReelsFeed(
        controller: _controller,
        itemCount: _posts.length,
        isLoadingMore: _loadingMore,
        onEndReached: _loadingMore ? null : _loadMore,
        onItemViewed: (index) => setState(() => _viewed++),
        itemBuilder: (context, index) => _PostView(
          post: _posts[index],
          onLike: () => _toggleLike(_posts[index]),
          onNote: _note,
          onSave: () =>
              setState(() => _posts[index].saved = !_posts[index].saved),
        ),
      ),
    );
  }
}

class _PostView extends StatelessWidget {
  const _PostView({
    required this.post,
    required this.onLike,
    required this.onSave,
    required this.onNote,
  });

  final Post post;
  final VoidCallback onLike;
  final VoidCallback onSave;
  final ValueChanged<String> onNote;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ReelMediaCarousel(
          media: post.media,
          // Pictures load through any_source_image, which caches them on disk.
          imageBuilder: _cachedImage,
          // Double tap likes (it only adds a like, like the big apps do).
          onDoubleTap: (_) {
            if (!post.liked) onLike();
          },
          progressPadding: const EdgeInsets.only(bottom: 0),
        ),
        const ReelScrim(),
        const ReelScrim.top(),
        Positioned(
          right: 8,
          bottom: 56,
          child: SafeArea(
            top: false,
            child: ReelActionRail(
              actions: [
                ReelAction(
                  icon: Icons.favorite_border,
                  activeIcon: Icons.favorite,
                  isActive: post.liked,
                  count: post.likes,
                  semanticLabel: 'Like',
                  onTap: onLike,
                ),
                ReelAction(
                  icon: Icons.chat_bubble_outline,
                  count: post.comments,
                  semanticLabel: 'Comments',
                  onTap: () => onNote('Comments would open here'),
                ),
                ReelAction(
                  icon: Icons.send_outlined,
                  label: 'Share',
                  semanticLabel: 'Share',
                  onTap: () => onNote('Share sheet would open here'),
                ),
                ReelAction(
                  icon: Icons.bookmark_border,
                  activeIcon: Icons.bookmark,
                  isActive: post.saved,
                  activeColor: Colors.amber,
                  semanticLabel: 'Save',
                  onTap: onSave,
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 88,
          bottom: 56,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@${post.author}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    shadows: reelCheapShadow,
                  ),
                ),
                const SizedBox(height: 6),
                ReelCaption(
                  text: post.caption,
                  onHashtagTap: (tag) => onNote('Search #$tag'),
                  onMentionTap: (name) => onNote('Open @$name'),
                  onLinkTap: (url) => onNote('Open $url'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Loads a picture with `any_source_image`: network images are cached on disk,
/// with a placeholder while loading and an error widget if it fails.
Widget _cachedImage(BuildContext context, ReelSource source, BoxFit fit) {
  return AppImage(
    source.key,
    fit: fit,
    width: double.infinity,
    height: double.infinity,
    placeholderColor: Colors.white10,
  );
}
