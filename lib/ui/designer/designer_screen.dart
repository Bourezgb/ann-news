import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/news_category.dart';
import '../../models/news_result.dart';
import '../../models/template_def.dart';
import '../../services/media_picker.dart';
import '../../services/template_repository.dart';
import '../common/feedback.dart';
import 'editor_canvas.dart';
import 'editor_controller.dart';
import 'template_picker.dart';
import 'tool_panel.dart';

/// محرك التصميم: قالب PNG + خلفية + نصوص، ثم الحفظ في المعرض.
class DesignerScreen extends StatefulWidget {
  const DesignerScreen({super.key, this.document, this.language = OutputLanguage.ar});

  final NewsDocument? document;
  final OutputLanguage language;

  @override
  State<DesignerScreen> createState() => _DesignerScreenState();
}

class _DesignerScreenState extends State<DesignerScreen> {
  late final EditorController _c = EditorController(document: widget.document, language: widget.language);
  final _boundaryKey = GlobalKey();
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    // عند القدوم من خبر: تُعرض كل القوالب ليختار المحرر.
    if (widget.document != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _c.template == null) _chooseTemplate();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _chooseTemplate() async {
    final t = await pickTemplate(context, category: widget.document?.category);
    if (t != null) _c.setTemplate(t);
  }

  Future<void> _pickBackground({bool camera = false}) async {
    final path = await MediaPicker.pickBackground(camera: camera);
    if (path != null) {
      _c.setBackground(path);
      _c.select(-1);
    }
  }

  Future<void> _editText(TextLayer l) async {
    final ctl = TextEditingController(text: l.text);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('النص'),
        content: TextField(controller: ctl, autofocus: true, minLines: 1, maxLines: 6),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('تم')),
        ],
      ),
    );
    if (v != null) _c.setLayerText(l, v);
  }

  Future<File?> _render() async {
    final previous = _c.selected;
    _c.select(null);
    setState(() => _exporting = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final bytes = await exportPng(_boundaryKey);
      if (bytes == null) return null;
      final dir = await getTemporaryDirectory();
      final f = File(p.join(dir.path, 'ann_news_${DateTime.now().millisecondsSinceEpoch}.png'));
      await f.writeAsBytes(bytes);
      return f;
    } finally {
      if (mounted) setState(() => _exporting = false);
      _c.select(previous);
    }
  }

  Future<void> _saveToGallery() async {
    try {
      if (!await Gal.hasAccess(toAlbum: true) && !await Gal.requestAccess(toAlbum: true)) {
        if (mounted) showMessage(context, 'لم يُمنح إذن الوصول إلى المعرض.', error: true);
        return;
      }
      final f = await _render();
      if (f == null) return;
      await Gal.putImage(f.path, album: 'ANN');
      if (mounted) showMessage(context, 'تم حفظ الصورة في المعرض ✓');
    } on GalException catch (e) {
      if (mounted) showMessage(context, 'تعذر الحفظ: ${e.type.message}', error: true);
    }
  }

  Future<void> _share() async {
    final f = await _render();
    if (f == null) return;
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'image/png')]));
  }

  Future<void> _saveLayout() async {
    final t = _c.template;
    if (t == null) return;
    await context.read<TemplateRepository>().saveLayout(t, _c.layers);
    if (mounted) showMessage(context, 'تم حفظ مواضع النصوص كافتراضية لهذا القالب');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final hasTemplate = _c.template != null;
        return Scaffold(
          appBar: AppBar(
            title: Text(hasTemplate ? _c.template!.name : 'التصميم', style: const TextStyle(fontSize: 16)),
            actions: [
              IconButton(
                tooltip: 'تغيير القالب',
                onPressed: _chooseTemplate,
                icon: const Icon(Icons.dashboard_customize_outlined),
              ),
              if (hasTemplate)
                IconButton(
                  tooltip: 'حفظ في المعرض',
                  onPressed: _exporting ? null : _saveToGallery,
                  icon: _exporting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_alt),
                ),
              if (hasTemplate)
                PopupMenuButton<String>(
                  onSelected: (v) => switch (v) {
                    'layout' => _saveLayout(),
                    'share' => _share(),
                    _ => null,
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'share', child: Text('مشاركة الصورة')),
                    PopupMenuItem(value: 'layout', child: Text('حفظ المواضع كافتراضية للقالب')),
                  ],
                ),
            ],
          ),
          body: !hasTemplate
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.dashboard_customize_outlined, size: 64),
                      const SizedBox(height: 12),
                      const Text('اختر قالباً للبدء'),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _chooseTemplate, child: const Text('اختيار القالب')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    if (widget.document != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              const Text('نص التصميم: '),
                              SegmentedButton<TitleSource>(
                                showSelectedIcon: false,
                                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                                segments: [
                                  for (final s in _c.titleSources) ButtonSegment(value: s, label: Text(s.label)),
                                ],
                                selected: {_c.titleSource},
                                onSelectionChanged: (s) => _c.setTitleSource(s.first),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: Container(
                        color: Colors.blueGrey.shade800,
                        padding: const EdgeInsets.all(12),
                        child: EditorCanvas(controller: _c, boundaryKey: _boundaryKey, onEditText: _editText),
                      ),
                    ),
                    ToolPanel(controller: _c, onEditText: _editText, onPickBackground: _pickBackground),
                  ],
                ),
        );
      },
    );
  }
}
