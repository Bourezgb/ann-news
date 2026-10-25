import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// خطأ مفهوم للمستخدم صادر عن Gemini API.
class GeminiException implements Exception {
  GeminiException(this.message, {this.statusCode, this.details, this.timedOut = false});

  final String message;
  final int? statusCode;
  final String? details;
  final bool timedOut;

  /// الرسالة مع نص الخطأ الأصلي من Gemini (مفيد للتشخيص).
  String get fullMessage {
    final d = details?.trim() ?? '';
    if (d.isEmpty) return message;
    return '$message\n${d.length > 220 ? '${d.substring(0, 220)}…' : d}';
  }

  @override
  String toString() => fullMessage;
}

class GeminiFile {
  GeminiFile({required this.name, required this.uri, required this.mimeType, required this.state});

  final String name;
  final String uri;
  final String mimeType;
  final String state;

  factory GeminiFile.fromJson(Map<String, dynamic> j) => GeminiFile(
    name: j['name'] as String,
    uri: j['uri'] as String,
    mimeType: (j['mimeType'] ?? '') as String,
    state: (j['state'] ?? 'ACTIVE') as String,
  );
}

class GeminiModelInfo {
  GeminiModelInfo(this.id, this.displayName);

  final String id;
  final String displayName;
}

/// عميل REST منخفض المستوى لـ Gemini API.
///
/// هذا هو الملف الوحيد الذي يعرف تفاصيل البروتوكول (العناوين، رفع الملفات،
/// شكل الردود). عند تغيّر الـ API يُعدَّل هنا فقط.
class GeminiClient {
  GeminiClient({
    required this.apiKey,
    required this.model,
    this.fallbackModels = const [],
    this.retryDelays = const [Duration(seconds: 2), Duration(seconds: 5), Duration(seconds: 10)],
    http.Client? httpClient,
    this.baseUrl = 'https://generativelanguage.googleapis.com',
    this.apiVersion = 'v1beta',
  }) : _http = httpClient ?? http.Client();

  final String apiKey;
  final String model;

  /// نماذج تُجرَّب بالترتيب إذا تعذر الطلب على [model].
  final List<String> fallbackModels;

  /// فترات الانتظار بين محاولات إعادة الطلب عند انشغال الخادم.
  final List<Duration> retryDelays;
  final String baseUrl;
  final String apiVersion;
  final http.Client _http;

  Map<String, String> get _headers => {'x-goog-api-key': apiKey, 'Content-Type': 'application/json'};

  /// يستدعي generateContent مع إعادة المحاولة، ثم الانتقال تلقائياً إلى النماذج
  /// الاحتياطية إذا كان النموذج مشغولاً (5xx) أو تجاوز حده (429) أو غير موجود (404).
  /// حدود الخطة المجانية مستقلة لكل نموذج، لذا ينجح الطلب غالباً على نموذج آخر.
  Future<Map<String, dynamic>> generateContent(
    Map<String, dynamic> body, {
    void Function(String status)? onStatus,
  }) async {
    final chain = [model, ...fallbackModels.where((m) => m.trim().isNotEmpty && m != model)];
    GeminiException? last;
    for (var i = 0; i < chain.length; i++) {
      if (i > 0) onStatus?.call('«${chain[i - 1]}» غير متاح حالياً، المحاولة عبر «${chain[i]}»…');
      try {
        return await _generateWith(chain[i], body, onStatus);
      } on GeminiException catch (e) {
        last = e;
        final code = e.statusCode ?? 0;
        final switchable = code == 404 || code == 429 || code >= 500 || e.timedOut;
        if (!switchable) rethrow;
      }
    }
    throw last!;
  }

  Future<Map<String, dynamic>> _generateWith(
    String model,
    Map<String, dynamic> body,
    void Function(String status)? onStatus,
  ) async {
    final path = model.startsWith('models/') ? model : 'models/$model';
    final uri = Uri.parse('$baseUrl/$apiVersion/$path:generateContent');
    final delays = retryDelays;
    var waitedForQuota = false;
    for (var attempt = 0; ; attempt++) {
      http.Response res;
      try {
        res = await _http.post(uri, headers: _headers, body: jsonEncode(body)).timeout(const Duration(minutes: 3));
      } on TimeoutException {
        throw GeminiException('انتهت مهلة الاتصال بـ Gemini. أعد المحاولة.', timedOut: true);
      } on SocketException {
        throw GeminiException('لا يوجد اتصال بالإنترنت.');
      }
      if (res.statusCode == 200) {
        return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      }
      final code = res.statusCode;
      if ((code == 500 || code == 503 || code == 504) && attempt < delays.length) {
        onStatus?.call('خوادم Gemini مشغولة، إعادة المحاولة (${attempt + 1}/${delays.length})…');
        await Future<void>.delayed(delays[attempt]);
        continue;
      }
      // حد الدقيقة في الخطة المجانية: ننتظر المدة التي يقترحها الخادم إذا كانت قصيرة.
      if (code == 429 && !waitedForQuota) {
        final wait = _retryDelay(res);
        if (wait != null && wait <= const Duration(seconds: 30)) {
          waitedForQuota = true;
          onStatus?.call('تم بلوغ حد الاستخدام مؤقتاً، الانتظار ${wait.inSeconds} ثانية…');
          await Future<void>.delayed(wait);
          continue;
        }
      }
      throw _error(res, model);
    }
  }

