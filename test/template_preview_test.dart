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

/// يرسم كل قالب بنصوص الأمثلة المنشورة للمقارنة البصرية معها.
/// يعمل فقط عند تعيين RENDER_OUT (مجلد الإخراج).
void main() {
  final out = Platform.environment['RENDER_OUT'];

  const samples = <String, (NewsCategory, String, String)>{
    'latest_solid': (
      NewsCategory.latest,
      'وزير الصحة يعلن تخصيص 76 منصبًا ماليًا لتوظيف أطباء أخصائيين بولاية أدرار',
      '',
    ),
    'latest_photo': (NewsCategory.latest, 'إنجاز طبي يُعد الأول من نوعه على المستوى الوطني', ''),
    'urgent_solid': (NewsCategory.urgent, 'تحويل طلبة ملحقة الطب بجيجل بشكل فوري', ''),
    'urgent_photo': (NewsCategory.urgent, 'وزير الصحة ينصب المدير العام الجديد للصيدلية المركزية للمستشفيات', ''),
    'important_solid': (NewsCategory.important, 'تحويل طلبة ملحقة الطب بجيجل بشكل فوري', ''),
    'important_photo': (NewsCategory.important, 'وزير الصحة ينصب المدير العام الجديد للصيدلية المركزية للمستشفيات', ''),
    'statement_quote': (NewsCategory.statement, 'عنوان', 'x'),
    'reel': (NewsCategory.reel, 'عنوان', '20 عاما من الملاحة العصبية'),
    'youtube': (NewsCategory.youtube, 'عنوان', 'الملاحة العصبية تصل إلى البليدة'),
  };

  testWidgets('render all templates with sample texts', (tester) async {
    final font = FontLoader('BeIN')..addFont(rootBundle.load('assets/fonts/BeIN-Normal.ttf'));
    await font.load();
    final manifest = jsonDecode(await rootBundle.loadString('assets/templates/templates.json')) as Map;
    final defs = (manifest['templates'] as List)
        .map((e) => TemplateDef.fromJson(Map<String, dynamic>.from(e as Map), assetDir: 'assets/templates'))
        .toList();

    for (final t in defs) {
      final (cat, headline, thumb) = samples[t.id]!;
      final doc = NewsDocument(
        id: t.id,
        createdAt: DateTime(2026),
        category: cat,
        statementStyle: StatementStyle.fusha,
        weAreSource: false,
        inputsSummary: const [],
        ar: NewsContent(
          points: const ['نقطة'],
          headlinesSerious: [headline],
          headlinesInteractive: const [],
          caption: '',
          thumbnailsSerious: [thumb.isEmpty ? 'عنوان' : thumb],
          thumbnailsInteractive: const [],
          speakerName: 'رضوان صدام كمال',
          speakerRole: 'منسق اللجنة الولائية الطبية للحج بوهران',
          quotes: const ['320 حاجًا يخضعون للفحص الطبي والعملية متواصلة بإشراف اللجنة الطبية للحج'],
        ),
      );
      final c = EditorController(document: doc)
        ..setTemplate(t)
        ..bgColor = const Color(0x00000000);
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
      await tester.runAsync(() => precacheImage(t.image, tester.element(find.byType(Composition))));
      await tester.pumpAndSettle();
      final bytes = (await tester.runAsync(() => exportPng(key)))!;
      File('$out/${t.id}.png').writeAsBytesSync(bytes);
    }
  }, skip: out == null);
}
