import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/template_def.dart';
import 'editor_controller.dart';

const _palette = <Color>[
  BrandColors.primary,
  BrandColors.primaryDark,
  BrandColors.logoRed,
  BrandColors.orange,
  Colors.white,
  Colors.black,
  Color(0xFF333333),
  Color(0xFFFFD54F),
  BrandColors.grey,
];

/// أدوات التحكم أسفل اللوحة حسب العنصر المحدد.
class ToolPanel extends StatelessWidget {
  const ToolPanel({super.key, required this.controller, required this.onEditText, required this.onPickBackground});

  final EditorController controller;
  final void Function(TextLayer) onEditText;
  final Future<void> Function({bool camera}) onPickBackground;

  EditorController get c => controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final l = c.selectedLayer;
        final child = l != null
            ? _textTools(context, l)
            : c.selected == -1
            ? _backgroundTools(context)
            : _idle(context);
        return Material(
          elevation: 8,
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: SafeArea(top: false, child: SizedBox(height: 250, child: child)),
        );
      },
    );
  }

  Widget _idle(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        'المس نصاً لتحديده وتحريكه (بإصبعين لتكبيره)، أو المس الخلفية لتحريك الصورة وتكبيرها. انقر مرتين على النص لتعديله.',
        style: TextStyle(color: Theme.of(context).colorScheme.outline),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.tonalIcon(
            onPressed: c.addTextLayer,
            icon: const Icon(Icons.text_fields),
            label: const Text('إضافة نص'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => onPickBackground(),
            icon: const Icon(Icons.image_outlined),
            label: Text(c.backgroundPath == null ? 'اختيار خلفية' : 'تغيير الخلفية'),
          ),
          if (c.backgroundPath != null)
            OutlinedButton.icon(
              onPressed: () => c.select(-1),
              icon: const Icon(Icons.open_with),
              label: const Text('ضبط الخلفية'),
            ),
        ],
      ),
    ],
  );

  Widget _textTools(BuildContext context, TextLayer l) {
    final u = c.unit;
    final content = c.content;
    final suggestions = content == null
        ? const <String>[]
        : {
            ?c.designTitle,
            if (c.document!.category.isVideoCover) ...[
              ...content.thumbnailsSerious,
              ...content.thumbnailsInteractive,
              content.headline,
            ] else ...[
              ...content.headlinesSerious,
              ...content.headlinesInteractive,
              content.thumbnail,
            ],
            if (c.document!.category.isStatement && content.speakerName.isNotEmpty) content.speakerName,
            c.document!.category.label,
          }.where((s) => s.trim().isNotEmpty).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onEditText(l),
                icon: const Icon(Icons.edit),
                label: Text(l.text.isEmpty ? 'كتابة النص' : l.text, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            IconButton(tooltip: 'نسخة', onPressed: c.duplicateSelected, icon: const Icon(Icons.copy)),
            IconButton(tooltip: 'حذف', onPressed: c.deleteSelected, icon: const Icon(Icons.delete_outline)),
            IconButton(tooltip: 'إلغاء التحديد', onPressed: () => c.select(null), icon: const Icon(Icons.done)),
          ],
        ),
        if (suggestions.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final s in suggestions)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ActionChip(label: Text(s), onPressed: () => c.setLayerText(l, s)),
                  ),
              ],
            ),
          ),
        _slider('حجم الخط', l.fontSize, u * 0.01, u * 0.3, (v) => l.fontSize = v),
        _slider('عرض المربع', l.width, u * 0.1, c.size.width * 1.2, (v) => l.width = v),
        _slider('تباعد الأسطر', l.lineHeight, 0.8, 2.2, (v) => l.lineHeight = v, decimals: 2),
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<TextAlign>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: TextAlign.right, icon: Icon(Icons.format_align_right)),
                ButtonSegment(value: TextAlign.center, icon: Icon(Icons.format_align_center)),
                ButtonSegment(value: TextAlign.left, icon: Icon(Icons.format_align_left)),
                ButtonSegment(value: TextAlign.justify, icon: Icon(Icons.format_align_justify)),
              ],
              selected: {l.align},
              onSelectionChanged: (s) {
                l.align = s.first;
                c.update();
              },
            ),
            _toggle(Icons.format_bold, 'عريض', l.bold, () => l.bold = !l.bold),
            _toggle(Icons.blur_on, 'ظل', l.shadow, () => l.shadow = !l.shadow),
            IconButton(
              tooltip: 'توسيط أفقي',
              onPressed: c.centerHorizontally,
              icon: const Icon(Icons.vertical_align_center, textDirection: TextDirection.ltr),
            ),
          ],
        ),
        Row(
          children: [
            const Text('تحريك دقيق:'),
            IconButton(onPressed: () => c.nudge(Offset(0, -u * 0.004)), icon: const Icon(Icons.arrow_upward)),
            IconButton(onPressed: () => c.nudge(Offset(0, u * 0.004)), icon: const Icon(Icons.arrow_downward)),
            IconButton(
              onPressed: () => c.nudge(Offset(u * 0.004, 0)),
              icon: const Icon(Icons.arrow_forward, textDirection: TextDirection.ltr),
            ),
            IconButton(
              onPressed: () => c.nudge(Offset(-u * 0.004, 0)),
              icon: const Icon(Icons.arrow_back, textDirection: TextDirection.ltr),
            ),
          ],
        ),
        _colors('لون النص', l.color, (col) => l.color = col),
        Row(
          children: [
            const Text('إطار:'),
            const SizedBox(width: 8),
            SegmentedButton<BoxStyle>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: BoxStyle.none, label: Text('بدون')),
                ButtonSegment(value: BoxStyle.outline, label: Text('محيط')),
                ButtonSegment(value: BoxStyle.filled, label: Text('معبأ')),
              ],
              selected: {l.box},
              onSelectionChanged: (s) {
                l.box = s.first;
                c.update();
              },
            ),
          ],
        ),
        if (l.box != BoxStyle.none) _colors('لون الإطار', l.boxColor, (col) => l.boxColor = col),
      ],
    );
  }

  Widget _backgroundTools(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          FilledButton.tonalIcon(
            onPressed: () => onPickBackground(),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('المعرض'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => onPickBackground(camera: true),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('الكاميرا'),
          ),
          OutlinedButton.icon(
            onPressed: c.resetBackground,
            icon: const Icon(Icons.center_focus_strong),
            label: const Text('إعادة الضبط'),
          ),
          OutlinedButton.icon(
            onPressed: () => c.setBackground(null),
            icon: const Icon(Icons.hide_image_outlined),
            label: const Text('إزالة'),
          ),
          IconButton(tooltip: 'تم', onPressed: () => c.select(null), icon: const Icon(Icons.done)),
        ],
      ),
      const SizedBox(height: 6),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('ملء القالب')),
          ButtonSegment(value: true, label: Text('الصورة كاملة')),
        ],
        selected: {c.bgContain},
        onSelectionChanged: (s) {
          c.bgContain = s.first;
          c.update();
        },
      ),
      _slider('التكبير', c.bgScale, 0.2, 5, (v) => c.bgScale = v, decimals: 2),
      _colors('لون ما خلف الصورة', c.bgColor, (col) => c.bgColor = col),
    ],
  );

  Widget _slider(String label, double value, double min, double max, ValueChanged<double> set, {int decimals = 0}) =>
      Row(
        children: [
          SizedBox(width: 90, child: Text(label)),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: (v) {
                set(v);
                c.update();
              },
            ),
          ),
          SizedBox(width: 48, child: Text(value.toStringAsFixed(decimals), textAlign: TextAlign.center)),
        ],
      );

  Widget _toggle(IconData icon, String tip, bool on, VoidCallback flip) => IconButton(
    tooltip: tip,
    isSelected: on,
    style: IconButton.styleFrom(backgroundColor: on ? BrandColors.primary.withValues(alpha: 0.25) : null),
    onPressed: () {
      flip();
      c.update();
    },
    icon: Icon(icon),
  );

  Widget _colors(String label, Color current, ValueChanged<Color> set) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(width: 90, child: Text(label)),
        Expanded(
          child: SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final col in _palette)
                  GestureDetector(
                    onTap: () {
                      set(col);
                      c.update();
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: col,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: col.toARGB32() == current.toARGB32() ? Colors.lightBlueAccent : Colors.grey,
                          width: col.toARGB32() == current.toARGB32() ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
