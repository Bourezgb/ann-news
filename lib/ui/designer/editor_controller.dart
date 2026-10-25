import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/news_category.dart';
import '../../models/news_result.dart';
import '../../models/template_def.dart';

/// النص الذي يُكتب في منطقة العنوان على التصميم.
enum TitleSource {
  headline('العنوان الرئيسي'),
  caption('الكابشن'),
  thumbnail('عنوان الصورة المصغرة'),

  /// أول تصريح حرفي للمتحدث (في التصريحات فقط).
  quote('التصريح');

  const TitleSource(this.label);

  final String label;
}

/// حالة محرر التصميم. الإحداثيات كلها بوحدات بكسل القالب.
class EditorController extends ChangeNotifier {
  EditorController({this.document, this.language = OutputLanguage.ar}) {
    backgroundPath = document?.backgroundImagePath;
    final doc = document;
    titleSource = doc == null
        ? TitleSource.headline
        : doc.category.isVideoCover
        ? TitleSource.thumbnail
        : (doc.category.isStatement && doc.ar.quotes.isNotEmpty)
        ? TitleSource.quote
        : TitleSource.headline;
  }

  /// مصدر نص العنوان على التصميم (يختاره المحرر).
  late TitleSource titleSource;

  final NewsDocument? document;
  final OutputLanguage language;

  TemplateDef? template;
  List<TextLayer> layers = [];

  String? backgroundPath;
  Offset bgOffset = Offset.zero;
  double bgScale = 1;
  bool bgContain = false;
  Color bgColor = Colors.black;

  /// null: لا تحديد، -1: الخلفية، غير ذلك: فهرس طبقة النص.
  int? selected;

  /// خط المحاذاة الأفقي يظهر عند التوسيط أثناء السحب.
  bool showCenterGuide = false;

  Size get size =>
      template == null ? const Size(2000, 2000) : Size(template!.width.toDouble(), template!.height.toDouble());

  double get unit => math.min(size.width, size.height);

  TextLayer? get selectedLayer => (selected ?? -1) >= 0 && selected! < layers.length ? layers[selected!] : null;

  NewsContent? get content => document?.content(language);

  /// النص الافتراضي على التصميم: العنوان الرئيسي، إلا في الريل واليوتيوب
  /// حيث يُستعمل عنوان الصورة المصغرة.
  String? get designTitle {
    final c = content;
    if (c == null) return null;
    return switch (titleSource) {
      TitleSource.headline => c.headline,
      TitleSource.caption => c.caption,
      TitleSource.thumbnail => c.thumbnail,
      TitleSource.quote => c.quotes.isNotEmpty ? c.quotes.first : c.headline,
    };
  }

  /// مصادر العنوان المتاحة لهذا الخبر.
  List<TitleSource> get titleSources => [
    for (final s in TitleSource.values)
      if (s != TitleSource.quote || (document?.category.isStatement ?? false)) s,
  ];

  /// في قوالب الريل واليوتيوب يُقسَّم العنوان على مربعين: النصف الأول ثم الباقي.
  static (String, String) splitTitle(String text) {
    final words = text.trim().split(RegExp(r'\s+'));
    if (words.length < 2) return (text.trim(), '');
    final k = words.length ~/ 2;
    return (words.take(k).join(' '), words.skip(k).join(' '));
  }

  bool get _twoLineTitle => layers.any((l) => l.role == 'title2');

  /// النص الافتراضي لكل دور في القالب، أو null للإبقاء على نص القالب.
  String? _textFor(String role) {
    final c = content;
    final t = designTitle;
    switch (role) {
      case 'title':
        if (t == null) return 'عنوان الخبر';
        return _twoLineTitle ? splitTitle(t).$1 : t;
      case 'title2':
        return t == null ? 'تتمة العنوان' : splitTitle(t).$2;
      case 'speaker_name':
        return c == null ? 'اسم المتحدث' : c.speakerName;
      case 'speaker_role':
        return c == null ? 'صفة المتحدث' : c.speakerRole;
    }
    return null;
  }

  /// تغيير مصدر العنوان وتحديث طبقة العنوان مباشرة.
  void setTitleSource(TitleSource s) {
    titleSource = s;
    for (final l in layers.where((l) => l.role == 'title' || l.role == 'title2')) {
      final text = _textFor(l.role);
      if (text != null) setLayerText(l, text);
    }
    notifyListeners();
  }

