import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ann_news/models/news_category.dart';
import 'package:ann_news/models/news_input.dart';
import 'package:ann_news/services/ai/gemini_client.dart';
import 'package:ann_news/services/ai/gemini_news_service.dart';
import 'package:ann_news/services/ai/news_ai_service.dart';

void main() {
  final modelJson = {
    'source': 'وزارة الصحة',
    'speaker_name': 'السيد محمد',
    'speaker_role': '',
    'points': ['🔴 الوزير أكد #المجال_الصحي أولوية', 'اللقاء شكل فرصة 👍'],
    'headlines_serious': ['أ', 'ب', 'ج'],
    'headlines_interactive': ['د', 'هـ', 'و'],
    'caption': 'كابشن',
    'thumbnails_serious': ['تعاون 🔥 صحي', 'x', 'y'],
    'thumbnails_interactive': ['z', 'w', 'v'],
    'notes': [],
    'quotes_intro': ' الوزير #فلان يتحدث عن: ',
    'quotes': ['🔴 « راني نقول لكم »', 'السيد الوزير قال'],
  };

  test('generate sends schema + system prompt and cleans the result', () async {
    late Map<String, dynamic> sent;
    late http.Request sentRequest;
    final client = MockClient((req) async {
      sentRequest = req;
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'thinking…', 'thought': true},
                    {'text': '```json\n${jsonEncode(modelJson)}\n```'},
                  ],
                },
              },
            ],
          }),
        ),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = GeminiNewsService(GeminiClient(apiKey: 'k', model: 'gemini-flash-latest', httpClient: client));
    final result = await service.generate(
      NewsRequest(
        category: NewsCategory.latest,
        statementStyle: StatementStyle.fusha,
        weAreSource: false,
        inputs: [NewsInput(kind: InputKind.text, value: 'نص الخبر')],
      ),
    );

    expect(sentRequest.url.path, '/v1beta/models/gemini-flash-latest:generateContent');
    expect(sentRequest.headers['x-goog-api-key'], 'k');
    expect(sent['generationConfig']['responseMimeType'], 'application/json');
    expect(sent['generationConfig'].containsKey('temperature'), isFalse);
    expect(sent['systemInstruction'], isNotNull);
    expect(result.points, ['الوزير أكد المجال الصحي أولوية', 'اللقاء شكل فرصة']);
    expect(result.thumbnail, 'تعاون صحي');
    expect(result.headline, 'أ');
    expect(result.source, 'وزارة الصحة');
    expect(result.speakerName, 'محمد');
    // التصريحات الحرفية لا تُعدَّل (تُزال علامات التنصيص الخارجية فقط).
    expect(result.quotes, ['راني نقول لكم', 'السيد الوزير قال']);
    expect(result.quotesIntro, 'الوزير #فلان يتحدث عن:');
  });

  test('HTTP errors map to Arabic messages', () async {
    final client = MockClient((_) async => http.Response('{"error":{"message":"quota"}}', 429));
    final service = GeminiNewsService(GeminiClient(apiKey: 'k', model: 'm', httpClient: client));
    expect(
      () => service.generate(
        NewsRequest(
          category: NewsCategory.general,
          statementStyle: StatementStyle.fusha,
          weAreSource: true,
          inputs: [NewsInput(kind: InputKind.text, value: 'x')],
        ),
      ),
      throwsA(isA<GeminiException>().having((e) => e.message, 'message', contains('حد الاستخدام'))),
    );
  });

  test('busy model falls back to the next model after retries', () async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add(req.url.path);
      if (req.url.path.contains('gemini-flash-latest')) {
        return http.Response('{"error":{"code":503,"message":"The model is overloaded."}}', 503);
      }
      if (req.url.path.contains('missing-model')) return http.Response('{"error":{"message":"not found"}}', 404);
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': jsonEncode(modelJson)},
                  ],
                },
              },
            ],
          }),
        ),
        200,
      );
    });
    final statuses = <String>[];
    final gemini = GeminiClient(
      apiKey: 'k',
      model: 'gemini-flash-latest',
      fallbackModels: ['missing-model', 'gemini-2.5-flash'],
      retryDelays: const [Duration.zero, Duration.zero, Duration.zero],
      httpClient: client,
    );
    final res = await GeminiNewsService(gemini).generate(
      NewsRequest(
        category: NewsCategory.urgent,
        statementStyle: StatementStyle.fusha,
        weAreSource: false,
        inputs: [NewsInput(kind: InputKind.text, value: 'x')],
      ),
      onStatus: statuses.add,
    );
    expect(res.points, isNotEmpty);
    expect(calls.where((c) => c.contains('gemini-flash-latest')).length, 4, reason: '1 call + 3 retries');
    expect(calls.last, contains('gemini-2.5-flash'));
    expect(statuses.any((s) => s.contains('gemini-2.5-flash')), isTrue);
  });

  test('youtube detection', () {
    expect(NewsInput.isYoutubeUrl('https://www.youtube.com/watch?v=abc'), isTrue);
    expect(NewsInput.isYoutubeUrl('https://youtu.be/abc'), isTrue);
    expect(NewsInput.isYoutubeUrl('https://www.sante.gov.dz/'), isFalse);
  });
}
