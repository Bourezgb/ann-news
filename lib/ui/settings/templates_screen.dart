import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/news_category.dart';
import '../../services/media_picker.dart';
import '../../services/template_repository.dart';
import '../common/feedback.dart';

class TemplatesScreen extends StatelessWidget {
  const TemplatesScreen({super.key});

  Future<void> _import(BuildContext context) async {
    final file = await MediaPicker.pickTemplateFile();
    if (file == null || !context.mounted) return;
    final result = await _editDialog(context, name: file.uri.pathSegments.last.split('.').first, categories: {});
    if (result == null || !context.mounted) return;
    final t = await context.read<TemplateRepository>().importTemplate(file, result.$1, result.$2.toList());
    if (context.mounted) showMessage(context, 'تمت إضافة القالب (${t.sizeLabel})');
  }

  Future<(String, Set<NewsCategory>)?> _editDialog(
    BuildContext context, {
    required String name,
    required Set<NewsCategory> categories,
  }) {
    final ctl = TextEditingController(text: name);
    final selected = {...categories};
    return showDialog<(String, Set<NewsCategory>)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('بيانات القالب'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctl,
                decoration: const InputDecoration(labelText: 'اسم القالب'),
              ),
              const SizedBox(height: 12),
              const Text('يُقترح لأنواع:'),
              Wrap(
                spacing: 6,
                children: [
                  for (final c in NewsCategory.selectable)
                    FilterChip(
                      label: Text(c.label),
                      selected: selected.contains(c),
                      onSelected: (v) => setState(() => v ? selected.add(c) : selected.remove(c)),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, (ctl.text.trim().isEmpty ? 'قالب' : ctl.text.trim(), selected)),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<TemplateRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة القوالب')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _import(context),
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('إضافة قالب PNG'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          for (final t in repo.all)
            ListTile(
              leading: Container(
                width: 56,
                height: 56,
                color: Colors.blueGrey.shade300,
                child: Image(image: ResizeImage(t.image, width: 160), fit: BoxFit.contain),
              ),
              title: Text(t.name),
              subtitle: Text(
                '${t.sizeLabel} · ${t.categories.map((c) => c.label).join('، ')}'
                '${t.isUserTemplate ? '' : ' · مضمّن'}',
              ),
              trailing: t.isUserTemplate
                  ? PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'delete') {
                          await repo.delete(t);
                        } else {
                          final r = await _editDialog(context, name: t.name, categories: t.categories.toSet());
                          if (r != null) {
                            t
                              ..name = r.$1
                              ..categories = r.$2.toList();
                            await repo.update(t);
                          }
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('تعديل')),
                        PopupMenuItem(value: 'delete', child: Text('حذف')),
                      ],
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}
