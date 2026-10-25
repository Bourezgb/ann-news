import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/news_result.dart';

/// سجل الأخبار المُنتَجة، محفوظ محلياً في ملف JSON.
class HistoryRepository extends ChangeNotifier {
  HistoryRepository._(this._file, this._items);

  final File _file;
  final List<NewsDocument> _items;

  static Future<HistoryRepository> load() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'history.json'));
    final items = <NewsDocument>[];
    if (await file.exists()) {
      try {
        final list = jsonDecode(await file.readAsString()) as List;
        for (final e in list) {
          try {
            items.add(NewsDocument.fromJson(Map<String, dynamic>.from(e as Map)));
          } catch (_) {}
        }
      } catch (_) {}
    }
    return HistoryRepository._(file, items);
  }

  List<NewsDocument> get items => List.unmodifiable(_items);

  List<NewsDocument> search(String query) {
    final q = query.trim();
    if (q.isEmpty) return items;
    return _items.where((d) {
      final hay = [d.ar.headline, d.ar.caption, d.ar.source, d.ar.speakerName, ...d.ar.points].join(' ');
      return hay.contains(q);
    }).toList();
  }

  Future<void> save(NewsDocument doc) async {
    final i = _items.indexWhere((d) => d.id == doc.id);
    i >= 0 ? _items[i] = doc : _items.insert(0, doc);
    await _persist();
  }

  Future<void> delete(String id) async {
    _items.removeWhere((d) => d.id == id);
    await _persist();
  }

  Future<void> _persist() async {
    notifyListeners();
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(_items.map((d) => d.toJson()).toList()));
    await tmp.rename(_file.path);
  }
}
