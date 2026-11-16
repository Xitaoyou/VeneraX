part of 'settings_page.dart';

/// Management page for offline translation model files: download (with
/// progress and mirror fallback), delete, and choice of download endpoint.
class TranslationModelsPage extends StatefulWidget {
  const TranslationModelsPage({super.key, this.sourceLang});

  /// Source language whose OCR models are marked "required", or null to use the
  /// global setting. Passed by the reader's per-comic settings so the page marks
  /// the models that comic actually needs, not the ones the global default does.
  final String? sourceLang;

  @override
  State<TranslationModelsPage> createState() => _TranslationModelsPageState();
}

class _TranslationModelsPageState extends State<TranslationModelsPage> {
  @override
  void initState() {
    TranslationModelStore.instance.addListener(_update);
    super.initState();
  }

  @override
  void dispose() {
    TranslationModelStore.instance.removeListener(_update);
    super.dispose();
  }

  void _update() {
    if (mounted) setState(() {});
  }

  static String _componentName(String id) {
    return switch (id) {
      'text_detector' => "Text detector".tl,
      'ocr_ja' => "Japanese OCR (manga)".tl,
      'ocr_ja_custom' => "Japanese OCR (imported)".tl,
      'ocr_zh_v5' => "Chinese OCR (Simplified + Traditional)".tl,
      'ocr_zh' => "Chinese / Latin OCR".tl,
      'ocr_en' => "English OCR".tl,
      'ocr_ko' => "Korean OCR".tl,
      _ => id,
    };
  }

  static String _formatSize(int bytes) {
    if (bytes >= 1 << 30) {
      return "${(bytes / (1 << 30)).toStringAsFixed(2)} GB";
    }
    if (bytes >= 1 << 20) {
      return "${(bytes / (1 << 20)).toStringAsFixed(1)} MB";
    }
    return "${(bytes / (1 << 10)).toStringAsFixed(0)} KB";
  }

  @override
  Widget build(BuildContext context) {
    var requiredIds = TranslationModels.requiredFor(
      widget.sourceLang ?? TranslationConfig.global.sourceLang,
    ).map((c) => c.id).toSet();
    return Scaffold(
      body: SmoothCustomScrollView(
        scrollbarTopPadding: context.padding.top + 56,
        slivers: [
          SliverAppbar(title: Text("Translation models".tl)),
          SelectSetting(
            title: "Model download source".tl,
            settingKey: "imageTranslationHfEndpoint",
            optionTranslation: const {
              'https://huggingface.co': "HuggingFace",
              'https://hf-mirror.com': "hf-mirror.com",
            },
          ).toSliver(),
          ListTile(
            title: Text("Storage used by models".tl),
            subtitle: Text(
              _formatSize(TranslationModelStore.instance.installedSizeBytes),
            ),
          ).toSliver(),
          _buildSectionHeader(context, "Text detection".tl).toSliver(),
          _buildActiveDetectorRow(context).toSliver(),
          for (var component in TranslationModels.all)
            if (component.id == 'text_detector')
              _buildComponent(context, component, requiredIds).toSliver(),
          _buildSectionHeader(context, "Text recognition".tl).toSliver(),
          for (var component in TranslationModels.all)
            if (component.id != 'text_detector' &&
                !component.id.startsWith('detector_'))
              _buildComponent(context, component, requiredIds).toSliver(),
          _buildJaOcrImport(context).toSliver(),
          const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: context.colorScheme.primary,
        ),
      ),
    );
  }

