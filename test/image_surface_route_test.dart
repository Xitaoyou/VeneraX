import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/pull_down_to_dismiss.dart';
import 'package:venera/foundation/app_page_route.dart';
import 'package:venera/foundation/image_surface_route.dart';

import 'pull_down_to_dismiss_test.dart' show testImage;

const _source = ValueKey('source-page');
const _surface = ValueKey('surface-page');
const _chrome = ValueKey('surface-chrome');
const _picture = ValueKey('surface-picture');
const _tag = 'visible-photo';

Future<ImageSurfaceRoute<void>> openSurface(
  WidgetTester tester, {
  bool preview = false,
  bool sourceVisible = true,
  bool offscreen = false,
  bool nested = false,
  bool reduced = false,
  ValueNotifier<bool>? canPop,
}) async {
  final navigator = GlobalKey<NavigatorState>();
  Widget thumbnail() => Align(
    alignment: Alignment.topLeft,
    child: Padding(
      padding: EdgeInsets.only(left: 30, top: offscreen ? 1000 : 60),
      child: SizedBox(
        width: 100,
        height: 150,
        child: Hero(
          tag: _tag,
          createRectTween: imageSurfaceRectTween,
          flightShuttleBuilder: imageSurfaceHeroFlight,
          transitionOnUserGestures: true,
          child: Image(image: testImage, fit: BoxFit.cover),
        ),
      ),
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      ),
      onGenerateRoute: (settings) => AppPageRoute<void>(
        settings: settings,
        builder: (_) => Scaffold(
          key: _source,
          body: nested
              ? Navigator(
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) =>
                        sourceVisible ? thumbnail() : const SizedBox.expand(),
                  ),
                )
              : sourceVisible
              ? thumbnail()
              : const SizedBox.expand(),
        ),
      ),
    ),
  );
  await tester.runAsync(
    () => precacheImage(testImage, navigator.currentContext!),
  );
  final route = ImageSurfaceRoute<void>(
    preview: preview,
    builder: (_) {
      final page = Scaffold(
        key: _surface,
        body: PullDownToDismiss(
          enabled: () => true,
          heroTag: () => _tag,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              const Positioned(
                left: 0,
                top: 0,
                right: 0,
                height: 48,
                child: ColoredBox(key: _chrome, color: Colors.blue),
              ),
              Center(
                child: SizedBox(
                  width: 320,
                  height: 480,
                  child: preview
                      ? Hero(
                          tag: _tag,
                          createRectTween: imageSurfaceRectTween,
                          flightShuttleBuilder: imageSurfaceHeroFlight,
                          transitionOnUserGestures: true,
                          child: Image(
                            key: _picture,
                            image: testImage,
                            fit: BoxFit.contain,
                          ),
                        )
                      : Image(
                          key: _picture,
                          image: testImage,
                          fit: BoxFit.contain,
                        ),
                ),
              ),
            ],
          ),
        ),
      );
      return canPop == null
          ? page
          : ValueListenableBuilder<bool>(
              valueListenable: canPop,
              builder: (_, allowed, child) =>
                  PopScope(canPop: allowed, child: child!),
              child: page,
            );
    },
  );
  navigator.currentState!.push(route);
  await tester.pumpAndSettle();
  return route;
}

