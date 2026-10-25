import 'dart:io';

import 'package:flutter/material.dart';

import 'news_category.dart';

enum BoxStyle { none, outline, filled }

/// طبقة نص فوق القالب. كل القياسات بوحدات بكسل القالب الأصلي.
class TextLayer {
  TextLayer({
    required this.role,
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.fontSize,
    this.color = Colors.white,
    this.align = TextAlign.center,
    this.bold = true,
    this.shadow = false,
    this.lineHeight = 1.35,
    this.box = BoxStyle.none,
    this.boxColor = Colors.white,
    this.maxHeight,
  });

  /// label = شارة النوع (آخر خبر، هام...)، title = عنوان الخبر، custom = نص حر.
  String role;
  String text;
  double x;
  double y;
  double width;
  double fontSize;
  Color color;
  TextAlign align;
  bool bold;
  bool shadow;
  double lineHeight;
  BoxStyle box;
  Color boxColor;

  /// أقصى ارتفاع للمنطقة المخصصة للنص في القالب؛ يُصغَّر الخط تلقائياً ليبقى ضمنها.
  double? maxHeight;

  TextLayer copy() => TextLayer.fromJson(toJson());

  factory TextLayer.fromJson(Map<String, dynamic> j) => TextLayer(
    role: (j['role'] ?? 'custom') as String,
    text: (j['text'] ?? '') as String,
    x: (j['x'] as num).toDouble(),
    y: (j['y'] as num).toDouble(),
    width: (j['width'] as num).toDouble(),
    fontSize: (j['fontSize'] as num).toDouble(),
    color: parseColor(j['color'] as String?) ?? Colors.white,
    align: TextAlign.values.asNameMap()[j['align']] ?? TextAlign.center,
    bold: j['bold'] != false,
    shadow: j['shadow'] == true,
    lineHeight: (j['lineHeight'] as num?)?.toDouble() ?? 1.35,
    box: BoxStyle.values.asNameMap()[j['box']] ?? BoxStyle.none,
    boxColor: parseColor(j['boxColor'] as String?) ?? Colors.white,
    maxHeight: (j['maxHeight'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'role': role,
    'text': text,
    'x': x,
    'y': y,
    'width': width,
    'fontSize': fontSize,
    'color': colorHex(color),
    'align': align.name,
    'bold': bold,
    'shadow': shadow,
    'lineHeight': lineHeight,
    'box': box.name,
    'boxColor': colorHex(boxColor),
    'maxHeight': ?maxHeight,
  };
}

Color? parseColor(String? hex) {
  if (hex == null) return null;
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

String colorHex(Color c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

/// قالب بصري: ملف PNG (شفاف غالباً) + طبقات النص الافتراضية.
class TemplateDef {
  TemplateDef({
    required this.id,
    required this.name,
    required this.categories,
    required this.width,
    required this.height,
    required this.layers,
    this.asset,
    this.filePath,
  });

  final String id;
  String name;
  List<NewsCategory> categories;
  final int width;
  final int height;
  List<TextLayer> layers;

  /// قالب مضمّن في التطبيق.
  final String? asset;

  /// قالب أضافه المستخدم من الإعدادات.
  final String? filePath;

  bool get isUserTemplate => filePath != null;

  String get sizeLabel => '$width×$height';

  ImageProvider get image => asset != null ? AssetImage(asset!) : FileImage(File(filePath!)) as ImageProvider;

  factory TemplateDef.fromJson(Map<String, dynamic> j, {String? assetDir}) => TemplateDef(
    id: j['id'] as String,
    name: j['name'] as String,
    categories: (j['categories'] as List? ?? const []).map((e) => NewsCategory.fromName(e as String)).toList(),
    width: (j['width'] as num).toInt(),
    height: (j['height'] as num).toInt(),
    layers: (j['layers'] as List? ?? const [])
        .map((e) => TextLayer.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    asset: assetDir != null ? '$assetDir/${j['file']}' : null,
    filePath: assetDir == null ? j['path'] as String? : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'categories': categories.map((c) => c.name).toList(),
    'width': width,
    'height': height,
    'layers': layers.map((l) => l.toJson()).toList(),
    'path': ?filePath,
  };
}
