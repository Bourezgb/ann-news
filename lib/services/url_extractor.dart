import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PageContent {
  PageContent({required this.title, required this.text, this.imageUrl});

  final String title;
  final String text;
  final String? imageUrl;
}

/// جلب المقالات على الجهاز واستخلاص نصها (Web Scraping).
class UrlExtractor {
  UrlExtractor({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  static const _ua =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Mobile Safari/537.36';
  static const _maxChars = 30000;

  /// يعيد null إذا تعذر الجلب أو كان النص قصيراً جداً (صفحة تعتمد على JavaScript).
  Future<PageContent?> fetch(String url) async {
    try {
      final res = await _http
          .get(Uri.parse(url), headers: {'User-Agent': _ua, 'Accept-Language': 'ar,fr;q=0.8,en;q=0.6'})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final page = parse(utf8.decode(res.bodyBytes, allowMalformed: true), Uri.parse(url));
      return page.text.length < 200 ? null : page;
    } catch (_) {
      return null;
    }
  }

  static PageContent parse(String source, Uri base) {
    final doc = html.parse(source);
    String? meta(String key) =>
        doc.querySelector('meta[property="$key"]')?.attributes['content'] ??
        doc.querySelector('meta[name="$key"]')?.attributes['content'];

    final title = (meta('og:title') ?? doc.querySelector('h1')?.text ?? doc.querySelector('title')?.text ?? '').trim();
    var image = meta('og:image');
    if (image != null) image = base.resolve(image).toString();

    for (final junk in doc.querySelectorAll(
      'script, style, noscript, iframe, nav, header, footer, aside, form, svg, '
      '[class*="share"], [class*="related"], [class*="comment"], [class*="menu"], [class*="sidebar"]',
    )) {
      junk.remove();
    }
    final root = _bestContainer(doc);
    final blocks = root
        .querySelectorAll('h1, h2, h3, p, li, blockquote')
        .map((e) => e.text.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((t) => t.length > 1)
        .toList();
    var text = blocks.isNotEmpty ? blocks.join('\n') : root.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length > _maxChars) text = text.substring(0, _maxChars);
    return PageContent(title: title, text: text, imageUrl: image);
  }

  /// أفضل حاوية للمقال: article/main إن وجدت، وإلا العنصر الأغنى بالفقرات.
  static Element _bestContainer(Document doc) {
    final direct =
        doc.querySelector('article') ??
        doc.querySelector('main') ??
        doc.querySelector('[itemprop="articleBody"]') ??
        doc.querySelector('[class*="article"]') ??
        doc.querySelector('[class*="content"]');
    if (direct != null && direct.querySelectorAll('p').length >= 2) return direct;
    Element best = doc.body ?? doc.documentElement!;
    var bestScore = 0;
    for (final el in doc.querySelectorAll('div, section')) {
      final score = el.children.where((c) => c.localName == 'p').fold<int>(0, (s, pEl) => s + pEl.text.trim().length);
      if (score > bestScore) {
        bestScore = score;
        best = el;
      }
    }
    return best;
  }

  /// تنزيل صورة المقال لاقتراحها خلفيةً للتصميم.
  Future<String?> downloadImage(String url) async {
    try {
      final res = await _http.get(Uri.parse(url), headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 20));
      final type = res.headers['content-type'] ?? '';
      if (res.statusCode != 200 || !type.startsWith('image/')) return null;
      final ext = type.contains('png') ? '.png' : (type.contains('webp') ? '.webp' : '.jpg');
      final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'backgrounds'));
      await dir.create(recursive: true);
      final f = File(p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}$ext'));
      await f.writeAsBytes(res.bodyBytes);
      return f.path;
    } catch (_) {
      return null;
    }
  }
}
