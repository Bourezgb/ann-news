// استخلاص العنوان والنص وصورة الغلاف من صفحة خبر (HTML). بلا مكتبات خارجية.

const ENTITIES = { amp: '&', quot: '"', apos: "'", lt: '<', gt: '>', nbsp: ' ', laquo: '«', raquo: '»' };

export function decodeEntities(s) {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, code) => {
    if (code[0] === '#') {
      const n = code[1].toLowerCase() === 'x' ? parseInt(code.slice(2), 16) : parseInt(code.slice(1), 10);
      return Number.isFinite(n) ? String.fromCodePoint(n) : m;
    }
    return ENTITIES[code.toLowerCase()] ?? m;
  });
}

function meta(html, name) {
  const re = new RegExp(
    `<meta[^>]+(?:property|name)=["']${name}["'][^>]*content=["']([^"']*)["'][^>]*>|<meta[^>]+content=["']([^"']*)["'][^>]+(?:property|name)=["']${name}["'][^>]*>`,
    'i',
  );
  const m = html.match(re);
  return m ? decodeEntities((m[1] ?? m[2]).trim()) : '';
}

export function extractArticle(html, baseUrl) {
  const cleaned = html
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<!--[\s\S]*?-->/g, '');

  const title =
    meta(cleaned, 'og:title') ||
    decodeEntities((cleaned.match(/<title[^>]*>([\s\S]*?)<\/title>/i) || [])[1] || '').trim() ||
    decodeEntities((cleaned.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i) || [])[1] || '').replace(/<[^>]+>/g, '').trim();

  const description = meta(cleaned, 'og:description') || meta(cleaned, 'description');

  const imageRaw = meta(cleaned, 'og:image');
  let image = '';
  if (imageRaw) {
    try {
      image = new URL(imageRaw, baseUrl).href;
    } catch {
      image = '';
    }
  }

  // نفضّل فقرات داخل <article> إن وُجدت، وإلا فكل الفقرات.
  const article = (cleaned.match(/<article[^>]*>([\s\S]*?)<\/article>/i) || [])[1] || cleaned;
  const paragraphs = [...article.matchAll(/<p[^>]*>([\s\S]*?)<\/p>/gi)]
    .map((m) => decodeEntities(m[1].replace(/<[^>]+>/g, '')).replace(/\s+/g, ' ').trim())
    .filter((p) => p.length > 40);

  return { title, description, image, text: paragraphs.join('\n\n') };
}
