// واجهة ANN Studio: توجيه بسيط بالهاش، وشاشات المقالات والمحرر والمصادر والتصميم.
import { proofread, seoReport, countWords } from './checks.js';
import { renderDesign } from './design.js';

const view = document.getElementById('view');
const toastEl = document.getElementById('toast');

// ---------- أدوات مساعدة ----------

function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v === false || v == null) continue;
    if (k === 'class') el.className = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (k === 'value') el.value = v;
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const c of children.flat()) {
    if (c == null || c === false) continue;
    el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
  return el;
}

function toast(message, isError = false) {
  toastEl.textContent = message;
  toastEl.classList.toggle('error', isError);
  toastEl.classList.add('show');
  clearTimeout(toast.t);
  toast.t = setTimeout(() => toastEl.classList.remove('show'), 2600);
}

async function api(path, { method = 'GET', body } = {}) {
  const res = await fetch(path, {
    method,
    headers: body ? { 'Content-Type': 'application/json' } : {},
    body: body ? JSON.stringify(body) : undefined,
  });
  if (res.status === 204) return null;
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `خطأ ${res.status}`);
  return data;
}

const TYPE_CLASS = { 'عاجل': 'urgent' };
const STATUS_CLASS = { 'جاهز للنشر': 'status-ready', 'للتدقيق': 'status-review' };

function fmtDate(iso) {
  return new Date(iso).toLocaleString('ar-DZ', { dateStyle: 'medium', timeStyle: 'short' });
}

function setNav(name) {
  document.querySelectorAll('[data-nav]').forEach((a) => a.classList.toggle('active', a.dataset.nav === name));
}

function pageHead(title, subtitle, actions = []) {
  return h('div', { class: 'page-head' }, h('div', {}, h('h1', {}, title), subtitle ? h('p', {}, subtitle) : null), h('div', { class: 'actions' }, actions));
}

const EMPTY_ARTICLE = { title: '', description: '', keyword: '', body: '', type: 'خبر', status: 'مسودة', source: '', image: '', imageAlt: '' };

// ---------- الشاشات ----------

async function screenHome() {
  setNav('home');
  const list = await api('/api/articles');
  const count = (s) => list.filter((a) => a.status === s).length;
  view.replaceChildren(
    pageHead('المقالات', 'كل ما تكتبه يُحفظ على جهازك', [h('a', { class: 'btn primary', href: '#/new' }, '＋ مقال جديد')]),
    h(
      'div',
      { class: 'stats' },
      stat(list.length, 'إجمالي المقالات'),
      stat(count('مسودة'), 'مسودات'),
      stat(count('للتدقيق'), 'بانتظار التدقيق'),
      stat(count('جاهز للنشر'), 'جاهزة للنشر'),
    ),
    h(
      'div',
      { class: 'card' },
      list.length
        ? h(
            'div',
            { class: 'list' },
            list.map((a) =>
              h(
                'a',
                { class: 'row', href: `#/article/${a.id}` },
                h('div', { style: 'min-width:0' }, h('div', { class: 't' }, a.title || 'بلا عنوان'), h('div', { class: 'meta' }, fmtDate(a.updatedAt))),
                h('span', { class: `pill ${TYPE_CLASS[a.type] || ''}` }, a.type),
                h('span', { class: `pill ${STATUS_CLASS[a.status] || ''}` }, a.status),
              ),
            ),
          )
        : h('div', { class: 'empty' }, 'لا توجد مقالات بعد. ابدأ بـ«مقال جديد» أو بـ«جلب من مصدر».'),
    ),
  );
}

function stat(n, label) {
  return h('div', { class: 'card stat' }, h('div', { class: 'n' }, n), h('div', { class: 'l' }, label));
}

function field(label, control, counter = null) {
  return h('div', { class: 'field' }, h('label', {}, h('span', {}, label), counter), control);
}

