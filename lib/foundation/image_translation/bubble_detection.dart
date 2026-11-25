import 'legacy_balloon_detection.dart';
import 'dart:typed_data';

import 'package:venera/foundation/image_translation/ort_ffi.dart';
import 'package:venera/foundation/image_translation/translation_types.dart';
import 'package:venera/foundation/image_translation/translation_worker.dart';

// =============================================================================
// Object-detection / segmentation bubble-detection backends.
//
// Contracts were extracted from ImageTrans's shipped inference code
// (com.xulihang.ONNXRFDETR, com.xulihang.ONNXYOLO,
// ImageTrans manga-panel profile) and verified
// by running the shipped models on real manga pages:
//
// manga-panel (YOLO26, fp32):
//   input  'images'  [1,3,640,640]  plain resize (ImageTrans profile), RGB, v/255
//   output 'output0' [1,300,6]      rows of [x1,y1,x2,y2,conf,class] in
//                                   640-canvas pixels; class 0 = panel,
//                                   class 1 = text block.
// =============================================================================

/// One raw detection of the manga-panel model.
class PanelDetection {
  PanelDetection(this.box, this.score, this.cls);

  final IntRect box;
  final double score;

  /// 0 = panel, 1 = text block.
  final int cls;
}

/// Runs the manga-panel YOLO26 model over [image] and returns filtered
/// detections. Coordinates are mapped back to [image] pixels.
List<PanelDetection> runMangaPanelDetector(
  OrtFfiSession session,
  RgbaImage image, {
  double confThreshold = 0.25,
}) {
  const input = 640;
  final sx = image.width / input, sy = image.height / input;
  final tensor = prepareObjectDetectorInput(image, input, letterbox: false);
  var output = session
      .run({
        session.inputNames.first: OrtInput.float32(tensor, const [
          1,
          3,
          input,
          input,
        ]),
      })
      .values
      .first;
  if (output.shape.length != 3 || output.shape[2] < 6) {
    throw const ModelCheckException(ModelCheckFailure.notDetector);
  }
  var rows = output.shape[1];
  var step = output.shape[2];
  var data = output.data;
  var detections = <PanelDetection>[];
  for (var i = 0; i < rows; i++) {
    var base = i * step;
    var score = data[base + 4];
    if (score < confThreshold) continue;
    // Rows are [x1,y1,x2,y2,conf,class] in 640-canvas pixels; the canvas is
    // a plain resize of the page, so canvas -> original MULTIPLIES by the
    // page/canvas ratio.
    var x1 = (data[base] * sx).round().clamp(0, image.width);
    var y1 = (data[base + 1] * sy).round().clamp(0, image.height);
    var x2 = (data[base + 2] * sx).round().clamp(0, image.width);
    var y2 = (data[base + 3] * sy).round().clamp(0, image.height);
    if (x2 - x1 < 4 || y2 - y1 < 4) continue;
    detections.add(
      PanelDetection(IntRect(x1, y1, x2, y2), score, data[base + 5].round()),
    );
  }
  return detections;
}

/// Extracts bounding boxes from a probability mask via connected components.
/// Coordinates are scaled back by [scaleX]/[scaleY] and clamped to
/// [maxW]x[maxH] when provided.
List<IntRect> maskBoxes(
  Float32List mask,
  int w,
  int h, {
  required double threshold,
  required int minArea,
  required double maxAreaFrac,
  double scaleX = 1.0,
  double scaleY = 1.0,
  int? maxW,
  int? maxH,
}) {
  var labels = Int32List(w * h);
  var boxes = <IntRect>[];
  var stack = <int>[];
  var nextLabel = 0;
  var maxArea = (w * h * maxAreaFrac).round();
  for (var start = 0; start < w * h; start++) {
    if (labels[start] != 0 || mask[start] < threshold) continue;
    nextLabel++;
    var minX = w, minY = h, maxX = 0, maxY = 0;
    var count = 0;
    var scoreSum = 0.0;
    stack.add(start);
    labels[start] = nextLabel;
    while (stack.isNotEmpty) {
      var index = stack.removeLast();
      var x = index % w;
      var y = index ~/ w;
      count++;
      scoreSum += mask[index];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      for (var d = 0; d < 4; d++) {
        var nx = x + const [1, -1, 0, 0][d];
        var ny = y + const [0, 0, 1, -1][d];
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        var ni = ny * w + nx;
        if (labels[ni] == 0 && mask[ni] >= threshold) {
          labels[ni] = nextLabel;
          stack.add(ni);
        }
      }
    }
    if (count < minArea || scoreSum / count < threshold * 0.5) continue;
    if (count > maxArea) continue;
    var x1 = (minX * scaleX).floor();
    var y1 = (minY * scaleY).floor();
    var x2 = ((maxX + 1) * scaleX).ceil();
    var y2 = ((maxY + 1) * scaleY).ceil();
    if (maxW != null) x2 = x2.clamp(x1, maxW);
    if (maxH != null) y2 = y2.clamp(y1, maxH);
    boxes.add(IntRect(x1, y1, x2, y2));
  }
  return boxes;
}

/// Sorts block bounds in comic reading order. [rightToLeft] selects the
/// page direction: manga (Japanese/Chinese) reads panels and vertical
/// columns right-to-left, western comics read left-to-right. Vertical
/// columns always read top-to-bottom within their band; horizontal rows
/// top-to-bottom, then along the page direction.
int compareMangaBlocks(IntRect a, IntRect b, {bool rightToLeft = true}) {
  var aVertical = a.height > a.width * 1.3;
  var bVertical = b.height > b.width * 1.3;
  if (aVertical && bVertical) {
    // Columns: along the page direction, then top to bottom.
    var along = rightToLeft
        ? b.right.compareTo(a.right)
        : a.left.compareTo(b.left);
    if (along != 0) return along;
    return a.top.compareTo(b.top);
  }
  if (aVertical != bVertical) {
    // Vertical text first (speech bubbles), then horizontal captions.
    return aVertical ? -1 : 1;
  }
  var byTop = a.top.compareTo(b.top);
  if (byTop != 0) return byTop;
  return rightToLeft ? b.right.compareTo(a.right) : a.left.compareTo(b.left);
}
