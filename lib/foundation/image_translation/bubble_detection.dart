import 'dart:math' as math;
import 'dart:typed_data';

import 'package:venera/foundation/image_translation/ort_ffi.dart';
import 'package:venera/foundation/image_translation/translation_types.dart';
import 'package:venera/foundation/image_translation/translation_worker.dart';

// =============================================================================
// Object-detection / segmentation bubble-detection backends.
//
// Contracts were extracted from ImageTrans's shipped inference code
// (com.xulihang.ONNXRFDETR, com.xulihang.ONNXYOLO,
// org.xulihang.imagetrans.jballoonsegmentation$BalloonSegmenter) and verified
// by running the shipped models on real manga pages:
//
// manga-panel (RT-DETR, fp32):
//   input  'images'  [1,3,640,640]  plain resize (NO letterbox), RGB, v/255
//   output 'output0' [1,300,6]      rows of [x1,y1,x2,y2,conf,class] in
//                                   640-canvas pixels; class 0 = panel,
//                                   class 1 = text block.
// balloonseg (legacy balloon, fp16):
//   input  'image'   [1,1024,768,1] NHWC fp16; grayscale, aspect-fit into
//                                   768x1024 (W x H), white padding, and each
//                                   pixel mapped to (v/255 - 0.449) / 0.226.
//   output 'logits'  [1,1024,768,3] fp16; sigmoid -> channel 0 = balloon
//                                   body, 1 = balloon edge (unused by
//                                   ImageTrans), 2 = text.
// =============================================================================

/// One raw detection of the manga-panel model.
class PanelDetection {
  PanelDetection(this.box, this.score, this.cls);

  final IntRect box;
  final double score;

  /// 0 = panel, 1 = text block.
  final int cls;
}

/// Boxes produced by the legacy balloon segmentation model.
class BalloonSegBoxes {
  BalloonSegBoxes(this.balloons, this.texts);

  /// Connected balloon-interior regions (channel 0).
  final List<IntRect> balloons;

  /// Connected text regions (channel 2).
  final List<IntRect> texts;
}

