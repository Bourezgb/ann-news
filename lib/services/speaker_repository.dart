import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Speaker {
  const Speaker(this.name, this.role);

  final String name;
  final String role;

  Map<String, String> toJson() => {'name': name, 'role': role};
}

/// قائمة الشخصيات المتكررة لاختيارها بسرعة في التصريحات.
class SpeakerRepository extends ChangeNotifier {
  SpeakerRepository._(this._prefs, this._items);

  final SharedPreferences _prefs;
  final List<Speaker> _items;

  static Future<SpeakerRepository> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('speakers');
    final items = <Speaker>[];
    if (raw != null) {
      for (final e in jsonDecode(raw) as List) {
        final m = e as Map;
        items.add(Speaker(m['name'] as String, m['role'] as String));
      }
    }
    return SpeakerRepository._(prefs, items);
  }

  List<Speaker> get items => List.unmodifiable(_items);

  /// يضيف الشخصية أو يحدّث صفتها، ويضعها في أعلى القائمة.
  Future<void> remember(String name, String role) async {
    name = name.trim();
    role = role.trim();
    if (name.isEmpty || role.isEmpty) return;
    _items.removeWhere((s) => s.name == name);
    _items.insert(0, Speaker(name, role));
    await _persist();
  }

  Future<void> remove(Speaker s) async {
    _items.remove(s);
    await _persist();
  }

  Future<void> _persist() async {
    notifyListeners();
    await _prefs.setString('speakers', jsonEncode(_items.map((s) => s.toJson()).toList()));
  }
}