async function screenEditor(id) {
  setNav(id ? 'home' : 'new');
  let article = id ? await api(`/api/articles/${id}`) : { ...EMPTY_ARTICLE, ...(pendingPrefill || {}) };
  pendingPrefill = null;
  let saved = '';
  let activeTab = 'proof';

  const inputs = {};
  const title = (inputs.title = h('input', { type: 'text', value: article.title, placeholder: 'عنوان الخبر' }));
  const description = (inputs.description = h('textarea', { rows: 3, placeholder: 'وصف قصير يظهر في محركات البحث (120 إلى 160 حرفاً)' }, article.description));
  const keyword = (inputs.keyword = h('input', { type: 'text', value: article.keyword, placeholder: 'مثال: الجزائر' }));
  const body = (inputs.body = h('textarea', { rows: 18, placeholder: 'نص الخبر...' }, article.body));
  const type = (inputs.type = h('select', {}, ...['خبر', 'عاجل', 'آخر خبر', 'هام', 'تصريح', 'تحقيق', 'رأي'].map((t) => h('option', { value: t, selected: t === article.type }, t))));
  const status = (inputs.status = h('select', {}, ...['مسودة', 'للتدقيق', 'جاهز للنشر'].map((s) => h('option', { value: s, selected: s === article.status }, s))));
  const source = (inputs.source = h('input', { type: 'text', value: article.source, placeholder: 'المصدر (وكالة، مؤسسة، رابط)' }));
  const image = (inputs.image = h('input', { type: 'url', value: article.image, placeholder: 'رابط صورة الغلاف' }));
  const imageAlt = (inputs.imageAlt = h('input', { type: 'text', value: article.imageAlt, placeholder: 'وصف الصورة (نص بديل)' }));

  const titleCount = h('span', { class: 'count muted' });
  const descCount = h('span', { class: 'count muted' });
  const bodyCount = h('span', { class: 'count muted' });
  const side = h('div', { class: 'card' });
  const proofBox = h('div', {});

  const current = () => ({
    title: title.value,
    description: description.value,
    keyword: keyword.value,
    body: body.value,
    type: type.value,
    status: status.value,
    source: source.value,
    image: image.value,
    imageAlt: imageAlt.value,
  });

  const refresh = () => {
    const c = current();
    titleCount.textContent = `${[...c.title].length} حرف`;
    descCount.textContent = `${[...c.description].length} حرف`;
    bodyCount.textContent = `${countWords(c.body)} كلمة`;
    renderSide();
  };

  // ---- اللوحة الجانبية: تدقيق / سيو / تصميم ----
  const renderSide = () => {
    const c = current();
    const tabs = [
      ['proof', 'التدقيق'],
      ['seo', 'السيو'],
      ['design', 'التصميم'],
    ];
    const tabBar = h(
      'div',
      { class: 'tabs' },
      tabs.map(([key, label]) =>
        h('button', { class: activeTab === key ? 'on' : '', onclick: () => { activeTab = key; renderSide(); } }, label),
      ),
    );
    let content;
    if (activeTab === 'proof') content = proofPanel(c.body);
    else if (activeTab === 'seo') content = seoPanel(c);
    else content = h('div', { class: 'stack' }, h('p', { class: 'muted' }, 'صمّم صورة السوشيال من نص هذا المقال باستخدام قوالب ANN.'), h('a', { class: 'btn primary', href: `#/design/${article.id || ''}`, onclick: (e) => { if (!article.id) { e.preventDefault(); toast('احفظ المقال أولاً ثم صمّم الصورة', true); } } }, 'فتح مصمم السوشيال'));
    side.replaceChildren(tabBar, content);
  };

  const proofPanel = (text) => {
    const issues = proofread(text);
    if (!text.trim()) return h('p', { class: 'muted' }, 'اكتب نص الخبر ليبدأ التدقيق.');
    if (!issues.length) return h('p', { class: 'muted' }, '✔ لم يُعثر على مشكلات في التدقيق الآلي.');
    return h(
      'div',
      {},
      h('p', { class: 'muted' }, `${issues.length} ملاحظة. راجعها كلها قبل النشر، والتدقيق الآلي لا يغني عن القراءة.`),
      issues.slice(0, 60).map((issue) => {
        const ctx = text.slice(Math.max(0, issue.index - 18), issue.index + issue.length + 18).replace(/\n/g, ' ');
        return h(
          'div',
          { class: `issue ${issue.level}` },
          h('div', { class: 'msg' }, issue.message),
          h('div', { class: 'ctx' }, `…${ctx}…`),
          issue.suggestion !== undefined
            ? h('div', { class: 'sug' }, `الاقتراح: «${issue.suggestion || '(حذف)'}»`)
            : null,
          issue.suggestion !== undefined
            ? h('button', { class: 'btn small', onclick: () => applyFix(issue) }, 'تطبيق الاقتراح')
            : null,
        );
      }),
    );
  };

  const applyFix = (issue) => {
    const text = body.value;
    body.value = text.slice(0, issue.index) + issue.suggestion + text.slice(issue.index + issue.length);
    refresh();
    toast('تم تطبيق الاقتراح');
  };

  const seoPanel = (c) => {
    const r = seoReport({ title: c.title, description: c.description, body: c.body, keyword: c.keyword, image: c.image ? { alt: c.imageAlt } : null });
    return h(
      'div',
      {},
      h('div', { class: 'score' }, h('div', { class: 'ring', style: `--p:${r.score}` }, h('span', {}, r.score)), h('div', {}, h('div', { class: 'muted' }, 'درجة السيو'), h('div', { dir: 'ltr', style: 'font-size:13px' }, `/${r.slug || '…'}`))),
      h(
        'ul',
        { class: 'checks' },
        r.items.map((it) => h('li', { class: it.level }, it.text)),
      ),
    );
  };

  // ---- الأزرار ----
  const snapshot = () => JSON.stringify(current());
  const save = async () => {
    const data = current();
    try {
      article = article.id ? await api(`/api/articles/${article.id}`, { method: 'PUT', body: data }) : await api('/api/articles', { method: 'POST', body: data });
      saved = snapshot();
      toast('تم الحفظ');
      if (!id) location.hash = `#/article/${article.id}`;
    } catch (err) {
      toast(err.message, true);
    }
  };
  const remove = async () => {
    if (!article.id) return (location.hash = '#/');
    if (!confirm('حذف هذا المقال نهائياً؟')) return;
    await api(`/api/articles/${article.id}`, { method: 'DELETE' });
    toast('تم الحذف');
    location.hash = '#/';
  };

  for (const el of Object.values(inputs)) el.addEventListener('input', refresh);
  for (const el of [type, status]) el.addEventListener('change', refresh);

  view.replaceChildren(
    pageHead(
      article.id ? 'تحرير المقال' : 'مقال جديد',
      'الكتابة، ثم التدقيق، ثم السيو، ثم التصميم',
      [
        h('button', { class: 'btn ghost danger', onclick: remove }, 'حذف'),
        h('button', { class: 'btn primary', onclick: save }, 'حفظ'),
      ],
    ),
    h(
      'div',
      { class: 'grid-2' },
      h(
        'div',
        { class: 'card stack' },
        h('div', { style: 'display:grid;grid-template-columns:1fr 1fr 1fr;gap:12px' }, field('النوع', type), field('الحالة', status), field('المصدر', source)),
        field('العنوان', title, titleCount),
        field('الوصف', description, descCount),
        h('div', { style: 'display:grid;grid-template-columns:1fr 1fr;gap:12px' }, field('الكلمة المفتاحية', keyword), field('رابط الصورة', image)),
        field('النص البديل للصورة', imageAlt),
        field('متن الخبر', body, bodyCount),
      ),
      side,
    ),
  );
  refresh();
  saved = snapshot();
  // تحذير قبل مغادرة الشاشة إذا وُجدت تعديلات غير محفوظة
  leaveGuard = () => snapshot() === saved || confirm('توجد تعديلات غير محفوظة. متابعة؟');
}

