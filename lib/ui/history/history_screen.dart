import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/history_repository.dart';
import '../result/result_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<HistoryRepository>();
    final items = repo.search(_query);
    final fmt = DateFormat('yyyy/MM/dd – HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('السجل')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث في الأخبار السابقة'),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('لا توجد أخبار محفوظة'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final d = items[i];
                      return Dismissible(
                        key: ValueKey(d.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: AlignmentDirectional.centerEnd,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          color: Theme.of(context).colorScheme.errorContainer,
                          child: const Icon(Icons.delete),
                        ),
                        confirmDismiss: (_) => showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('حذف هذا الخبر من السجل؟'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
                            ],
                          ),
                        ),
                        onDismissed: (_) => repo.delete(d.id),
                        child: Card(
                          child: ListTile(
                            title: Text(d.ar.headline, maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              '${d.category.label} · ${fmt.format(d.createdAt)}${d.fr != null ? ' · FR' : ''}',
                            ),
                            trailing: const Icon(Icons.chevron_left),
                            onTap: () =>
                                Navigator.of(context)
                                    .push(MaterialPageRoute(builder: (_) => ResultScreen(document: d))),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
