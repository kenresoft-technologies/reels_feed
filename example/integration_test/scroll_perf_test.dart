import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reels_feed_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('scrolling through the feed', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump(const Duration(seconds: 4));

    final timings = <FrameTiming>[];
    void onTimings(List<FrameTiming> batch) => timings.addAll(batch);
    SchedulerBinding.instance.addTimingsCallback(onTimings);

    for (var i = 0; i < 10; i++) {
      await tester.fling(
        find.byType(PageView).first,
        const Offset(0, -600),
        2500,
      );
      await tester.pump(const Duration(milliseconds: 1500));
    }
    await tester.pump(const Duration(seconds: 1));
    SchedulerBinding.instance.removeTimingsCallback(onTimings);

    double ms(Duration d) => d.inMicroseconds / 1000;
    // Only frames that did work: idle frames are not scheduled at all.
    final build = timings.map((t) => ms(t.buildDuration)).toList()..sort();
    final raster = timings.map((t) => ms(t.rasterDuration)).toList()..sort();
    final total = timings.map((t) => ms(t.totalSpan)).toList()..sort();
    double pct(List<double> v, double p) =>
        v.isEmpty ? 0 : v[((v.length - 1) * p).round()];
    final over16 = total.where((t) => t > 16.7).length;
    final over50 = total.where((t) => t > 50).length;
    final over100 = total.where((t) => t > 100).length;
    // ignore: avoid_print
    print(
      'PERF frames=${timings.length} '
      'build(avg=${(build.reduce((a, b) => a + b) / build.length).toStringAsFixed(1)} p90=${pct(build, .9).toStringAsFixed(1)} p99=${pct(build, .99).toStringAsFixed(1)} max=${build.last.toStringAsFixed(1)}) '
      'raster(avg=${(raster.reduce((a, b) => a + b) / raster.length).toStringAsFixed(1)} p90=${pct(raster, .9).toStringAsFixed(1)} p99=${pct(raster, .99).toStringAsFixed(1)} max=${raster.last.toStringAsFixed(1)}) '
      'total(p90=${pct(total, .9).toStringAsFixed(1)} p99=${pct(total, .99).toStringAsFixed(1)} max=${total.last.toStringAsFixed(1)}) '
      'over16.7=$over16 over50=$over50 over100=$over100',
    );
  });
}
