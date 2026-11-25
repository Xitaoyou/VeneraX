import 'dart:math' as math;
import 'dart:typed_data';
import 'ort_ffi.dart';
import 'translation_types.dart';
import 'translation_worker.dart';

/// ImageTrans profile: RGB /255, stretch to 512, no letterbox or crop.
/// The panel YOLO model instead uses centered 114 letterboxing.
Float32List prepareObjectDetectorInput(
  RgbaImage image,
  int side, {
  required bool letterbox,
}) {
  final scale = math.min(side / image.width, side / image.height);
  final w = letterbox ? (image.width * scale).round() : side;
  final h = letterbox ? (image.height * scale).round() : side;
  final left = (side - w) ~/ 2, top = (side - h) ~/ 2;
  final data = Float32List(3 * side * side)
    ..fillRange(0, 3 * side * side, 114 / 255);
  for (var y = 0; y < h; y++) {
    final fy = ((y + .5) * image.height / h - .5).clamp(
      0.0,
      image.height - 1.0,
    );
    final y0 = fy.floor(), y1 = math.min(y0 + 1, image.height - 1);
    for (var x = 0; x < w; x++) {
      final fx = ((x + .5) * image.width / w - .5).clamp(
        0.0,
        image.width - 1.0,
      );
      final x0 = fx.floor(), x1 = math.min(x0 + 1, image.width - 1);
      for (var c = 0; c < 3; c++) {
        double pixel(int xx, int yy) =>
            image.pixels[(yy * image.width + xx) * 4 + c].toDouble();
        final a = pixel(x0, y0) * (1 - fx + x0) + pixel(x1, y0) * (fx - x0);
        final b = pixel(x0, y1) * (1 - fx + x0) + pixel(x1, y1) * (fx - x0);
        data[c * side * side + (y + top) * side + x + left] =
            (a * (1 - fy + y0) + b * (fy - y0)) / 255;
      }
    }
  }
  return data;
}

List<IntRect> runLegacyBalloonDetector(OrtFfiSession session, RgbaImage image) {
  final outputs = session.run({
    session.inputNames.first: OrtInput.float32(
      prepareObjectDetectorInput(image, 512, letterbox: false),
      const [1, 3, 512, 512],
    ),
  });
  return decodeLegacyBalloons(
    outputs.values.toList(),
    image.width,
    image.height,
  );
}

/// Original Scaled YOLOv4 new_coords=1. Class confidence includes objectness,
/// exactly as OpenCV's Darknet Region layer used by AiNieePlus does.
List<IntRect> decodeLegacyBalloons(
  List<OrtOutput> outputs,
  int width,
  int height,
) {
  const anchors = [
    (7, 10),
    (18, 14),
    (14, 29),
    (35, 26),
    (27, 58),
    (68, 55),
    (55, 108),
    (124, 105),
    (98, 219),
    (185, 258),
    (352, 353),
    (457, 457),
  ];
  if (outputs.length != 3 || outputs.any((o) => o.shape.length != 4)) {
    throw const ModelCheckException(ModelCheckFailure.notDetector);
  }
  final sorted = [...outputs]..sort((a, b) => b.shape[2].compareTo(a.shape[2]));
  final candidates = <({IntRect box, double score})>[];
  for (var head = 0; head < 3; head++) {
    final out = sorted[head], side = 64 >> head;
    if (out.shape[0] != 1 ||
        out.shape[1] != 24 ||
        out.shape[2] != side ||
        out.shape[3] != side) {
      throw const ModelCheckException(ModelCheckFailure.notDetector);
    }
    final plane = side * side;
    for (var a = 0; a < 4; a++) {
      for (var y = 0; y < side; y++) {
        for (var x = 0; x < side; x++) {
          final index = y * side + x;
          double v(int c) => out.data[(a * 6 + c) * plane + index];
          final score = v(4) * v(5);
          if (!score.isFinite ||
              score <= .20 ||
              ![v(0), v(1), v(2), v(3)].every((v) => v.isFinite)) {
            continue;
          }
          final cx = ((v(0) * 1.05 - .025 + x) / side * width).toInt();
          final cy = ((v(1) * 1.05 - .025 + y) / side * height).toInt();
          final w = (4 * v(2) * v(2) * anchors[head * 4 + a].$1 / 512 * width)
              .toInt();
          final h = (4 * v(3) * v(3) * anchors[head * 4 + a].$2 / 512 * height)
              .toInt();
          if (w > 0 && h > 0) {
            candidates.add((
              box: IntRect(
                cx - w ~/ 2,
                cy - h ~/ 2,
                cx - w ~/ 2 + w,
                cy - h ~/ 2 + h,
              ),
              score: score,
            ));
          }
        }
      }
    }
  }
  candidates.sort((a, b) => b.score.compareTo(a.score));
  final kept = <IntRect>[];
  for (final candidate in candidates) {
    if (kept.any(
      (b) =>
          boxIntersection(candidate.box, b) /
              (candidate.box.area +
                  b.area -
                  boxIntersection(candidate.box, b)) >
          .50,
    )) {
      continue;
    }
    kept.add(candidate.box);
  }
  return [
    for (final b in kept)
      IntRect(
        b.left.clamp(0, width),
        b.top.clamp(0, height),
        b.right.clamp(0, width),
        b.bottom.clamp(0, height),
      ),
  ].where((b) => b.width > 0 && b.height > 0).toList();
}

num boxIntersection(IntRect a, IntRect b) =>
    math.max(0, math.min(a.right, b.right) - math.max(a.left, b.left)) *
    math.max(0, math.min(a.bottom, b.bottom) - math.max(a.top, b.top));

/// Whole object boxes must never be regrouped with text-line gap heuristics.
/// Legacy boundaries split a panel box spanning two bubbles. A missed bubble
/// is still sent to OCR; unmatched panel captions remain separate blocks.
List<List<IntRect>> groupDetectedBubbles(
  List<IntRect> texts,
  List<IntRect> balloons,
) {
  final groups = <List<IntRect>>[], assigned = <int>{};
  for (final bubble in balloons) {
    final inside = <IntRect>[];
    for (var i = 0; i < texts.length; i++) {
      final t = texts[i];
      if (boxIntersection(t, bubble) /
              math.max(1, math.min(t.area, bubble.area)) <
          .5) {
        continue;
      }
      inside.add(
        IntRect(
          math.max(t.left, bubble.left),
          math.max(t.top, bubble.top),
          math.min(t.right, bubble.right),
          math.min(t.bottom, bubble.bottom),
        ),
      );
      assigned.add(i);
    }
    groups.add(inside.isEmpty ? [bubble] : inside);
  }
  for (var i = 0; i < texts.length; i++) {
    if (!assigned.contains(i)) groups.add([texts[i]]);
  }
  return groups;
}