void iosTest(String name, WidgetTesterCallback test) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await test(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  iosTest(
    'whole page and chrome move together; previous AppPageRoute stays fixed',
    (tester) async {
      await openSurface(tester);
      final drag = await tester.startGesture(const Offset(400, 200));
      await drag.moveBy(const Offset(0, 160));
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(_source)).dx, closeTo(0, 0.01));
      final transform = find.byKey(const ValueKey('image-surface-translation'));
      expect(
        find.ancestor(of: find.byKey(_chrome), matching: transform),
        findsOneWidget,
      );
      expect(
        find.ancestor(of: find.byKey(_picture), matching: transform),
        findsOneWidget,
      );
      expect(
        tester.widget<Transform>(transform).transform.storage[13],
        inInclusiveRange(1, 80),
      );
      await drag.up();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        expect(tester.getTopLeft(find.byKey(_source)).dx, closeTo(0, 0.01));
        if (find.byKey(_surface).evaluate().isNotEmpty) {
          final matrix = tester.widget<Transform>(transform).transform;
          expect(matrix.storage[12], closeTo(0, 0.01));
          expect(matrix.storage[13], inInclusiveRange(0, 80));
        }
      }
      await tester.pumpAndSettle();
      expect(find.byKey(_surface), findsNothing);
    },
  );

  for (final nested in [false, true]) {
    iosTest('preview returns to its visible thumbnail, nested=$nested', (
      tester,
    ) async {
      final route = await openSurface(tester, preview: true, nested: nested);
      final before = tester.getRect(find.byKey(_picture));
      final drag = await tester.startGesture(const Offset(400, 200));
      await drag.moveBy(const Offset(0, 160));
      await tester.pump();
      final released = tester.getRect(find.byKey(_picture));
      expect(released.top, greaterThan(before.top));
      await drag.up();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      await tester.pump();
      expect(route.debugReturnsToThumbnail, isTrue);
      final flight = find.byKey(const ValueKey('image-surface-hero-flight'));
      expect(flight, findsOneWidget);
      final midway = tester.getRect(flight);
      final target = const Rect.fromLTWH(30, 60, 100, 150);
      expect(
        (midway.center - target.center).distance,
        lessThan((released.center - target.center).distance),
      );
      expect(midway.bottom, lessThanOrEqualTo(released.bottom + 1));
      expect(tester.getTopLeft(find.byKey(_source)).dx, closeTo(0, 0.01));
      await tester.pumpAndSettle();
      expect(find.byKey(_surface), findsNothing);
      expect(
        find.byKey(const ValueKey('image-surface-hero-flight')),
        findsNothing,
      );
    });
  }

  iosTest(
    'missing source falls back to one whole-page collapse without a Hero flight',
    (tester) async {
      final route = await openSurface(
        tester,
        preview: true,
        sourceVisible: false,
      );
      await tester.dragFrom(const Offset(400, 200), const Offset(0, 160));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      expect(route.debugReturnsToThumbnail, isFalse);
      expect(
        find.byKey(const ValueKey('image-surface-hero-flight')),
        findsNothing,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_surface), findsNothing);
    },
  );

  iosTest('offscreen thumbnail does not receive a flying image', (
    tester,
  ) async {
    final route = await openSurface(tester, preview: true, offscreen: true);
    await tester.dragFrom(const Offset(400, 200), const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(route.debugReturnsToThumbnail, isFalse);
    expect(find.byKey(_surface), findsNothing);
  });

  iosTest('disposing a page during a drag leaves no live ticker', (
    tester,
  ) async {
    await openSurface(tester);
    final drag = await tester.startGesture(const Offset(400, 200));
    await drag.moveBy(const Offset(0, 160));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await drag.cancel();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  iosTest('PopScope veto restores the page and its opaque state', (
    tester,
  ) async {
    final allowed = ValueNotifier(true);
    final route = await openSurface(tester, canPop: allowed);
    final drag = await tester.startGesture(const Offset(400, 200));
    await drag.moveBy(const Offset(0, 160));
    await tester.pump();
    allowed.value = false;
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(find.byKey(_surface), findsOneWidget);
    expect(route.opaque, isTrue);
    expect(route.isDismissing, isFalse);
    expect(
      tester
          .widget<Transform>(
            find.byKey(const ValueKey('image-surface-translation')),
          )
          .transform
          .storage[13],
      closeTo(0, 0.01),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    allowed.dispose();
  });

  for (final preview in [false, true]) {
    iosTest('left-edge back still works, preview=$preview', (tester) async {
      await openSurface(tester, preview: preview);
      await tester.dragFrom(const Offset(5, 300), const Offset(650, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(_surface), findsNothing);
      expect(tester.getTopLeft(find.byKey(_source)).dx, closeTo(0, 0.01));
    });
  }

  iosTest('reduced motion avoids movement and Hero flight', (tester) async {
    final route = await openSurface(tester, preview: true, reduced: true);
    final drag = await tester.startGesture(const Offset(400, 200));
    await drag.moveBy(const Offset(0, 160));
    await tester.pump();
    expect(
      tester
          .widget<Transform>(
            find.byKey(const ValueKey('image-surface-translation')),
          )
          .transform
          .storage[13],
      closeTo(0, 0.01),
    );
    await drag.up();
    await tester.pumpAndSettle();
    expect(route.debugReturnsToThumbnail, isFalse);
    expect(find.byKey(_surface), findsNothing);
  });
}
