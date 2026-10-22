import 'package:flutter_test/flutter_test.dart';
import 'package:reels_feed/reels_feed.dart';

void main() {
  group('formatReelCount', () {
    test('leaves small counts alone', () {
      expect(formatReelCount(0), '0');
      expect(formatReelCount(7), '7');
      expect(formatReelCount(999), '999');
    });

    test('shortens thousands, millions and billions', () {
      expect(formatReelCount(1000), '1K');
      expect(formatReelCount(1200), '1.2K');
      expect(formatReelCount(9999), '9.9K');
      expect(formatReelCount(12345), '12K');
      expect(formatReelCount(999999), '999K');
      expect(formatReelCount(1000000), '1M');
      expect(formatReelCount(1550000), '1.5M');
      expect(formatReelCount(2000000000), '2B');
    });

    test('cuts instead of rounding so a count never reads higher than it is', () {
      expect(formatReelCount(1999), '1.9K');
      expect(formatReelCount(19999), '19K');
    });

    test('handles negatives', () {
      expect(formatReelCount(-1500), '-1.5K');
    });
  });

  group('ReelSource', () {
    test('sources with the same address are equal', () {
      expect(const ReelSource.network('https://a/b.mp4'), const ReelSource.network('https://a/b.mp4'));
      expect(
        const ReelSource.network('https://a/b.mp4'),
        isNot(const ReelSource.network('https://a/c.mp4')),
      );
    });

    test('an asset and a file with the same text are different sources', () {
      expect(const ReelSource.asset('x.mp4'), isNot(const ReelSource.file('x.mp4')));
    });

    test('an asset key includes its package', () {
      expect(const ReelSource.asset('a.mp4', package: 'pkg').key, 'packages/pkg/a.mp4');
    });
  });

  group('ReelMedia', () {
    test('describes pictures and videos', () {
      final video = ReelMedia.videoUrl('https://a/v.mp4', posterUrl: 'https://a/p.jpg');
      expect(video.isVideo, isTrue);
      expect(video.poster, const ReelSource.network('https://a/p.jpg'));
      expect(ReelMedia.imageUrl('https://a/i.jpg').isVideo, isFalse);
    });

    test('equal media compare equal', () {
      expect(ReelMedia.imageUrl('https://a/i.jpg'), ReelMedia.imageUrl('https://a/i.jpg'));
    });
  });

  group('ReelsPreload', () {
    test('the visible post is active', () {
      expect(const ReelsPreload().phaseOf(4, 4), ReelItemPhase.active);
    });

    test('neighbours within the window preload, the rest are idle', () {
      const preload = ReelsPreload(ahead: 2, behind: 1);
      expect(preload.phaseOf(5, 4), ReelItemPhase.preload);
      expect(preload.phaseOf(6, 4), ReelItemPhase.preload);
      expect(preload.phaseOf(7, 4), ReelItemPhase.idle);
      expect(preload.phaseOf(3, 4), ReelItemPhase.preload);
      expect(preload.phaseOf(2, 4), ReelItemPhase.idle);
    });

    test('none keeps only the visible post', () {
      const none = ReelsPreload.none();
      expect(none.phaseOf(5, 4), ReelItemPhase.idle);
      expect(none.reach, 0);
    });
  });

  group('ReelsFeedController', () {
    test('mute and pause toggle', () {
      final c = ReelsFeedController(startMuted: false);
      addTearDown(c.dispose);
      expect(c.muted.value, isFalse);
      c.toggleMute();
      expect(c.muted.value, isTrue);
      c.setPaused(true);
      expect(c.paused.value, isTrue);
      c.togglePause();
      expect(c.paused.value, isFalse);
    });

    test('publishing a new index clears the pause', () {
      final c = ReelsFeedController();
      addTearDown(c.dispose);
      c.setPaused(true);
      c.updateIndex(3);
      expect(c.currentIndex.value, 3);
      expect(c.paused.value, isFalse);
    });

    test('starts at the initial index', () {
      final c = ReelsFeedController(initialIndex: 2);
      addTearDown(c.dispose);
      expect(c.currentIndex.value, 2);
    });
  });
}
