import 'dart:convert';
import 'dart:io';

import 'package:mime/mime.dart';

import '../../core/text_rules.dart';
import '../../models/news_input.dart';
import '../../models/news_result.dart';
import 'gemini_client.dart';
import 'news_ai_service.dart';
import 'prompts.dart';

/// تنفيذ [NewsAiService] باستعمال Gemini مع مخرجات منظمة (JSON Schema).
class GeminiNewsService implements NewsAiService {
  GeminiNewsService(this.client, {this.temperature});

  final GeminiClient client;

  /// null = الإعداد الافتراضي للنموذج.
  final double? temperature;

  /// الملفات الأصغر من هذا الحجم تُرسل مضمّنة، والأكبر تُرفع عبر Files API.
  static const _inlineLimitBytes = 7 * 1024 * 1024;

  // المخطط بسيط عمداً (دون minItems/maxItems): القيود المعقدة تسبب أخطاء 500 لدى
  // بعض النماذج. العدد المطلوب مذكور في التعليمات ويُفرض في [clean].
  static Map<String, dynamic> _strings() => {
    'type': 'ARRAY',
    'items': {'type': 'STRING'},
  };

  /// هيكل المخرجات الثابت. الترتيب مقصود: النقاط أولاً ثم العناوين المشتقة منها.
  static final Map<String, dynamic> schema = {
    'type': 'OBJECT',
    'properties': {
      'source': {'type': 'STRING'},
      'speaker_name': {'type': 'STRING'},
      'speaker_role': {'type': 'STRING'},
      'points': _strings(),
      'evidence': _strings(),
      'headlines_serious': _strings(),
      'headlines_interactive': _strings(),
      'quotes_intro': {'type': 'STRING'},
      'quotes': _strings(),
      'caption': {'type': 'STRING'},
      'thumbnails_serious': _strings(),
      'thumbnails_interactive': _strings(),
      'notes': _strings(),
    },
    'required': [
      'source',
      'speaker_name',
      'speaker_role',
      'points',
      'evidence',
      'headlines_serious',
      'headlines_interactive',
      'quotes_intro',
      'quotes',
      'caption',
      'thumbnails_serious',
      'thumbnails_interactive',
      'notes',
    ],
    'propertyOrdering': [
      'source',
      'speaker_name',
      'speaker_role',
      'points',
      'evidence',
      'headlines_serious',
      'headlines_interactive',
      'quotes_intro',
      'quotes',
      'caption',
      'thumbnails_serious',
      'thumbnails_interactive',
      'notes',
    ],
  };

  static const _safety = [
    'HARM_CATEGORY_HARASSMENT',
    'HARM_CATEGORY_HATE_SPEECH',
    'HARM_CATEGORY_SEXUALLY_EXPLICIT',
    'HARM_CATEGORY_DANGEROUS_CONTENT',
  ];

  /// [mediaResolution]: منخفضة مع الفيديو (توفير الحصة)، عالية مع الصور (قراءة أدق للنص).
  Map<String, dynamic> _config({String? mediaResolution}) => {
    'responseMimeType': 'application/json',
    'responseSchema': schema,
    'temperature': ?temperature,
    'mediaResolution': ?mediaResolution,
  };

  @override
  Future<NewsContent> generate(NewsRequest request, {StatusCallback? onStatus}) async {
    final parts = <Map<String, dynamic>>[
      {
        'text': Prompts.request(
          category: request.category,
          style: request.statementStyle,
          weAreSource: request.weAreSource,
        ),
      },
    ];
    var hasVideo = false;
    final hasImage = request.inputs.any((i) => i.kind == InputKind.image);
    var n = 0;
    for (final input in request.inputs) {
      n++;
      switch (input.kind) {
        case InputKind.text:
          parts.add({'text': '[المدخل $n: نص]\n${input.value}'});
        case InputKind.url:
          final page = request.pages[input.id];
          parts.add({
            'text': page == null
                ? '[المدخل $n: رابط تعذر جلبه] ${input.value}'
                : '[المدخل $n: محتوى الرابط ${page.url}]\nالعنوان: ${page.title}\n${page.text}',
          });
        case InputKind.youtube:
          hasVideo = true;
          parts
            ..add({'text': '[المدخل $n: فيديو يوتيوب]'})
            ..add({
              'fileData': {'fileUri': input.value.trim()},
            });
        case InputKind.image:
        case InputKind.audio:
        case InputKind.video:
          if (input.kind == InputKind.video) hasVideo = true;
          parts.add({'text': '[المدخل $n: ${input.kind.label}]'});
          parts.add(await _filePart(input, n, onStatus));
      }
    }

    final resolution = hasVideo ? 'MEDIA_RESOLUTION_LOW' : (hasImage ? 'MEDIA_RESOLUTION_HIGH' : null);
    onStatus?.call('جاري تحليل المحتوى وصياغة الخبر…');
    final body = {
      'systemInstruction': {
        'parts': [
          {'text': Prompts.system},
        ],
      },
      'contents': [
        {'role': 'user', 'parts': parts},
      ],
      'generationConfig': _config(mediaResolution: resolution),
      'safetySettings': [
        for (final c in _safety) {'category': c, 'threshold': 'BLOCK_ONLY_HIGH'},
      ],
    };

    Map<String, dynamic> res;
    try {
      res = await client.generateContent(body, onStatus: onStatus);
    } on GeminiException catch (e) {
      // بعض النماذج لا تدعم mediaResolution: نعيد الطلب دونه.
      if (resolution != null && e.statusCode == 400 && (e.details ?? '').toLowerCase().contains('media')) {
        body['generationConfig'] = _config();
        res = await client.generateContent(body, onStatus: onStatus);
      } else {
        rethrow;
      }
    }
    return clean(parseJson(GeminiClient.responseText(res)), weAreSource: request.weAreSource);
  }