let pendingPrefill = null;
let leaveGuard = null;
let currentHash = '';
let restoring = false;

async function screenSource() {
  setNav('source');
  const urlInput = h('input', { type: 'url', placeholder: 'https://… رابط الخبر', dir: 'ltr' });
  const out = h('div', {});
  const go = async () => {
    const url = urlInput.value.trim();
    if (!url) return toast('أدخل رابطاً', true);
    out.replaceChildren(h('p', { class: 'muted' }, 'جارٍ جلب الصفحة...'));
    try {
      const data = await api('/api/source', { method: 'POST', body: { url } });
      out.replaceChildren(
        h(
          'div',
          { class: 'card stack' },
          h('div', {}, h('div', { class: 'muted' }, 'العنوان المستخرج'), h('h2', { style: 'margin:4px 0' }, data.title || '(لم يُعثر على عنوان)')),
          data.description ? h('p', { class: 'muted' }, data.description) : null,
          data.image ? h('img', { src: data.image, alt: '', style: 'max-width:100%;border-radius:12px;max-height:260px;object-fit:cover' }) : null,
          h('div', { class: 'field' }, h('label', {}, h('span', {}, 'نص الخبر المستخرج'), h('span', { class: 'count muted' }, `${countWords(data.text)} كلمة`)), h('textarea', { rows: 12, readonly: true }, data.text || '')),
          h('div', { class: 'actions' }, h('button', { class: 'btn primary', onclick: () => createFrom(data) }, 'إنشاء مقال من هذا المصدر'), h('a', { class: 'btn ghost', href: data.url, target: '_blank', rel: 'noopener' }, 'فتح الأصل')),
        ),
      );
    } catch (err) {
      out.replaceChildren(h('div', { class: 'card', style: 'color:var(--error)' }, err.message));
    }
  };
  urlInput.addEventListener('keydown', (e) => e.key === 'Enter' && go());
  view.replaceChildren(
    pageHead('جلب من مصدر', 'الصق رابط خبر من موقع أو وكالة، وسنستخرج العنوان والنص والصورة'),
    h('div', { class: 'card stack' }, h('div', { style: 'display:flex;gap:10px' }, urlInput, h('button', { class: 'btn primary', onclick: go }, 'جلب'))),
    h('div', { style: 'margin-top:16px' }, out),
  );
  urlInput.focus();
}

