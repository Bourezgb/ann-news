import { test } from 'node:test';
import assert from 'node:assert/strict';
import { GeminiClient, GeminiError } from '../src/gemini.js';
import { locateIssues, proofreadWithAI, seoWithAI } from '../src/ai.js';

// يحاكي استجابة generateContent من Gemini بنص JSON داخل candidates
function fakeFetch(payload, { status = 200, calls = [] } = {}) {
  return async (url, opts) => {
    calls.push({ url, opts });
    if (status !== 200) return { ok: false, status, json: async () => ({}) };
    return {
      ok: true,
      status: 200,
      json: async () => ({ candidates: [{ content: { parts: [{ text: JSON.stringify(payload) }] } }] }),
    };
  };
}

test('client sends the key in a header and the model in the URL', async () => {
  const calls = [];
  const client = new GeminiClient({ apiKey: 'K123', model: 'gemini-test', fetchImpl: fakeFetch({ ok: 1 }, { calls }) });
  const out = await client.generateJson({ system: 's', user: 'u', schema: {} });
  assert.deepEqual(out, { ok: 1 });
  assert.match(calls[0].url, /models\/gemini-test:generateContent$/);
  assert.equal(calls[0].opts.headers['x-goog-api-key'], 'K123');
  assert.ok(!calls[0].url.includes('K123'), 'key must not be in the URL');
});

test('client without a key refuses before any request', () => {
  assert.throws(() => new GeminiClient({ apiKey: '' }), (e) => e instanceof GeminiError && e.status === 400);
});

test('client maps quota errors to Arabic messages', async () => {
  const client = new GeminiClient({ apiKey: 'K', fetchImpl: fakeFetch({}, { status: 429 }) });
  await assert.rejects(client.generateJson({ system: 's', user: 'u', schema: {} }), (e) => e.status === 429 && e.message.includes('حد الاستخدام'));
});

test('locateIssues keeps only quotes found verbatim, in order', () => {
  const text = 'ذهب الولد إلى المدرسة، وقال الولد الكلام.';
  const issues = locateIssues(text, [
    { original: 'الولد', suggestion: 'الولدُ', category: 'إعراب', reason: 'r1' },
    { original: 'الولد', suggestion: 'الصبي', category: 'أسلوب', reason: 'r2' },
    { original: 'غير موجود', suggestion: 'x', category: 'نحو', reason: 'r3' },
    { original: 'الكلام', suggestion: 'الكلام', category: 'نحو', reason: 'r4' },
  ]);
  assert.equal(issues.length, 2);
  assert.equal(text.slice(issues[0].index, issues[0].index + issues[0].length), 'الولد');
  assert.ok(issues[1].index > issues[0].index, 'second duplicate points further along');
  assert.equal(issues[0].source, 'ai');
});

test('proofreadWithAI returns located issues from the model reply', async () => {
  const client = new GeminiClient({
    apiKey: 'K',
    fetchImpl: fakeFetch({ issues: [{ original: 'قرروا', suggestion: 'قرّروا', category: 'إملاء', reason: 'شدة' }] }),
  });
  const r = await proofreadWithAI(client, 'قرروا الاجتماع');
  assert.equal(r.issues.length, 1);
  assert.equal(r.issues[0].index, 0);
  assert.equal(r.issues[0].category, 'إملاء');
});

test('seoWithAI trims lists to the allowed size', async () => {
  const client = new GeminiClient({
    apiKey: 'K',
    fetchImpl: fakeFetch({ titles: ['a', 'b', 'c', 'd'], description: ' وصف ', keywords: ['k1', 'k2'] }),
  });
  const r = await seoWithAI(client, { title: 't', body: 'b', keyword: 'k' });
  assert.equal(r.titles.length, 3);
  assert.equal(r.description, 'وصف');
  assert.deepEqual(r.keywords, ['k1', 'k2']);
});