  Future<Map<String, dynamic>> _filePart(NewsInput input, int n, StatusCallback? onStatus) async {
    final file = File(input.value);
    final mime = input.mimeType ?? lookupMimeType(file.path) ?? _fallbackMime(input.kind);
    final size = await file.length();
    if (input.kind == InputKind.image && size <= _inlineLimitBytes) {
      return {
        'inlineData': {'mimeType': mime, 'data': base64Encode(await file.readAsBytes())},
      };
    }
    onStatus?.call('رفع ${input.kind.label} (المدخل $n)…');
    final uploaded = await client.uploadFile(
      file,
      mime,
      onProgress: (p) => onStatus?.call('رفع ${input.kind.label} (المدخل $n): ${(p * 100).round()}%'),
    );
    return {
      'fileData': {'mimeType': uploaded.mimeType.isEmpty ? mime : uploaded.mimeType, 'fileUri': uploaded.uri},
    };
  }

  static String _fallbackMime(InputKind kind) => switch (kind) {
    InputKind.image => 'image/jpeg',
    InputKind.audio => 'audio/mpeg',
    _ => 'video/mp4',
  };

  @override
  Future<NewsContent> translateToFrench(NewsDocument doc) async {
    final ar = doc.ar;
    final payload = {
      'source': doc.weAreSource ? '' : ar.source,
      'speaker_name': ar.speakerName,
      'speaker_role': ar.speakerRole,
      'points': ar.points,
      // العنوان المختار/المعدّل يوضع أولاً ليبقى هو الافتراضي بالفرنسية.
      'headlines_serious': _withFirst(ar.headline, ar.headlinesSerious),
      'headlines_interactive': ar.headlinesInteractive,
      'caption': ar.caption,
      'thumbnails_serious': _withFirst(ar.thumbnail, ar.thumbnailsSerious),
      'thumbnails_interactive': ar.thumbnailsInteractive,
      'notes': <String>[],
      'evidence': <String>[],
      'quotes_intro': ar.quotesIntro,
      'quotes': ar.quotes,
    };
    final res = await client.generateContent({
      'systemInstruction': {
        'parts': [
          {'text': Prompts.translateSystem},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': jsonEncode(payload)},
          ],
        },
      ],
      'generationConfig': _config(),
    });
    // التصريحات الحرفية لا تُترجم: تبقى كما قالها المتحدث.
    return clean(parseJson(GeminiClient.responseText(res)), weAreSource: doc.weAreSource);
  }

  static List<String> _withFirst(String first, List<String> rest) =>
      [if (first.trim().isNotEmpty) first, ...rest.where((e) => e != first)].take(3).toList();

  @override
  Future<String> extractPageText(String url) async {
    final res = await client.generateContent({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {
              'text':
                  'انسخ النص الكامل للمقال الموجود في هذا الرابط حرفياً كما هو، مع عنوانه، '
                  'دون تلخيص أو إعادة صياغة أو إضافة أي شيء، ودون القوائم والإعلانات وروابط الموقع:\n$url',
            },
          ],
        },
      ],
      'tools': [
        {'url_context': <String, dynamic>{}},
      ],
    });
    return GeminiClient.responseText(res);
  }

  /// تحليل JSON بتسامح (بعض النماذج تحيطه بعلامات ```).
  static Map<String, dynamic> parseJson(String text) {
    var t = text.trim();
    final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$').firstMatch(t);
    if (fence != null) t = fence.group(1)!;
    final start = t.indexOf('{');
    final end = t.lastIndexOf('}');
    if (start < 0 || end <= start) throw GeminiException('رد Gemini ليس بالصيغة المتوقعة.');
    try {
      return jsonDecode(t.substring(start, end + 1)) as Map<String, dynamic>;
    } on FormatException {
      throw GeminiException('رد Gemini ليس بالصيغة المتوقعة.');
    }
  }

  /// فرض القواعد الشكلية بشكل حتمي بعد رد النموذج.
  static NewsContent clean(Map<String, dynamic> json, {required bool weAreSource}) {
    final c = NewsContent.fromJson(json);
    // تنظيف النقاط مع إبقاء كل دليل مقابلاً لنقطته.
    final rawPoints = json['points'] is List ? (json['points'] as List).map((e) => e.toString()).toList() : <String>[];
    final points = <String>[], evidence = <String>[];
    for (var i = 0; i < rawPoints.length; i++) {
      final p = sanitizePoint(rawPoints[i]);
      if (p.isEmpty) continue;
      points.add(p);
      evidence.add(c.evidenceAt(i));
    }
    c
      ..points = points
      ..evidence = evidence;
    c.headlinesSerious = c.headlinesSerious.take(3).toList();
    c.headlinesInteractive = c.headlinesInteractive.take(3).toList();
    c.thumbnailsSerious = c.thumbnailsSerious.map(sanitizeThumbnail).take(3).toList();
    c.thumbnailsInteractive = c.thumbnailsInteractive.map(sanitizeThumbnail).take(3).toList();
    c.thumbnail = sanitizeThumbnail(c.thumbnail);
    c
      ..speakerName = stripHonorifics(c.speakerName)
      ..quotesIntro = c.quotesIntro.trim()
      ..quotes = c.quotes
          .map((q) => q.trim().replaceFirst(RegExp(r'^🔴\s*'), '').replaceAll(RegExp(r'^[«"“]+|[»"”]+$'), '').trim())
          .where((q) => q.isNotEmpty)
          .toList();
    if (weAreSource) c.source = '';
    return c;
  }
}
