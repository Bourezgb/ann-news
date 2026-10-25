/// التحقق من المخرجات مقابل المصدر، على الجهاز ودون أي طلب إضافي.
///
/// لكل نقطة يُرجع Gemini «دليلاً»: اقتباساً حرفياً من المصدر. هنا نتأكد أن
/// الاقتباس موجود فعلاً في النص المصدري، وأن كل رقم في النقطة موجود في المصدر.
library;

enum CheckStatus {
  /// الدليل موجود في المصدر وكل الأرقام موجودة.
  verified,

  /// الدليل أو أحد الأرقام غير موجود في المصدر: يحتاج مراجعة.
  unverified,

  /// لا يمكن التحقق آلياً (المصدر صوت/فيديو/صورة، أو خبر قديم دون نص مصدر).
  unknown,
}

class PointCheck {
  const PointCheck(this.status, {this.evidence = '', this.missingNumbers = const [], this.evidenceFound});

  final CheckStatus status;
  final String evidence;
  final List<String> missingNumbers;

  /// null إذا لم يمكن البحث عن الدليل.
  final bool? evidenceFound;
}

final _diacritics = RegExp('[ً-ٰٟۖ-ۭـ]');
final _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final _number = RegExp(r'\d+(?:[.,]\d+)?');

const _arabicDigits = '٠١٢٣٤٥٦٧٨٩';
const _persianDigits = '۰۱۲۳۴۵۶۷۸۹';

/// توحيد النص للمقارنة: حذف التشكيل والتطويل، توحيد الألف والياء والتاء المربوطة
/// والأرقام، وإزالة علامات الترقيم.
String normalizeForMatch(String s) {
  final b = StringBuffer();
  for (final ch in s.replaceAll(_diacritics, '').runes) {
    var c = String.fromCharCode(ch);
    final ai = _arabicDigits.indexOf(c);
    final pi = _persianDigits.indexOf(c);
    if (ai >= 0) {
      c = '$ai';
    } else if (pi >= 0) {
      c = '$pi';
    } else if ('أإآٱ'.contains(c)) {
      c = 'ا';
    } else if (c == 'ى') {
      c = 'ي';
    } else if (c == 'ة') {
      c = 'ه';
    } else if (c == 'ؤ') {
      c = 'و';
    } else if (c == 'ئ') {
      c = 'ي';
    }
    b.write(c);
  }
  return ' ${b.toString().toLowerCase().replaceAll(_nonWord, ' ').trim()} ';
}

/// الأرقام الواردة في النص (بعد التوحيد)، مثل 25 و 3.5.
List<String> numbersIn(String text) {
  final t = text.replaceAllMapped(RegExp('[٠-٩۰-۹]'), (m) {
    final c = m[0]!;
    final i = _arabicDigits.indexOf(c);
    return '${i >= 0 ? i : _persianDigits.indexOf(c)}';
  });
  return _number.allMatches(t).map((m) => m[0]!.replaceAll(',', '.')).toSet().toList();
}

/// مصدر مُهيّأ للمقارنة (يُحسب مرة واحدة لكل خبر).
class SourceIndex {
  SourceIndex(String source, {required this.hasMedia})
    : normalized = normalizeForMatch(source),
      numbers = numbersIn(source).toSet(),
      isEmpty = source.trim().isEmpty;

  final String normalized;
  final Set<String> numbers;
  final bool isEmpty;

  /// المصدر يحتوي صوتاً أو فيديو أو صوراً لا نملك نصها.
  final bool hasMedia;

  late final Set<String> _tokens = normalized.split(' ').where((w) => w.length > 1).toSet();

  bool containsQuote(String quote) {
    final q = normalizeForMatch(quote);
    if (q.trim().isEmpty) return false;
    if (normalized.contains(q)) return true;
    // تسامح مع فروقات طفيفة في النقل: 85% من كلمات الاقتباس موجودة في المصدر.
    final words = q.split(' ').where((w) => w.length > 2).toList();
    if (words.length < 4) return false;
    final hits = words.where(_tokens.contains).length;
    return hits / words.length >= 0.85;
  }

  /// أرقام النص غير الموجودة في المصدر.
  List<String> missingNumbers(String text) => numbersIn(text).where((n) => !numbers.contains(n)).toList();
}

PointCheck checkPoint(String point, String evidence, SourceIndex? source) {
  if (source == null || source.isEmpty) return PointCheck(CheckStatus.unknown, evidence: evidence);
  final missing = source.missingNumbers(point);
  final found = evidence.trim().isEmpty ? false : source.containsQuote(evidence);
  if (found && missing.isEmpty) {
    return PointCheck(CheckStatus.verified, evidence: evidence, evidenceFound: true);
  }
  // مع وجود صوت/فيديو/صور، قد يكون الدليل أو الرقم منها: لا نحكم بالخطأ.
  if (source.hasMedia) {
    return PointCheck(CheckStatus.unknown, evidence: evidence, evidenceFound: found);
  }
  return PointCheck(CheckStatus.unverified, evidence: evidence, missingNumbers: missing, evidenceFound: found);
}
