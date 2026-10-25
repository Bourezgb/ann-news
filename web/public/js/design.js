// مصمم السوشيال: يرسم نص المقال فوق قوالب ANN بالمقاس الأصلي للقالب، ويصدّر PNG.
// كل النصوص تُرسم بخط beIN، ومواضع النصوص وأحجامها من assets/templates/templates.json.

const TEMPLATE_BY_TYPE = {
  عاجل: 'urgent_solid',
  هام: 'important_solid',
  تصريح: 'statement_quote',
};

const ROLE_LABELS = {
  title: 'العنوان',
  label: 'الشارة',
  speaker_name: 'اسم المتحدث',
  speaker_role: 'صفة المتحدث',
  title2: 'العنوان الثاني',
};

const FONT_FAMILY = 'BeIN';

let fontReady = null;
function loadFont() {
  if (!fontReady) {
    const face = new FontFace(FONT_FAMILY, 'url(assets/fonts/BeIN-Normal.ttf)');
    fontReady = face.load().then((loaded) => {
      document.fonts.add(loaded);
      return loaded;
    });
  }
  return fontReady;
}

function loadImage(src) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error(`تعذّر تحميل الصورة: ${src}`));
    img.src = src;
  });
}

function readFileAsDataUrl(file) {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(r.result);
    r.onerror = () => reject(r.error);
    r.readAsDataURL(file);
  });
}

// يرسم الصورة بحجم يغطي المساحة كاملة (cover) ويقص الزائد من الوسط.
function drawCover(ctx, img, w, h) {
  const scale = Math.max(w / img.width, h / img.height);
  const dw = img.width * scale;
  const dh = img.height * scale;
  ctx.drawImage(img, (w - dw) / 2, (h - dh) / 2, dw, dh);
}

// يلفّ النص على الكلمات ضمن العرض المحدد، ويصغّر الخط إن تجاوز الارتفاع المسموح.
function layoutText(ctx, text, layer) {
  let size = layer.fontSize;
  const lineHeight = layer.lineHeight || 1.3;
  for (let attempt = 0; attempt < 24; attempt++) {
    ctx.font = `${size}px ${FONT_FAMILY}`;
    const lines = wrap(ctx, text, layer.width);
    const height = lines.length * size * lineHeight;
    if (!layer.maxHeight || height <= layer.maxHeight || size <= 16) return { lines, size, lineHeight };
    size *= 0.94;
  }
  return { lines: wrap(ctx, text, layer.width), size, lineHeight };
}

function wrap(ctx, text, maxWidth) {
  const words = text.split(/\s+/).filter(Boolean);
  const lines = [];
  let line = '';
  for (const word of words) {
    const candidate = line ? `${line} ${word}` : word;
    if (ctx.measureText(candidate).width <= maxWidth || !line) {
      line = candidate;
    } else {
      lines.push(line);
      line = word;
    }
  }
  if (line) lines.push(line);
  return lines;
}

function drawLayer(ctx, layer, text) {
  if (!text) return;
  const { lines, size, lineHeight } = layoutText(ctx, text, layer);
  const align = layer.align || 'right';
  const x = align === 'center' ? layer.x + layer.width / 2 : align === 'left' ? layer.x : layer.x + layer.width;
  ctx.direction = 'rtl';
  ctx.textAlign = align;
  ctx.textBaseline = 'top';
  ctx.fillStyle = layer.color || '#ffffff';
  ctx.strokeStyle = layer.color || '#ffffff';
  // الخط غير عريض في الملف، فنحاكي الوزن الثقيل بحدّ رفيع من لون النص
  ctx.lineWidth = layer.bold ? size * 0.035 : 0;
  lines.forEach((ln, i) => {
    const y = layer.y + i * size * lineHeight;
    if (layer.bold) ctx.strokeText(ln, x, y);
    ctx.fillText(ln, x, y);
  });
}

function h2(text) {
  const el = document.createElement('h3');
  el.textContent = text;
  el.style.margin = '0';
  return el;
}

