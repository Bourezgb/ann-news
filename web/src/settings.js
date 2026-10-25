// إعدادات محلية (مفتاح Gemini والنموذج). تُحفظ في data/settings.json على جهازك ولا تُرسل إلى المتصفح.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MODEL } from './gemini.js';

const here = dirname(fileURLToPath(import.meta.url));
const FILE = join(here, '..', 'data', 'settings.json');

let cache = null;

async function load() {
  if (cache) return cache;
  try {
    cache = JSON.parse(await readFile(FILE, 'utf8'));
  } catch (err) {
    if (err.code !== 'ENOENT') throw err;
    cache = {};
  }
  return cache;
}

/** ما يُسمح للمتصفح برؤيته: لا المفتاح نفسه، فقط وجوده وآخر 4 خانات. */
export async function publicSettings() {
  const s = await load();
  return {
    hasKey: Boolean(s.geminiKey),
    keyHint: s.geminiKey ? `…${s.geminiKey.slice(-4)}` : '',
    model: s.model || DEFAULT_MODEL,
  };
}

/** القيم الداخلية للخادم فقط. */
export async function serverSettings() {
  const s = await load();
  return { geminiKey: s.geminiKey || '', model: s.model || DEFAULT_MODEL };
}

export async function updateSettings(input = {}) {
  const s = await load();
  if (typeof input.geminiKey === 'string') {
    const key = input.geminiKey.trim();
    if (key) s.geminiKey = key.slice(0, 200);
    else delete s.geminiKey; // سلسلة فارغة تعني حذف المفتاح
  }
  if (typeof input.model === 'string' && input.model.trim()) {
    s.model = input.model.trim().slice(0, 80);
  }
  await mkdir(dirname(FILE), { recursive: true });
  await writeFile(FILE, JSON.stringify(s, null, 2), 'utf8');
  return publicSettings();
}
