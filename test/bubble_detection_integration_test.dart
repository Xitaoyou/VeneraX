import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/image_translation/bubble_detection.dart';
import 'package:venera/foundation/image_translation/ort_ffi.dart';
import 'package:venera/foundation/image_translation/translation_types.dart';

/// End-to-end detection verification against the bundled ImageTrans models
/// and a real manga crop (assets/translation_models/test_page.png, 1100x1400).
/// Ground-truth boxes were measured with the reference Python inference
/// (plain-resize/bilinear for manga-panel, area-average resize for
/// balloonseg — the contracts extracted from ImageTrans's javap).
///
/// Skips when the ONNX Runtime library is unavailable (CI hosts without the
/// plugin's native library); the pure decode/mask logic stays covered by
/// bubble_detection_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late RgbaImage page;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('venera_det_models_');
    var data = await rootBundle.load(
      'assets/translation_models/test_page.png',
    );
    var bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    var codec = await ui.instantiateImageCodec(bytes);
    var frame = await codec.getNextFrame();
    var rgba = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    page = RgbaImage(
      frame.image.width,
      frame.image.height,
      rgba!.buffer.asUint8List(),
    );
    frame.image.dispose();
    codec.dispose();
  });

  tearDownAll(() {
    tempDir.deleteSync(recursive: true);
  });

  Future<String> extract(String asset, String name) async {
    var file = File('${tempDir.path}/$name');
    if (!file.existsSync()) {
      var data = await rootBundle.load(asset);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    }
    return file.path;
  }

  OrtFfiSession? openOrSkip(String path) {
    try {
      return OrtFfiSession.open(path, intraOpThreads: 1);
    } catch (_) {
      // The host test runner has no ONNX Runtime library; nothing to verify.
      return null;
    }
  }

  double iou(IntRect a, IntRect b) {
    var ix1 = a.left > b.left ? a.left : b.left;
    var iy1 = a.top > b.top ? a.top : b.top;
    var ix2 = a.right < b.right ? a.right : b.right;
    var iy2 = a.bottom < b.bottom ? a.bottom : b.bottom;
    var inter = (ix2 - ix1) * (iy2 - iy1);
    if (inter <= 0) return 0;
    var union = a.area + b.area - inter;
    return inter / union;
  }

  test('manga-panel finds the text block at the ground-truth position', () async {
    var modelPath = await extract(
      'assets/translation_models/manga-panel/model.onnx',
      'panel.onnx',
    );
    var session = openOrSkip(modelPath);
    if (session == null) {
      markTestSkipped('ONNX Runtime library unavailable on this host');
      return;
    }
    var dets = runMangaPanelDetector(session, page);
    session.close();
    var texts = [for (var d in dets) if (d.cls == 1) d.box];
    var panels = [for (var d in dets) if (d.cls == 0) d.box];
    expect(texts, isNotEmpty, reason: 'text blocks detected');
    expect(panels, isNotEmpty, reason: 'panels detected');
    // Reference inference: text block [520, 21, 722, 601] conf 0.47.
    var truth = IntRect(520, 21, 722, 601);
    var best = texts
        .map((b) => iou(b, truth))
        .reduce((a, b) => a > b ? a : b);
    expect(best, greaterThan(0.5),
        reason: 'a text block overlaps the ground truth');
    for (var b in [...texts, ...panels]) {
      expect(b.left >= -5 && b.right <= page.width + 5, isTrue);
      expect(b.top >= -5 && b.bottom <= page.height + 5, isTrue);
    }
  });

  test('balloonseg finds text regions at the ground-truth positions', () async {
    var modelPath = await extract(
      'assets/translation_models/balloonseg/model.onnx',
      'seg.onnx',
    );
    var session = openOrSkip(modelPath);
    if (session == null) {
      markTestSkipped('ONNX Runtime library unavailable on this host');
      return;
    }
    var seg = runBalloonSegmenter(session, page);
    session.close();
    expect(seg.texts.length, greaterThanOrEqualTo(3),
        reason: 'the reference run finds four text components >= 64px');
    // Reference inference (area-average resize): text covers [610, 531,
    // 679, 725] among others. Component boundaries shift a little with the
    // fp16 rounding, so assert the detected boxes COVER that region rather
    // than matching one component exactly.
    var truthText = IntRect(610, 531, 679, 725);
    var covered = 0;
    for (var b in seg.texts) {
      var ix1 = b.left > truthText.left ? b.left : truthText.left;
      var iy1 = b.top > truthText.top ? b.top : truthText.top;
      var ix2 = b.right < truthText.right ? b.right : truthText.right;
      var iy2 = b.bottom < truthText.bottom ? b.bottom : truthText.bottom;
      if (ix2 > ix1 && iy2 > iy1) covered += (ix2 - ix1) * (iy2 - iy1);
    }
    expect(covered / truthText.area, greaterThan(0.4),
        reason: 'text regions cover the ground-truth text area');
    // The reference finds a bubble >= 64px around [617, 812, 639, 848].
    expect(seg.balloons, isNotEmpty, reason: 'a balloon region is detected');
    for (var b in [...seg.texts, ...seg.balloons]) {
      expect(b.left >= 0 && b.right <= page.width, isTrue);
      expect(b.top >= 0 && b.bottom <= page.height, isTrue);
    }
  });
}
