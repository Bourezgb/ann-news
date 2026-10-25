import { test } from 'node:test';
import assert from 'node:assert/strict';
import { extractArticle, decodeEntities } from '../src/extract.js';

const page = `
<html><head>
<title>ignored &amp; title</title>
<meta property="og:title" content="عنوان &quot;الخبر&quot;">
<meta name="description" content="وصف قصير">
<meta property="og:image" content="/img/cover.jpg">
<script>var x = "<p>not text</p>";</script>
</head><body>
<article>
<p>هذه فقرة أولى طويلة بما يكفي لتجاوز حد الأربعين حرفاً في الاستخلاص.</p>
<p>قصيرة</p>
<p>فقرة ثانية طويلة أيضاً وفيها <a href="#">رابط</a> ونص إضافي كافٍ للاختبار.</p>
</article></body></html>`;

test('extractArticle reads og title, description, image and paragraphs', () => {
  const r = extractArticle(page, 'https://example.dz/news/1');
  assert.equal(r.title, 'عنوان "الخبر"');
  assert.equal(r.description, 'وصف قصير');
  assert.equal(r.image, 'https://example.dz/img/cover.jpg');
  assert.equal(r.text.split('\n\n').length, 2);
  assert.ok(!r.text.includes('not text'));
});

test('decodeEntities handles named and numeric entities', () => {
  assert.equal(decodeEntities('a&amp;b &#1575; &#x627;'), 'a&b ا ا');
});
