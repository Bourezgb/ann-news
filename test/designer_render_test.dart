import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ann_news/models/news_category.dart';
import 'package:ann_news/models/news_result.dart';
import 'package:ann_news/models/template_def.dart';
import 'package:ann_news/ui/designer/editor_canvas.dart';
import 'package:ann_news/ui/designer/editor_controller.dart';

/// يرسم قالباً مؤقتاً مع نص عربي ويصدّره بالمقاس الأصلي.
/// عند تعيين RENDER_OUT يُحفظ الناتج للمعاينة.
NewsDocument _doc(NewsCategory category) => NewsDocument(
  id: 'y',
  createdAt: DateTime(2026),
  category: category,
  statementStyle: StatementStyle.fusha,
  weAreSource: false,
  inputsSummary: const [],
  ar: NewsContent(
    points: const ['نقطة'],
    headlinesSerious: const ['العنوان الرئيسي للخبر'],
    headlinesInteractive: const [],
    caption: '',
    thumbnailsSerious: const ['عنوان مصغر'],
    thumbnailsInteractive: const [],
  ),
);

void main() {
  test('design title: headline by default, thumbnail for reel/youtube (no label)', () {
    final t = TemplateDef(
      id: 't',
      name: 't',
      categories: const [],
      width: 2000,
      height: 2000,
      layers: [
        TextLayer(role: 'label', text: 'آخر خبر', x: 0, y: 0, width: 100, fontSize: 40),
        TextLayer(role: 'title', text: '', x: 0, y: 100, width: 100, fontSize: 40),
      ],
    );
    for (final cat in [NewsCategory.latest, NewsCategory.important, NewsCategory.statement]) {
      final c = EditorController(document: _doc(cat))..setTemplate(t);
      expect(c.layers.firstWhere((l) => l.role == 'title').text, 'العنوان الرئيسي للخبر', reason: cat.name);
      expect(c.layers.any((l) => l.role == 'label'), isTrue);
    }
    for (final cat in [NewsCategory.reel, NewsCategory.youtube]) {
      final c = EditorController(document: _doc(cat))..setTemplate(t);
      expect(c.layers.firstWhere((l) => l.role == 'title').text, 'عنوان مصغر', reason: cat.name);
      expect(c.layers.any((l) => l.role == 'label'), isFalse);
    }
  });

  test('editor lets the user pick headline, caption or thumbnail for the design', () {
    final t = TemplateDef(
      id: 't2',
      name: 't2',
      categories: const [],
      width: 2000,
      height: 2000,
      layers: [TextLayer(role: 'title', text: '', x: 0, y: 100, width: 1800, fontSize: 80)],
    );
    final doc = _doc(NewsCategory.latest)..ar.caption = 'كابشن الخبر';
    final c = EditorController(document: doc)..setTemplate(t);
    String title() => c.layers.single.text;
    expect(title(), 'العنوان الرئيسي للخبر');
    c.setTitleSource(TitleSource.caption);
    expect(title(), 'كابشن الخبر');
    c.setTitleSource(TitleSource.thumbnail);
    expect(title(), 'عنوان مصغر');
  });

  test('reel/youtube split the title over two boxes; quote fills the speaker', () {
    final reel = TemplateDef(
      id: 'r',
      name: 'r',
      categories: const [],
      width: 1080,
      height: 1920,
      layers: [
        TextLayer(role: 'title', text: '', x: 148, y: 1101, width: 784, fontSize: 72),
        TextLayer(role: 'title2', text: '', x: 148, y: 1235, width: 784, fontSize: 72),
      ],
    );
    final doc = _doc(NewsCategory.reel)..ar.thumbnail = '20 عاما من الملاحة العصبية';
    final c = EditorController(document: doc)..setTemplate(reel);
    expect(c.layers.map((l) => l.text), ['20 عاما', 'من الملاحة العصبية']);

    final quote = TemplateDef(
      id: 'q',
      name: 'q',
      categories: const [],
      width: 2000,
      height: 2000,
      layers: [
        TextLayer(role: 'title', text: '', x: 990, y: 555, width: 910, fontSize: 118),
        TextLayer(role: 'speaker_name', text: '', x: 1000, y: 1515, width: 580, fontSize: 56),
        TextLayer(role: 'speaker_role', text: '', x: 1000, y: 1610, width: 580, fontSize: 58),
      ],
    );
    final st = _doc(NewsCategory.statement)
      ..ar.speakerName = 'رضوان صدام كمال'
      ..ar.speakerRole = 'منسق اللجنة'
      ..ar.quotes = ['التصريح الحرفي'];
    final q = EditorController(document: st)..setTemplate(quote);
    expect(q.layers.map((l) => l.text), ['التصريح الحرفي', 'رضوان صدام كمال', 'منسق اللجنة']);
    expect(q.titleSources, contains(TitleSource.quote));
  });

  test('selectable categories: no «عام», includes ريل and يوتيوب', () {
    final labels = NewsCategory.selectable.map((c) => c.label).toList();
    expect(labels, ['تصريح', 'عاجل', 'آخر خبر', 'هام', 'ريل', 'يوتيوب']);
  });

  testWidgets('composition exports at template native size', (tester) async {
    final font = FontLoader('BeIN')..addFont(rootBundle.load('assets/fonts/BeIN-Normal.ttf'));
    await font.load();

    final manifest = jsonDecode(await rootBundle.loadString('assets/templates/templates.json')) as Map;
    final defs = (manifest['templates'] as List)
        .map((e) => TemplateDef.fromJson(Map<String, dynamic>.from(e as Map), assetDir: 'assets/templates'))
        .toList();

    // كل القوالب عند المعاينة (RENDER_OUT)، وإلا عينة من كل نوع.
    final ids = Platform.environment['RENDER_OUT'] != null
        ? defs.map((d) => d.id).toList()
        : ['latest_photo', 'urgent_solid'];
    for (final id in ids) {
      final t = defs.firstWhere((d) => d.id == id);
      final doc = NewsDocument(
        id: 'x',
        createdAt: DateTime(2026),
        category: id.contains('red') ? NewsCategory.important : NewsCategory.latest,
        statementStyle: StatementStyle.fusha,
        weAreSource: false,
        inputsSummary: const [],
        ar: NewsContent(
          points: const ['نقطة'],
          headlinesSerious: const ['الأولى من نوعها في شمال إفريقيا: تقنية الملاحة العصبية تصل إلى البليدة'],
          headlinesInteractive: const [],
          caption: '',
          thumbnailsSerious: const ['تقنية الملاحة العصبية تصل إلى مستشفى البليدة'],
          thumbnailsInteractive: const [],
        ),
      );
      final c = EditorController(document: doc)
        ..setTemplate(t)
        // شفاف عند المعاينة لتُركَّب صورة الخلفية خارج الاختبار.
        ..bgColor = Platform.environment['RENDER_OUT'] != null ? const Color(0x00000000) : const Color(0xFF6E8B74);
      final key = GlobalKey();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: FittedBox(
            child: RepaintBoundary(
              key: key,
              child: Composition(controller: c),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await precacheImage(t.image, tester.element(find.byType(Composition)));
      });
      await tester.pumpAndSettle();

      final bytes = (await tester.runAsync(() => exportPng(key)))!;
      final decoded = await tester.runAsync(() => decodeImageFromList(bytes));
      expect(decoded!.width, t.width);
      expect(decoded.height, t.height);
      if (!c.layers.any((l) => l.role == 'title2')) {
        expect(c.layers.firstWhere((l) => l.role == 'title').text, doc.ar.headline);
      }

      final out = Platform.environment['RENDER_OUT'];
      if (out != null) File('$out/$id.png').writeAsBytesSync(bytes);
    }
  });
}
