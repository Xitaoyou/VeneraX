import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app_page_route.dart';

class _TestBackGestureController implements IOSBackGestureController {
  @override
  AnimationController get controller => throw UnimplementedError();

  @override
  NavigatorState get navigator => throw UnimplementedError();

  @override
  void dragUpdate(double delta) {}

  @override
  void dragEnd(double velocity) {}
}

void main() {
  var starts = 0;
  setUp(() => starts = 0);
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
          enabledCallback: () => true,
          onStartPopGesture: () {
            starts++;
            return _TestBackGestureController();
          },
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
