// فحوص النصوص المشتركة بين الخادم والمتصفح: السيو والتدقيق اللغوي وإنشاء الرابط.
import { allRules } from './rules.js';

const TASHKEEL = /[ً-ٰٟ]/g;
const ARABIC_WORD = /[؀-ۿ]+/g;

export function stripTashkeel(text) {
  return text.replace(TASHKEEL, '');
}

export function countWords(text) {
  return (text.match(ARABIC_WORD) || []).length + (text.match(/[A-Za-z0-9]+/g) || []).length;
}

export function slugify(title) {
  return stripTashkeel(title)
    .trim()
    .replace(/[^\p{L}\p{N}\s-]/gu, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 80);
}

/**
 * تدقيق لغوي وترقيمي. يُرجع المشكلات مرتبةً بالموضع.
 * كل مشكلة: { category, level, message, index, length, suggestion? }
 */
export function proofread(text) {
  const issues = [];
  for (const rule of allRules()) {
    for (const found of rule.find(text)) {
      const { suggestion, word, ...pos } = found;
      const message = word ? `${rule.message}: «${word}»` : rule.message;
      issues.push({
        category: rule.category,
        level: rule.level,
        message,
        ...pos,
        ...(suggestion !== undefined ? { suggestion } : {}),
      });
    }
  }
  return issues.sort((a, b) => a.index - b.index || a.length - b.length);
}

/**
 * تقرير السيو. المستوى: ok | warn | error. النتيجة من 100.
 */
export function seoReport({ title = '', description = '', body = '', keyword = '', image = null }) {
  const items = [];
  const add = (level, text) => items.push({ level, text });
  const kw = stripTashkeel(keyword.trim());

  const tLen = [...title.trim()].length;
  if (!tLen) add('error', 'العنوان فارغ');
  else if (tLen < 30) add('warn', `العنوان قصير (${tLen} حرفاً)، الأفضل بين 40 و65`);
  else if (tLen > 70) add('warn', `العنوان طويل (${tLen} حرفاً)، قد يُقطع في نتائج البحث`);
  else add('ok', `طول العنوان مناسب (${tLen} حرفاً)`);

  const dLen = [...description.trim()].length;
  if (!dLen) add('error', 'وصف الصفحة (meta description) فارغ');
  else if (dLen < 120) add('warn', `الوصف قصير (${dLen} حرفاً)، الأفضل بين 120 و160`);
  else if (dLen > 160) add('warn', `الوصف طويل (${dLen} حرفاً)، سيُقطع بعد 160 حرفاً`);
  else add('ok', `طول الوصف مناسب (${dLen} حرفاً)`);

  const words = countWords(body);
  if (words < 150) add('warn', `المتن قصير (${words} كلمة)، الأخبار المعمّقة تحتاج 300 كلمة فأكثر`);
  else add('ok', `عدد كلمات المتن: ${words}`);

  if (kw) {
    const inTitle = stripTashkeel(title).includes(kw);
    const inDesc = stripTashkeel(description).includes(kw);
    const head = stripTashkeel(body).split(/\s+/).slice(0, 100).join(' ');
    const inHead = head.includes(kw);
    const count = stripTashkeel(body).split(kw).length - 1;
    const density = words ? (count * kw.split(/\s+/).length / words) * 100 : 0;
    add(inTitle ? 'ok' : 'error', inTitle ? 'الكلمة المفتاحية في العنوان' : 'أدرج الكلمة المفتاحية في العنوان');
    add(inDesc ? 'ok' : 'warn', inDesc ? 'الكلمة المفتاحية في الوصف' : 'أدرج الكلمة المفتاحية في الوصف');
    add(inHead ? 'ok' : 'warn', inHead ? 'الكلمة المفتاحية في أول 100 كلمة' : 'الكلمة المفتاحية غير موجودة في أول 100 كلمة');
    if (density > 2.5) add('warn', `كثافة الكلمة المفتاحية مرتفعة (${density.toFixed(1)}%)`);
    else if (count === 0) add('warn', 'الكلمة المفتاحية غير موجودة في المتن');
    else add('ok', `كثافة الكلمة المفتاحية ${density.toFixed(1)}%`);
  } else {
    add('warn', 'حدّد كلمة مفتاحية لتحليل أدق');
  }

  if (image !== null) {
    if (!image.alt || !image.alt.trim()) add('error', 'الصورة بلا نص بديل (alt)');
    else add('ok', 'الصورة لها نص بديل');
  }

  const penalty = { ok: 0, warn: 5, error: 12 };
  const score = Math.max(0, 100 - items.reduce((s, it) => s + penalty[it.level], 0));
  return { score, items, slug: slugify(title) };
}
