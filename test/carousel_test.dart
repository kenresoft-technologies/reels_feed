import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reels_feed/reels_feed.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'fake_video_platform.dart';

const _video = 'https://cdn/clip.mp4';
final _clip = ReelMedia.videoUrl(_video, semanticLabel: 'A clip');

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 400, height: 800, child: child)),
);

Widget _blank(BuildContext context, ReelSource source, BoxFit fit) =>
    ColoredBox(color: Colors.blue, child: Text(source.key));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

// Disposing a native player finishes on the real event loop, not the test clock.
Future<void> _realSettle(WidgetTester tester) =>
    tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));

void main() {
  late FakeVideoPlatform platform;

  setUp(() {
    platform = FakeVideoPlatform();
    VideoPlayerPlatform.instance = platform;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('an active video opens, loops and plays', (tester) async {
    await tester.pumpWidget(_app(ReelMediaCarousel(media: [_clip])));
    await _settle(tester);

    expect(platform.created, [_video]);
    expect(platform.count('play', _video), 1);
    expect(platform.count('loop', _video), greaterThan(0));

    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
  });

  testWidgets('an idle post does not open its video at all', (tester) async {
    await tester.pumpWidget(_app(ReelMediaCarousel(media: [_clip], active: false)));
    await _settle(tester);

    expect(platform.created, isEmpty);
  });

  testWidgets('a preloading post opens its video but does not play it', (tester) async {
    await tester.pumpWidget(
      _app(
        ReelItemScope(
          state: const ReelItemState(index: 1, phase: ReelItemPhase.preload),
          child: ReelMediaCarousel(media: [_clip]),
        ),
      ),
    );
    await _settle(tester);

    expect(platform.created, [_video]);
    expect(platform.count('play', _video), 0);

    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
  });

  testWidgets('a preloaded video starts playing when its post becomes active', (tester) async {
    Widget carousel(ReelItemPhase phase) => _app(
      ReelItemScope(
        state: ReelItemState(index: 1, phase: phase),
        child: ReelMediaCarousel(media: [_clip]),
      ),
    );
    await tester.pumpWidget(carousel(ReelItemPhase.preload));
    await _settle(tester);
    expect(platform.count('play', _video), 0);

    await tester.pumpWidget(carousel(ReelItemPhase.active));
    await _settle(tester);

    expect(platform.created, hasLength(1));
    expect(platform.count('play', _video), 1);

    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
  });

  testWidgets('a video is paused when its post stops being active', (tester) async {
    Widget carousel(ReelItemPhase phase) => _app(
      ReelItemScope(
        state: ReelItemState(index: 1, phase: phase),
        child: ReelMediaCarousel(media: [_clip]),
      ),
    );
    await tester.pumpWidget(carousel(ReelItemPhase.active));
    await _settle(tester);
    final pausesBefore = platform.count('pause', _video);
    await tester.pumpWidget(carousel(ReelItemPhase.preload));
    await _settle(tester);

    expect(platform.count('pause', _video), pausesBefore + 1);

    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
  });

  testWidgets('tapping pauses and tapping again resumes', (tester) async {
    await tester.pumpWidget(_app(ReelMediaCarousel(media: [_clip])));
    await _settle(tester);
    final pausesBefore = platform.count('pause', _video);

    await tester.tapAt(const Offset(200, 400));
    await _settle(tester);
    expect(platform.count('pause', _video), pausesBefore + 1);

    await tester.tapAt(const Offset(200, 400));
    await _settle(tester);
    expect(platform.count('play', _video), 2);

    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
  });

  testWidgets('pressing and holding pauses until release', (tester) async {
    await tester.pumpWidget(_app(ReelMediaCarousel(media: [_clip])));
    await _settle(tester);
    final pausesBefore = platform.count('pause', _video);

    final gesture = await tester.startGesture(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 700));
    await _settle(tester);
    expect(platform.count('pause', _video), pausesBefore + 1);

    await gesture.up();
    await _settle(tester);
    expect(platform.count('play', _video), 2);

    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
  });

  testWidgets('the mute button silences the video and back', (tester) async {
    await tester.pumpWidget(_app(ReelMediaCarousel(media: [_clip])));
    await _settle(tester);
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.volume_up_rounded));
    await _settle(tester);
    expect(platform.volumeOf(_video), 0);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.volume_off_rounded));
    await _settle(tester);
    expect(platform.volumeOf(_video), 1);

    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
  });

  testWidgets('mute is shared across a feed through its controller', (tester) async {
    final controller = ReelsFeedController(startMuted: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        ReelsFeed(
          itemCount: 1,
          controller: controller,
          itemBuilder: (context, index) => ReelMediaCarousel(media: [_clip]),
        ),
      ),
    );
    await _settle(tester);

    await tester.tap(find.byIcon(Icons.volume_up_rounded));
    await _settle(tester);
    expect(controller.muted.value, isTrue);
    expect(platform.volumeOf(_video), 0);

    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
  });

  testWidgets('a feed disposes its players when it goes away', (tester) async {
    await tester.pumpWidget(
      _app(
        ReelsFeed(
          itemCount: 3,
          itemBuilder: (context, index) =>
              ReelMediaCarousel(media: [ReelMedia.videoUrl('https://cdn/$index.mp4')]),
        ),
      ),
    );
    await _settle(tester);
    expect(platform.openCount, greaterThan(0));

    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
    await _realSettle(tester);
    expect(platform.openCount, 0);
  });

  testWidgets('a feed keeps only a few players open while scrolling', (tester) async {
    final controller = ReelsFeedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        ReelsFeed(
          itemCount: 12,
          controller: controller,
          itemBuilder: (context, index) =>
              ReelMediaCarousel(media: [ReelMedia.videoUrl('https://cdn/$index.mp4')]),
        ),
      ),
    );
    await _settle(tester);

    for (var i = 1; i <= 8; i++) {
      final move = controller.animateToIndex(i, duration: const Duration(milliseconds: 50));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await _settle(tester);
      await move;
      await _realSettle(tester);
      // Visible post + one before + one ahead + one idle spare.
      expect(platform.openCount, lessThanOrEqualTo(4), reason: 'at post $i');
    }
    expect(platform.created.length, greaterThan(8));

    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
  });

  testWidgets('a video that cannot open shows a message and retry works', (tester) async {
    platform.failing.add(_video);
    await tester.pumpWidget(_app(ReelMediaCarousel(media: [_clip])));
    await _settle(tester);

    expect(find.text("Couldn't play this video"), findsOneWidget);

    platform.failing.clear();
    await tester.tap(find.text('Try again'));
    await _settle(tester);
    expect(find.text("Couldn't play this video"), findsNothing);
    expect(platform.count('play', _video), 1);

    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
  });

  group('pictures', () {
    testWidgets('a single picture shows no indicator', (tester) async {
      await tester.pumpWidget(
        _app(ReelMediaCarousel(media: [ReelMedia.imageUrl('https://cdn/a.jpg')], imageBuilder: _blank)),
      );
      await tester.pump();

      expect(find.text('https://cdn/a.jpg'), findsOneWidget);
      expect(find.bySemanticsLabel('Item 1 of 1'), findsNothing);
    });

    testWidgets('several media swipe sideways and report the page', (tester) async {
      final pages = <int>[];
      await tester.pumpWidget(
        _app(
          ReelMediaCarousel(
            media: [ReelMedia.imageUrl('https://cdn/a.jpg'), ReelMedia.imageUrl('https://cdn/b.jpg')],
            imageBuilder: _blank,
            onPageChanged: pages.add,
          ),
        ),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('Item 1 of 2'), findsOneWidget);

      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1500);
      await tester.pumpAndSettle();

      expect(pages, [1]);
      expect(find.text('https://cdn/b.jpg'), findsOneWidget);
      expect(find.bySemanticsLabel('Item 2 of 2'), findsOneWidget);
    });

    testWidgets('the indicator can be hidden', (tester) async {
      await tester.pumpWidget(
        _app(
          ReelMediaCarousel(
            media: [ReelMedia.imageUrl('https://cdn/a.jpg'), ReelMedia.imageUrl('https://cdn/b.jpg')],
            imageBuilder: _blank,
            indicator: ReelIndicatorStyle.none,
          ),
        ),
      );
      await tester.pump();

      expect(find.bySemanticsLabel('Item 1 of 2'), findsNothing);
    });
  });

  group('double tap', () {
    testWidgets('reports the position and bursts a heart', (tester) async {
      Offset? tapped;
      await tester.pumpWidget(
        _app(
          ReelMediaCarousel(
            media: [ReelMedia.imageUrl('https://cdn/a.jpg')],
            imageBuilder: _blank,
            onDoubleTap: (position) => tapped = position,
          ),
        ),
      );
      await tester.pump();

      final center = tester.getCenter(find.byType(ReelMediaCarousel));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 100));

      expect(tapped, isNotNull);
      expect(find.byIcon(Icons.favorite), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite), findsNothing);
    });
  });

  testWidgets('an empty list of media shows just the background', (tester) async {
    await tester.pumpWidget(_app(const ReelMediaCarousel(media: [])));
    expect(find.byType(PageView), findsNothing);
  });
}
