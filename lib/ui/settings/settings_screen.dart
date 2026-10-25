import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/ai/gemini_client.dart';
import '../../services/settings_service.dart';
import '../common/feedback.dart';
import 'speakers_screen.dart';
import 'templates_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _key = TextEditingController(text: context.read<SettingsService>().apiKey);
  late final _model = TextEditingController(text: context.read<SettingsService>().model);
  late final _fallbacks = TextEditingController(text: context.read<SettingsService>().fallbackModels.join('، '));
  bool _obscure = true;
  bool _loadingModels = false;

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    _fallbacks.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    await context.read<SettingsService>().setApiKey(_key.text);
    if (mounted) showMessage(context, 'تم حفظ المفتاح');
  }

  Future<void> _chooseModel() async {
    final settings = context.read<SettingsService>();
    if (_key.text.trim() != settings.apiKey) await settings.setApiKey(_key.text);
    if (!settings.hasApiKey) {
      if (mounted) showMessage(context, 'أدخل مفتاح API أولاً', error: true);
      return;
    }
    setState(() => _loadingModels = true);
    try {
      final client = settings.createClient();
      final models = await client.listModels();
      client.close();
      if (!mounted) return;
      final picked = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => FractionallySizedBox(
          heightFactor: 0.8,
          child: ListView(
            children: [
              for (final m in models)
                ListTile(
                  title: Text(m.id, textDirection: TextDirection.ltr),
                  subtitle: Text(m.displayName, textDirection: TextDirection.ltr),
                  selected: m.id == settings.model,
                  onTap: () => Navigator.pop(ctx, m.id),
                ),
            ],
          ),
        ),
      );
      if (picked != null) {
        _model.text = picked;
        await settings.setModel(picked);
      }
    } on GeminiException catch (e) {
      if (mounted) showMessage(context, e.fullMessage, error: true);
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _saveFallbacks(SettingsService s, String text) async {
    await s.setFallbackModels(text.split(RegExp(r'[,،\s]+')));
    if (mounted) showMessage(context, 'تم حفظ النماذج الاحتياطية');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _Title('Gemini API'),
          TextField(
            controller: _key,
            obscureText: _obscure,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'مفتاح API',
              helperText: 'يُحفظ مشفّراً على هذا الجهاز فقط',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _saveKey(),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(onPressed: _saveKey, child: const Text('حفظ المفتاح')),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _model,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'النموذج',
              helperText: 'gemini-flash-latest يتحدّث تلقائياً إلى أحدث نموذج Flash',
            ),
            onSubmitted: (v) => s.setModel(v),
          ),
          Row(
            children: [
              TextButton.icon(
                onPressed: _loadingModels ? null : _chooseModel,
                icon: _loadingModels
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.list),
                label: const Text('اختيار من النماذج المتاحة'),
              ),
              const Spacer(),
              TextButton(onPressed: () => s.setModel(_model.text), child: const Text('حفظ')),
              TextButton(
                onPressed: () {
                  _model.text = SettingsService.defaultModel;
                  s.setModel(SettingsService.defaultModel);
                },
                child: const Text('افتراضي'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _fallbacks,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'نماذج احتياطية (مفصولة بفاصلة)',
              helperText: 'تُستعمل تلقائياً إذا كان النموذج الأساسي مشغولاً أو تجاوز حده',
              helperMaxLines: 2,
            ),
            onSubmitted: (v) => _saveFallbacks(s, v),
          ),
          Row(
            children: [
              const Spacer(),
              TextButton(onPressed: () => _saveFallbacks(s, _fallbacks.text), child: const Text('حفظ')),
              TextButton(
                onPressed: () {
                  _fallbacks.text = SettingsService.defaultFallbackModels.join('، ');
                  s.setFallbackModels(SettingsService.defaultFallbackModels);
                },
                child: const Text('افتراضي'),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('ضبط الحرارة يدوياً'),
            subtitle: Text(
              s.temperatureOverride == null
                  ? 'تلقائي (${s.effectiveTemperature?.toString() ?? 'افتراضي النموذج'})'
                  : 'قيمة منخفضة = دقة والتزام أعلى بالمصدر',
            ),
            value: s.temperatureOverride != null,
            onChanged: (v) => s.setTemperatureOverride(v ? 0.2 : null),
          ),
          if (s.temperatureOverride != null)
            Slider(
              value: s.temperatureOverride!,
              max: 1,
              divisions: 20,
              label: s.temperatureOverride!.toStringAsFixed(2),
              onChanged: (v) => s.setTemperatureOverride(v),
            ),
          const Divider(height: 32),
          const _Title('عام'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('«نحن مصدر الخبر» مفعّل افتراضياً'),
            value: s.defaultWeAreSource,
            onChanged: s.setDefaultWeAreSource,
          ),
          const SizedBox(height: 8),
          const Text('المظهر'),
          const SizedBox(height: 6),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('تلقائي')),
              ButtonSegment(value: ThemeMode.light, label: Text('فاتح')),
              ButtonSegment(value: ThemeMode.dark, label: Text('ليلي')),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (v) => s.setThemeMode(v.first),
          ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.dashboard_customize_outlined),
            title: const Text('إدارة القوالب'),
            subtitle: const Text('إضافة قوالب PNG جديدة وحذفها'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TemplatesScreen())),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.people_outline),
            title: const Text('الشخصيات المحفوظة'),
            subtitle: const Text('للتصريحات'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SpeakersScreen())),
          ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
    ),
  );
}
