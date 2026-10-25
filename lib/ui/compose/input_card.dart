import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/news_input.dart';

class InputCard extends StatelessWidget {
  const InputCard({super.key, required this.input, required this.onRemove});

  final NewsInput input;
  final VoidCallback onRemove;

  IconData get _icon => switch (input.kind) {
    InputKind.text => Icons.notes,
    InputKind.url => Icons.link,
    InputKind.youtube => Icons.smart_display_outlined,
    InputKind.image => Icons.image_outlined,
    InputKind.audio => Icons.graphic_eq,
    InputKind.video => Icons.movie_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final leading = input.kind == InputKind.image
        ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(File(input.value), width: 48, height: 48, fit: BoxFit.cover, cacheWidth: 144),
          )
        : CircleAvatar(child: Icon(_icon));
    return Card(
      child: ListTile(
        leading: leading,
        title: Text(input.kind.label, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(input.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: onRemove),
      ),
    );
  }
}
