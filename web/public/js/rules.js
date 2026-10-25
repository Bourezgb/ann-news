// قواعد التدقيق اللغوي والترقيمي (حتمية، بلا ذكاء اصطناعي).
// كل قاعدة تُرجع مواضع المشكلة، ومع كل موضع اقتراحاً إن أمكن الجزم به.
// ما لا يُحسم بالقواعد (الإعراب، المطابقة، الفعل المناسب) يحتاج نموذجاً لغوياً وهو خارج هذا الملف.

export const CATEGORY = {
  spelling: 'إملاء',
  punctuation: 'ترقيم',
  style: 'أسلوب',
  format: 'تنسيق',
};

// صيغ خاطئة شائعة في الكتابة الصحفية ← الصيغة الصحيحة.
// لا تُضاف كلمات لها أكثر من صيغة صحيحة حسب السياق.
export const WORD_FIXES = {
  // الهمزات
  الى: 'إلى',
  انه: 'أنه',
  انها: 'أنها',
  اننا: 'أننا',
  الاخبار: 'الأخبار',
  اعلن: 'أعلن',
  اكد: 'أكد',
  اكثر: 'أكثر',
  اخرى: 'أخرى',
  الاخرى: 'الأخرى',
  الاول: 'الأول',
  الاولى: 'الأولى',
  الامن: 'الأمن',
  الاوضاع: 'الأوضاع',
  الاسلامي: 'الإسلامي',
  الاستاذ: 'الأستاذ',
  الامم: 'الأمم',
  انشاء: 'إنشاء',
  اعادة: 'إعادة',
  اجراء: 'إجراء',
  اطلاق: 'إطلاق',
  اقرار: 'إقرار',
  بالاضافة: 'بالإضافة',
  الاف: 'آلاف',
  الغاء: 'إلغاء',
  ابريل: 'أبريل',
  امس: 'أمس',
  ايضا: 'أيضاً',
  مسئول: 'مسؤول',
  مسئولية: 'مسؤولية',
  اسبوع: 'أسبوع',
  // الألف اللينة والتاء المربوطة
  ماتزال: 'ما تزال',
  مازال: 'ما زال',
  لايزال: 'لا يزال',
  لاكن: 'لكن',
  كذالك: 'كذلك',
  هذة: 'هذه',
  هاذا: 'هذا',
  هاذه: 'هذه',
  ذالك: 'ذلك',
  اللذى: 'الذي',
  الذى: 'الذي',
  التى: 'التي',
  فى: 'في',
  المدرسه: 'المدرسة',
  الجامعه: 'الجامعة',
  الحكومه: 'الحكومة',
  الدوله: 'الدولة',
  الشركه: 'الشركة',
  المنطقه: 'المنطقة',
  الصحه: 'الصحة',
  القضيه: 'القضية',
  الحاله: 'الحالة',
  الخدمه: 'الخدمة',
  المعلومه: 'المعلومة',
  الاداره: 'الإدارة',
  الحمايه: 'الحماية',
  الولايه: 'الولاية',
  البلديه: 'البلدية',
  الوزاره: 'الوزارة',
  المديريه: 'المديرية',
  الجمعيه: 'الجمعية',
  العمليه: 'العملية',
  الاتفاقيه: 'الاتفاقية',
};

const WORD = /[؀-ۿ]+/g;

// قاعدة تطابق نمطاً بحثياً. fix يُرجع الاقتراح لكل تطابق.
const pattern = (id, category, level, message, re, fix) => ({
  id,
  category,
  level,
  message,
  find(text) {
    return [...text.matchAll(re)].map((m) => ({
      index: m.index,
      length: m[0].length,
      ...(fix ? { suggestion: fix(m[0]) } : {}),
    }));
  },
});

// قاعدة تعيد المواضع مباشرة (للحالات التي تحتاج منطقاً أكثر من تعبير نمطي).
const custom = (id, category, level, message, find) => ({ id, category, level, message, find });

