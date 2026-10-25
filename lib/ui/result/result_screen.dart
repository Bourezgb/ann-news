import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/text_rules.dart';
import '../../core/verification.dart';
import '../../models/news_category.dart';
import '../../models/news_result.dart';
import '../../services/ai/gemini_client.dart';
import '../../services/history_repository.dart';
import '../../services/settings_service.dart';
import '../../services/speaker_repository.dart';
import '../common/editable_field.dart';
import '../common/feedback.dart';
import '../designer/designer_screen.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.document});

  final NewsDocument document;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  NewsDocument get doc => widget.document;
  OutputLanguage _lang = OutputLanguage.ar;
  bool _translating = false;
  Timer? _saveTimer;
  late final HistoryRepository _history = context.read<HistoryRepository>();
  late final SpeakerRepository _speakers = context.read<SpeakerRepository>();

  NewsContent get c => doc.content(_lang);

  /// المصدر مهيأ مرة واحدة للتحقق من النقاط.
  late final SourceIndex? _source = doc.sourceText == null
      ? null
      : SourceIndex(doc.sourceText!, hasMedia: doc.hasMediaSources);

  /// التحقق متاح للنسخة العربية فقط (الأدلة مقتبسة من المصدر بلغته).
  List<PointCheck> get _checks => _lang == OutputLanguage.ar
      ? [for (var i = 0; i < c.points.length; i++) checkPoint(c.points[i], c.evidenceAt(i), _source)]
      : const [];

  List<String> _accuracyWarnings(List<PointCheck> checks) {
    final w = <String>[];
    for (var i = 0; i < checks.length; i++) {
      final k = checks[i];
      if (k.status != CheckStatus.unverified) continue;
      if (k.missingNumbers.isNotEmpty) {
        w.add('النقطة ${i + 1}: الرقم ${k.missingNumbers.join('، ')} غير موجود في المصدر.');
      }
      if (k.evidenceFound == false) w.add('النقطة ${i + 1}: لم يُعثر على ما يثبتها في المصدر، راجعها.');
    }
    final src = _source;
    if (_lang == OutputLanguage.ar && src != null && !src.isEmpty && !src.hasMedia) {
      for (final (name, text) in [
        ('العنوان', c.headline),
        ('الكابشن', c.caption),
        ('عنوان الصورة المصغرة', c.thumbnail),
      ]) {
        final missing = src.missingNumbers(text);
        if (missing.isNotEmpty) w.add('$name: الرقم ${missing.join('، ')} غير موجود في المصدر.');
      }
    }
    return w;
  }

  void _showCheck(int i, PointCheck k, {String label = 'النقطة'}) {
    final (title, color) = _checkLook(k.status);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$label ${i + 1}: $title',
              style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Text(switch (k.status) {
              CheckStatus.verified => 'الاقتباس التالي موجود في المصدر، وكل أرقام النقطة واردة فيه:',
              CheckStatus.unverified => 'لم يتم تأكيد هذه النقطة من النص المصدري. راجعها قبل النشر.',
              CheckStatus.unknown =>
                'المصدر يتضمن صوتاً أو فيديو أو صوراً، أو أن الخبر قديم: لا يمكن التحقق آلياً. '
                    'هذا ما قال Gemini إنه الدليل:',
            }),
            if (k.missingNumbers.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('أرقام غير موجودة في المصدر: ${k.missingNumbers.join('، ')}', style: TextStyle(color: color)),
            ],
            if (k.evidence.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('«${k.evidence}»'),
              ),
            ] else ...[
              const SizedBox(height: 8),
              const Text('لم يُرجع Gemini أي اقتباس لهذه النقطة.'),
            ],
          ],
        ),
      ),
    );
  }

  static (String, Color) _checkLook(CheckStatus s) => switch (s) {
    CheckStatus.verified => ('موثّقة من المصدر', Colors.green),
    CheckStatus.unverified => ('تحتاج مراجعة', Colors.orange.shade800),
    CheckStatus.unknown => ('غير قابلة للتحقق آلياً', Colors.blueGrey),
  };

  Widget _checkIcon(int i, PointCheck k, {String label = 'النقطة'}) {
    final (title, color) = _checkLook(k.status);
    return IconButton(
      tooltip: title,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      onPressed: () => _showCheck(i, k, label: label),
      icon: Icon(
        switch (k.status) {
          CheckStatus.verified => Icons.verified,
          CheckStatus.unverified => Icons.report_problem,
          CheckStatus.unknown => Icons.help_outline,
        },
        color: color,
        size: 20,
      ),
    );
  }

  void _changed() {
    setState(() {});
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () => _history.save(doc));
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _history.save(doc);
    if (doc.category.isStatement) _speakers.remember(doc.ar.speakerName, doc.ar.speakerRole);
    super.dispose();
  }

  Future<void> _french() async {
    if (doc.fr != null) {
      setState(() => _lang = OutputLanguage.fr);
      return;
    }
    await _translate();
  }

  Future<void> _translate() async {
    setState(() => _translating = true);
    try {
      doc.fr = await context.read<SettingsService>().createAiService().translateToFrench(doc);
      _lang = OutputLanguage.fr;
      _changed();
    } on GeminiException catch (e) {
      if (mounted) showMessage(context, e.fullMessage, error: true);
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  Future<void> _pickSpeaker() async {
    final list = _speakers.items;
    if (list.isEmpty) {
      showMessage(context, 'لا توجد شخصيات محفوظة بعد.');
      return;
    }
    final s = await showModalBottomSheet<Speaker>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          for (final s in list)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(s.name),
              subtitle: Text(s.role),
              onTap: () => Navigator.pop(ctx, s),
            ),
        ],
      ),
    );
    if (s == null) return;
    doc.ar
      ..speakerName = s.name
      ..speakerRole = s.role;
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fr = _lang == OutputLanguage.fr;
    final checks = _checks;
    final warnings = [...validate(doc, _lang), ..._accuracyWarnings(checks), ...c.notes.map((n) => 'ملاحظة: $n')];
    final verified = checks.where((k) => k.status == CheckStatus.verified).length;
    final checkable = checks.where((k) => k.status != CheckStatus.unknown).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(doc.category.label),
        actions: [
          IconButton(
            tooltip: 'نسخ الكل',
            icon: const Icon(Icons.copy_all),
            onPressed: () => copyText(context, formatFullPost(doc, _lang), what: 'كل المخرجات'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<OutputLanguage>(
                    segments: const [
                      ButtonSegment(value: OutputLanguage.ar, label: Text('العربية')),
                      ButtonSegment(value: OutputLanguage.fr, label: Text('Français')),
                    ],
                    selected: {_lang},
                    onSelectionChanged: (s) =>
                        s.first == OutputLanguage.fr ? _french() : setState(() => _lang = OutputLanguage.ar),
                  ),
                ),
                if (fr)
                  IconButton(
                    tooltip: 'إعادة الترجمة من النسخة العربية الحالية',
                    onPressed: _translating ? null : _translate,
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
          ),
          if (_translating) const LinearProgressIndicator(),
          Expanded(
            child: Directionality(
              textDirection: fr ? TextDirection.ltr : TextDirection.rtl,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  if (warnings.isNotEmpty)
                    Card(
                      color: scheme.errorContainer.withValues(alpha: 0.5),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Directionality(
                          textDirection: TextDirection.rtl,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final w in warnings)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
                                      const SizedBox(width: 6),
                                      Expanded(child: Text(w, style: const TextStyle(fontSize: 13))),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (doc.category.isStatement) ...[
                    _Header(
                      fr ? 'Intervenant' : 'المتحدث (النقطة الأولى)',
                      trailing: fr
                          ? null
                          : TextButton.icon(
                              onPressed: _pickSpeaker,
                              icon: const Icon(Icons.people_outline),
                              label: const Text('من القائمة'),
                            ),
                    ),
                    EditableField(
                      label: fr ? 'Nom' : 'الاسم',
                      value: c.speakerName,
                      required: true,
                      copyLabel: 'الاسم',
                      onChanged: (v) {
                        c.speakerName = v;
                        _changed();
                      },
                    ),
                    EditableField(
                      label: fr ? 'Fonction' : 'المهنة / الصفة',
                      value: c.speakerRole,
                      required: true,
                      copyLabel: 'الصفة',
                      onChanged: (v) {
                        c.speakerRole = v;
                        _changed();
                      },
                    ),
                  ],
                  _Header(fr ? 'Titre principal' : 'العنوان الرئيسي'),
                  EditableField(
                    value: c.headline,
                    minWords: WordLimits.headlineMin,
                    maxWords: WordLimits.headline,
                    copyLabel: 'العنوان',
                    onChanged: (v) {
                      c.headline = v;
                      _changed();
                    },
                  ),
                  _Suggestions(
                    serious: c.headlinesSerious,
                    interactive: c.headlinesInteractive,
                    selected: c.headline,
                    fr: fr,
                    onSelect: (v) {
                      c.headline = v;
                      _changed();
                    },
                  ),
                  _Header(
                    fr ? 'Points' : 'نقاط الخبر',
                    trailing: TextButton.icon(
                      onPressed: () => copyText(context, formatPoints(doc, _lang), what: 'النقاط'),
                      icon: const Icon(Icons.copy_all, size: 18),
                      label: Text(fr ? 'Copier tout' : 'نسخ كل النقاط'),
                    ),
                  ),
                  if (checks.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Icon(
                            checkable == 0
                                ? Icons.help_outline
                                : verified == checkable
                                ? Icons.verified
                                : Icons.report_problem,
                            size: 18,
                            color: checkable == 0
                                ? Colors.blueGrey
                                : verified == checkable
                                ? Colors.green
                                : Colors.orange.shade800,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              checkable == 0
                                  ? 'التحقق الآلي غير متاح لهذا المصدر (صوت/فيديو/صور). المس ؟ لرؤية الدليل.'
                                  : 'التحقق من المصدر: $verified من ${checks.length} نقاط موثّقة. المس الأيقونة لرؤية الدليل.',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (doc.category.isStatement)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '$bulletMark${speakerIntro(c, _lang).isEmpty ? (fr ? '(nom, fonction)' : '(الاسم، الصفة)') : speakerIntro(c, _lang)}',
                        style: TextStyle(color: scheme.outline),
                      ),
                    ),
                  for (var i = 0; i < c.points.length; i++)
                    EditableField(
                      key: ValueKey('p$i'),
                      value: c.points[i],
                      leading: i < checks.length ? _checkIcon(i, checks[i]) : null,
                      prefix: bulletMark,
                      maxWords: WordLimits.point,
                      copyLabel: 'النقطة',
                      onChanged: (v) {
                        c.points[i] = v;
                        _changed();
                      },
                      onDelete: () {
                        c.removePoint(i);
                        _changed();
                      },
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () {
                        c.addPoint();
                        _changed();
                      },
                      icon: const Icon(Icons.add),
                      label: Text(fr ? 'Ajouter un point' : 'إضافة نقطة'),
                    ),
                  ),
                  if (doc.category.isStatement) ...[
                    _Header(
                      fr ? 'Déclarations de l’intervenant' : 'تصريحات المتحدث (على لسانه)',
                      trailing: c.quotes.isEmpty
                          ? null
                          : TextButton.icon(
                              onPressed: () => copyText(context, formatQuotes(c), what: 'التصريحات'),
                              icon: const Icon(Icons.copy_all, size: 18),
                              label: Text(fr ? 'Copier tout' : 'نسخ الكل'),
                            ),
                    ),
                    EditableField(
                      label: fr ? 'Introduction' : 'جملة التقديم',
                      value: c.quotesIntro,
                      copyLabel: 'جملة التقديم',
                      onChanged: (v) {
                        c.quotesIntro = v;
                        _changed();
                      },
                    ),
                    if (c.quotes.isEmpty)
                      Text(
                        fr ? 'Aucune citation directe détectée.' : 'لم يُعثر على كلام مباشر للمتحدث في المصدر.',
                        style: TextStyle(color: scheme.outline),
                      ),
                    for (var i = 0; i < c.quotes.length; i++)
                      EditableField(
                        key: ValueKey('q$i'),
                        value: c.quotes[i],
                        prefix: bulletMark,
                        copyLabel: 'التصريح',
                        onChanged: (v) {
                          c.quotes[i] = v;
                          _changed();
                        },
                        onDelete: () {
                          c.quotes.removeAt(i);
                          _changed();
                        },
                      ),
                  ],
                  _Header(
                    fr ? 'Source' : 'المصدر',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(fr ? 'Nous sommes la source' : 'نحن المصدر', style: const TextStyle(fontSize: 13)),
                        Switch(
                          value: doc.weAreSource,
                          onChanged: (v) {
                            doc.weAreSource = v;
                            _changed();
                          },
                        ),
                      ],
                    ),
                  ),
                  if (!doc.weAreSource)
                    EditableField(
                      value: c.source,
                      required: true,
                      prefix: fr ? 'Source : ' : 'المصدر: ',
                      copyLabel: 'المصدر',
                      onChanged: (v) {
                        c.source = v;
                        _changed();
                      },
                    ),
                  _Header(fr ? 'Légende réseaux sociaux' : 'كابشن السوشيال ميديا'),
                  EditableField(
                    value: c.caption,
                    maxWords: WordLimits.caption,
                    copyLabel: 'الكابشن',
                    onChanged: (v) {
                      c.caption = v;
                      _changed();
                    },
                  ),
                  _Header(fr ? 'Titre de la miniature' : 'عنوان الصورة المصغرة (Thumbnail)'),
                  EditableField(
                    value: c.thumbnail,
                    maxWords: WordLimits.thumbnail,
                    copyLabel: 'عنوان الصورة',
                    onChanged: (v) {
                      c.thumbnail = v;
                      _changed();
                    },
                  ),
                  _Suggestions(
                    serious: c.thumbnailsSerious,
                    interactive: c.thumbnailsInteractive,
                    selected: c.thumbnail,
                    fr: fr,
                    onSelect: (v) {
                      c.thumbnail = v;
                      _changed();
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => copyText(context, formatFullPost(doc, _lang), what: 'كل المخرجات'),
                  icon: const Icon(Icons.copy_all),
                  label: const Text('نسخ الكل'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DesignerScreen(document: doc, language: _lang),
                    ),
                  ),
                  icon: const Icon(Icons.palette_outlined),
                  label: const Text('إلى التصميم'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// ثلاثة اقتراحات جادة وثلاثة تفاعلية، مع اختيار ونسخ.
class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.serious,
    required this.interactive,
    required this.selected,
    required this.onSelect,
    required this.fr,
  });

  final List<String> serious;
  final List<String> interactive;
  final String selected;
  final ValueChanged<String> onSelect;
  final bool fr;

  @override
  Widget build(BuildContext context) {
    Widget group(String title, List<String> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text(title, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.outline)),
        ),
        for (final s in items)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onSelect(s),
            child: Row(
              children: [
                Icon(
                  s == selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(s)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () => copyText(context, s),
                ),
              ],
            ),
          ),
      ],
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (serious.isNotEmpty) group(fr ? 'Sérieux' : 'اقتراحات جادة', serious),
            if (interactive.isNotEmpty) group(fr ? 'Interactifs' : 'اقتراحات تفاعلية', interactive),
          ],
        ),
      ),
    );
  }
}
