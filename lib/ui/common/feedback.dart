import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// نسخ مع تنبيه «تم النسخ» واهتزاز خفيف.
Future<void> copyText(BuildContext context, String text, {String? what}) async {
  await Clipboard.setData(ClipboardData(text: text));
  await HapticFeedback.lightImpact();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.lightGreenAccent),
            const SizedBox(width: 8),
            Text(what == null ? 'تم النسخ' : 'تم نسخ $what'),
          ],
        ),
        duration: const Duration(milliseconds: 1400),
      ),
    );
}

void showMessage(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        duration: Duration(seconds: error ? 8 : 3),
        action: error ? SnackBarAction(label: 'إغلاق', textColor: Colors.white, onPressed: () {}) : null,
      ),
    );
}
