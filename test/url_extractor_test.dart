import 'package:flutter_test/flutter_test.dart';
import 'package:ann_news/services/url_extractor.dart';

void main() {
  test('extracts article text and og metadata', () {
    const html = '''
<html><head>
<meta property="og:title" content="وزير الصحة يستقبل وفداً">
<meta property="og:image" content="/img/a.jpg">
<script>var x = 1;</script></head>
<body><nav><p>القائمة الرئيسية</p></nav>
<article><h1>وزير الصحة يستقبل وفداً</h1>
<p>استقبل وزير الصحة اليوم وفداً رسمياً.</p>
<p>وتناول اللقاء سبل التعاون.</p></article>
<footer><p>حقوق النشر</p></footer></body></html>''';
    final page = UrlExtractor.parse(html, Uri.parse('https://www.sante.gov.dz/news/1'));
    expect(page.title, 'وزير الصحة يستقبل وفداً');
    expect(page.imageUrl, 'https://www.sante.gov.dz/img/a.jpg');
    expect(page.text, contains('استقبل وزير الصحة اليوم وفداً رسمياً.'));
    expect(page.text, isNot(contains('القائمة الرئيسية')));
    expect(page.text, isNot(contains('حقوق النشر')));
  });
}