  static Duration? _retryDelay(http.Response res) {
    try {
      final details = ((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['error'] as Map)['details'] as List? ?? const [];
      for (final d in details.whereType<Map>()) {
        final v = d['retryDelay'];
        if (v is String && v.endsWith('s')) {
          return Duration(milliseconds: (double.parse(v.substring(0, v.length - 1)) * 1000).round());
        }
      }
    } catch (_) {}
    return null;
  }

  /// يستخرج النص من الرد متجاهلاً أجزاء التفكير.
  static String responseText(Map<String, dynamic> response) {
    final candidates = response['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      final reason = (response['promptFeedback'] as Map?)?['blockReason'];
      throw GeminiException(reason != null ? 'رفض Gemini معالجة المحتوى ($reason).' : 'لم يُرجع Gemini أي نتيجة.');
    }
    final c = candidates.first as Map<String, dynamic>;
    final parts = (c['content'] as Map?)?['parts'] as List? ?? const [];
    final text = parts
        .whereType<Map>()
        .where((p) => p['thought'] != true && p['text'] is String)
        .map((p) => p['text'] as String)
        .join();
    if (text.trim().isEmpty) {
      final finish = c['finishReason'];
      throw GeminiException(
        finish == 'SAFETY' || finish == 'PROHIBITED_CONTENT'
            ? 'حجب Gemini الرد لأسباب تتعلق بسياسة المحتوى.'
            : 'رد Gemini فارغ (${finish ?? 'سبب غير معروف'}).',
      );
    }
    return text;
  }

  /// رفع ملف (صوت/فيديو/صورة كبيرة) عبر Files API بطريقة resumable، ثم انتظار جاهزيته.
  Future<GeminiFile> uploadFile(File file, String mimeType, {void Function(double progress)? onProgress}) async {
    final length = await file.length();
    final start = await _http.post(
      Uri.parse('$baseUrl/upload/$apiVersion/files'),
      headers: {
        ..._headers,
        'X-Goog-Upload-Protocol': 'resumable',
        'X-Goog-Upload-Command': 'start',
        'X-Goog-Upload-Header-Content-Length': '$length',
        'X-Goog-Upload-Header-Content-Type': mimeType,
      },
      body: jsonEncode({
        'file': {'display_name': file.uri.pathSegments.last},
      }),
    );
    final uploadUrl = start.headers['x-goog-upload-url'];
    if (start.statusCode != 200 || uploadUrl == null) throw _error(start, model);

    final req = http.StreamedRequest('POST', Uri.parse(uploadUrl))
      ..headers.addAll({
        'Content-Length': '$length',
        'X-Goog-Upload-Offset': '0',
        'X-Goog-Upload-Command': 'upload, finalize',
      })
      ..contentLength = length;
    var sent = 0;
    final pipe = file.openRead().listen(
      (chunk) {
        req.sink.add(chunk);
        sent += chunk.length;
        onProgress?.call(sent / length);
      },
      onDone: req.sink.close,
      onError: req.sink.addError,
      cancelOnError: true,
    );
    final streamed = await _http.send(req);
    await pipe.cancel();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) throw _error(res, model);
    var f = GeminiFile.fromJson(
      (jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)['file'] as Map<String, dynamic>,
    );

    // الفيديو يحتاج وقتاً للمعالجة قبل استعماله.
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    while (f.state == 'PROCESSING') {
      if (DateTime.now().isAfter(deadline)) {
        throw GeminiException('استغرقت معالجة الملف على خوادم Gemini وقتاً طويلاً.');
      }
      await Future<void>.delayed(const Duration(seconds: 3));
      final r = await _http.get(Uri.parse('$baseUrl/$apiVersion/${f.name}'), headers: _headers);
      if (r.statusCode != 200) throw _error(r, model);
      f = GeminiFile.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
    }
    if (f.state == 'FAILED') throw GeminiException('فشلت معالجة الملف على خوادم Gemini.');
    return f;
  }

  /// قائمة النماذج المتاحة لهذا المفتاح والتي تدعم generateContent.
  Future<List<GeminiModelInfo>> listModels() async {
    final models = <GeminiModelInfo>[];
    String? pageToken;
    do {
      final uri = Uri.parse('$baseUrl/$apiVersion/models')
          .replace(queryParameters: {'pageSize': '100', 'pageToken': ?pageToken});
      final res = await _http.get(uri, headers: _headers);
      if (res.statusCode != 200) throw _error(res, model);
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      for (final m in (j['models'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        final methods = (m['supportedGenerationMethods'] as List? ?? const []).cast<String>();
        final id = (m['name'] as String).replaceFirst('models/', '');
        if (methods.contains('generateContent') && id.startsWith('gemini')) {
          models.add(GeminiModelInfo(id, (m['displayName'] ?? id) as String));
        }
      }
      pageToken = j['nextPageToken'] as String?;
    } while (pageToken != null && pageToken.isNotEmpty);
    return models;
  }

  GeminiException _error(http.Response res, String model) {
    String? apiMessage;
    try {
      apiMessage = ((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['error'] as Map?)?['message'] as String?;
    } catch (_) {}
    final msg = switch (res.statusCode) {
      400 when (apiMessage ?? '').contains('API key') => 'مفتاح Gemini API غير صالح. تحقق منه في الإعدادات.',
      400 => 'طلب غير صالح لـ Gemini.',
      401 || 403 => 'مفتاح Gemini API مرفوض أو لا يملك الصلاحية.',
      404 => 'النموذج «$model» غير موجود. اختر نموذجاً آخر من الإعدادات.',
      413 => 'حجم المدخلات كبير جداً.',
      429 => 'تم تجاوز حد الاستخدام المجاني للنموذج «$model». انتظر قليلاً ثم أعد المحاولة.',
      500 ||
      503 ||
      504 => 'خوادم Gemini مشغولة حالياً (النموذج «$model»). أعد المحاولة بعد قليل أو غيّر النموذج من الإعدادات.',
      _ => 'خطأ من Gemini (${res.statusCode}).',
    };
    return GeminiException(msg, statusCode: res.statusCode, details: apiMessage);
  }

  void close() => _http.close();
}
