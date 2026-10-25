import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/speaker_repository.dart';

class SpeakersScreen extends StatelessWidget {
  const SpeakersScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final name = TextEditingController();
    final role = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('شخصية جديدة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'الاسم'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: role,
              decoration: const InputDecoration(labelText: 'المهنة / الصفة'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true && context.mounted) await context.read<SpeakerRepository>().remember(name.text, role.text);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<SpeakerRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('الشخصيات المحفوظة')),
      floatingActionButton: FloatingActionButton(onPressed: () => _add(context), child: const Icon(Icons.person_add)),
      body: repo.items.isEmpty
          ? const Center(child: Text('تُحفظ الشخصيات تلقائياً عند استعمالها في التصريحات'))
          : ListView(
              children: [
                for (final s in repo.items)
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(s.name),
                    subtitle: Text(s.role),
                    trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => repo.remove(s)),
                  ),
              ],
            ),
    );
  }
}
