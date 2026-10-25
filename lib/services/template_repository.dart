import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/news_category.dart';
import '../models/template_def.dart';

/// القوالب المضمّنة (assets/templates) + القوالب التي يضيفها المستخدم.
///
/// المواضع التي يحفظها المحرر كافتراضية لأي قالب تُخزَّن كتعديلات فوقه.
class TemplateRepository extends ChangeNotifier {
  TemplateRepository._(this._dir, this._prefs, this._bundled, this._user);

  static const _assetDir = 'assets/templates';

  final Directory _dir;
  final SharedPreferences _prefs;
  final List<TemplateDef> _bundled;
  final List<TemplateDef> _user;

  static Future<TemplateRepository> load() async {
    final prefs = await SharedPreferences.getInstance();
    final manifest = jsonDecode(await rootBundle.loadString('$_assetDir/templates.json')) as Map;
    final bundled = (manifest['templates'] as List)
        .map((e) => TemplateDef.fromJson(Map<String, dynamic>.from(e as Map), assetDir: _assetDir))
        .toList();

    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'templates'));
    await dir.create(recursive: true);
    final user = <TemplateDef>[];
    final f = File(p.join(dir.path, 'user_templates.json'));
    if (await f.exists()) {
      for (final e in jsonDecode(await f.readAsString()) as List) {
        final t = TemplateDef.fromJson(Map<String, dynamic>.from(e as Map));
        if (File(t.filePath!).existsSync()) user.add(t);
      }
    }
    final repo = TemplateRepository._(dir, prefs, bundled, user);
    repo._applyLayoutOverrides();
    return repo;
  }

  List<TemplateDef> get all => [..._user, ..._bundled];

  List<TemplateDef> get userTemplates => List.unmodifiable(_user);

  /// القوالب المناسبة لنوع الخبر أولاً ثم البقية.
  List<TemplateDef> forCategory(NewsCategory? c) {
    if (c == null) return all;
    final list = all;
    return [...list.where((t) => t.categories.contains(c)), ...list.where((t) => !t.categories.contains(c))];
  }

  Future<TemplateDef> importTemplate(File source, String name, List<NewsCategory> categories) async {
    final bytes = await source.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    final w = image.width, h = image.height;
    image.dispose();

    final id = const Uuid().v4();
    final dest = File(p.join(_dir.path, '$id${p.extension(source.path).isEmpty ? '.png' : p.extension(source.path)}'));
    await dest.writeAsBytes(bytes);
    final u = w < h ? w : h;
    final t = TemplateDef(
      id: id,
      name: name,
      categories: categories,
      width: w,
      height: h,
      filePath: dest.path,
      layers: [
        TextLayer(
          role: 'title',
          text: '',
          x: w * 0.06,
          y: h * 0.70,
          width: w * 0.88,
          fontSize: (u * 0.058).roundToDouble(),
          maxHeight: h * 0.22,
          color: const ui.Color(0xFFB61A1B),
        ),
      ],
    );
    _user.insert(0, t);
    await _persist();
    return t;
  }

  Future<void> update(TemplateDef t) async {
    await _persist();
  }

  Future<void> delete(TemplateDef t) async {
    _user.removeWhere((e) => e.id == t.id);
    await _prefs.remove('layout_${t.id}');
    try {
      await File(t.filePath!).delete();
    } catch (_) {}
    await _persist();
  }

  /// حفظ مواضع الطبقات الحالية كافتراضية لهذا القالب.
  Future<void> saveLayout(TemplateDef t, List<TextLayer> layers) async {
    t.layers = layers.map((l) => l.copy()..text = l.role == 'label' ? l.text : '').toList();
    await _prefs.setString('layout_${t.id}', jsonEncode(t.layers.map((l) => l.toJson()).toList()));
    notifyListeners();
  }

  void _applyLayoutOverrides() {
    for (final t in all) {
      final raw = _prefs.getString('layout_${t.id}');
      if (raw == null) continue;
      try {
        t.layers = (jsonDecode(raw) as List)
            .map((e) => TextLayer.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      } catch (_) {}
    }
  }

  Future<void> _persist() async {
    notifyListeners();
    await File(p.join(_dir.path, 'user_templates.json'))
        .writeAsString(jsonEncode(_user.map((t) => t.toJson()).toList()));
  }
}
