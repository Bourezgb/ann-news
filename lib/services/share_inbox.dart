import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../models/news_input.dart';

/// يستقبل ما يُشارَك إلى التطبيق من تطبيقات أخرى (روابط، نصوص، صور، فيديو، صوت)
/// ويحوّله إلى مدخلات تنتظر شاشة الصياغة.
class ShareInbox extends ChangeNotifier {
  final List<NewsInput> _pending = [];
  StreamSubscription<List<SharedMediaFile>>? _sub;

  bool get hasPending => _pending.isNotEmpty;

  /// يزداد مع كل مشاركة جديدة (لتنتقل الواجهة إلى شاشة الصياغة).
  int received = 0;

  /// يسلّم المدخلات المنتظرة ويفرغ القائمة.
  List<NewsInput> take() {
    final items = List.of(_pending);
    _pending.clear();
    return items;
  }

  Future<void> start() async {
    if (!Platform.isAndroid) return;
    try {
      _sub = ReceiveSharingIntent.instance.getMediaStream().listen(_receive, onError: (_) {});
      await _receive(await ReceiveSharingIntent.instance.getInitialMedia());
      await ReceiveSharingIntent.instance.reset();
    } catch (_) {}
  }

  Future<void> _receive(List<SharedMediaFile> files) async {
    final inputs = <NewsInput>[];
    for (final f in files) {
      inputs.addAll(await convert(f.path, f.type, f.mimeType, keepFile: _keep));
    }
    if (inputs.isEmpty) return;
    _pending.addAll(inputs);
    received++;
    notifyListeners();
  }

  static final _url = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

  /// يحوّل عنصراً مشارَكاً إلى مدخل أو أكثر (النص الذي يحتوي روابط يُفصل عنها).
  @visibleForTesting
  static Future<List<NewsInput>> convert(
    String value,
    SharedMediaType type,
    String? mimeType, {
    required Future<String> Function(String path) keepFile,
  }) async {
    switch (type) {
      case SharedMediaType.text:
      case SharedMediaType.url:
        final urls = _url.allMatches(value).map((m) => m[0]!.replaceFirst(RegExp(r'[).,،]+$'), '')).toSet();
        final rest = value.replaceAll(_url, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        return [
          for (final u in urls)
            NewsInput(kind: NewsInput.isYoutubeUrl(u) ? InputKind.youtube : InputKind.url, value: u),
          // النص المرافق للرابط يُضاف فقط إذا كان محتوى فعلياً وليس عنواناً قصيراً.
          if (rest.isNotEmpty && (urls.isEmpty || rest.length > 120)) NewsInput(kind: InputKind.text, value: rest),
        ];
      case SharedMediaType.image:
        return [NewsInput(kind: InputKind.image, value: await keepFile(value), mimeType: mimeType)];
      case SharedMediaType.video:
        return [NewsInput(kind: InputKind.video, value: await keepFile(value), mimeType: mimeType)];
      case SharedMediaType.file:
        final mime = mimeType ?? '';
        final kind = mime.startsWith('audio/')
            ? InputKind.audio
            : mime.startsWith('video/')
            ? InputKind.video
            : mime.startsWith('image/')
            ? InputKind.image
            : null;
        return kind == null ? [] : [NewsInput(kind: kind, value: await keepFile(value), mimeType: mimeType)];
    }
  }

  /// الملفات المشارَكة تُنسخ في ذاكرة مؤقتة قد تُمسح؛ ننقلها لمجلد التطبيق.
  static Future<String> _keep(String path) async {
    try {
      final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'inputs'));
      await dir.create(recursive: true);
      final dest = p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}${p.extension(path)}');
      await File(path).copy(dest);
      return dest;
    } catch (_) {
      return path;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
