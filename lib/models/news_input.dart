import 'package:uuid/uuid.dart';

enum InputKind {
  text('نص'),
  url('رابط'),
  youtube('يوتيوب'),
  image('صورة'),
  audio('صوت'),
  video('فيديو');

  const InputKind(this.label);

  final String label;
}

/// مدخل واحد من مدخلات الخبر. [value] هو النص نفسه أو الرابط أو مسار الملف.
class NewsInput {
  NewsInput({required this.kind, required this.value, this.mimeType, String? id}) : id = id ?? const Uuid().v4();

  final String id;
  final InputKind kind;
  final String value;
  final String? mimeType;

  bool get isFile => kind == InputKind.image || kind == InputKind.audio || kind == InputKind.video;

  /// وصف قصير يُحفظ في السجل.
  String get summary {
    switch (kind) {
      case InputKind.text:
        final t = value.replaceAll(RegExp(r'\s+'), ' ').trim();
        return t.length > 120 ? '${t.substring(0, 120)}…' : t;
      case InputKind.url:
      case InputKind.youtube:
        return value;
      case InputKind.image:
      case InputKind.audio:
      case InputKind.video:
        return value.split('/').last;
    }
  }

  static bool isYoutubeUrl(String url) {
    final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
    return host.endsWith('youtube.com') || host == 'youtu.be' || host.endsWith('.youtu.be');
  }
}
