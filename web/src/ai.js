// وظائف الذكاء الاصطناعي للاستوديو: تدقيق نحوي، واقتراحات سيو وعناوين، وصياغة من مصدر.
// كل ردّ من Gemini يُتحقق منه على الخادم قبل أن يصل إلى الواجهة.

const MAX_INPUT = 20_000;

const PROOFREAD_SYSTEM = `أنت مدقّق لغوي صارم للعربية الفصحى الإخبارية في الشبكة الجزائرية للأخبار.
مهمتك: إيجاد أخطاء النحو والصرف والإعراب الواضح والمطابقة (العدد والجنس والتذكير والتأنيث) والإملاء في النص المرفق.
القواعد:
- لا تغيّر المعنى، ولا الأسماء، ولا الأرقام، ولا التواريخ، ولا الاقتباسات المنقولة من متحدث.
- كل عنصر يحتوي "original" وهو مقطع قصير منسوخ حرفياً من النص دون أي تعديل، و"suggestion" هو البديل له.
- إن لم تكن متأكداً بنسبة عالية من الخطأ فلا تقترح شيئاً.
- اكتب "reason" بالعربية في جملة قصيرة تشرح القاعدة.
- لا تقترح تغيير الأسلوب أو الترتيب، ولا تضف معلومات.
- أعد قائمة فارغة إن لم تجد أخطاءً.`;

const PROOFREAD_SCHEMA = {
  type: 'OBJECT',
  properties: {
    issues: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          original: { type: 'STRING' },
          suggestion: { type: 'STRING' },
          category: { type: 'STRING', enum: ['نحو', 'صرف', 'مطابقة', 'إعراب', 'إملاء'] },
          reason: { type: 'STRING' },
        },
        required: ['original', 'suggestion', 'category', 'reason'],
      },
    },
  },
  required: ['issues'],
};

/**
 * يطلب التدقيق من Gemini، ثم يحسب موضع كل مقطع في النص ويُسقط ما لا يطابق النص.
 */
export async function proofreadWithAI(client, text) {
  const input = limit(text);
  const data = await client.generateJson({
    system: PROOFREAD_SYSTEM,
    user: `النص:\n${input}`,
    schema: PROOFREAD_SCHEMA,
    temperature: 0.1,
  });
  return { issues: locateIssues(input, data.issues || []) };
}

/** يحوّل المقاطع إلى مواضع. يتقدم المؤشر لتمييز التكرار، ويُسقط المقاطع غير الموجودة. */
export function locateIssues(text, raw) {
  const out = [];
  let cursor = 0;
  for (const item of raw) {
    const original = (item.original || '').trim();
    const suggestion = (item.suggestion ?? '').trim();
    if (!original || original === suggestion) continue;
    let index = text.indexOf(original, cursor);
    if (index === -1) index = text.indexOf(original);
    if (index === -1) continue;
    cursor = index + original.length;
    out.push({
      category: item.category || 'نحو',
      level: 'warn',
      message: item.reason || 'خطأ لغوي محتمل',
      index,
      length: original.length,
      original,
      suggestion,
      source: 'ai',
    });
  }
  return out.sort((a, b) => a.index - b.index);
}

const SEO_SYSTEM = `أنت محرر سيو لموقع أخبار عربي في الجزائر.
اقترح بالعربية الفصحى الإخبارية: ثلاثة عناوين جادة واضحة دون تهويل أو تضليل، ووصفاً لمحركات البحث بين 120 و160 حرفاً، وخمس كلمات مفتاحية.
لا تضف معلومات غير موجودة في النص. لا تستعمل إيموجي.`;

const SEO_SCHEMA = {
  type: 'OBJECT',
  properties: {
    titles: { type: 'ARRAY', items: { type: 'STRING' } },
    description: { type: 'STRING' },
    keywords: { type: 'ARRAY', items: { type: 'STRING' } },
  },
  required: ['titles', 'description', 'keywords'],
};

export async function seoWithAI(client, { title = '', body = '', keyword = '' }) {
  const data = await client.generateJson({
    system: SEO_SYSTEM,
    user: `العنوان الحالي: ${title || '(فارغ)'}\nالكلمة المفتاحية: ${keyword || '(غير محددة)'}\nالنص:\n${limit(body)}`,
    schema: SEO_SCHEMA,
    temperature: 0.4,
  });
  return {
    titles: (data.titles || []).map((t) => String(t).trim()).filter(Boolean).slice(0, 3),
    description: String(data.description || '').trim(),
    keywords: (data.keywords || []).map((k) => String(k).trim()).filter(Boolean).slice(0, 5),
  };
}

const DRAFT_SYSTEM = `أنت محرر أخبار في الشبكة الجزائرية للأخبار. تكتب بالعربية الفصحى الإخبارية.
- اكتب الخبر من المادة المصدرية فقط، ولا تضف أي معلومة أو رقم أو اسم أو سياق غير موجود فيها.
- انقل الأسماء والمناصب والأرقام والتواريخ كما وردت.
- ابدأ بالمعلومة الأهم ثم التفاصيل (الهرم المقلوب)، وفقرات قصيرة مفصولة بسطر فارغ.
- العنوان أقل من 15 كلمة ولا يحمل معلومة غير مؤكدة.
- في "notes" اذكر ما يحتاج تحقق المحرر: معلومات ناقصة أو متناقضة أو غير واضحة في المصدر.`;

const DRAFT_SCHEMA = {
  type: 'OBJECT',
  properties: {
    title: { type: 'STRING' },
    description: { type: 'STRING' },
    body: { type: 'STRING' },
    notes: { type: 'ARRAY', items: { type: 'STRING' } },
  },
  required: ['title', 'description', 'body', 'notes'],
};

export async function draftWithAI(client, { sourceText, sourceUrl = '', type = 'خبر' }) {
  const data = await client.generateJson({
    system: DRAFT_SYSTEM,
    user: `نوع المادة: ${type}\nالمصدر: ${sourceUrl || '(غير محدد)'}\n\nالمادة المصدرية:\n${limit(sourceText)}`,
    schema: DRAFT_SCHEMA,
    temperature: 0.2,
  });
  return {
    title: String(data.title || '').trim(),
    description: String(data.description || '').trim(),
    body: String(data.body || '').trim(),
    notes: (data.notes || []).map((n) => String(n).trim()).filter(Boolean),
  };
}

function limit(text = '') {
  return String(text).slice(0, MAX_INPUT);
}
