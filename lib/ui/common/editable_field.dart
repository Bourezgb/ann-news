import 'package:flutter/material.dart';

import '../../core/text_rules.dart';
import 'feedback.dart';

/// حقل مخرجات قابل للتعديل مع زر نسخ مستقل وعداد كلمات اختياري.
class EditableField extends StatefulWidget {
  const EditableField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.maxWords,
    this.minWords,
    this.prefix,
    this.leading,
    this.copyLabel,
    this.required = false,
    this.maxLines,
    this.onDelete,
    this.textDirection,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final int? maxWords;
  final int? minWords;

  /// يُضاف قبل النص عند النسخ فقط (مثل 🔴).
  final String? prefix;

  /// عنصر يظهر قبل الحقل (مثل أيقونة حالة التحقق).
  final Widget? leading;
  final String? copyLabel;
  final bool required;
  final int? maxLines;
  final VoidCallback? onDelete;
  final TextDirection? textDirection;

  @override
  State<EditableField> createState() => _EditableFieldState();
}

class _EditableFieldState extends State<EditableField> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(EditableField old) {
    super.didUpdateWidget(old);
    if (widget.value != _controller.text) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final words = countWords(_controller.text);
    final over =
        // مع وجود حد أدنى يصبح الحد الأقصى مجرد توصية (العنوان الرئيسي).
        (widget.minWords == null && widget.maxWords != null && words > widget.maxWords!) ||
        (widget.minWords != null && _controller.text.trim().isNotEmpty && words < widget.minWords!);
    final missing = widget.required && _controller.text.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?widget.leading,
          if (widget.prefix != null)
            Padding(
              padding: const EdgeInsets.only(top: 12, left: 4),
              child: Text(widget.prefix!, style: const TextStyle(fontSize: 12)),
            ),
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: widget.maxLines,
              textDirection: widget.textDirection,
              onChanged: (v) {
                setState(() {});
                widget.onChanged(v);
              },
              decoration: InputDecoration(
                labelText: widget.label,
                errorText: missing ? 'حقل إلزامي' : null,
                enabledBorder: over
                    ? OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: scheme.error, width: 1.5),
                      )
                    : null,
                helperText: widget.maxWords == null
                    ? null
                    : widget.minWords == null
                    ? '$words / ${widget.maxWords} كلمات'
                    : '$words كلمة (${widget.minWords} على الأقل، ويُفضّل حتى ${widget.maxWords})',
                helperStyle: over ? TextStyle(color: scheme.error, fontWeight: FontWeight.bold) : null,
              ),
            ),
          ),
          IconButton(
            tooltip: 'نسخ',
            icon: const Icon(Icons.copy_rounded),
            color: scheme.primary,
            onPressed: () =>
                copyText(context, '${widget.prefix ?? ''}${_controller.text.trim()}', what: widget.copyLabel),
          ),
          if (widget.onDelete != null)
            IconButton(
              tooltip: 'حذف',
              icon: const Icon(Icons.close_rounded),
              color: scheme.outline,
              onPressed: widget.onDelete,
            ),
        ],
      ),
    );
  }
}
