import '../../models/news_category.dart';
import '../../models/news_input.dart';
import '../../models/news_result.dart';

/// محتوى رابط تم استخلاصه مسبقاً على الجهاز.
class ExtractedPage {
  ExtractedPage({required this.url, required this.title, required this.text});

  final String url;
  final String title;
  final String text;
}

class NewsRequest {
  NewsRequest({
    required this.category,
    required this.statementStyle,
    required this.weAreSource,
    required this.inputs,
    this.pages = const {},
  });

  final NewsCategory category;
  final StatementStyle statementStyle;
  final bool weAreSource;
  final List<NewsInput> inputs;

  /// نصوص الروابط المستخلصة على الجهاز، مفهرسة بمعرّف المدخل.
  final Map<String, ExtractedPage> pages;
}

typedef StatusCallback = void Function(String status);

/// الواجهة الوحيدة التي تعرفها شاشات التطبيق عن الذكاء الاصطناعي.
/// استبدال Gemini أو تغيير إصداره لا يمسّ الواجهة.
abstract class NewsAiService {
  Future<NewsContent> generate(NewsRequest request, {StatusCallback? onStatus});

  Future<NewsContent> translateToFrench(NewsDocument doc);

  /// استخلاص نص صفحة يتعذر جلبها على الجهاز (مواقع تعتمد على JavaScript مثلاً).
  Future<String> extractPageText(String url);
}
