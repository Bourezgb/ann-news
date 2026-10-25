import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai/gemini_client.dart';
import 'ai/gemini_news_service.dart';
import 'ai/news_ai_service.dart';

class SettingsService extends ChangeNotifier {
  SettingsService._(this._prefs, this._secure, this._apiKey);

  static const defaultModel = 'gemini-flash-latest';

  /// تُجرَّب بالترتيب عند انشغال النموذج الأساسي (النماذج غير الموجودة تُتخطى تلقائياً).
  static const defaultFallbackModels = ['gemini-2.5-flash', 'gemini-flash-lite-latest', 'gemini-2.5-flash-lite'];

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;
  String _apiKey;

  static Future<SettingsService> load() async {
    const secure = FlutterSecureStorage();
    final prefs = await SharedPreferences.getInstance();
    String key;
    try {
      key = await secure.read(key: 'gemini_api_key') ?? '';
    } catch (_) {
      key = '';
    }
    return SettingsService._(prefs, secure, key);
  }

  String get apiKey => _apiKey;
  bool get hasApiKey => _apiKey.trim().isNotEmpty;

  Future<void> setApiKey(String value) async {
    _apiKey = value.trim();
    await _secure.write(key: 'gemini_api_key', value: _apiKey);
    notifyListeners();
  }

  String get model => _prefs.getString('model') ?? defaultModel;

  Future<void> setModel(String value) async {
    await _prefs.setString('model', value.trim().isEmpty ? defaultModel : value.trim());
    notifyListeners();
  }

  List<String> get fallbackModels => _prefs.getStringList('fallback_models') ?? defaultFallbackModels;

  Future<void> setFallbackModels(List<String> models) async {
    await _prefs.setStringList('fallback_models', models.map((m) => m.trim()).where((m) => m.isNotEmpty).toList());
    notifyListeners();
  }

  /// null = تلقائي.
  double? get temperatureOverride => _prefs.getDouble('temperature');

  Future<void> setTemperatureOverride(double? value) async {
    value == null ? await _prefs.remove('temperature') : await _prefs.setDouble('temperature', value);
    notifyListeners();
  }

  /// في الوضع التلقائي: حرارة منخفضة لنماذج الجيلين 1 و 2، والقيمة الافتراضية
  /// للنماذج الأحدث (توصي Google بعدم خفضها في الجيل 3 لتفادي التكرار).
  double? get effectiveTemperature => temperatureOverride ?? (RegExp(r'gemini-[12]\.').hasMatch(model) ? 0.2 : null);

  ThemeMode get themeMode => ThemeMode.values.byName(_prefs.getString('theme') ?? ThemeMode.system.name);

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString('theme', mode.name);
    notifyListeners();
  }

  bool get defaultWeAreSource => _prefs.getBool('we_are_source') ?? false;

  Future<void> setDefaultWeAreSource(bool v) async {
    await _prefs.setBool('we_are_source', v);
    notifyListeners();
  }

  GeminiClient createClient({String? model}) =>
      GeminiClient(apiKey: _apiKey, model: model ?? this.model, fallbackModels: fallbackModels);

  NewsAiService createAiService() => GeminiNewsService(createClient(), temperature: effectiveTemperature);
}
