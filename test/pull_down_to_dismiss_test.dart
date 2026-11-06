import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:venera/components/pull_down_to_dismiss.dart';

// Real PhotoView recognizers, including the fork's gallery recognizer.
final testImage = MemoryImage(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAADklEQVR4nGP4DwYMKBQAvFgR71PJ/rgAAAAASUVORK5CYII=',
  ),
);

Future<void> openPhoto(
  WidgetTester tester, {
  bool Function()? enabled,
  PhotoViewController? controller,
  bool gallery = false,
}) async {
  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: nav,
      home: const Scaffold(body: Text('library')),
    ),
  );
  nav.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        body: PullDownToDismiss(
          enabled: enabled ?? () => !isPhotoViewZoomed(controller),
          child: gallery
              ? PhotoViewGallery.builder(
                  itemCount: 3,
                  builder: (_, index) => PhotoViewGalleryPageOptions(
                    imageProvider: testImage,
                    controller: index == 0 ? controller : null,
                    initialScale: PhotoViewComputedScale.contained,
                    minScale: PhotoViewComputedScale.contained,
                  ),
                )
              : PhotoView(
                  imageProvider: testImage,
                  controller: controller,
                  initialScale: PhotoViewComputedScale.contained,
                  minScale: PhotoViewComputedScale.contained,
                ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
  }
  await tester.pumpAndSettle();
}

void main() {
  double offsetOf(WidgetTester tester) => tester
      .widget<Transform>(find.byKey(const ValueKey('pull-down-translation')))
      .transform
      .storage[13];

  testWidgets('image follows the finger and short drags animate back', (
    tester,
  ) async {
    await openPhoto(tester);
    final drag = await tester.startGesture(const Offset(400, 200));
    await drag.moveBy(const Offset(0, 80));
    await tester.pump();
    final dragged = offsetOf(tester);
    expect(dragged, greaterThan(0));
    await drag.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(offsetOf(tester), greaterThan(0));
    expect(offsetOf(tester), lessThan(dragged));
    await tester.pumpAndSettle();
    expect(offsetOf(tester), closeTo(0, 0.01));
    expect(find.byType(PullDownToDismiss), findsOneWidget);
  });

  testWidgets('successful dismissal animates out before popping', (
    tester,
  ) async {
    await openPhoto(tester, gallery: true);
    final drag = await tester.startGesture(const Offset(400, 200));
    await drag.moveBy(const Offset(0, 160));
    await tester.pump();
    final dragged = offsetOf(tester);
    await drag.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(find.byType(PullDownToDismiss), findsOneWidget);
    expect(offsetOf(tester), greaterThan(dragged));
    await tester.pumpAndSettle();
    expect(find.byType(PullDownToDismiss), findsNothing);
  });

  testWidgets('a canceled drag animates back without leaving the page', (
    tester,
  ) async {
    await openPhoto(tester);
    final drag = await tester.startGesture(const Offset(400, 200));
    await drag.moveBy(const Offset(0, 170));
    await tester.pump();
    expect(offsetOf(tester), greaterThan(0));
    await drag.cancel();
    await tester.pumpAndSettle();
    expect(offsetOf(tester), closeTo(0, 0.01));
  });

  for (final gallery in [false, true]) {
    testWidgets('downward drag pops real PhotoView, gallery=$gallery', (
      tester,
    ) async {
      await openPhoto(tester, gallery: gallery);
      await tester.dragFrom(const Offset(400, 200), const Offset(0, 160));
      await tester.pumpAndSettle();
      expect(find.text('library'), findsOneWidget);
      expect(find.byType(PullDownToDismiss), findsNothing);
    });
  }

  testWidgets('horizontal paging still works before pull down', (tester) async {
    await openPhoto(tester, gallery: true);
    await tester.dragFrom(const Offset(600, 300), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.byType(PullDownToDismiss), findsOneWidget);
    final pager = tester.widget<PageView>(find.byType(PageView));
    expect(pager.controller!.page, closeTo(1, 0.01));
    await tester.dragFrom(const Offset(400, 200), const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(find.byType(PullDownToDismiss), findsNothing);
  });

  testWidgets('disabled gesture never pops', (tester) async {
    await openPhoto(tester, enabled: () => false, gallery: true);
    await tester.dragFrom(const Offset(400, 200), const Offset(0, 180));
    await tester.pumpAndSettle();
    expect(find.byType(PullDownToDismiss), findsOneWidget);
  });

  testWidgets('zoomed image pans; fit image can dismiss again', (tester) async {
    final controller = PhotoViewController();
    await openPhoto(tester, controller: controller);
    final fit = controller.getInitialScale!.call()!;
    controller.scale = fit * 2;
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(400, 200), const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(find.byType(PullDownToDismiss), findsOneWidget);
    controller.scale = fit;
    controller.position = Offset.zero;
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(400, 200), const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(find.byType(PullDownToDismiss), findsNothing);
    controller.dispose();
  });

  testWidgets('pinch, cancel, short and upward drags cannot dismiss', (
    tester,
  ) async {
    await openPhoto(tester);
    final a = await tester.startGesture(const Offset(300, 200), pointer: 1);
    final b = await tester.startGesture(const Offset(500, 200), pointer: 2);
    await a.moveBy(const Offset(0, 160));
    await b.up();
    await a.up();
    await tester.pumpAndSettle();
    final canceled = await tester.startGesture(const Offset(400, 200));
    await canceled.moveBy(const Offset(0, 160));
    await canceled.cancel();
    await tester.dragFrom(const Offset(400, 200), const Offset(0, 55));
    await tester.dragFrom(const Offset(400, 350), const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(find.byType(PullDownToDismiss), findsOneWidget);
  });

  testWidgets('changing policy during a drag cancels dismissal', (
    tester,
  ) async {
    var enabled = true;
    await openPhoto(tester, enabled: () => enabled);
    final gesture = await tester.startGesture(const Offset(400, 200));
    await gesture.moveBy(const Offset(0, 120));
    enabled = false;
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(PullDownToDismiss), findsOneWidget);
  });
}
