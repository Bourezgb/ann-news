import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/news_category.dart';
import '../../models/template_def.dart';
import '../../services/template_repository.dart';

enum _Shape { all, square, landscape, portrait }

Future<TemplateDef?> pickTemplate(BuildContext context, {NewsCategory? category}) => showModalBottomSheet<TemplateDef>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => FractionallySizedBox(heightFactor: 0.85, child: _Picker(category: category)),
);

class _Picker extends StatefulWidget {
  const _Picker({this.category});

  final NewsCategory? category;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  _Shape _shape = _Shape.all;

  bool _matches(TemplateDef t) => switch (_shape) {
    _Shape.all => true,
    _Shape.square => t.width == t.height,
    _Shape.landscape => t.width > t.height,
    _Shape.portrait => t.width < t.height,
  };

  @override
  Widget build(BuildContext context) {
    final list = context.watch<TemplateRepository>().forCategory(widget.category).where(_matches).toList();
    return Column(
      children: [
        Text('اختيار القالب', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<_Shape>(
          segments: const [
            ButtonSegment(value: _Shape.all, label: Text('الكل')),
            ButtonSegment(value: _Shape.square, label: Text('مربع')),
            ButtonSegment(value: _Shape.landscape, label: Text('أفقي')),
            ButtonSegment(value: _Shape.portrait, label: Text('عمودي')),
          ],
          selected: {_shape},
          onSelectionChanged: (s) => setState(() => _shape = s.first),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.78,
            ),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final t = list[i];
              final suited = widget.category != null && t.categories.contains(widget.category);
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.pop(context, t),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: suited
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: suited ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          color: Colors.blueGrey.shade300,
                          padding: const EdgeInsets.all(6),
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: t.width / t.height,
                              child: Image(image: ResizeImage(t.image, width: 300), fit: BoxFit.contain),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          children: [
                            Text(
                              t.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              t.sizeLabel,
                              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
