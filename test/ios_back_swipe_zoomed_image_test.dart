import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:venera/components/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app_page_route.dart';

/// Regression test for #310.
///
/// On iOS a right swipe anywhere on the reader pops it. Once the image is
/// zoomed, a right drag pans the image instead, so the back swipe must fall
/// back to the screen's left edge — also when the zoom began after the finger
/// went down (long-press zoom).
void main() {
  var starts = 0;
  var zoomed = false;

  Widget buildDetector({bool Function()? active}) {
    return MaterialApp(
      home: IOSBackGestureDetector(
        gestureWidth: 20,
        // Only called once the recognizer has claimed the drag; returning false
        // leaves the route alone.
        enabledCallback: () {
          starts++;
          return false;
        },
        onStartPopGesture: () => throw StateError('unreachable'),
        child: SwipeRegionMarker(
          active: active,
          child: const ColoredBox(
            color: Colors.white,
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  setUp(() {
    starts = 0;
    zoomed = false;
  });

  testWidgets('mid-page right swipe starts the back gesture when not zoomed', (
    tester,
  ) async {
    await tester.pumpWidget(buildDetector(active: () => zoomed));
    await tester.dragFrom(const Offset(300, 300), const Offset(150, 0));
    await tester.pump();
    expect(starts, 1);
  });

  testWidgets('mid-page right swipe on a zoomed image does not go back', (
    tester,
  ) async {
    zoomed = true;
    await tester.pumpWidget(buildDetector(active: () => zoomed));
    await tester.dragFrom(const Offset(300, 300), const Offset(150, 0));
    await tester.pump();
    expect(starts, 0);
  });

  testWidgets('left-edge swipe still goes back while zoomed', (tester) async {
    zoomed = true;
    await tester.pumpWidget(buildDetector(active: () => zoomed));
    await tester.dragFrom(const Offset(5, 300), const Offset(150, 0));
    await tester.pump();
    expect(starts, 1);
  });

  testWidgets('zoom that starts after pointer down is honored', (tester) async {
    await tester.pumpWidget(buildDetector(active: () => zoomed));
    final gesture = await tester.startGesture(const Offset(300, 300));
    // Long-press zoom kicks in while the finger is still resting.
    zoomed = true;
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    await tester.pump();
    expect(starts, 0);
  });

  testWidgets('marker without a predicate always claims horizontal drags', (
    tester,
  ) async {
    await tester.pumpWidget(buildDetector());
    await tester.dragFrom(const Offset(300, 300), const Offset(150, 0));
    await tester.pump();
    expect(starts, 0);
  });

  Widget buildTileDetector({bool startPane = false, VoidCallback? onTap}) {
    final pane = SwipePane(
      actions: [
        SwipeAction(icon: Icons.favorite, label: 'Favorite', onPressed: () {}),
      ],
    );
    return MaterialApp(
      home: Material(
        child: IOSBackGestureDetector(
          gestureWidth: 20,
          enabledCallback: () {
            starts++;
            return false;
          },
          onStartPopGesture: () => throw StateError('unreachable'),
          child: ListView(
            children: [
              SwipeActionTile(
                startPane: startPane ? pane : null,
                endPane: pane,
                child: InkWell(
                  onTap: onTap,
                  child: const SizedBox(
                    height: 220,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 150,
                          height: 200,
                          child: ColoredBox(color: Colors.blue),
                        ),
                        Expanded(child: Text('Comic title')),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 1800),
            ],
          ),
        ),
      ),
    );
  }

  for (final startPane in [false, true]) {
    for (final x in [80.0, 300.0]) {
      testWidgets(
        'closed comic tile yields right swipe at $x, start pane $startPane',
        (tester) async {
          await tester.pumpWidget(buildTileDetector(startPane: startPane));
          await tester.dragFrom(Offset(x, 100), const Offset(220, 0));
          await tester.pumpAndSettle();
          expect(starts, 1);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      );
    }
  }

  testWidgets(
    'left swipe opens actions, right swipe closes without back',
    (tester) async {
      await tester.pumpWidget(buildTileDetector());
      final controller = Slidable.of(
        tester.element(find.byType(InkWell).first),
      )!;
      await tester.dragFrom(const Offset(300, 100), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(controller.ratio, lessThan(0));
      expect(starts, 0);
      await tester.dragFrom(const Offset(100, 100), const Offset(220, 0));
      await tester.pumpAndSettle();
      expect(controller.ratio, 0);
      expect(starts, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'comic tile retains taps and vertical scrolling',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(buildTileDetector(onTap: () => taps++));
      await tester.tapAt(const Offset(80, 100));
      await tester.pumpAndSettle();
      expect(taps, 1);
      await tester.dragFrom(const Offset(80, 160), const Offset(0, -130));
      await tester.pumpAndSettle();
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
        greaterThan(0),
      );
      expect(starts, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
