import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera/components/pull_down_to_dismiss.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/image_provider/reader_image.dart';
import 'package:venera/pages/reader/reader.dart';
import 'package:venera/utils/translations.dart';
import 'package:venera/utils/io.dart' show overrideIO;

// Painting work runs in the binding's zone. Apply the app's file:// handling
// globally for this test isolate, so decoding also sees the production paths.
final class ReaderFileOverrides extends IOOverrides {
  @override
  File createFile(String path) =>
      super.createFile(path.startsWith('file://') ? path.substring(7) : path);
}

void iosTestWidgets(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await overrideIO(() async {
        await callback(tester);
        await tester.pumpWidget(const SizedBox.shrink());
        // Reader disposal intentionally retains translation models for 90s.
        // Advance that idle-release timer before the test checks for leaks.
        await tester.pump(const Duration(minutes: 2));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      });
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<void> settleReader(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

// Mounts the production Reader, its gesture listener, scaffold, image loading
// and gallery/continuous widgets. No replacement gesture or policy in the test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixture;
  late LocalComic comic;

  setUpAll(() async {
    IOOverrides.global = ReaderFileOverrides();
    if (Platform.isWindows) {
      open.overrideFor(
        OperatingSystem.windows,
        () => DynamicLibrary.open('winsqlite3.dll'),
      );
    }
    fixture = Directory.systemTemp.createTempSync('venerax_gesture_');
    App.dataPath = fixture.path;
    App.cachePath = fixture.path;
    AppTranslation.translations = {};
    await HistoryManager().init();
    // Keep the database for the real favorite toolbar; suppress asynchronous
    // history persistence isolates, which are unrelated to these gestures.
    HistoryManager().isInitialized = false;
    final blank = '${fixture.path}/blank.db';
    sqlite3.open(blank).dispose();
    // The restore API opens the real library database, without booting the
    // unrelated JavaScript source engine or resuming background downloads.
    LocalManager().isInitialized = true;
    LocalManager().path = fixture.path;
    await LocalManager().restoreFrom(blank);
    final pages = Directory('${fixture.path}/pages')..createSync();
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAADklEQVR4nGP4DwYMKBQAvFgR71PJ/rgAAAAASUVORK5CYII=',
    );
    for (var i = 1; i <= 3; i++) {
      File('${pages.path}/$i.png').writeAsBytesSync(png);
    }
    comic = LocalComic(
      id: 'gesture-fixture',
      title: 'Gesture fixture',
      subtitle: '',
      tags: [],
      directory: pages.path,
      chapters: null,
      cover: '1.png',
      comicType: ComicType.local,
      downloadedChapters: [],
      createdAt: DateTime.now(),
    );
    await LocalManager().add(comic);
  });

  setUp(() {
    appdata.settings['quickCollectImage'] = 'No';
    appdata.settings['enableClockAndBatteryInfoInReader'] = false;
    appdata.settings['enableTurnPageByVolumeKey'] = false;
    appdata.settings['readerKeepScreenOn'] = false;
    appdata.settings['autoRemoveFromReadLater'] = false;
    appdata.settings['followUpdatesAllFolders'] = false;
    appdata.settings['followUpdatesFolders'] = <String>[];
    appdata.settings['enableReaderImageEnhance'] = false;
    appdata.settings['enableAutoPageTurning'] = false;
    appdata.settings['enableDoubleTapToZoom'] = false;
    for (final name in ['flutter_memory_info', 'venera/screen']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (_) async => null);
    }
  });
  tearDownAll(() {
    LocalManager().close();
    HistoryManager().isInitialized = true;
    HistoryManager().close();
    IOOverrides.global = null;
    // The OS reclaims this unique temp fixture after the test process exits;
    // image decoding may still hold a file handle during suite teardown.
  });

  Future<void> mountReader(WidgetTester tester, ReaderMode mode) async {
    appdata.settings['readerMode'] = mode.key;
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('library')),
      ),
    );
    // Start actual disk IO and decoding in the real async zone; starting it
    // inside FakeAsync can strand a file read behind the test clock.
    await tester.runAsync(() async {
      final keys = await LocalManager().getImages(comic.id, ComicType.local, 1);
      for (var i = 0; i < keys.length; i++) {
        await precacheImage(
          ReaderImageProvider(
            keys[i],
            null,
            comic.id,
            '0',
            i + 1,
            enableResize: mode.isContinuous,
          ),
          nav.currentContext!,
        );
      }
    });
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => Reader(
          type: ComicType.local,
          cid: comic.id,
          name: comic.title,
          chapters: null,
          history: History.fromModel(model: comic, ep: 1, page: 1),
          author: '',
          tags: const [],
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(Reader), findsOneWidget);
    expect(find.byType(PullDownToDismiss), findsOneWidget);
    expect(
      tester
          .widgetList<RawImage>(find.byType(RawImage))
          .any((image) => image.image != null),
      isTrue,
      reason: 'The production reader must display a decoded comic image.',
    );
  }

  for (final mode in [
    ReaderMode.galleryLeftToRight,
    ReaderMode.galleryRightToLeft,
    ReaderMode.continuousLeftToRight,
    ReaderMode.continuousRightToLeft,
  ]) {
    iosTestWidgets('production ${mode.key} reader dismisses downward', (
      tester,
    ) async {
      await mountReader(tester, mode);
      if (mode.isGallery) expect(find.byType(PhotoViewGallery), findsOneWidget);
      await tester.dragFrom(const Offset(400, 180), const Offset(0, 170));
      await settleReader(tester);
      expect(find.byType(Reader), findsNothing);
      expect(find.text('library'), findsOneWidget);
    });
  }

  for (final mode in [
    ReaderMode.galleryTopToBottom,
    ReaderMode.continuousTopToBottom,
  ]) {
    iosTestWidgets('production ${mode.key} quietly disables dismissal', (
      tester,
    ) async {
      await mountReader(tester, mode);
      await tester.dragFrom(const Offset(400, 180), const Offset(0, 170));
      await settleReader(tester);
      expect(find.byType(Reader), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
    });
  }

  iosTestWidgets('production reader honors swipe-collection priority', (
    tester,
  ) async {
    await mountReader(tester, ReaderMode.galleryLeftToRight);
    // A live setting change also has to work without rebuilding the wrapper.
    appdata.settings['quickCollectImage'] = 'Swipe';
    await tester.dragFrom(const Offset(400, 180), const Offset(0, 120));
    await settleReader(tester);
    expect(find.byType(Reader), findsOneWidget);
    appdata.settings['quickCollectImage'] = 'No';
    await tester.dragFrom(const Offset(400, 180), const Offset(0, 170));
    await settleReader(tester);
    expect(find.byType(Reader), findsNothing);
  });
}
