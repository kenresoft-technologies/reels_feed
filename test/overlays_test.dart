import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reels_feed/reels_feed.dart';

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 300, child: child)),
  ),
);

TextSpan? _findSpan(WidgetTester tester, String text) {
  TextSpan? found;
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.text == text) found = span;
      return true;
    });
  }
  return found;
}

void main() {
  group('ReelActionRail', () {
    testWidgets('shows shortened counts and calls onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(
          ReelActionRail(
            actions: [
              ReelAction(
                icon: Icons.favorite_border,
                activeIcon: Icons.favorite,
                count: 1234,
                semanticLabel: 'Like',
                onTap: () => taps++,
              ),
              const ReelAction(icon: Icons.share_outlined, semanticLabel: 'Share'),
            ],
          ),
        ),
      );

      expect(find.text('1.2K'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.favorite_border));
      expect(taps, 1);
    });

    testWidgets('an active action shows its active icon', (tester) async {
      await tester.pumpWidget(
        _app(
          const ReelActionRail(
            actions: [
              ReelAction(
                icon: Icons.favorite_border,
                activeIcon: Icons.favorite,
                isActive: true,
                semanticLabel: 'Like',
              ),
            ],
          ),
        ),
      );

      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
    });

    testWidgets('exposes the label and count to screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          const ReelActionRail(
            actions: [ReelAction(icon: Icons.chat_bubble_outline, count: 52, semanticLabel: 'Comments')],
          ),
        ),
      );

      expect(find.bySemanticsLabel('Comments'), findsOneWidget);
      handle.dispose();
    });
  });

  group('ReelCaption', () {
    testWidgets('a short caption shows no more link', (tester) async {
      await tester.pumpWidget(_app(const ReelCaption(text: 'Hello world')));

      expect(find.text('more'), findsNothing);
    });

    testWidgets('a long caption can be expanded and collapsed', (tester) async {
      await tester.pumpWidget(_app(ReelCaption(text: List.filled(60, 'word').join(' '))));
      expect(find.text('more'), findsOneWidget);

      await tester.tap(find.text('more'));
      await tester.pumpAndSettle();
      expect(find.text('less'), findsOneWidget);

      await tester.tap(find.text('less'));
      await tester.pumpAndSettle();
      expect(find.text('more'), findsOneWidget);
    });

    testWidgets('hashtags, mentions and links are tappable', (tester) async {
      String? tag;
      String? mention;
      String? link;
      await tester.pumpWidget(
        _app(
          ReelCaption(
            text: 'Look #flutter by @ken_resoft at https://example.com now',
            onHashtagTap: (v) => tag = v,
            onMentionTap: (v) => mention = v,
            onLinkTap: (v) => link = v,
          ),
        ),
      );

      (_findSpan(tester, '#flutter')!.recognizer! as TapGestureRecognizer).onTap!();
      (_findSpan(tester, '@ken_resoft')!.recognizer! as TapGestureRecognizer).onTap!();
      (_findSpan(tester, 'https://example.com')!.recognizer! as TapGestureRecognizer).onTap!();

      expect(tag, 'flutter');
      expect(mention, 'ken_resoft');
      expect(link, 'https://example.com');
    });

    testWidgets('hashtags without a handler are plain styled text', (tester) async {
      await tester.pumpWidget(_app(const ReelCaption(text: 'A #tag')));

      expect(_findSpan(tester, '#tag')!.recognizer, isNull);
    });

    testWidgets('understands non-English hashtags', (tester) async {
      String? tag;
      await tester.pumpWidget(_app(ReelCaption(text: 'Ọjọ́ #ẹwà', onHashtagTap: (v) => tag = v)));

      (_findSpan(tester, '#ẹwà')!.recognizer! as TapGestureRecognizer).onTap!();
      expect(tag, 'ẹwà');
    });
  });

  group('ReelHeartBurst', () {
    testWidgets('shows a heart where asked and removes it when done', (tester) async {
      final key = GlobalKey<ReelHeartBurstState>();
      await tester.pumpWidget(_app(SizedBox(height: 300, child: ReelHeartBurst(key: key))));
      expect(find.byIcon(Icons.favorite), findsNothing);

      key.currentState!.burst(const Offset(100, 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.favorite), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite), findsNothing);
    });

    testWidgets('several bursts can overlap', (tester) async {
      final key = GlobalKey<ReelHeartBurstState>();
      await tester.pumpWidget(_app(SizedBox(height: 300, child: ReelHeartBurst(key: key))));

      key.currentState!.burst(const Offset(50, 50));
      key.currentState!.burst(const Offset(150, 150));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.favorite), findsNWidgets(2));
      await tester.pumpAndSettle();
    });

    testWidgets('does not block touches', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(
          SizedBox(
            height: 300,
            child: Stack(
              children: [
                GestureDetector(
                  key: const Key('target'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const SizedBox.expand(),
                ),
                const ReelHeartBurst(),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('target')));
      expect(taps, 1);
    });
  });

  testWidgets('ReelScrim does not take touches', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        SizedBox(
          height: 400,
          child: Stack(
            children: [
              GestureDetector(
                key: const Key('target'),
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: const SizedBox.expand(),
              ),
              const ReelScrim(),
              const ReelScrim.top(),
            ],
          ),
        ),
      ),
    );

    await tester.tapAt(tester.getBottomLeft(find.byKey(const Key('target'))) + const Offset(20, -20));
    expect(taps, 1);
  });
}
