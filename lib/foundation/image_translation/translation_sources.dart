import 'dart:convert';

import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/image_translation/translation_models.dart';
import 'package:venera/foundation/image_translation/translation_targets.dart';

/// A source language the user added, recognized by a PP-OCR recognition model
/// (ONNX + character dictionary) they supplied.
class CustomSourceLanguage {
  const CustomSourceLanguage({
    required this.code,
    required this.name,
    required this.modelUrl,
    required this.dictUrl,
    this.inputHeight = 48,
    this.sizeBytes = 0,
  });

  /// Part of stored translation keys, so fixed once added.
  final String code;
  final String name;
  final String modelUrl;
  final String dictUrl;

  /// Recognition input height: 48 for PP-OCRv3 and later, 32 for older models.
  final int inputHeight;

  /// Download size probed when the entry was saved; 0 when the host did not
  /// report one.
  final int sizeBytes;

  /// Worker engine key. Derived from the files rather than the code, so
  /// editing a URL never reuses the files downloaded for the old one.
  String get engine =>
      'custom_${modelHash('$modelUrl\n$dictUrl\n$inputHeight')}';

  ModelComponent get component => ModelComponent(
    id: engine,
    approxSizeBytes: sizeBytes,
    marker: true,
    files: [
      ModelFile('rec.onnx', [modelUrl]),
      ModelFile('dict.txt', [dictUrl]),
    ],
  );

  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
    'model': modelUrl,
    'dict': dictUrl,
    'height': inputHeight,
    'size': sizeBytes,
  };

  static CustomSourceLanguage? fromJson(Object? item) {
    if (item is! Map) return null;
    var code = TranslationTargets.normalizeCode('${item['code'] ?? ''}');
    var name = '${item['name'] ?? ''}'.trim();
    var model = '${item['model'] ?? ''}'.trim();
    var dict = '${item['dict'] ?? ''}'.trim();
    if (code == null || name.isEmpty) return null;
    if (!TranslationSources.isValidUrl(model)) return null;
    if (!TranslationSources.isValidUrl(dict)) return null;
    var height = item['height'] == 32 ? 32 : 48;
    var size = item['size'] is int ? item['size'] as int : 0;
    return CustomSourceLanguage(
      code: code,
      name: name,
      modelUrl: model,
      dictUrl: dict,
      inputHeight: height,
      sizeBytes: size,
    );
  }
}

/// A user-supplied text detection model replacing the built-in detector.
/// Language independent. [kind] selects the inference backend:
/// - 'dbnet': PP-OCR DBNet probability map (URL download or local import).
/// - 'manga-panel': YOLO26 text/panel detector (local import).
/// - 'legacy-balloon': legacy Legacy YOLOv4 (local import).
/// - 'manga-panel-legacy': YOLO26 plus the Legacy YOLOv4 model
///   (local import, two files).
class CustomDetectorModel {
  const CustomDetectorModel({
    required this.url,
    this.sizeBytes = 0,
    this.kind = 'dbnet',
  });

  final String url;
  final int sizeBytes;

  /// 'dbnet' | 'manga-panel' | 'legacy-balloon' | 'manga-panel-legacy'.
  final String kind;

  /// Whether this kind needs the Legacy YOLOv4 model as a second file.
  bool get needsBalloonModel => kind == 'manga-panel-legacy';

  ModelComponent get component => ModelComponent(
    id: 'detector_${modelHash('$kind\n$url')}',
    approxSizeBytes: sizeBytes,
    marker: true,
    files: [
      ModelFile('det.onnx', [if (url.isNotEmpty) url]),
      if (needsBalloonModel) const ModelFile('balloon.onnx', []),
    ],
  );

  Map<String, dynamic> toJson() => {
    'url': url,
    'size': sizeBytes,
    'kind': kind,
  };

  static CustomDetectorModel? fromJson(Object? item) {
    if (item is! Map) return null;
    var url = '${item['url'] ?? ''}'.trim();
    var kind = '${item['kind'] ?? 'dbnet'}';
    if (kind == 'balloon-seg' || kind == 'manga-panel-balloon') return null;
    const kinds = {
      'dbnet',
      'manga-panel',
      'legacy-balloon',
      'manga-panel-legacy',
    };
    if (!kinds.contains(kind)) kind = 'dbnet';
    // URL models must have a valid URL; imported models carry no URL.
    if (url.isNotEmpty && !TranslationSources.isValidUrl(url)) return null;
    var size = item['size'] is int ? item['size'] as int : 0;
    return CustomDetectorModel(url: url, sizeBytes: size, kind: kind);
  }
}

/// A user-supplied manga-ocr encoder/decoder/vocab triple (local import)
/// replacing the downloaded Japanese OCR component.
class CustomJaOcrModel {
  const CustomJaOcrModel({this.sizeBytes = 0});

  final int sizeBytes;

  ModelComponent get component => const ModelComponent(
    id: 'ocr_ja_custom',
    approxSizeBytes: 0,
    marker: true,
    files: [
      ModelFile('encoder.onnx', []),
      ModelFile('decoder.onnx', []),
      ModelFile('vocab.txt', []),
    ],
  );

