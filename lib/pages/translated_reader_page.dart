import 'dart:async';

import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/image_translation/translation_config.dart';
import 'package:venera/foundation/image_translation/translation_service.dart';
import 'package:venera/foundation/image_translation/translation_store.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/network/images.dart';
import 'package:venera/utils/io.dart';
import 'package:venera/utils/translations.dart';

/// Reads and exports one translated chapter straight from the durable
/// [TranslationStore]: the stored page keys give the page order, the original
/// bytes come from the local library or the comic source, and rendering goes
/// through [ImageTranslationService.renderStoredPage] — no models, no LLM.
class TranslatedChapterReaderPage extends StatefulWidget {
  const TranslatedChapterReaderPage({super.key, required this.chapter});

  final StoredTranslationChapter chapter;

  @override
  State<TranslatedChapterReaderPage> createState() =>
      _TranslatedChapterReaderPageState();

  /// Resolves the ordered original image keys of the chapter: the downloaded
  /// local copy when present, the comic source otherwise.
  static Future<List<String>> resolveImageKeys(
    String cid,
    String sourceKey,
    String eid,
  ) async {
    var type = ComicType.fromKey(sourceKey);
    var downloaded = LocalManager().isDownloaded(
      cid,
      type,
      eid == '0' ? 0 : null,
    );
    if (downloaded) {
      return await LocalManager().getImages(
        cid,
        type,
        eid == '0' ? 0 : eid,
      );
    }
    var source = ComicSource.find(sourceKey);
    if (source?.loadComicPages == null) {
      throw 'Comic source not found';
    }
    var res = await source!.loadComicPages!(
      cid,
      eid == '0' ? null : eid,
    );
    if (res.error) {
      throw res.errorMessage ?? 'Failed to load pages';
    }
    return res.data;
  }

  /// Fetches one page's original bytes ([imageKey] may be a file:// path).
  static Future<Uint8List> fetchPageBytes(
    String imageKey,
    String sourceKey,
    String cid,
    String eid,
  ) async {
    if (imageKey.startsWith('file://')) {
      return await File(imageKey.substring(7)).readAsBytes();
    }
    await for (var event in ImageDownloader.loadComicImageUnwrapped(
      imageKey,
      sourceKey,
      cid,
      eid,
    )) {
      if (event.imageBytes != null) {
        return event.imageBytes!;
      }
    }
    throw 'Empty image data';
  }

  /// Renders every stored page of the chapter into [directory] as
  /// `001.png`, `002.png`, ... Pages whose original could not be fetched are
  /// skipped. Returns (written, skipped).
  static Future<(int, int)> exportChapter(
    StoredTranslationChapter chapter,
    String directory, {
    void Function(int done, int total)? onProgress,
  }) async {
    var identity = chapter.identity;
    var keys = TranslationStore().pageKeysByPrefix(identity.scopePrefix);
    var config = TranslationConfig.of(identity.comicId, identity.sourceKey);
    var written = 0;
    var skipped = 0;
    List<String>? imageKeys;
    try {
      imageKeys = await resolveImageKeys(
        identity.comicId,
        identity.sourceKey,
        identity.chapterId,
      );
    } catch (_) {
      imageKeys = null;
    }
    for (var i = 0; i < keys.length; i++) {
      onProgress?.call(i, keys.length);
      Uint8List? bytes;
      if (imageKeys != null && i < imageKeys.length) {
        try {
          bytes = await fetchPageBytes(
            imageKeys[i],
            identity.sourceKey,
            identity.comicId,
            identity.chapterId,
          );
        } catch (_) {
          bytes = null;
        }
      }
      if (bytes == null) {
        skipped++;
        continue;
      }
      Uint8List out;
      try {
        out = await ImageTranslationService.instance.renderStoredPage(
              keys[i],
              bytes,
              config.mode,
              chapter: identity,
            ) ??
            bytes;
      } catch (_) {
        skipped++;
        continue;
      }
      var file = File(
        FilePath.join(directory, '${(i + 1).toString().padLeft(3, '0')}.png'),
      );
      await file.writeAsBytes(out);
      written++;
    }
    onProgress?.call(keys.length, keys.length);
    return (written, skipped);
  }
}

class _TranslatedChapterReaderPageState
    extends State<TranslatedChapterReaderPage> {
  late final identity = widget.chapter.identity;
  late final config = TranslationConfig.of(identity.comicId, identity.sourceKey);

  var _loading = true;
  String? _error;
  var _keys = <String>[];
  var _imageKeys = <String>[];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _keys = TranslationStore().pageKeysByPrefix(identity.scopePrefix);
    if (_keys.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No stored pages'.tl;
      });
      return;
    }
    try {
      _imageKeys = await TranslatedChapterReaderPage.resolveImageKeys(
        identity.comicId,
        identity.sourceKey,
        identity.chapterId,
      );
    } catch (e) {
      _imageKeys = const [];
    }
    setState(() => _loading = false);
  }

  Future<Uint8List> _loadPage(int index) async {
    var bytes = await TranslatedChapterReaderPage.fetchPageBytes(
      _imageKeys[index],
      identity.sourceKey,
      identity.comicId,
      identity.chapterId,
    );
    var rendered = await ImageTranslationService.instance.renderStoredPage(
      _keys[index],
      bytes,
      config.mode,
      chapter: identity,
    );
    return rendered ?? bytes;
  }

  @override
  Widget build(BuildContext context) {
    var title = identity.chapterTitle.isNotEmpty
        ? identity.chapterTitle
        : identity.chapterId;
    return Scaffold(
      body: SmoothCustomScrollView(
        scrollbarTopPadding: context.padding.top + 56,
        slivers: [
          SliverAppbar(
            title: Text(
              '$title  ·  ${_keys.length} ${"pages".tl}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_loading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: const Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text(_error!)),
            )
          else if (_imageKeys.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'The original pages could not be loaded (source unavailable?). Export and reading need the comic source or a downloaded copy.'
                      .tl,
                  style: ts.s14,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: _keys.length,
              itemBuilder: (context, i) => _PageView(
                key: ValueKey(_keys[i]),
                load: () => _loadPage(i),
                page: i + 1,
                total: _keys.length,
              ),
            ),
        ],
      ),
    );
  }
}

class _PageView extends StatefulWidget {
  const _PageView({
    super.key,
    required this.load,
    required this.page,
    required this.total,
  });

  final Future<Uint8List> Function() load;
  final int page;
  final int total;

  @override
  State<_PageView> createState() => _PageViewState();
}

class _PageViewState extends State<_PageView> {
  late final _future = widget.load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                'Page @p failed to load'.tlParams({'p': widget.page}),
                style: ts.s14,
              ),
            ),
          );
        }
        if (snapshot.data == null) {
          return const SizedBox(
            height: 400,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        // Image sizes itself from its intrinsic aspect ratio; a Stack with
        // only Positioned.fill children has no size and rendered nothing.
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Image.memory(snapshot.data!, fit: BoxFit.contain),
        );
      },
    );
  }
}
