import '../models/news_category.dart';
import '../models/news_result.dart';

/// حدود طول المخرجات (بالكلمات).
class WordLimits {
  static const headlineMin = 8;

  /// الحد المفضّل للعنوان؛ يجوز تجاوزه عند الضرورة (لا يظهر تنبيه).
  static const headline = 15;
  static const caption = 15;
  static const thumbnail = 4;
  static const point = 30;
}

const bulletMark = '🔴';

final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);
// ignore: valid_regexps (خاصية Unicode مدعومة وقت التشغيل، راجع الاختبارات)
final _emoji = RegExp(r'[\p{Extended_Pictographic}\u{FE0F}\u{200D}\u{20E3}]', unicode: true);
// رموز القوائم في بداية النقطة، والترقيم من نوع «1.» أو «2)» فقط (لا تُحذف الأرقام التي هي جزء من الخبر).
final _leadingMarks = RegExp(r'^(?:[\s–—•·*▪►●○◦-]|🔴|\d{1,2}[.)]\s)+', unicode: true);
final _hashtag = RegExp(r'#([\p{L}\p{N}_]+)', unicode: true);

/// ألقاب التفخيم التي لا تُكتب في النقاط.
final _honorifics = RegExp(r'(^|[\s«"(،,])(?:السيدة|السيد|معالي|فخامة|سعادة)\s+(?=\S)', unicode: true);

/// حذف ألقاب «السيد، معالي، فخامة، سعادة» (مع إبقاء ما بعدها).
String stripHonorifics(String text) => text.replaceAllMapped(_honorifics, (m) => m[1]!).trim();

/// عدد الكلمات: كل مقطع يحتوي حرفاً أو رقماً (الإيموجي والرموز لا تُحسب).
int countWords(String text) => text.split(RegExp(r'\s+')).where((w) => _wordChar.hasMatch(w)).length;

bool exceeds(String text, int limit) => countWords(text) > limit;

/// تنظيف نقطة خبر: لا رموز في بدايتها، لا إيموجي ولا هاشتاغ داخلها.
String sanitizePoint(String point) {
  var p = point.trim().replaceFirst(_leadingMarks, '');
  p = p.replaceAllMapped(_hashtag, (m) => m[1]!.replaceAll('_', ' '));
  p = p.replaceAll(_emoji, '');
  p = stripHonorifics(p);
  return p.replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
}

/// عنوان الـ Thumbnail يُطبع على الصورة بخط BeIN، لذا تُزال منه الإيموجي.
String sanitizeThumbnail(String t) => t.replaceAll(_emoji, '').replaceAll(RegExp(r'\s{2,}'), ' ').trim();

/// نقطة التعريف بالمتحدث في التصريحات: «الاسم، الصفة».
String speakerIntro(NewsContent c, OutputLanguage lang) {
  final name = c.speakerName.trim();
  final role = c.speakerRole.trim();
  if (name.isEmpty && role.isEmpty) return '';
  if (name.isEmpty || role.isEmpty) return name.isEmpty ? role : name;
  return lang == OutputLanguage.ar ? '$name، $role' : '$name, $role';
}

/// كل النقاط كما تُنشر (مع نقطة التعريف بالمتحدث في التصريحات).
List<String> publishedPoints(NewsDocument doc, OutputLanguage lang) {
  final c = doc.content(lang);
  final intro = doc.category.isStatement ? speakerIntro(c, lang) : '';
  return [if (intro.isNotEmpty) intro, ...c.points].where((p) => p.trim().isNotEmpty).toList();
}

String formatPoints(NewsDocument doc, OutputLanguage lang) =>
    publishedPoints(doc, lang).map((p) => '$bulletMark$p').join('\n');

String sourceLine(NewsDocument doc, OutputLanguage lang) {
  final s = doc.content(lang).source.trim();
  if (doc.weAreSource || s.isEmpty) return '';
  return lang == OutputLanguage.ar ? 'المصدر: $s' : 'Source : $s';
}

/// التصريحات كما تُنشر: جملة التقديم ثم كل تصريح يبدأ بـ 🔴.
String formatQuotes(NewsContent c) => [
  if (c.quotesIntro.trim().isNotEmpty) c.quotesIntro.trim(),
  ...c.quotes.where((q) => q.trim().isNotEmpty).map((q) => '$bulletMark${q.trim()}'),
].join('\n');

/// النص الكامل لزر «نسخ الكل».
String formatFullPost(NewsDocument doc, OutputLanguage lang) {
  final c = doc.content(lang);
  final ar = lang == OutputLanguage.ar;
  final src = sourceLine(doc, lang);
  final quotes = formatQuotes(c);
  return [
    c.headline.trim(),
    '',
    formatPoints(doc, lang),
    if (src.isNotEmpty) ...['', src],
    if (doc.category.isStatement && quotes.isNotEmpty) ...['', ar ? 'التصريحات:' : 'Déclarations :', quotes],
    '',
    '${ar ? 'الكابشن' : 'Caption'} : ${c.caption.trim()}',
    '${ar ? 'عنوان الصورة المصغرة' : 'Miniature'} : ${c.thumbnail.trim()}',
  ].join('\n').trim();
}

/// تنبيهات تُعرض للمحرر (لا تمنع النسخ).
List<String> validate(NewsDocument doc, OutputLanguage lang) {
  final c = doc.content(lang);
  final w = <String>[];
  final hw = countWords(c.headline);
  if (c.headline.trim().isNotEmpty && hw < WordLimits.headlineMin) {
    w.add('العنوان الرئيسي أقل من ${WordLimits.headlineMin} كلمات ($hw).');
  }
  if (exceeds(c.caption, WordLimits.caption)) {
    w.add('الكابشن يتجاوز ${WordLimits.caption} كلمة (${countWords(c.caption)}).');
  }
  if (exceeds(c.thumbnail, WordLimits.thumbnail)) {
    w.add('عنوان الصورة المصغرة يتجاوز ${WordLimits.thumbnail} كلمات (${countWords(c.thumbnail)}).');
  }
  for (var i = 0; i < c.points.length; i++) {
    if (exceeds(c.points[i], WordLimits.point)) {
      w.add('النقطة ${i + 1} تتجاوز ${WordLimits.point} كلمة (${countWords(c.points[i])}).');
    }
  }
  if (!doc.weAreSource && c.source.trim().isEmpty) {
    w.add('المصدر غير محدد: أدخله يدوياً أو فعّل «نحن مصدر الخبر».');
  }
  if (doc.category.isStatement && (c.speakerName.trim().isEmpty || c.speakerRole.trim().isEmpty)) {
    w.add('اسم المتحدث وصفته إلزاميان في التصريحات.');
  }
  return w;
}
