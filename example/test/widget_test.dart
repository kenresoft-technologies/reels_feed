import 'package:flutter_test/flutter_test.dart';
import 'package:reels_feed/reels_feed.dart';
import 'package:reels_feed_example/main.dart';

void main() {
  test('makePosts cycles through videos, carousels and pictures', () {
    final posts = makePosts(0, 3);

    expect(posts[0].media.single.isVideo, isTrue);
    expect(posts[1].media, hasLength(3));
    expect(posts[2].media.single.type, ReelMediaType.image);
    expect(makePosts(3, 1).single.id, 3);
  });

  testWidgets('the demo shows a feed with the first post', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();

    expect(find.text('Reels'), findsOneWidget);
    expect(find.byType(ReelsFeed), findsOneWidget);
    expect(find.text('@bee_keeper_0'), findsOneWidget);
    expect(find.text('Like'), findsNothing);
  });
}
