import 'news_category.dart';

/// مخرجات الخبر بلغة واحدة. كل الحقول قابلة للتعديل من طرف المحرر.
class NewsContent {
  NewsContent({
    required this.points,
    required this.headlinesSerious,
    required this.headlinesInteractive,
    required this.caption,
    required this.thumbnailsSerious,
    required this.thumbnailsInteractive,
    this.source = '',
    this.speakerName = '',
    this.speakerRole = '',
    this.notes = const [],
    List<String>? evidence,
    List<String>? quotes,
    this.quotesIntro = '',
    String? headline,
    String? thumbnail,
  }) : evidence = evidence ?? [],
       quotes = quotes ?? [],
       headline = headline ?? _first(headlinesSerious, headlinesInteractive),
       thumbnail = thumbnail ?? _first(thumbnailsSerious, thumbnailsInteractive);

  /// نقاط الخبر دون الرمز 🔴 (يُضاف عند العرض والنسخ).
  List<String> points;
  List<String> headlinesSerious;
  List<String> headlinesInteractive;
  String caption;
  List<String> thumbnailsSerious;
  List<String> thumbnailsInteractive;
  String source;
  String speakerName;
  String speakerRole;
  List<String> notes;

  /// لكل نقطة (بنفس الترتيب) اقتباس حرفي من المصدر يثبتها، للتحقق من الدقة.
  List<String> evidence;

  /// تصريحات المتحدث مُعاد صياغتها على لسانه (في التصريحات فقط).
  List<String> quotes;

  /// جملة تقديم التصريحات، مثل: «الإعلامي القدير #فلان يكشف عن ...:».
  String quotesIntro;

  /// الدليل الخاص بالنقطة [i] (فارغ إذا لم يوجد).
  String evidenceAt(int i) => i < evidence.length ? evidence[i] : '';

  void removePoint(int i) {
    points.removeAt(i);
    if (i < evidence.length) evidence.removeAt(i);
  }

  void addPoint() {
    while (evidence.length < points.length) {
      evidence.add('');
    }
    points.add('');
    evidence.add('');
  }

  /// العنوان والـ Thumbnail المختاران (قابلان للتعديل).
  String headline;
  String thumbnail;

  static String _first(List<String> a, List<String> b) => a.isNotEmpty ? a.first : (b.isNotEmpty ? b.first : '');

  factory NewsContent.fromJson(Map<String, dynamic> j) => NewsContent(
    points: _list(j['points']),
    headlinesSerious: _list(j['headlines_serious']),
    headlinesInteractive: _list(j['headlines_interactive']),
    caption: (j['caption'] ?? '').toString(),
    thumbnailsSerious: _list(j['thumbnails_serious']),
    thumbnailsInteractive: _list(j['thumbnails_interactive']),
    source: (j['source'] ?? '').toString(),
    speakerName: (j['speaker_name'] ?? '').toString(),
    speakerRole: (j['speaker_role'] ?? '').toString(),
    notes: _list(j['notes']),
    evidence: j['evidence'] is List ? (j['evidence'] as List).map((e) => e.toString().trim()).toList() : null,
    quotes: _list(j['quotes']),
    quotesIntro: (j['quotes_intro'] ?? '').toString(),
    headline: j['headline'] as String?,
    thumbnail: j['thumbnail'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'points': points,
    'headlines_serious': headlinesSerious,
    'headlines_interactive': headlinesInteractive,
    'caption': caption,
    'thumbnails_serious': thumbnailsSerious,
    'thumbnails_interactive': thumbnailsInteractive,
    'source': source,
    'speaker_name': speakerName,
    'speaker_role': speakerRole,
    'notes': notes,
    'evidence': evidence,
    'quotes': quotes,
    'quotes_intro': quotesIntro,
    'headline': headline,
    'thumbnail': thumbnail,
  };

  static List<String> _list(dynamic v) =>
      v is List ? v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList() : <String>[];
}

/// وثيقة خبر كاملة كما تُحفظ في السجل.
class NewsDocument {
  NewsDocument({
    required this.id,
    required this.createdAt,
    required this.category,
    required this.statementStyle,
    required this.weAreSource,
    required this.inputsSummary,
    required this.ar,
    this.fr,
    this.backgroundImagePath,
    this.sourceText,
    this.hasMediaSources = false,
  });

  final String id;
  final DateTime createdAt;
  final NewsCategory category;
  final StatementStyle statementStyle;
  bool weAreSource;
  final List<String> inputsSummary;
  NewsContent ar;
  NewsContent? fr;

  /// النص المصدري (النصوص المدخلة + محتوى الروابط) للتحقق من الدقة.
  final String? sourceText;

  /// المدخلات تضمنت صوتاً أو فيديو أو صوراً (لا يمكن التحقق منها نصياً).
  final bool hasMediaSources;

  /// صورة مرفقة بالخبر (من المدخلات أو من الرابط) تُقترح كخلفية للتصميم.
  String? backgroundImagePath;

  NewsContent content(OutputLanguage lang) => lang == OutputLanguage.ar ? ar : fr!;

  factory NewsDocument.fromJson(Map<String, dynamic> j) => NewsDocument(
    id: j['id'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    category: NewsCategory.fromName(j['category'] as String?),
    statementStyle: StatementStyle.fromName(j['statement_style'] as String?),
    weAreSource: j['we_are_source'] == true,
    inputsSummary: (j['inputs'] as List? ?? const []).map((e) => e.toString()).toList(),
    ar: NewsContent.fromJson(Map<String, dynamic>.from(j['ar'] as Map)),
    fr: j['fr'] == null ? null : NewsContent.fromJson(Map<String, dynamic>.from(j['fr'] as Map)),
    backgroundImagePath: j['background'] as String?,
    sourceText: j['source_text'] as String?,
    hasMediaSources: j['has_media'] == true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'created_at': createdAt.toIso8601String(),
    'category': category.name,
    'statement_style': statementStyle.name,
    'we_are_source': weAreSource,
    'inputs': inputsSummary,
    'ar': ar.toJson(),
    'fr': fr?.toJson(),
    'background': backgroundImagePath,
    'source_text': sourceText,
    'has_media': hasMediaSources,
  };
}