export function spellingRules() {
  return [
    custom('misspelled-word', CATEGORY.spelling, 'error', 'خطأ إملائي محتمل', (text) =>
      [...text.matchAll(WORD)]
        .filter((w) => WORD_FIXES[w[0]])
        .map((w) => ({ index: w.index, length: w[0].length, suggestion: WORD_FIXES[w[0]], word: w[0] })),
    ),
    custom('repeated-word', CATEGORY.spelling, 'error', 'كلمة مكررة', (text) => {
      const words = [...text.matchAll(WORD)];
      const out = [];
      // نقارن بعد حذف واو العطف من بداية الكلمة، فـ«والحدث الحدث» تُعدّ تكراراً
      const core = (s) => s.replace(/^و(?=.{3,})/, '');
      words.forEach((w, i) => {
        const next = words[i + 1];
        if (next && core(next[0]) === core(w[0]) && /^\s+$/.test(text.slice(w.index + w[0].length, next.index))) {
          // نحذف المسافة قبل الكلمة المكررة والكلمة نفسها معاً
          const start = w.index + w[0].length;
          out.push({ index: start, length: next.index + next[0].length - start, suggestion: '' });
        }
      });
      return out;
    }),
  ];
}

export function punctuationRules() {
  return [
    pattern('space-before-mark', CATEGORY.punctuation, 'warn', 'مسافة قبل علامة الترقيم', /[^\S\n]+[،؛؟!.:]/g, (s) => s.replace(/^\s+/, '')),
    pattern('no-space-after-comma', CATEGORY.punctuation, 'warn', 'لا توجد مسافة بعد الفاصلة', /[،؛][^\s«»"'\n)]/g, (s) => `${s[0]} ${s[1]}`),
    pattern('no-space-after-stop', CATEGORY.punctuation, 'warn', 'لا توجد مسافة بعد النقطة', /[.؟!](?=[؀-ۿ])/g, (s) => `${s} `),
    pattern('repeated-marks', CATEGORY.punctuation, 'warn', 'علامات ترقيم متكررة', /[!?؟]{2,}/g, (s) => s[0]),
    pattern('three-dots', CATEGORY.punctuation, 'info', 'استعمل علامة الحذف « … » بدل ثلاث نقاط', /\.{3}/g, () => '…'),
    custom('straight-quotes', CATEGORY.style, 'info', 'استعمل علامات التنصيص « »', (text) => {
      let open = true;
      return [...text.matchAll(/"/g)].map((m) => {
        const suggestion = open ? '«' : '»';
        open = !open;
        return { index: m.index, length: 1, suggestion };
      });
    }),
    custom('unbalanced-quotes', CATEGORY.punctuation, 'error', 'علامات التنصيص « » غير متوازنة', (text) => unbalanced(text, '«', '»')),
    custom('unbalanced-brackets', CATEGORY.punctuation, 'error', 'الأقواس غير متوازنة', (text) => unbalanced(text, '(', ')')),
  ];
}

export function styleRules() {
  return [
    pattern('tatweel', CATEGORY.format, 'warn', 'احذف التطويل (ـ) من النص', /ـ+/g, () => ''),
    pattern('trailing-space', CATEGORY.format, 'info', 'مسافة في آخر السطر', /[^\S\n]+$/gm, () => ''),
    custom('long-sentence', CATEGORY.style, 'info', 'جملة طويلة (أكثر من 35 كلمة)', (text) => {
      const out = [];
      const re = /[^.؟!\n]+[.؟!]?/g;
      for (const m of text.matchAll(re)) {
        const words = (m[0].match(WORD) || []).length;
        if (words > 35) out.push({ index: m.index, length: m[0].length });
      }
      return out;
    }),
  ];
}

// يتحقق من توازن زوج من الرموز (مثل « »). يرجع موضع أول خلل.
function unbalanced(text, open, close) {
  const stack = [];
  const out = [];
  [...text].forEach((ch, i) => {
    if (ch === open) stack.push(i);
    else if (ch === close) {
      if (stack.length) stack.pop();
      else out.push({ index: i, length: 1 });
    }
  });
  for (const i of stack) out.push({ index: i, length: 1 });
  return out;
}

export function allRules() {
  return [...spellingRules(), ...punctuationRules(), ...styleRules()];
}