/// Runs the manga-panel RT-DETR model over [image] and returns filtered
/// detections. Coordinates are mapped back to [image] pixels.
List<PanelDetection> runMangaPanelDetector(
  OrtFfiSession session,
  RgbaImage image, {
  double confThreshold = 0.3,
}) {
  const input = 640;
  var tensor = Float32List(3 * input * input);
  var plane = input * input;
  var sx = image.width / input;
  var sy = image.height / input;
  var pixels = image.pixels;
  // Plain resize (no letterbox), RGB, /255 — the model's exported contract.
  // Bilinear sampling: the detector was verified against smooth resampling;
  // nearest-neighbour aliasing drops small or thin lettering.
  int clampX(int x) => x < 0 ? 0 : (x > image.width - 1 ? image.width - 1 : x);
  int clampY(int y) => y < 0 ? 0 : (y > image.height - 1 ? image.height - 1 : y);
  double sample(int c, double fy, double fx) {
    var y0 = clampY(fy.floor());
    var y1 = clampY(y0 + 1);
    var x0 = clampX(fx.floor());
    var x1 = clampX(x0 + 1);
    var wy = fy - fy.floor();
    var wx = fx - fx.floor();
    var p00 = pixels[(y0 * image.width + x0) * 4 + c].toDouble();
    var p01 = pixels[(y0 * image.width + x1) * 4 + c].toDouble();
    var p10 = pixels[(y1 * image.width + x0) * 4 + c].toDouble();
    var p11 = pixels[(y1 * image.width + x1) * 4 + c].toDouble();
    var top = p00 + (p01 - p00) * wx;
    var bottom = p10 + (p11 - p10) * wx;
    return (top + (bottom - top) * wy) / 255.0;
  }

  for (var y = 0; y < input; y++) {
    var fy = (y + 0.5) * sy - 0.5;
    for (var x = 0; x < input; x++) {
      var fx = (x + 0.5) * sx - 0.5;
      var di = y * input + x;
      tensor[di] = sample(0, fy, fx); // R
      tensor[plane + di] = sample(1, fy, fx); // G
      tensor[2 * plane + di] = sample(2, fy, fx); // B
    }
  }
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

/// Runs the legacy balloon segmentation model over [image] and returns
/// balloon / text boxes. Coordinates are mapped back to [image] pixels.
BalloonSegBoxes runBalloonSegmenter(
  OrtFfiSession session,
  RgbaImage image, {
  double threshold = 0.65,
  int minArea = 64,
  double maxAreaFrac = 0.9,
}) {
  const canvasW = 768;
  const canvasH = 1024;
  var scale = math.min(canvasW / image.width, canvasH / image.height);
  var nw = math.max(1, (image.width * scale).round());
  var nh = math.max(1, (image.height * scale).round());
  var padLeft = (canvasW - nw) ~/ 2;
  var padTop = (canvasH - nh) ~/ 2;

  // Grayscale (Rec.601), aspect-fit, white padding, ImageTrans normalization.
  // ImageTrans downscales with INTER_AREA (the javap shows interpolation
  // switches to 3 for scale < 1): an area-weighted average over the source
  // footprint. Plain point-sampled bilinear aliases on the downscale and
  // the masks come out fragmented, so replicate the area average.
  var gray = Float32List(canvasW * canvasH);
  gray.fillRange(0, gray.length, (1.0 - 0.449) / 0.226); // white padding
  var pixels = image.pixels;
  double lum(int y, int x) {
    var i = (y * image.width + x) * 4;
    return 0.299 * pixels[i] + 0.587 * pixels[i + 1] + 0.114 * pixels[i + 2];
  }

  // Area-average the source luminance into the nw x nh window.
  for (var y = 0; y < nh; y++) {
    var sy0 = y * image.height / nh;
    var sy1 = (y + 1) * image.height / nh;
    var y0 = sy0.floor();
    var y1 = math.min(image.height, (sy1).ceil());
    var dstRow = (y + padTop) * canvasW + padLeft;
    for (var x = 0; x < nw; x++) {
      var sx0 = x * image.width / nw;
      var sx1 = (x + 1) * image.width / nw;
      var x0 = sx0.floor();
      var x1 = math.min(image.width, sx1.ceil());
      var sum = 0.0;
      var weight = 0.0;
      for (var yy = y0; yy < y1; yy++) {
        var wy = math.min(sy1, yy + 1.0) - math.max(sy0, yy.toDouble());
        for (var xx = x0; xx < x1; xx++) {
          var wx = math.min(sx1, xx + 1.0) - math.max(sx0, xx.toDouble());
          sum += lum(yy, xx) * wy * wx;
          weight += wy * wx;
        }
      }
      var value = weight > 0 ? sum / weight : lum(y0, x0);
      gray[dstRow + x] = (value / 255.0 - 0.449) / 0.226;
    }
  }
  var input = session
      .run(
        {
          session.inputNames.first: OrtInput.float16(
            floatToHalfList(gray),
            const [1, canvasH, canvasW, 1],
          ),
        },
        // The graph's output is FLOAT16; without this the raw half-float bits
        // are reinterpreted as fp32 and every mask decodes to noise.
        fp16Outputs: true,
      )
      .values
      .first;
  if (input.shape.length != 4 || input.shape[3] != 3) {
    throw const ModelCheckException(ModelCheckFailure.notDetector);
  }
  var logits = input.data; // [canvasH, canvasW, 3]

  List<IntRect> decode(int channel) {
    var mask = Float32List(nw * nh);
    for (var y = 0; y < nh; y++) {
      var srcRow = ((y + padTop) * canvasW + padLeft) * 3;
      var dstRow = y * nw;
      for (var x = 0; x < nw; x++) {
        var z = logits[srcRow + x * 3 + channel];
        mask[dstRow + x] = 1.0 / (1.0 + math.exp(-z));
      }
    }
    return maskBoxes(
      mask,
      nw,
      nh,
      threshold: threshold,
      minArea: minArea,
      maxAreaFrac: maxAreaFrac,
      scaleX: 1 / scale,
      scaleY: 1 / scale,
      maxW: image.width,
      maxH: image.height,
    );
  }

  return BalloonSegBoxes(decode(0), decode(2));
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
  return rightToLeft
      ? b.right.compareTo(a.right)
      : a.left.compareTo(b.left);
}
