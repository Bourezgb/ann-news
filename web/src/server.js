// خادم ANN Studio المحلي: يقدّم واجهة الاستوديو وواجهة JSON للمقالات واستخلاص المصادر.
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { listArticles, getArticle, createArticle, updateArticle, deleteArticle, CONSTANTS } from './store.js';
import { extractArticle } from './extract.js';

const here = dirname(fileURLToPath(import.meta.url));
const PUBLIC = join(here, '..', 'public');
const PORT = Number(process.env.PORT) || 3000;
const HOST = process.env.HOST || '127.0.0.1';
const MAX_BODY = 2 * 1024 * 1024;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.ttf': 'font/ttf',
  '.svg': 'image/svg+xml',
};

function send(res, status, body, type = 'application/json; charset=utf-8') {
  const payload = typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body);
  res.writeHead(status, { 'Content-Type': type, 'Cache-Control': 'no-store' });
  res.end(payload);
}

async function readJson(req) {
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY) throw Object.assign(new Error('الطلب كبير جداً'), { status: 413 });
    chunks.push(chunk);
  }
  if (!chunks.length) return {};
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw Object.assign(new Error('JSON غير صالح'), { status: 400 });
  }
}

async function fetchSource(url) {
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    throw Object.assign(new Error('الرابط غير صالح'), { status: 400 });
  }
  if (!['http:', 'https:'].includes(parsed.protocol)) {
    throw Object.assign(new Error('يُسمح بروابط http و https فقط'), { status: 400 });
  }
  const res = await fetch(parsed, {
    headers: { 'User-Agent': 'ANN-Studio/0.1 (local editorial tool)', 'Accept-Language': 'ar,fr;q=0.8' },
    signal: AbortSignal.timeout(15_000),
    redirect: 'follow',
  });
  if (!res.ok) throw Object.assign(new Error(`تعذّر جلب الصفحة (${res.status})`), { status: 502 });
  const html = await res.text();
  return { url: res.url, ...extractArticle(html, res.url) };
}

async function handleApi(req, res, path) {
  const method = req.method;
  const parts = path.split('/').filter(Boolean); // ['api', ...]

  if (parts[1] === 'health') return send(res, 200, { ok: true });
  if (parts[1] === 'meta') return send(res, 200, CONSTANTS);

  if (parts[1] === 'source' && method === 'POST') {
    const { url } = await readJson(req);
    return send(res, 200, await fetchSource(String(url || '')));
  }

  if (parts[1] === 'articles') {
    const id = parts[2];
    if (!id) {
      if (method === 'GET') return send(res, 200, await listArticles());
      if (method === 'POST') return send(res, 201, await createArticle(await readJson(req)));
    } else {
      if (method === 'GET') {
        const a = await getArticle(id);
        return a ? send(res, 200, a) : send(res, 404, { error: 'غير موجود' });
      }
      if (method === 'PUT') {
        const a = await updateArticle(id, await readJson(req));
        return a ? send(res, 200, a) : send(res, 404, { error: 'غير موجود' });
      }
      if (method === 'DELETE') {
        return (await deleteArticle(id)) ? send(res, 204, '') : send(res, 404, { error: 'غير موجود' });
      }
    }
  }
  return send(res, 404, { error: 'مسار غير موجود' });
}

async function serveStatic(res, path) {
  const rel = path === '/' ? '/index.html' : path;
  const file = normalize(join(PUBLIC, decodeURIComponent(rel)));
  if (!file.startsWith(PUBLIC)) return send(res, 403, { error: 'ممنوع' });
  try {
    const data = await readFile(file);
    return send(res, 200, data, MIME[extname(file)] || 'application/octet-stream');
  } catch {
    return send(res, 404, { error: 'غير موجود' });
  }
}

export function createApp() {
  return createServer(async (req, res) => {
    try {
      const path = new URL(req.url, `http://${req.headers.host || 'localhost'}`).pathname;
      if (path.startsWith('/api/')) return await handleApi(req, res, path);
      if (req.method !== 'GET' && req.method !== 'HEAD') return send(res, 405, { error: 'غير مسموح' });
      return await serveStatic(res, path);
    } catch (err) {
      const status = err.status || 500;
      if (status === 500) console.error(err);
      return send(res, status, { error: err.message || 'خطأ داخلي' });
    }
  });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  createApp().listen(PORT, HOST, () => {
    console.log(`ANN Studio يعمل على http://${HOST}:${PORT}`);
  });
}