  void setTemplate(TemplateDef t) {
    template = t;
    final videoCover = document?.category.isVideoCover ?? false;
    layers = t.layers
        // غلاف الريل/اليوتيوب لا يحمل شارة النوع.
        .where((l) => !(videoCover && l.role == 'label'))
        .map((l) => l.copy())
        .toList();
    // الشارة (آخر خبر، عاجل...) جزء من القالب نفسه؛ باقي الأدوار تُملأ من الخبر.
    for (final l in layers) {
      final text = _textFor(l.role);
      if (text != null) l.text = text;
      fitText(l);
    }
    selected = null;
    notifyListeners();
  }

  void update() => notifyListeners();

  /// يصغّر الخط (حتى 40% من حجمه) حتى يدخل النص في [TextLayer.maxHeight].
  static void fitText(TextLayer l) {
    final max = l.maxHeight;
    if (max == null || l.text.trim().isEmpty) return;
    final floor = l.fontSize * 0.4;
    while (rectOf(l).height > max && l.fontSize > floor) {
      l.fontSize = (l.fontSize * 0.95).floorToDouble();
    }
  }

  /// تعيين نص طبقة من الاقتراحات مع الملاءمة التلقائية.
  void setLayerText(TextLayer l, String text) {
    l.text = text;
    final base = template?.layers.where((t) => t.role == l.role).firstOrNull;
    if (base != null && l.maxHeight != null) l.fontSize = base.fontSize;
    fitText(l);
    notifyListeners();
  }

  void select(int? index) {
    selected = index;
    notifyListeners();
  }

  // ---------- طبقات النص ----------

  void addTextLayer() {
    final s = size;
    layers.add(
      TextLayer(
        role: 'custom',
        text: 'نص جديد',
        x: s.width * 0.1,
        y: s.height * 0.45,
        width: s.width * 0.8,
        fontSize: (unit * 0.05).roundToDouble(),
        color: BrandColors.primary,
      ),
    );
    selected = layers.length - 1;
    notifyListeners();
  }

  void duplicateSelected() {
    final l = selectedLayer;
    if (l == null) return;
    layers.add(
      l.copy()
        ..role = 'custom'
        ..y = l.y + l.fontSize * 1.5,
    );
    selected = layers.length - 1;
    notifyListeners();
  }

  void deleteSelected() {
    if (selectedLayer == null) return;
    layers.removeAt(selected!);
    selected = null;
    notifyListeners();
  }

  void nudge(Offset d) {
    final l = selectedLayer;
    if (l == null) return;
    l
      ..x += d.dx
      ..y += d.dy;
    notifyListeners();
  }

  void centerHorizontally() {
    final l = selectedLayer;
    if (l == null) return;
    l.x = (size.width - l.width) / 2;
    notifyListeners();
  }

  static const _hPad = 0.3, _vPad = 0.12;

  static EdgeInsets padding(TextLayer l) =>
      EdgeInsets.symmetric(horizontal: l.fontSize * _hPad, vertical: l.fontSize * _vPad);

  static TextDirection directionOf(String text) {
    final m = RegExp(r'[A-Za-zÀ-ÿ؀-ۿ]').firstMatch(text);
    return m == null || RegExp(r'[؀-ۿ]').hasMatch(m[0]!) ? TextDirection.rtl : TextDirection.ltr;
  }

  static TextStyle style(TextLayer l) => TextStyle(
    fontFamily: appFont,
    fontSize: l.fontSize,
    color: l.color,
    height: l.lineHeight,
    fontWeight: l.bold ? FontWeight.bold : FontWeight.normal,
    shadows: l.shadow
        ? [
            Shadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: l.fontSize * 0.15,
              offset: Offset(0, l.fontSize * 0.05),
            ),
          ]
        : null,
  );

  /// المستطيل الذي تشغله الطبقة (لاختيارها باللمس).
  static Rect rectOf(TextLayer l) {
    final pad = padding(l);
    final tp = TextPainter(
      text: TextSpan(text: l.text.isEmpty ? ' ' : l.text, style: style(l)),
      textDirection: directionOf(l.text),
      textAlign: l.align,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: math.max(1, l.width - pad.horizontal));
    final r = Rect.fromLTWH(l.x, l.y, l.width, tp.height + pad.vertical);
    tp.dispose();
    return r;
  }

  int? layerAt(Offset p) {
    for (var i = layers.length - 1; i >= 0; i--) {
      if (rectOf(layers[i]).inflate(unit * 0.01).contains(p)) return i;
    }
    return null;
  }

  // ---------- الخلفية ----------

  void setBackground(String? path) {
    backgroundPath = path;
    resetBackground();
  }

  void resetBackground() {
    bgOffset = Offset.zero;
    bgScale = 1;
    notifyListeners();
  }
}
