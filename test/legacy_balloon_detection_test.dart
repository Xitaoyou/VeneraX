import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'dart:ui' as ui;
import 'package:venera/foundation/image_translation/legacy_balloon_detection.dart';
import 'package:venera/foundation/image_translation/ort_ffi.dart';
import 'package:venera/foundation/image_translation/translation_models.dart';
import 'package:venera/foundation/image_translation/translation_sources.dart';
import 'package:venera/foundation/image_translation/translation_types.dart';
import 'package:venera/foundation/appdata.dart';

void main() {
  List<OrtOutput> heads() => [
    for (final s in [64, 32, 16])
      OrtOutput(Float32List(24 * s * s), [1, 24, s, s]),
  ];
  void put(
    OrtOutput head,
    int x,
    int y, {
    double objectness = .9,
    double confidence = .9,
  }) {
    final s = head.shape[2], p = s * s, i = y * s + x;
    for (var c = 0; c < 4; c++) {
      head.data[c * p + i] = .5;
    }
    head.data[4 * p + i] = objectness;
    head.data[5 * p + i] = confidence;
  }

  test('original Legacy decodes new_coords with separate adjacent bubbles', () {
    final out = heads();
    put(out[0], 10, 20);
    put(out[0], 12, 20);
    final boxes = decodeLegacyBalloons(out.reversed.toList(), 1024, 1024);
    expect(boxes.length, 2);
    expect(
      [boxes[0].left, boxes[0].top, boxes[0].right, boxes[0].bottom],
      [161, 318, 175, 338],
    );
  });
  test(
    'Legacy thresholds objectness times class confidence, not class alone',
    () {
      final out = heads();
      put(out[0], 10, 20, objectness: .1, confidence: .99);
      expect(decodeLegacyBalloons(out, 512, 512), isEmpty);
    },
  );
  test('adjacent full panel blocks are never line-clustered', () {
    final groups = groupDetectedBubbles([
      IntRect(10, 10, 60, 100),
      IntRect(65, 10, 115, 100),
    ], []);
    expect(groups.length, 2);
  });
  test(
    'panel box covering two bubbles is split; missing text still gets OCR',
    () {
      final groups = groupDetectedBubbles(
        [IntRect(10, 10, 115, 100)],
        [
          IntRect(5, 5, 60, 105),
          IntRect(65, 5, 120, 105),
          IntRect(10, 130, 60, 200),
        ],
      );
      expect(groups.length, 3);
      expect(groups[0].single.right, 60);
      expect(groups[1].single.left, 65);
      expect(groups[2].single.top, 130);
    },
  );
  test('panel letterbox keeps aspect ratio and correct padding', () {
    final pixels = Uint8List(2 * 4 * 4)..fillRange(0, 2 * 4 * 4, 255);
    final tensor = prepareObjectDetectorInput(
      RgbaImage(2, 4, pixels),
      4,
      letterbox: true,
    );
    expect(tensor[0], closeTo(114 / 255, 1e-6));
    expect(tensor[1], 1);
    expect(
      prepareObjectDetectorInput(
        RgbaImage(2, 4, pixels),
        4,
        letterbox: false,
      )[0],
      1,
    );
  });
  test(
    'obsolete bundled choices migrate and old custom segmenter is rejected',
    () {
      final previous = appdata.settings['imageTranslationDetectorKind'];
      try {
        appdata.settings['imageTranslationDetectorKind'] = 'balloon-seg';
        expect(TranslationModels.activeDetectorKind, 'legacy-balloon');
        appdata.settings['imageTranslationDetectorKind'] =
            'manga-panel-balloon';
        expect(TranslationModels.activeDetectorKind, 'manga-panel-legacy');
        expect(
          CustomDetectorModel.fromJson({'kind': 'balloon-seg', 'url': ''}),
          isNull,
        );
      } finally {
        appdata.settings['imageTranslationDetectorKind'] = previous;
      }
    },
  );
  test(
    'converted original model executes through production Dart FFI',
    () async {
      final session = OrtFfiSession.open(
        'assets/translation_models/legacy-balloon/model.onnx',
      );
      try {
        final pixels = Uint8List(512 * 512 * 4)
          ..fillRange(0, 512 * 512 * 4, 255);
        expect(
          runLegacyBalloonDetector(session, RgbaImage(512, 512, pixels)),
          isEmpty,
        );
        final path = Platform.environment['VENERAX_MODEL_PAGE'];
        if (path != null) {
          final codec = await ui.instantiateImageCodec(
            File(path).readAsBytesSync(),
          );
          final frame = await codec.getNextFrame();
          final data = await frame.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final image = RgbaImage(
            frame.image.width,
            frame.image.height,
            data!.buffer.asUint8List(),
          );
          frame.image.dispose();
          codec.dispose();
          final boxes = runLegacyBalloonDetector(session, image);
          expect(boxes.length, 1);
          final b = boxes.single;
          expect(b.left / image.width, closeTo(.769, .005));
          expect(b.top / image.height, closeTo(.108, .005));
          expect(b.width / image.width, closeTo(.084, .005));
        }
      } finally {
        session.close();
      }
    },
    skip: Platform.environment['VENERAX_NATIVE_MODEL_TEST'] != '1',
  );
}
