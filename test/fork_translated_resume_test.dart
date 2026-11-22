import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/app_page_route.dart';
import 'package:venera/foundation/cache_manager.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/image_surface_route.dart';
import 'package:venera/foundation/image_translation/translation_store.dart';
import 'package:venera/foundation/image_provider/reader_image.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/read_later.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'package:venera/pages/reader/reader.dart';
import 'package:venera/pages/translated_comics_page.dart';
import 'package:venera/components/components.dart';
import 'package:venera/utils/translations.dart';

import 'reader_pull_down_integration_test.dart' as reader_fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LocalComic comic;

  setUpAll(() async {
    IOOverrides.global = reader_fixture.ReaderFileOverrides();
    if (Platform.isWindows) {
      open.overrideFor(
        OperatingSystem.windows,
        () => DynamicLibrary.open('winsqlite3.dll'),
      );
    }
    root = await Directory.systemTemp.createTemp('fork-translated-resume-');
    App.dataPath = root.path;
    App.cachePath = root.path;
    AppTranslation.translations = {};
    await appdata.init();
    await HistoryManager().init();
    HistoryManager().isInitialized = false;
    await LocalFavoritesManager().init();
    await ReadLaterManager().init();
    await TranslationStore().init();
    final blank = '${root.path}/blank.db';
    sqlite3.open(blank).dispose();
    LocalManager().isInitialized = true;
    LocalManager().path = root.path;
    await LocalManager().restoreFrom(blank);
    final pages = await Directory('${root.path}/pages').create();
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAADklEQVR4nGP4DwYMKBQAvFgR71PJ/rgAAAAASUVORK5CYII=',
    );
    for (var i = 1; i <= 3; i++) {
      await File('${pages.path}/$i.png').writeAsBytes(png);
    }
    comic = LocalComic(
      id: 'resume',
      title: 'Resume fixture',
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
    await CacheManager().ready;
    App.isInitialized = true;
  });

  setUp(() {
    appdata.settings['quickCollectImage'] = 'No';
    appdata.settings['enableClockAndBatteryInfoInReader'] = false;
    appdata.settings['enableTurnPageByVolumeKey'] = false;
    appdata.settings['readerKeepScreenOn'] = false;
    appdata.settings['autoRemoveFromReadLater'] = false;
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
    LocalFavoritesManager().close();
    ReadLaterManager().close();
    TranslationStore().close();
    HistoryManager().isInitialized = true;
    HistoryManager().close();
    IOOverrides.global = null;
    App.isInitialized = false;
  });

  for (final mode in [
    ReaderMode.galleryLeftToRight,
    ReaderMode.galleryRightToLeft,
  ]) {
    reader_fixture.iosTestWidgets(
      'translation resume uses ${mode.key} image route and dismisses to comic details',
      (tester) async {
        appdata.settings['readerMode'] = mode.key;
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: App.rootNavigatorKey,
            home: const Scaffold(body: Text('translation library')),
          ),
        );
        await tester.runAsync(() async {
          final images = await LocalManager().getImages(
            comic.id,
            ComicType.local,
            1,
          );
          for (var i = 0; i < images.length; i++) {
            await precacheImage(
              ReaderImageProvider(images[i], null, comic.id, '0', i + 1),
              App.rootContext,
            );
          }
        });
        App.rootNavigatorKey.currentState!.push(
          AppPageRoute(
            builder: (_) => ComicPage(
              id: comic.id,
              sourceKey: 'local',
              title: comic.title,
              resumeOnOpen: true,
            ),
          ),
        );
        await tester.pump();
        await reader_fixture.settleReader(tester);
        expect(find.byType(Reader), findsOneWidget);
        expect(
          ModalRoute.of(tester.element(find.byType(Reader))),
          isA<ImageSurfaceRoute>(),
        );
        expect(find.byType(ComicPage, skipOffstage: false), findsOneWidget);
        await tester.dragFrom(const Offset(400, 270), const Offset(0, 190));
        await tester.pumpAndSettle();
        expect(find.byType(Reader), findsNothing);
        expect(find.byType(ComicPage), findsOneWidget);
        expect(find.text('translation library'), findsNothing);
        expect(App.rootNavigatorKey.currentState!.canPop(), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
  reader_fixture.iosTestWidgets(
    'translation library Continue reading opens details under the standard reader',
    (tester) async {
      appdata.settings['readerMode'] = ReaderMode.galleryLeftToRight.key;
      const identity = TranslationChapterIdentity(
        scopePrefix: 'pageTranslation@2@auto>zh@local@resume@0@',
        sourceKey: 'local',
        comicId: 'resume',
        chapterId: '0',
        sourceLang: 'auto',
        targetLang: 'zh',
        comicTitle: 'Resume fixture',
        chapterTitle: 'Chapter 1',
      );
      TranslationStore().put(
        '${identity.scopePrefix}page1',
        const [],
        chapter: identity,
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: App.rootNavigatorKey,
          home: const TranslatedComicsPage(),
        ),
      );
      await reader_fixture.settleReader(tester);
      expect(find.byType(ComicTile), findsOneWidget);
      await tester.longPress(find.byType(ComicTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue reading'));
      await tester.pump();
      await reader_fixture.settleReader(tester);
      expect(find.byType(Reader), findsOneWidget);
      expect(
        ModalRoute.of(tester.element(find.byType(Reader))),
        isA<ImageSurfaceRoute>(),
      );
      await tester.dragFrom(const Offset(400, 270), const Offset(0, 190));
      await tester.pumpAndSettle();
      expect(find.byType(Reader), findsNothing);
      expect(find.byType(ComicPage), findsOneWidget);
      expect(find.byType(TranslatedComicsPage), findsNothing);
    },
  );
  reader_fixture.iosTestWidgets(
    'closing details while it loads cannot reopen the reader',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: App.rootNavigatorKey,
          home: const Scaffold(body: Text('library')),
        ),
      );
      App.rootNavigatorKey.currentState!.push(
        AppPageRoute(
          builder: (_) =>
              ComicPage(id: comic.id, sourceKey: 'local', resumeOnOpen: true),
        ),
      );
      await tester.pump();
      App.rootNavigatorKey.currentState!.pop();
      await reader_fixture.settleReader(tester);
      expect(find.byType(Reader), findsNothing);
      expect(find.text('library'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
