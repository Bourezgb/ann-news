import 'package:flutter_test/flutter_test.dart';
import 'package:ann_news/core/text_rules.dart';
import 'package:ann_news/models/news_category.dart';
import 'package:ann_news/models/news_result.dart';

NewsContent _content({List<String>? points, String source = 'وزارة الصحة'}) => NewsContent(
  points: points ?? ['الوزير أكد أهمية التعاون', 'الجانبان اتفقا على مواصلة العمل'],
  headlinesSerious: ['وزير الصحة يستقبل رئيس البرلمان اليوناني'],
  headlinesInteractive: [],
  caption: 'تعاون صحي جديد بين الجزائر واليونان',
  thumbnailsSerious: ['تعاون صحي جزائري يوناني'],
  thumbnailsInteractive: [],
  source: source,
);

NewsDocument _doc(NewsContent c, {NewsCategory category = NewsCategory.general, bool weAreSource = false}) =>
    NewsDocument(
      id: '1',
      createdAt: DateTime(2026),
      category: category,
      statementStyle: StatementStyle.fusha,
      weAreSource: weAreSource,
      inputsSummary: const [],
      ar: c,
    );

void main() {
  test('countWords ignores emoji and punctuation', () {
    expect(countWords('وزير الصحة يستقبل 🔥 الوفد'), 4);
    expect(countWords('  '), 0);
    expect(countWords('Le ministre reçoit 3 délégations'), 5);
  });

  test('sanitizePoint strips bullets, emoji and hashtags', () {
    expect(sanitizePoint('🔴 وزير الصحة يستقبل رئيس #البرلمان_اليوناني'), 'وزير الصحة يستقبل رئيس البرلمان اليوناني');
    expect(sanitizePoint('- 1. النقطة الأولى 👍'), 'النقطة الأولى');
    expect(sanitizePoint('25 منصبا لتوظيف مساعدي التمريض'), '25 منصبا لتوظيف مساعدي التمريض');
    expect(sanitizePoint('3) المديرية أعلنت'), 'المديرية أعلنت');
  });

  test('honorifics are removed from points', () {
    expect(sanitizePoint('السيد وزير الصحة يستقبل معالي سفير اليونان'), 'وزير الصحة يستقبل سفير اليونان');
    expect(sanitizePoint('فخامة رئيس الجمهورية يوجه بمتابعة التوصيات'), 'رئيس الجمهورية يوجه بمتابعة التوصيات');
    expect(sanitizePoint('سعادة السفير أكد «أهمية التعاون»'), 'السفير أكد «أهمية التعاون»');
    expect(sanitizePoint('الوزيرة استقبلت السيدة مديرة المستشفى'), 'الوزيرة استقبلت مديرة المستشفى');
    expect(stripHonorifics('السيد محمد بن علي'), 'محمد بن علي');
  });

  test('sanitizeThumbnail removes emoji', () {
    expect(sanitizeThumbnail('عاجل 🚨 لقاح جديد'), 'عاجل لقاح جديد');
  });

  test('points are formatted with the red bullet and no space', () {
    final d = _doc(_content());
    expect(formatPoints(d, OutputLanguage.ar), '🔴الوزير أكد أهمية التعاون\n🔴الجانبان اتفقا على مواصلة العمل');
  });

  test('statement adds speaker intro as first point', () {
    final c = _content()
      ..speakerName = 'محمد صديق آيت مسعودان'
      ..speakerRole = 'وزير الصحة';
    final d = _doc(c, category: NewsCategory.statement);
    expect(publishedPoints(d, OutputLanguage.ar).first, 'محمد صديق آيت مسعودان، وزير الصحة');
  });

  test('source line omitted when we are the source', () {
    expect(sourceLine(_doc(_content()), OutputLanguage.ar), 'المصدر: وزارة الصحة');
    expect(sourceLine(_doc(_content(), weAreSource: true), OutputLanguage.ar), '');
  });

  test('validate flags limits, missing source and speaker', () {
    final c = _content(source: '')..headline = List.filled(5, 'كلمة').join(' ');
    final w = validate(_doc(c, category: NewsCategory.statement), OutputLanguage.ar);
    expect(w.any((e) => e.contains('العنوان الرئيسي')), isTrue);
    expect(w.any((e) => e.contains('المصدر')), isTrue);
    expect(w.any((e) => e.contains('المتحدث')), isTrue);
  });

  test('headline: at least 8 words, more than 15 allowed when needed', () {
    String words(int n) => List.filled(n, 'كلمة').join(' ');
    bool flagged(int n) =>
        validate(_doc(_content()..headline = words(n)), OutputLanguage.ar).any((e) => e.contains('العنوان الرئيسي'));
    expect(flagged(7), isTrue);
    expect(flagged(8), isFalse);
    expect(flagged(15), isFalse);
    expect(flagged(20), isFalse);
  });

  test('statements: intro line then each rephrased quote with the red bullet', () {
    final c = _content()
      ..speakerName = 'سليم سعدون'
      ..speakerRole = 'إعلامي'
      ..quotesIntro = 'الإعلامي القدير #سليم_سعدون يكشف عن حالته الصحية:'
      ..quotes = ['ليس لدي سرطان واحد.. بل اثنان!', 'السرطان ليس نهاية العالم.'];
    expect(
      formatQuotes(c),
      'الإعلامي القدير #سليم_سعدون يكشف عن حالته الصحية:\n🔴ليس لدي سرطان واحد.. بل اثنان!\n🔴السرطان ليس نهاية العالم.',
    );
    final post = formatFullPost(_doc(c, category: NewsCategory.statement), OutputLanguage.ar);
    expect(post, contains('🔴السرطان ليس نهاية العالم.'));
    expect(formatFullPost(_doc(_content()..quotes = ['x']), OutputLanguage.ar), isNot(contains('🔴x')));
  });

  test('document json round-trip', () {
    final d = _doc(_content());
    final back = NewsDocument.fromJson(d.toJson());
    expect(back.ar.points, d.ar.points);
    expect(back.ar.headline, d.ar.headline);
    expect(back.category, d.category);
  });
}
