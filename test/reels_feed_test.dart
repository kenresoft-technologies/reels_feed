import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reels_feed/reels_feed.dart';

Widget _item(BuildContext context, int index) {
  final state = ReelItemScope.of(context);
  return Center(child: Text('$index:${state.phase.name}'));
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows the first post as active and builds its neighbour as preload', (tester) async {
    await tester.pumpWidget(_app(const ReelsFeed(itemCount: 5, itemBuilder: _item)));

    expect(find.text('0:active'), findsOneWidget);
    expect(find.text('1:preload', skipOffstage: false), findsOneWidget);
  });

  testWidgets('swiping up moves to the next post and reports it', (tester) async {
    final pages = <int>[];
    await tester.pumpWidget(_app(ReelsFeed(itemCount: 5, itemBuilder: _item, onPageChanged: pages.add)));

    await tester.fling(find.byType(PageView), const Offset(0, -300), 1500);
    await tester.pumpAndSettle();

    expect(pages, [1]);
    expect(find.text('1:active'), findsOneWidget);
    expect(find.text('0:preload', skipOffstage: false), findsOneWidget);
  });

  testWidgets('a controller reads and drives the feed', (tester) async {
    final controller = ReelsFeedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(ReelsFeed(itemCount: 5, itemBuilder: _item, controller: controller)));

    unawaited(controller.animateToIndex(3));
    await tester.pumpAndSettle();

    expect(controller.currentIndex.value, 3);
    expect(find.text('3:active'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no posts', (tester) async {
    await tester.pumpWidget(
      _app(
        ReelsFeed(
          itemCount: 0,
          itemBuilder: _item,
          emptyBuilder: (_) => const Center(child: Text('Nothing here')),
        ),
      ),
    );

    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
  });

  group('onEndReached', () {
    testWidgets('fires once the viewer is near the end, and only once per position', (tester) async {
      var calls = 0;
      final controller = ReelsFeedController();
      addTearDown(controller.dispose);
      Widget feed() => _app(
        ReelsFeed(
          itemCount: 10,
          itemBuilder: _item,
          controller: controller,
          endReachedThreshold: 2,
          onEndReached: () => calls++,
        ),
      );
      await tester.pumpWidget(feed());
      expect(calls, 0);

      controller.jumpToIndex(7);
      await tester.pumpAndSettle();
      expect(calls, 1);

      // Rebuilding at the same place does not ask again.
      await tester.pumpWidget(feed());
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets('asks again when more posts arrive', (tester) async {
      var calls = 0;
      final controller = ReelsFeedController(initialIndex: 4);
      addTearDown(controller.dispose);
      Widget feed(int count) => _app(
        ReelsFeed(
          itemCount: count,
          itemBuilder: _item,
          controller: controller,
          endReachedThreshold: 2,
          onEndReached: () => calls++,
        ),
      );
      await tester.pumpWidget(feed(6));
      await tester.pump();
      expect(calls, 1);

      await tester.pumpWidget(feed(7));
      await tester.pump();
      expect(calls, 2);
    });

    testWidgets('waits while more posts are loading', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        _app(
          ReelsFeed(itemCount: 3, itemBuilder: _item, isLoadingMore: true, onEndReached: () => calls++),
        ),
      );
      await tester.pump();

      expect(calls, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('onItemViewed', () {
    testWidgets('reports a post after it has stayed on screen, once', (tester) async {
      final viewed = <int>[];
      await tester.pumpWidget(
        _app(ReelsFeed(itemCount: 5, itemBuilder: _item, onItemViewed: viewed.add)),
      );

      await tester.pump(const Duration(milliseconds: 900));
      expect(viewed, isEmpty);
      await tester.pump(const Duration(milliseconds: 200));
      expect(viewed, [0]);
      await tester.pump(const Duration(seconds: 5));
      expect(viewed, [0]);
    });

    testWidgets('does not count a post that was swiped past quickly', (tester) async {
      final viewed = <int>[];
      final controller = ReelsFeedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          ReelsFeed(itemCount: 5, itemBuilder: _item, controller: controller, onItemViewed: viewed.add),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      unawaited(controller.animateToIndex(1));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 1100));

      expect(viewed, [1]);
    });

    testWidgets('does not count while the feed is inactive', (tester) async {
      final viewed = <int>[];
      await tester.pumpWidget(
        _app(ReelsFeed(itemCount: 5, itemBuilder: _item, active: false, onItemViewed: viewed.add)),
      );

      await tester.pump(const Duration(seconds: 3));
      expect(viewed, isEmpty);
    });
  });

  testWidgets('an inactive feed has no active post', (tester) async {
    await tester.pumpWidget(_app(const ReelsFeed(itemCount: 5, itemBuilder: _item, active: false)));

    expect(find.text('0:preload', skipOffstage: false), findsOneWidget);
    expect(find.text('0:active'), findsNothing);
  });

  testWidgets('going to the background deactivates the post and coming back restores it', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const ReelsFeed(itemCount: 5, itemBuilder: _item)));
    expect(find.text('0:active'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.text('0:active'), findsNothing);
    expect(find.text('0:preload', skipOffstage: false), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('0:active'), findsOneWidget);
  });

  testWidgets('a route covering the feed deactivates it', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: ReelsFeed(itemCount: 5, itemBuilder: _item)),
      ),
    );
    expect(find.text('0:active'), findsOneWidget);

    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('covering'))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0:active', skipOffstage: false), findsNothing);
  });

  testWidgets('arrow keys move between posts and M toggles mute', (tester) async {
    final controller = ReelsFeedController(startMuted: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(ReelsFeed(itemCount: 5, itemBuilder: _item, controller: controller)));

    await tester.tapAt(const Offset(400, 300));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(controller.currentIndex.value, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(controller.currentIndex.value, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(controller.muted.value, isTrue);
  });

  testWidgets('shortening the list below the current post brings the viewer back', (tester) async {
    final controller = ReelsFeedController(initialIndex: 4);
    addTearDown(controller.dispose);
    Widget feed(int count) =>
        _app(ReelsFeed(itemCount: count, itemBuilder: _item, controller: controller));
    await tester.pumpWidget(feed(5));
    await tester.pumpWidget(feed(2));
    await tester.pumpAndSettle();

    expect(find.text('1:active'), findsOneWidget);
  });
}

void unawaited(Future<void> future) {}
