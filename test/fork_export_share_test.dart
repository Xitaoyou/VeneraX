import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:archive/archive_io.dart' show ZipDecoder;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/export_tasks.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/utils/io.dart' show IO, shareFileForExport;

Future<void> until(bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (!ready()) {
    if (watch.elapsed > const Duration(seconds: 20)) {
      throw TimeoutException('Export timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LocalComic comic;
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
  const saveChannel = MethodChannel('flutter_file_dialog');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Map<String, dynamic>? shared;
  List<int>? sharedBytes;
  var response = 'com.apple.UIKit.activity.SaveToFiles';
  var throwOnShare = false;

  setUpAll(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    if (Platform.isWindows) {
      open.overrideFor(
        OperatingSystem.windows,
        () => DynamicLibrary.open('winsqlite3.dll'),
      );
    }
    root = await Directory.systemTemp.createTemp('fork-export-share-');
    App.dataPath = root.path;
    App.cachePath = (await Directory('${root.path}/cache').create()).path;
    await appdata.init();
    final blank = '${root.path}/blank.db';
    sqlite3.open(blank).dispose();
    LocalManager().isInitialized = true;
    LocalManager().path = root.path;
    await LocalManager().restoreFrom(blank);
    final pages = await Directory(
      '${LocalManager().path}/comic',
    ).create(recursive: true);
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAADklEQVR4nGP4DwYMKBQAvFgR71PJ/rgAAAAASUVORK5CYII=',
    );
    await File('${pages.path}/1.png').writeAsBytes(png);
    comic = LocalComic(
      id: 'export',
      title: 'Export fixture',
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
    debugDefaultTargetPlatformOverride = null;
  });

  setUp(() {
    shared = null;
    sharedBytes = null;
    response = 'com.apple.UIKit.activity.SaveToFiles';
    throwOnShare = false;
    messenger.setMockMethodCallHandler(
      saveChannel,
      (_) async => throw StateError('iOS export must not use a save picker'),
    );
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      expect(call.method, 'share');
      shared = Map<String, dynamic>.from(call.arguments as Map);
      final file = File((shared!['paths'] as List).single as String);
      expect(file.existsSync(), isTrue);
      expect(IO.isSelectingFiles, isTrue);
      sharedBytes = await file.readAsBytes();
      expect(shared!['originWidth'], greaterThan(0));
      expect(shared!['originHeight'], greaterThan(0));
      if (throwOnShare) throw PlatformException(code: 'share_failed');
      return response;
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(shareChannel, null);
    messenger.setMockMethodCallHandler(saveChannel, null);
    await appdata.saveData(false);
    expect(IO.isSelectingFiles, isFalse);
  });

  tearDownAll(() async {
    await appdata.saveData(false);
    LocalManager().close();

    // Native image/database handles can outlive a test isolate on Windows.
    if (!Platform.isWindows) await root.delete(recursive: true);
  });

  for (final format in [
    ExportFormat.zip,
    ExportFormat.pdf,
    ExportFormat.epub,
  ]) {
    testWidgets(
      '${format.label} generates a real book and delivers it through share',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: App.rootNavigatorKey,
            home: const Scaffold(),
          ),
        );
        await tester.runAsync(() async {
          final task = ExportTaskManager.instance.startExport(
            folderPath: '',
            format: format,
            comics: [comic],
            shareOutput: true,
          )!;
          await until(() => !task.isActive);
          expect(task.status, ExportTaskStatus.completed, reason: task.error);
          expect(task.done, 1);
          expect((shared!['paths'] as List).single, endsWith(format.ext));
          if (format == ExportFormat.zip) {
            final zip = ZipDecoder().decodeBytes(sharedBytes!, verify: true);
            expect(zip.files.where((f) => f.name.endsWith('.png')), isNotEmpty);
            expect(zip.findFile('ComicInfo.xml'), isNotNull);
          } else if (format == ExportFormat.pdf) {
            expect(ascii.decode(sharedBytes!.take(4).toList()), '%PDF');
            final text = latin1.decode(sharedBytes!);
            final images = RegExp(
              r'/Subtype /Image\n.*?/Length (\d+)\n>>\nstream\n',
              dotAll: true,
            ).allMatches(text).toList();
            expect(images, isNotEmpty);
            for (final image in images) {
              final length = int.parse(image.group(1)!);
              final pixels = ZLibDecoder().convert(
                sharedBytes!.sublist(image.end, image.end + length),
              );
              expect(pixels.length, 2 * 3 * 3);
              expect(pixels.every((value) => value == 255), isTrue);
            }
          } else {
            expect(
              ZipDecoder().decodeBytes(sharedBytes!).findFile('mimetype'),
              isNotNull,
            );
          }
          expect(
            File((shared!['paths'] as List).single as String).existsSync(),
            isFalse,
          );
        });
      },
    );
  }

  for (final failure in [false, true]) {
    testWidgets(
      'share ${failure ? 'failure' : 'dismissal'} does not mark a book saved',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: App.rootNavigatorKey,
            home: const Scaffold(),
          ),
        );
        response = '';
        throwOnShare = failure;
        await tester.runAsync(() async {
          final task = ExportTaskManager.instance.startExport(
            folderPath: '',
            format: ExportFormat.epub,
            comics: [comic],
            shareOutput: true,
          )!;
          await until(() => !task.isActive);
          expect(
            task.status,
            failure ? ExportTaskStatus.failed : ExportTaskStatus.canceled,
          );
          expect(task.done, 0);
          expect(
            File((shared!['paths'] as List).single as String).existsSync(),
            isFalse,
          );
        });
      },
    );
  }

  testWidgets(
    'share future keeps the file alive until the system action completes',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(navigatorKey: App.rootNavigatorKey, home: const Scaffold()),
      );
      await tester.runAsync(() async {
        final reply = Completer<String>();
        var entered = false;
        messenger.setMockMethodCallHandler(shareChannel, (_) async {
          entered = true;
          return reply.future;
        });
        final file = await File(
          '${root.path}/pending.pdf',
        ).writeAsString('%PDF-fixture');
        var completed = false;
        final pending = shareFileForExport(file: file, filename: 'pending.pdf')
            .then((value) {
              completed = true;
              return value;
            });
        await until(() => entered);
        expect(completed, isFalse);
        expect(IO.isSelectingFiles, isTrue);
        expect(file.existsSync(), isTrue);
        reply.complete('com.apple.UIKit.activity.SaveToFiles');
        expect(await pending, isTrue);
      });
    },
  );

  testWidgets(
    'a requested unique filename is used by the share attachment and cleaned up',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(navigatorKey: App.rootNavigatorKey, home: const Scaffold()),
      );
      await tester.runAsync(() async {
        final original = await File(
          '${root.path}/same.pdf',
        ).writeAsString('%PDF-fixture');
        expect(
          await shareFileForExport(file: original, filename: 'same (2).pdf'),
          isTrue,
        );
        final path = (shared!['paths'] as List).single as String;
        expect(File(path).uri.pathSegments.last, 'same (2).pdf');
        expect(File(path).existsSync(), isFalse);
        expect(original.existsSync(), isTrue);
      });
    },
  );

  test('ZIP and share delivery survive task persistence', () {
    final task = ExportTask(
      id: 'zip',
      folderPath: '',
      format: ExportFormat.zip,
      comics: const [],
      createdAt: DateTime.now(),
      saveWithDialog: true,
      shareOutput: true,
    );
    final restored = ExportTask.fromJson(task.toJson());
    expect(restored.format, ExportFormat.zip);
    expect(restored.shareOutput, isTrue);
    expect(
      ExportTask.fromJson(task.toJson()..remove('shareOutput')).shareOutput,
      isFalse,
    );
  });
}