  Map<String, dynamic> toJson() => {'size': sizeBytes};

  static CustomJaOcrModel? fromJson(Object? item) {
    if (item is! Map) return null;
    var size = item['size'] is int ? item['size'] as int : 0;
    return CustomJaOcrModel(sizeBytes: size);
  }
}

/// Source languages: the built-in set plus the user's own.
abstract class TranslationSources {
  static const settingKey = 'imageTranslationCustomSources';
  static const detectorKey = 'imageTranslationCustomDetector';
  static const jaOcrKey = 'imageTranslationCustomJaOcr';

  /// code -> English UI label. Codes are part of stored translation keys and
  /// of the per-comic language locks, so they must never change.
  static const builtIn = <String, String>{
    'ja': 'Japanese',
    'zh': 'Simplified Chinese',
    'zh-TW': 'Traditional Chinese',
    'en': 'English',
    'ko': 'Korean',
  };

  static List<CustomSourceLanguage> get custom {
    var raw = appdata.settings[settingKey];
    var result = <CustomSourceLanguage>[];
    if (raw is! List) return result;
    var seen = <String>{};
    for (var item in raw) {
      var language = CustomSourceLanguage.fromJson(item);
      if (language == null) continue;
      if (builtIn.containsKey(language.code) || !seen.add(language.code)) {
        continue;
      }
      result.add(language);
    }
    return result;
  }

  static CustomSourceLanguage? find(String code) {
    for (var e in custom) {
      if (e.code == code) return e;
    }
    return null;
  }

  static bool isTaken(String code) =>
      code == 'auto' || builtIn.containsKey(code) || find(code) != null;

  static bool isValidUrl(String value) {
    var uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  /// Adds [language], or replaces the entry with the same code. Files of a
  /// replaced model that no other entry uses are deleted.
  static void save(CustomSourceLanguage language) {
    var list = custom;
    var index = list.indexWhere((e) => e.code == language.code);
    CustomSourceLanguage? old;
    if (index == -1) {
      list.add(language);
    } else {
      old = list[index];
      list[index] = language;
    }
    _persist(list);
    if (old != null && old.engine != language.engine) {
      _deleteIfUnused(old);
    }
  }

  /// Removes the entry and its model files when no other entry shares them.
  /// Pages already translated from [code] stay stored.
  static void remove(String code) {
    var list = custom;
    var index = list.indexWhere((e) => e.code == code);
    if (index == -1) return;
    var removed = list.removeAt(index);
    _persist(list);
    _deleteIfUnused(removed);
  }

  static void _deleteIfUnused(CustomSourceLanguage language) {
    if (custom.any((e) => e.engine == language.engine)) return;
    TranslationModelStore.instance.delete(language.component);
  }

  static void _persist(List<CustomSourceLanguage> list) {
    appdata.settings[settingKey] = [for (var e in list) e.toJson()];
    appdata.saveData();
    TranslationModels.invalidateReadyCache();
  }

  static CustomDetectorModel? get detector {
    var raw = appdata.settings[detectorKey];
    if (raw is! Map) return null;
    var url = '${raw['url'] ?? ''}'.trim();
    if (!isValidUrl(url)) return null;
    var size = raw['size'] is int ? raw['size'] as int : 0;
    return CustomDetectorModel(url: url, sizeBytes: size);
  }

  /// Sets or clears (null) the custom detector, deleting the old one's files.
  static void setDetector(CustomDetectorModel? model) {
    var old = detector;
    appdata.settings[detectorKey] = model?.toJson() ?? <String, dynamic>{};
    appdata.saveData();
    TranslationModels.invalidateReadyCache();
    if (old != null && old.component.id != model?.component.id) {
      TranslationModelStore.instance.delete(old.component);
    }
  }

  static CustomJaOcrModel? get jaOcr {
    var raw = appdata.settings[jaOcrKey];
    if (raw is! Map) return null;
    return CustomJaOcrModel.fromJson(raw);
  }

  /// Sets or clears (null) the custom Japanese OCR model.
  static void setJaOcr(CustomJaOcrModel? model) {
    var old = jaOcr;
    appdata.settings[jaOcrKey] = model?.toJson() ?? <String, dynamic>{};
    appdata.saveData();
    TranslationModels.invalidateReadyCache();
    if (old != null && model == null) {
      TranslationModelStore.instance.delete(old.component);
    }
  }

  /// The Japanese OCR component in use: the user's imported one when it is
  /// installed, otherwise the downloaded one.
  static ModelComponent get activeJaOcr {
    var custom = jaOcr;
    if (custom != null && custom.component.isInstalled) {
      return custom.component;
    }
    return TranslationModels.ocrJa;
  }
}

/// Stable short hash (FNV-1a, 32 bit) for model folder names; unlike
/// [String.hashCode] it does not change between Dart versions.
String modelHash(String value) {
  var hash = 0x811c9dc5;
  for (var byte in utf8.encode(value)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