export async function renderDesign(root, { article, articles }) {
  const [templates] = await Promise.all([fetch('assets/templates/templates.json').then((r) => r.json()), loadFont()]);
  const list = templates.templates;

  const state = {
    templateId: TEMPLATE_BY_TYPE[article?.type] || 'latest_solid',
    texts: { title: article?.title || '', label: null, speaker_name: '', speaker_role: '', title2: '' },
    photo: null,
  };

  const canvas = document.createElement('canvas');
  canvas.id = 'designCanvas';
  const ctx = canvas.getContext('2d');
  const imageCache = new Map();
  const getImage = (file) => {
    if (!imageCache.has(file)) imageCache.set(file, loadImage(`assets/templates/${file}`));
    return imageCache.get(file);
  };

  const current = () => list.find((t) => t.id === state.templateId);
  const hint = document.createElement('p');
  hint.className = 'muted';

  const render = async () => {
    const tpl = current();
    canvas.width = tpl.width;
    canvas.height = tpl.height;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    if (tpl.file.endsWith('.png') && state.photo) {
      // القوالب بصورة: الصورة تُرسم أولاً ثم يُرسم القالب الشفاف فوقها
      drawCover(ctx, await loadImage(state.photo), canvas.width, canvas.height);
    }
    ctx.drawImage(await getImage(tpl.file), 0, 0, canvas.width, canvas.height);

    for (const layer of tpl.layers) {
      const text = layer.role === 'label' ? (state.texts.label ?? layer.text) : state.texts[layer.role];
      drawLayer(ctx, layer, text ?? '');
    }
    const needsPhoto = tpl.file.endsWith('.png') && tpl.id.endsWith('_photo') && !state.photo;
    hint.textContent = needsPhoto ? 'هذا القالب يحتاج صورة خلفية: ارفع صورة من الجهاز.' : `المقاس: ${tpl.width}×${tpl.height}`;
  };

  // ---- قائمة القوالب ----
  const tplButtons = list.map((tpl) => {
    const btn = document.createElement('button');
    btn.className = 'tpl' + (tpl.id === state.templateId ? ' on' : '');
    btn.type = 'button';
    const img = document.createElement('img');
    img.src = `assets/templates/${tpl.file}`;
    img.alt = '';
    const label = document.createElement('div');
    label.textContent = tpl.name;
    const small = document.createElement('small');
    small.textContent = `${tpl.width}×${tpl.height}`;
    label.append(small);
    btn.append(img, label);
    btn.addEventListener('click', async () => {
      state.templateId = tpl.id;
      tplButtons.forEach((b) => b.classList.toggle('on', b === btn));
      await render();
    });
    return btn;
  });

  // ---- حقول النص ----
  const textInputs = {};
  const textField = (role, { multiline = false, placeholder = '' } = {}) => {
    const input = document.createElement(multiline ? 'textarea' : 'input');
    if (!multiline) input.type = 'text';
    input.placeholder = placeholder;
    input.value = state.texts[role] ?? '';
    input.addEventListener('input', () => {
      state.texts[role] = input.value;
      render();
    });
    textInputs[role] = input;
    const wrapper = document.createElement('div');
    wrapper.className = 'field';
    const lbl = document.createElement('label');
    lbl.textContent = ROLE_LABELS[role] || role;
    wrapper.append(lbl, input);
    return wrapper;
  };

  // ---- الصورة الخلفية ----
  const fileInput = document.createElement('input');
  fileInput.type = 'file';
  fileInput.accept = 'image/*';
  fileInput.hidden = true;
  fileInput.addEventListener('change', async () => {
    const file = fileInput.files[0];
    if (!file) return;
    state.photo = await readFileAsDataUrl(file);
    await render();
  });
  const drop = document.createElement('div');
  drop.className = 'drop';
  drop.textContent = 'اختر صورة الخلفية من الجهاز (تُستعمل في القوالب بصورة)';
  drop.addEventListener('click', () => fileInput.click());

  const resetBtn = document.createElement('button');
  resetBtn.className = 'btn ghost';
  resetBtn.type = 'button';
  resetBtn.textContent = 'مسح الصورة';
  resetBtn.addEventListener('click', async () => {
    state.photo = null;
    await render();
  });

  // ---- تعبئة النص من مقال محفوظ ----
  const articleSelect = document.createElement('select');
  const none = document.createElement('option');
  none.value = '';
  none.textContent = 'اختر مقالاً لتعبئة النص';
  articleSelect.append(none);
  for (const a of articles) {
    const o = document.createElement('option');
    o.value = a.id;
    o.textContent = a.title || 'بلا عنوان';
    if (article && a.id === article.id) o.selected = true;
    articleSelect.append(o);
  }
  articleSelect.addEventListener('change', async () => {
    if (!articleSelect.value) return;
    const full = await fetch(`/api/articles/${articleSelect.value}`).then((r) => r.json());
    state.texts.title = full.title || '';
    textInputs.title.value = state.texts.title;
    await render();
  });

  // ---- تصدير ----
  const exportBtn = document.createElement('button');
  exportBtn.className = 'btn primary';
  exportBtn.type = 'button';
  exportBtn.textContent = 'تصدير PNG';
  exportBtn.addEventListener('click', () => {
    canvas.toBlob((blob) => {
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = `ann-${state.templateId}-${Date.now()}.png`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 1000);
    }, 'image/png');
  });

  const tplList = document.createElement('div');
  tplList.className = 'stack';
  tplList.append(...tplButtons);

  const controls = document.createElement('div');
  controls.className = 'stack';
  controls.append(
    h2('النص'),
    articleSelect,
    textField('title', { multiline: true, placeholder: 'عنوان الخبر' }),
    textField('title2', { placeholder: 'العنوان الثاني (للريل واليوتيوب)' }),
    textField('speaker_name', { placeholder: 'اسم المتحدث (للتصريح)' }),
    textField('speaker_role', { placeholder: 'صفة المتحدث (للتصريح)' }),
    h2('الخلفية'),
    drop,
    fileInput,
    resetBtn,
    hint,
    exportBtn,
  );

  const stage = document.createElement('div');
  stage.className = 'canvas-wrap';
  stage.append(canvas);

  const side = document.createElement('div');
  side.className = 'card';
  side.append(controls);

  const leftCol = document.createElement('div');
  leftCol.className = 'card tpl-col';
  leftCol.append(h2('القوالب'), tplList);

  const layout = document.createElement('div');
  layout.className = 'design-layout';
  layout.append(leftCol, stage, side);
  root.append(layout);

  await render();
}