  /// Import row for a user-supplied manga-ocr conversion (encoder/decoder/
  /// vocab from local files), e.g. ImageTrans's fp16 weights. When active it
  /// replaces the downloaded Japanese OCR component everywhere.
  Widget _buildJaOcrImport(BuildContext context) {
    var custom = TranslationSources.jaOcr;
    var active = custom != null && custom.component.isInstalled;
    var component = custom?.component ?? CustomJaOcrModel().component;
    var state = TranslationModelStore.instance.stateOf(component);
    var importing = state.downloading;
    Widget trailing;
    if (importing) {
      trailing = SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          value: state.progress <= 0 ? null : state.progress,
        ),
      );
    } else if (active) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: context.colorScheme.primary),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: "Use the downloaded model again".tl,
            onPressed: () {
              TranslationSources.setJaOcr(null);
              if (mounted) setState(() {});
            },
          ),
        ],
      );
    } else {
      trailing = Button.filled(
        onPressed: () => _importJaOcr(),
        child: Text("Import".tl),
      ).fixHeight(32);
    }
    var subtitle = active
        ? "Using the imported model".tl
        : TranslationModels.ocrJa.isInstalled
        ? "Using the bundled model".tl
        : "Import a manga-ocr encoder/decoder/vocab triple from local files, e.g. ImageTrans's fp16 weights (smaller and faster than the download)."
              .tl;
    if (state.error != null) {
      subtitle += "\\n${"Import failed".tl}: ${state.error}";
    }
    return ListTile(
      title: Text("Japanese OCR (imported)".tl),
      subtitle: Text(subtitle),
      isThreeLine: !active && state.error == null,
      trailing: trailing,
    );
  }

  Future<void> _importJaOcr() async {
    var encoder = await selectFile(ext: ['onnx']);
    if (encoder == null) return;
    var decoder = await selectFile(ext: ['onnx']);
    if (decoder == null) return;
    var vocab = await selectFile(ext: ['txt']);
    if (vocab == null) return;
    var model = CustomJaOcrModel();
    await TranslationModelStore.instance.importFiles(
      model.component,
      [
        ('encoder.onnx', encoder.path),
        ('decoder.onnx', decoder.path),
        ('vocab.txt', vocab.path),
      ],
      verify: () => checkJaOcrModel(
        model.component.filePath('encoder.onnx'),
        model.component.filePath('decoder.onnx'),
        model.component.filePath('vocab.txt'),
      ),
    );
    if (model.component.isInstalled) {
      TranslationSources.setJaOcr(model);
    }
    if (mounted) setState(() {});
  }

  /// The detector actually in use — the built-in DBNet or one of the
  /// bundled ImageTrans object-detection/segmentation backends — with the
  /// selector one tap away. The bundled default is the legacy balloon
  /// segmentation, so AI translation works out of the box.
  Widget _buildActiveDetectorRow(BuildContext context) {
    var custom = TranslationSources.detector;
    var customActive = custom != null && custom.component.isInstalled;
    var kind = TranslationModels.activeDetectorKind;
    var (kindLabel, hint) = switch (kind) {
      'manga-panel' => ("manga-panel (RT-DETR)".tl, "Text blocks + panels".tl),
      'balloon-seg' => ("Balloon segmentation (legacy)".tl, "Bubble masks".tl),
      'manga-panel-balloon' => (
        "manga-panel + balloon".tl,
        "Text blocks + panels + bubble grouping".tl,
      ),
      _ => ("Built-in (PP-OCRv4 mobile)".tl, "Text line boxes".tl),
    };
    if (customActive) {
      hint = "Custom imported model".tl;
    }
    return ListTile(
      title: Text("Detection model".tl),
      subtitle: Text("$kindLabel\n$hint"),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _pickDetectorKind(context),
    );
  }

  Future<void> _pickDetectorKind(BuildContext context) async {
    const options = <(String, String)>[
      ('balloon-seg', 'Balloon segmentation (legacy)'),
      ('manga-panel', 'manga-panel (RT-DETR)'),
      ('manga-panel-balloon', 'manga-panel + balloon'),
      ('dbnet', 'PP-OCR (DBNet)'),
    ];
    var current = TranslationModels.activeDetectorKind;
    var custom = TranslationSources.detector;
    var customActive = custom != null && custom.component.isInstalled;
    await showDialog(
      context: context,
      builder: (dialogContext) => ContentDialog(
        title: "Detection model".tl,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (customActive)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    "A custom imported model is active and overrides this selection."
                        .tl,
                    style: ts.s12.copyWith(color: context.colorScheme.outline),
                  ),
                ),
              for (var (value, label) in options)
                ListTile(
                  title: Text(label.tl),
                  leading: Icon(
                    value == current && !customActive
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: value == current && !customActive
                        ? context.colorScheme.primary
                        : null,
                  ),
                  dense: true,
                  onTap: () {
                    TranslationModels.setDetectorKind(value);
                    dialogContext.pop();
                    if (mounted) setState(() {});
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => dialogContext.pop(),
            child: Text("Cancel".tl),
          ),
        ],
      ),
    );
  }

  Widget _buildComponent(
    BuildContext context,
    ModelComponent component,
    Set<String> requiredIds,
  ) {
    var store = TranslationModelStore.instance;
    var state = store.stateOf(component);
    var installed = component.isInstalled;
    Widget trailing;
    if (state.downloading) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              value: state.progress <= 0 ? null : state.progress,
            ),
          ),
          const SizedBox(width: 8),
          Text("${(state.progress * 100).toStringAsFixed(0)}%"),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => store.cancelDownload(component),
          ),
        ],
      );
    } else if (installed) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: context.colorScheme.primary),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              showConfirmDialog(
                context: App.rootContext,
                title: "Delete".tl,
                content: "Delete the downloaded model files?".tl,
                btnColor: context.colorScheme.error,
                onConfirm: () {
                  store.delete(component);
                },
              );
            },
          ),
        ],
      );
    } else {
      trailing = Button.filled(
        onPressed: () => store.download(component),
        child: Text("Download".tl),
      ).fixHeight(32);
    }
    String subtitle = _formatSize(component.approxSizeBytes);
    if (requiredIds.contains(component.id) && !installed) {
      subtitle += " · ${"Required by current settings".tl}";
    }
    if (state.error != null) {
      subtitle += "\n${"Download failed".tl}: ${state.error}";
    }
    return ListTile(
      title: Text(_componentName(component.id)),
      subtitle: Text(subtitle),
      isThreeLine: state.error != null,
      trailing: trailing,
    );
  }
}
