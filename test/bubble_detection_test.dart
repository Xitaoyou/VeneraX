import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/image_translation/bubble_detection.dart';
import 'package:venera/foundation/image_translation/ort_ffi.dart';
import 'package:venera/foundation/image_translation/translation_types.dart';

void main() {
  group('fp16 conversion', () {
    test('floatToHalf/halfToFloat round-trips representative values', () {
      // Values the balloon model actually sees: zero, the white padding
      // constant, the normalization extremes, and ordinary image values.
      var values = [
        0.0,
        -0.0,
        1.0,
        -1.0,
        0.5,
        0.25,
        (1.0 - 0.449) / 0.226, // white padding: 2.4380531
        (0.0 - 0.449) / 0.226, // black: -1.9867
        0.449,
        0.226,
        0.001,
        -0.001,
      ];
      for (var v in values) {
        var half = floatToHalf(v);
        var back = halfToFloat(half);
        // half precision: ~0.1% of headroom on the values we care about.
        expect(
          (back - v).abs() <= v.abs() * 0.001 + 1e-6,
          isTrue,
          reason: '$v -> $half -> $back',
        );
      }
    });

    test('floatToHalfList/halfToFloatList round-trip a buffer', () {
      var input = Float32List.fromList([
        for (var i = 0; i < 256; i++) (i - 128) / 64.0,
      ]);
      var out = halfToFloatList(floatToHalfList(input));
      for (var i = 0; i < input.length; i++) {
        expect(
          (out[i] - input[i]).abs() < 0.002,
          isTrue,
          reason: 'index $i: ${input[i]} vs ${out[i]}',
        );
      }
    });

    test('infinity and zero are exact', () {
      expect(halfToFloat(floatToHalf(0.0)), 0.0);
      expect(floatToHalf(1e30), 0x7C00); // overflow -> +inf bits
      expect(halfToFloat(0x7C00), double.infinity);
    });
  });

  group('maskBoxes', () {
    test('extracts two blobs and maps coordinates back', () {
      var w = 40, h = 30;
      var m = Float32List(w * h);
      void fill(int x0, int y0, int x1, int y1) {
        for (var y = y0; y <= y1; y++) {
          for (var x = x0; x <= x1; x++) {
            m[y * w + x] = 0.9;
          }
        }
      }

      fill(2, 3, 9, 9); // blob A
      fill(20, 15, 29, 25); // blob B

      var boxes = maskBoxes(
        m,
        w,
        h,
        threshold: 0.5,
        minArea: 10,
        maxAreaFrac: 0.9,
        scaleX: 2.0,
        scaleY: 4.0,
      );
      expect(boxes.length, 2);
      boxes.sort((a, b) => a.left.compareTo(b.left));
      expect(boxes[0].left, 4); // 2 * 2.0
      expect(boxes[0].top, 12); // 3 * 4.0
      expect(boxes[0].right, 20); // (9 + 1) * 2.0
      expect(boxes[0].bottom, 40); // (9 + 1) * 4.0
      expect(boxes[1].left, 40);
      expect(boxes[1].top, 60);
    });

    test('filters small blobs below minArea', () {
      var w = 20, h = 20;
      var m = Float32List(w * h);
      m[5 * w + 5] = 0.9; // single pixel
      m[10 * w + 10] = 0.9;
      m[10 * w + 11] = 0.9;
      m[11 * w + 10] = 0.9;
      m[11 * w + 11] = 0.9;
      var boxes = maskBoxes(
        m,
        w,
        h,
        threshold: 0.5,
        minArea: 4,
        maxAreaFrac: 0.9,
      );
      expect(boxes.length, 1);
      expect(boxes[0].left, 10);
    });

    test('drops a blob covering more than maxAreaFrac', () {
      var w = 10, h = 10;
      var m = Float32List(w * h);
      m.fillRange(0, m.length, 0.9);
      var boxes = maskBoxes(
        m,
        w,
        h,
        threshold: 0.5,
        minArea: 1,
        maxAreaFrac: 0.5,
      );
      expect(boxes, isEmpty);
    });
  });

  group('compareMangaBlocks', () {
    test('vertical columns read right to left', () {
      var left = IntRect(10, 100, 40, 300);
      var right = IntRect(200, 100, 230, 300);
      expect(compareMangaBlocks(right, left), lessThan(0));
      expect(compareMangaBlocks(left, right), greaterThan(0));
    });

    test('columns at the same x sort top to bottom', () {
      var top = IntRect(100, 10, 130, 90);
      var bottom = IntRect(100, 200, 130, 280);
      expect(compareMangaBlocks(top, bottom), lessThan(0));
    });

    test('horizontal rows read top to bottom, then right to left', () {
      var topRow = IntRect(10, 10, 300, 30);
      var bottomRow = IntRect(10, 100, 300, 120);
      expect(compareMangaBlocks(topRow, bottomRow), lessThan(0));
      // Same row band: the rightmost caption comes first.
      var rightCaption = IntRect(200, 10, 300, 30);
      var leftCaption = IntRect(10, 10, 90, 30);
      expect(compareMangaBlocks(rightCaption, leftCaption), lessThan(0));
    });

    test('vertical text sorts before horizontal captions', () {
      var column = IntRect(10, 10, 40, 200);
      var caption = IntRect(100, 10, 300, 30);
      expect(compareMangaBlocks(column, caption), lessThan(0));
    });
  });
}
