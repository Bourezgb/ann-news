import 'package:flutter_test/flutter_test.dart';
import 'package:ann_news/core/verification.dart';

void main() {
  const source = '''
أعلنت مديرية الصحة لولاية عنابة عن تخصيص ٢٥ منصباً لتوظيف مساعدي التمريض خريجي المؤسسات الخاصة.
وأوضحت المديرية أنّ آخر أجل لإيداع الملفات هو 15 أكتوبر 2026، وأن نسبة النجاح المطلوبة 12.5 بالمائة.''';
  final idx = SourceIndex(source, hasMedia: false);

  test('normalization unifies alef, taa marbuta, diacritics and digits', () {
    expect(normalizeForMatch('أنّ الصحةَ ٢٥'), normalizeForMatch('ان الصحه 25'));
  });

  test('verified when quote exists and numbers match', () {
    final k = checkPoint(
      'مديرية الصحة بعنابة تخصص 25 منصبا لتوظيف مساعدي التمريض',
      'تخصيص ٢٥ منصباً لتوظيف مساعدي التمريض',
      idx,
    );
    expect(k.status, CheckStatus.verified);
  });

  test('invented number is flagged', () {
    final k = checkPoint('مديرية الصحة تخصص 30 منصبا', 'تخصيص ٢٥ منصباً لتوظيف مساعدي التمريض', idx);
    expect(k.status, CheckStatus.unverified);
    expect(k.missingNumbers, ['30']);
  });

  test('invented evidence is flagged', () {
    final k = checkPoint('الوزير دشّن مستشفى جديداً', 'دشّن الوزير اليوم مستشفى جديداً بسعة مائة سرير', idx);
    expect(k.status, CheckStatus.unverified);
    expect(k.evidenceFound, isFalse);
  });

  test('decimal and date numbers are matched', () {
    final k = checkPoint(
      'آخر أجل لإيداع الملفات 15 أكتوبر 2026 ونسبة النجاح 12.5 بالمائة',
      'آخر أجل لإيداع الملفات هو 15 أكتوبر 2026',
      idx,
    );
    expect(k.status, CheckStatus.verified);
  });

  test('media sources are never marked as wrong', () {
    final media = SourceIndex(source, hasMedia: true);
    expect(checkPoint('الوزير قال إن 40 مستشفى', 'قال الوزير', media).status, CheckStatus.unknown);
  });

  test('no source text gives unknown', () {
    expect(checkPoint('نقطة', 'دليل', null).status, CheckStatus.unknown);
  });
}