function createFrom(data) {
  pendingPrefill = {
    title: data.title,
    description: data.description,
    body: data.text,
    source: data.url,
    image: data.image,
    imageAlt: data.title,
  };
  location.hash = '#/new';
}

async function screenDesign(id) {
  setNav('design');
  const articles = await api('/api/articles');
  const article = id ? await api(`/api/articles/${id}`) : null;
  view.replaceChildren(
    pageHead('تصميم السوشيال', 'صور جاهزة بقوالب ANN، تُصدَّر بالمقاس الأصلي'),
  );
  renderDesign(view, { article, articles });
}

function screenSoon() {
  setNav('soon');
  view.replaceChildren(
    pageHead('الفيديو والإنفوغراف', 'المرحلة القادمة'),
    h(
      'div',
      { class: 'card stack' },
      h('p', {}, 'هذه الأدوات مخططة للمرحلة الثانية، وتشمل:'),
      h(
        'ul',
        { class: 'checks' },
        ['إنشاء إنفوغراف من أرقام المقال', 'مونتاج فيديو قصير للريل واليوتيوب', 'تصريحات بالصوت والصورة مع الترجمة', 'تصدير متعدد المقاسات لكل منصة'].map((t) => h('li', { class: 'info' }, t)),
      ),
      h('p', { class: 'muted' }, 'سنناقش الصيغ المطلوبة قبل البدء فيها.'),
    ),
  );
}

// ---------- التوجيه ----------

async function route() {
  if (restoring) {
    restoring = false;
    return;
  }
  if (leaveGuard && !leaveGuard()) {
    // المستخدم اختار البقاء: نعيد الهاش القديم دون إعادة رسم الشاشة
    restoring = true;
    location.hash = currentHash;
    return;
  }
  leaveGuard = null;
  currentHash = location.hash;
  const hash = location.hash.replace(/^#/, '') || '/';
  const parts = hash.split('/').filter(Boolean);
  try {
    if (parts[0] === 'new') return await screenEditor(null);
    if (parts[0] === 'article' && parts[1]) return await screenEditor(parts[1]);
    if (parts[0] === 'source') return await screenSource();
    if (parts[0] === 'design') return await screenDesign(parts[1] || null);
    if (parts[0] === 'soon') return screenSoon();
    return await screenHome();
  } catch (err) {
    view.replaceChildren(h('div', { class: 'card', style: 'color:var(--error)' }, err.message));
  }
}

window.addEventListener('hashchange', route);
route();
