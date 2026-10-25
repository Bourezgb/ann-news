/// نوع المادة المُدخلة كما يختاره المحرر قبل التوليد.
enum NewsCategory {
  statement('تصريح'),
  urgent('عاجل'),
  // لم يعد يظهر للاختيار؛ يبقى لقراءة الأخبار القديمة في السجل.
  general('عام'),
  latest('آخر خبر'),
  important('هام'),
  reel('ريل'),
  youtube('يوتيوب');

  const NewsCategory(this.label);

  final String label;

  /// الأنواع المعروضة للمحرر في شاشة الصياغة.
  static const selectable = [statement, urgent, latest, important, reel, youtube];

  bool get isStatement => this == NewsCategory.statement;

  /// الريل واليوتيوب: التصميم يستعمل عنوان الصورة المصغرة ولا يحمل شارة النوع.
  bool get isVideoCover => this == NewsCategory.reel || this == NewsCategory.youtube;

  static NewsCategory fromName(String? name) =>
      NewsCategory.values.firstWhere((c) => c.name == name, orElse: () => NewsCategory.general);
}

/// طريقة نقل كلام المتحدث في التصريحات.
enum StatementStyle {
  dialect('باللهجة المنطوقة'),
  fusha('بالفصحى');

  const StatementStyle(this.label);

  final String label;

  static StatementStyle fromName(String? name) =>
      StatementStyle.values.firstWhere((c) => c.name == name, orElse: () => StatementStyle.fusha);
}

enum OutputLanguage { ar, fr }
