import { test } from 'node:test';
import assert from 'node:assert/strict';
import { proofread } from '../public/js/checks.js';
import { WORD_FIXES } from '../public/js/rules.js';

const find = (text, pred) => proofread(text).filter(pred);

test('common misspellings get a fix and a category', () => {
  const [issue] = find('ذهب فى رحلة', (i) => i.suggestion === 'في');
  assert.ok(issue, 'expected فى → في');
  assert.equal(issue.category, 'إملاء');
  assert.equal(issue.level, 'error');
});

test('ta marbuta and hamza word list has no duplicate keys with different fixes', () => {
  for (const [wrong, right] of Object.entries(WORD_FIXES)) {
    assert.notEqual(wrong, right, `${wrong} should differ from its fix`);
  }
  assert.equal(WORD_FIXES['الحكومه'], 'الحكومة');
});

test('unbalanced guillemets are reported at the opening mark', () => {
  const [issue] = find('قال «نعم وانصرف', (i) => i.message.includes('غير متوازنة'));
  assert.ok(issue);
  assert.equal(issue.index, 4);
});

test('balanced guillemets are not reported', () => {
  assert.equal(find('قال «نعم» وانصرف', (i) => i.message.includes('غير متوازنة')).length, 0);
});

test('three dots suggest the ellipsis character', () => {
  const [issue] = find('ننتظر...', (i) => i.suggestion === '…');
  assert.ok(issue);
  assert.equal(issue.category, 'ترقيم');
});

test('missing space after a full stop before Arabic is flagged', () => {
  const [issue] = find('انتهى الحدث.ثم بدأ الحوار', (i) => i.message.includes('النقطة'));
  assert.equal(issue.suggestion, '. ');
});

test('a URL with a dot is not flagged as a missing space', () => {
  assert.equal(find('الموقع www.anndz.dz يعرض', (i) => i.message.includes('النقطة')).length, 0);
});

test('tatweel is flagged and suggested for removal', () => {
  const [issue] = find('الجزائـــر', (i) => i.message.includes('التطويل'));
  assert.equal(issue.suggestion, '');
});

test('a repeated word is removed together with its space', () => {
  const [issue] = find('وقع الحدث الحدث اليوم', (i) => i.message === 'كلمة مكررة');
  assert.equal('وقع الحدث الحدث اليوم'.slice(issue.index, issue.index + issue.length), ' الحدث');
  assert.equal(issue.suggestion, '');
});

test('a repeated word with a conjunction prefix is still caught', () => {
  assert.equal(find('والحدث الحدث', (i) => i.message === 'كلمة مكررة').length, 1);
});

test('very long sentences are flagged as style notes', () => {
  const long = Array.from({ length: 40 }, (_, i) => `كلمة${i}`).join(' ') + '.';
  const [issue] = find(long, (i) => i.message.includes('جملة طويلة'));
  assert.ok(issue);
  assert.equal(issue.category, 'أسلوب');
});

test('issues come back sorted by position', () => {
  const issues = proofread('فى  الدولة ،ثم الى');
  const positions = issues.map((i) => i.index);
  assert.deepEqual(positions, [...positions].sort((a, b) => a - b));
});
