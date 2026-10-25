import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme.dart';
import '../../models/news_category.dart';
import '../../models/news_input.dart';
import '../../models/news_result.dart';
import '../../services/ai/gemini_client.dart';
import '../../services/ai/news_ai_service.dart';
import '../../services/history_repository.dart';
import '../../services/media_picker.dart';
import '../../services/settings_service.dart';
import '../../services/share_inbox.dart';
import '../../services/url_extractor.dart';
import '../common/feedback.dart';
import '../result/result_screen.dart';
import 'input_card.dart';

class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  NewsCategory? _category;
  StatementStyle _style = StatementStyle.fusha;
  late bool _weAreSource = context.read<SettingsService>().defaultWeAreSource;
  final List<NewsInput> _inputs = [];
  bool _busy = false;

  /// صورة تُستعمل في التصميم فقط (لا تُرسل إلى Gemini).
  String? _designImage;

  Future<void> _pickDesignImage({bool camera = false}) async {
    final path = await MediaPicker.pickBackground(camera: camera);
    if (path != null) setState(() => _designImage = path);
  }

  String _status = '';

  late final ShareInbox _inbox = context.read<ShareInbox>();

  @override
  void initState() {
    super.initState();
    _inbox.addListener(_takeShared);
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeShared());
  }

  @override
  void dispose() {
    _inbox.removeListener(_takeShared);
    super.dispose();
  }

  void _takeShared() {
    if (!mounted || _busy || !_inbox.hasPending) return;
    final items = _inbox.take();
    setState(() => _inputs.addAll(items));
    showMessage(
      context,
      _category == null
          ? 'تمت إضافة ${items.length} مدخل من المشاركة. اختر نوع المدخلات ثم اضغط «صياغة الخبر».'
          : 'تمت إضافة ${items.length} مدخل من المشاركة.',
    );
  }

  bool get _canGenerate => !_busy && _category != null && _inputs.isNotEmpty;

  Future<void> _addText() async {
    final text = await _textDialog(title: 'إضافة نص', hint: 'الصق نص المقال أو الخبر هنا', multiline: true);
    if (text != null && text.trim().isNotEmpty) {
      setState(() => _inputs.add(NewsInput(kind: InputKind.text, value: text.trim())));
    }
  }

  Future<void> _addUrl() async {
    final url = await _textDialog(title: 'إضافة رابط', hint: 'رابط مقال أو فيديو يوتيوب', multiline: false);
    if (url == null || url.trim().isEmpty) return;
    final u = url.trim();
    final parsed = Uri.tryParse(u);
    if (parsed == null || !parsed.hasScheme || !parsed.scheme.startsWith('http')) {
      if (mounted) showMessage(context, 'الرابط غير صالح', error: true);
      return;
    }
    setState(
      () => _inputs.add(NewsInput(kind: NewsInput.isYoutubeUrl(u) ? InputKind.youtube : InputKind.url, value: u)),
    );
  }

  Future<void> _addImages({bool camera = false}) async {
    final paths = camera ? [?await MediaPicker.takePhoto()] : await MediaPicker.pickImages();
    setState(() => _inputs.addAll(paths.map((p) => NewsInput(kind: InputKind.image, value: p))));
  }

  Future<void> _addMedia(InputKind kind) async {
    final path = kind == InputKind.audio ? await MediaPicker.pickAudio() : await MediaPicker.pickVideo();
    if (path == null) return;
    final size = await File(path).length();
    if (size > 1900 * 1024 * 1024 && mounted) {
      showMessage(context, 'الملف أكبر من 2 جيغابايت (حد Gemini).', error: true);
      return;
    }
    setState(() => _inputs.add(NewsInput(kind: kind, value: path)));
  }

  Future<String?> _textDialog({required String title, required String hint, required bool multiline}) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 500,
          child: TextField(
            controller: c,
            autofocus: true,
            minLines: multiline ? 6 : 1,
            maxLines: multiline ? 14 : 1,
            keyboardType: multiline ? TextInputType.multiline : TextInputType.url,
            decoration: InputDecoration(hintText: hint),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.content_paste),
            label: const Text('لصق'),
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              if (data?.text != null) c.text = data!.text!;
            },
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('إضافة')),
        ],
      ),
    );
  }

  Future<void> _generate() async {
    final settings = context.read<SettingsService>();
    final history = context.read<HistoryRepository>();
    if (!settings.hasApiKey) {
      showMessage(context, 'أضف مفتاح Gemini API من الإعدادات أولاً.', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _status = 'تحضير المدخلات…';
    });
    final ai = settings.createAiService();
    final extractor = UrlExtractor();
    try {
      final pages = <String, ExtractedPage>{};
      // الأولوية لصورة التصميم التي اختارها المحرر، ثم صورة المقال، ثم أول صورة مدخلة.
      String? background = _designImage;
      final fallbackImage = _inputs.where((i) => i.kind == InputKind.image).firstOrNull?.value;
      for (final input in _inputs.where((i) => i.kind == InputKind.url)) {
        setState(() => _status = 'جلب الرابط: ${input.value}');
        final page = await extractor.fetch(input.value);
        if (page != null) {
          pages[input.id] = ExtractedPage(url: input.value, title: page.title, text: page.text);
          if (background == null && _designImage == null && page.imageUrl != null) {
            background = await extractor.downloadImage(page.imageUrl!);
          }
        } else {
          setState(() => _status = 'استخلاص الرابط عبر Gemini…');
          final text = await ai.extractPageText(input.value);
          pages[input.id] = ExtractedPage(url: input.value, title: '', text: text);
        }
      }

      background ??= fallbackImage;
      final category = _category!;
      final content = await ai.generate(
        NewsRequest(
          category: category,
          statementStyle: _style,
          weAreSource: _weAreSource,
          inputs: List.of(_inputs),
          pages: pages,
        ),
        onStatus: (s) {
          if (mounted) setState(() => _status = s);
        },
      );
      final doc = NewsDocument(
        id: const Uuid().v4(),
        createdAt: DateTime.now(),
        category: category,
        statementStyle: _style,
        weAreSource: _weAreSource,
        inputsSummary: _inputs.map((i) => '${i.kind.label}: ${i.summary}').toList(),
        ar: content,
        backgroundImagePath: background,
        sourceText: [
          for (final i in _inputs)
            if (i.kind == InputKind.text) i.value else if (pages[i.id] case final page?) '${page.title}\n${page.text}',
        ].join('\n\n'),
        hasMediaSources: _inputs.any((i) => i.isFile || i.kind == InputKind.youtube),
      );
      await history.save(doc);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResultScreen(document: doc)));
    } on GeminiException catch (e) {
      if (mounted) showMessage(context, e.fullMessage, error: true);
    } catch (e) {
      if (mounted) showMessage(context, 'حدث خطأ غير متوقع: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
      _takeShared();
    }
  }

  void _reset() => setState(() {
    _inputs.clear();
    _designImage = null;
    _category = null;
    _style = StatementStyle.fusha;
    _weAreSource = context.read<SettingsService>().defaultWeAreSource;
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/ann-logo-white.png', height: 34),
          ],
        ),
        actions: [
          if (_inputs.isNotEmpty || _category != null)
            IconButton(tooltip: 'مادة جديدة', onPressed: _busy ? null : _reset, icon: const Icon(Icons.restart_alt)),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            _SectionTitle('1. نوع المدخلات', required: _category == null),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in NewsCategory.selectable)
                  ChoiceChip(
                    label: Text(c.label),
                    selected: _category == c,
                    avatar: Icon(_categoryIcon(c), size: 18),
                    selectedColor: _categoryColor(c).withValues(alpha: 0.22),
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
            if (_category?.isStatement ?? false) ...[
              const SizedBox(height: 12),
              const Text('نقل كلام المتحدث:'),
              const SizedBox(height: 6),
              SegmentedButton<StatementStyle>(
                segments: [for (final s in StatementStyle.values) ButtonSegment(value: s, label: Text(s.label))],
                selected: {_style},
                onSelectionChanged: (s) => setState(() => _style = s.first),
              ),
            ],
            const SizedBox(height: 20),
            const _SectionTitle('2. المدخلات'),
            Text(
              'يمكن الجمع بين عدة مدخلات لنفس الخبر (نص، روابط، لقطات شاشة، صوت، فيديو حتى 10 دقائق).',
              style: TextStyle(color: scheme.outline, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(avatar: const Icon(Icons.notes), label: const Text('نص'), onPressed: _addText),
                ActionChip(avatar: const Icon(Icons.link), label: const Text('رابط / يوتيوب'), onPressed: _addUrl),
                ActionChip(
                  avatar: const Icon(Icons.photo_library_outlined),
                  label: const Text('صور ولقطات'),
                  onPressed: _addImages,
                ),
                ActionChip(
                  avatar: const Icon(Icons.photo_camera_outlined),
                  label: const Text('كاميرا'),
                  onPressed: () => _addImages(camera: true),
                ),
                ActionChip(
                  avatar: const Icon(Icons.mic_none),
                  label: const Text('ملف صوتي'),
                  onPressed: () => _addMedia(InputKind.audio),
                ),
                ActionChip(
                  avatar: const Icon(Icons.videocam_outlined),
                  label: const Text('فيديو'),
                  onPressed: () => _addMedia(InputKind.video),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final input in _inputs)
              InputCard(key: ValueKey(input.id), input: input, onRemove: () => setState(() => _inputs.remove(input))),
            if (_inputs.isEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'لم تُضف أي مدخلات بعد',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.outline),
                ),
              ),
            const SizedBox(height: 20),
            const _SectionTitle('3. صورة التصميم (اختيارية)'),
            Text(
              'صورة تظهر في خلفية التصميم فقط ولا تُرسل إلى Gemini. مفيدة عندما تكون المدخلات لقطات شاشة للنص.',
              style: TextStyle(color: scheme.outline, fontSize: 13),
            ),
            const SizedBox(height: 8),
            if (_designImage == null)
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.wallpaper),
                    label: const Text('من المعرض'),
                    onPressed: _pickDesignImage,
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.photo_camera_outlined),
                    label: const Text('كاميرا'),
                    onPressed: () => _pickDesignImage(camera: true),
                  ),
                ],
              )
            else
              Card(
                child: ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(_designImage!), width: 56, height: 56, fit: BoxFit.cover, cacheWidth: 168),
                  ),
                  title: const Text('صورة التصميم'),
                  subtitle: const Text('ستوضع خلفيةً للتصميم تلقائياً'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(tooltip: 'تغيير', icon: const Icon(Icons.swap_horiz), onPressed: _pickDesignImage),
                      IconButton(
                        tooltip: 'إزالة',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() => _designImage = null),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('نحن مصدر الخبر'),
              subtitle: const Text('لن يُذكر المصدر في المخرجات'),
              value: _weAreSource,
              onChanged: (v) => setState(() => _weAreSource = v),
            ),
          ],
        ),
      ),
      bottomSheet: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_busy) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 6),
              Text(_status, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
            ],
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: _canGenerate ? _generate : null,
                icon: const Icon(Icons.auto_awesome),
                label: Text(
                  _category == null
                      ? 'اختر نوع المدخلات أولاً'
                      : (_inputs.isEmpty ? 'أضف مدخلاً واحداً على الأقل' : 'صياغة الخبر'),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _categoryIcon(NewsCategory c) => switch (c) {
    NewsCategory.statement => Icons.record_voice_over_outlined,
    NewsCategory.urgent => Icons.bolt,
    NewsCategory.general => Icons.article_outlined,
    NewsCategory.latest => Icons.fiber_new_outlined,
    NewsCategory.important => Icons.priority_high,
    NewsCategory.reel => Icons.slow_motion_video,
    NewsCategory.youtube => Icons.smart_display_outlined,
  };

  static Color _categoryColor(NewsCategory c) => switch (c) {
    NewsCategory.urgent || NewsCategory.important => BrandColors.logoRed,
    NewsCategory.statement => BrandColors.orange,
    _ => BrandColors.primary,
  };
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        if (required) Text('  (إلزامي)', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
      ],
    ),
  );
}
