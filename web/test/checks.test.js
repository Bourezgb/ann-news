import { test } from 'node:test';
import assert from 'node:assert/strict';
import { proofread, seoReport, slugify, countWords } from '../public/js/checks.js';

test('countWords counts Arabic and Latin words', () => {
  assert.equal(countWords('وزير الصحة يستقبل AFP'), 4);
});

test('proofread flags a common misspelling with a suggestion', () => {
  const issues = proofread('ذهب الى السوق');
  const hit = issues.find((i) => i.suggestion === 'إلى');
  assert.ok(hit, 'expected suggestion إلى');
  assert.equal(hit.level, 'error');
});

test('proofread flags repeated words and punctuation spacing', () => {
  const messages = proofread('وقع الحدث الحدث ،ثم انتهى').map((i) => i.message);
  assert.ok(messages.some((m) => m.startsWith('كلمة مكررة')));
  assert.ok(messages.includes('لا توجد مسافة بعد الفاصلة'));
});

test('proofread suggests guillemets for straight quotes', () => {
  const issue = proofread('قال "نعم"').find((i) => i.message.includes('التنصيص'));
  assert.equal(issue.suggestion, '«');
});

test('slugify keeps Arabic and removes tashkeel and punctuation', () => {
  assert.equal(slugify('أَخبار الجزائر: اليوم!'), 'أخبار-الجزائر-اليوم');
});

test('seoReport reports missing title and keyword placement', () => {
  const r = seoReport({ title: '', description: '', body: 'كلام '.repeat(200), keyword: 'الجزائر' });
  assert.ok(r.items.some((i) => i.level === 'error' && i.text.includes('العنوان فارغ')));
  assert.ok(r.score < 100);
});

test('seoReport accepts a well-formed title and description', () => {
  const r = seoReport({
    title: 'الجزائر تطلق برنامجاً جديداً لدعم الصحافة المحلية والشباب',
    description: 'أعلنت الحكومة الجزائرية عن برنامج جديد لدعم الصحافة المحلية، يستهدف الشباب والمؤسسات الإعلامية الناشئة في مختلف الولايات، ضمن خطة وطنية متكاملة.',
    body: 'الجزائر '.repeat(320),
    keyword: 'الجزائر',
  });
  assert.equal(r.items.find((i) => i.text.includes('في العنوان'))?.level, 'ok');
});
