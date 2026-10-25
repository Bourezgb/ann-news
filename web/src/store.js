// تخزين المقالات في ملف JSON محلي (web/data/articles.json). مناسب لمستخدم واحد على الجهاز.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const FILE = join(here, '..', 'data', 'articles.json');

let cache = null;

async function load() {
  if (cache) return cache;
  try {
    cache = JSON.parse(await readFile(FILE, 'utf8'));
  } catch (err) {
    if (err.code !== 'ENOENT') throw err;
    cache = [];
  }
  return cache;
}

async function save() {
  await mkdir(dirname(FILE), { recursive: true });
  await writeFile(FILE, JSON.stringify(cache, null, 2), 'utf8');
}

export async function listArticles() {
  const all = await load();
  return all
    .map(({ id, title, type, status, updatedAt }) => ({ id, title, type, status, updatedAt }))
    .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
}

export async function getArticle(id) {
  return (await load()).find((a) => a.id === id) ?? null;
}

export async function createArticle(input) {
  const all = await load();
  const now = new Date().toISOString();
  const article = { ...pick(input), id: crypto.randomUUID(), createdAt: now, updatedAt: now };
  all.push(article);
  await save();
  return article;
}

export async function updateArticle(id, input) {
  const all = await load();
  const i = all.findIndex((a) => a.id === id);
  if (i === -1) return null;
  all[i] = { ...all[i], ...pick(input), id, createdAt: all[i].createdAt, updatedAt: new Date().toISOString() };
  await save();
  return all[i];
}

export async function deleteArticle(id) {
  const all = await load();
  const i = all.findIndex((a) => a.id === id);
  if (i === -1) return false;
  all.splice(i, 1);
  await save();
  return true;
}

const TYPES = ['خبر', 'عاجل', 'آخر خبر', 'هام', 'تصريح', 'تحقيق', 'رأي'];
const STATUSES = ['مسودة', 'للتدقيق', 'جاهز للنشر'];

function pick(input = {}) {
  const str = (v, max) => (typeof v === 'string' ? v.slice(0, max) : '');
  return {
    title: str(input.title, 300),
    description: str(input.description, 400),
    keyword: str(input.keyword, 80),
    body: str(input.body, 200_000),
    type: TYPES.includes(input.type) ? input.type : 'خبر',
    status: STATUSES.includes(input.status) ? input.status : 'مسودة',
    source: str(input.source, 500),
    image: str(input.image, 1000),
    imageAlt: str(input.imageAlt, 200),
  };
}

export const CONSTANTS = { TYPES, STATUSES };
