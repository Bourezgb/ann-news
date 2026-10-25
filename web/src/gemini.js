// عميل Gemini من جهة الخادم فقط: مفتاح API لا يصل إلى المتصفح أبداً.
// البروتوكول نفسه المستعمل في تطبيق Flutter (generateContent مع responseSchema).

export const DEFAULT_MODEL = 'gemini-flash-latest';
const BASE_URL = 'https://generativelanguage.googleapis.com/v1beta';

export class GeminiError extends Error {
  constructor(message, status = 502) {
    super(message);
    this.status = status;
  }
}

function describe(status, model) {
  switch (status) {
    case 400: return 'طلب غير صالح إلى Gemini. تحقق من النموذج المختار.';
    case 401:
    case 403: return 'مفتاح Gemini غير صالح أو لا يملك صلاحية. عدّله من الإعدادات.';
    case 404: return `النموذج «${model}» غير موجود. اختر نموذجاً آخر من الإعدادات.`;
    case 429: return 'تم تجاوز حد الاستخدام المجاني. انتظر دقيقة ثم أعد المحاولة.';
    case 500:
    case 503:
    case 504: return 'خوادم Gemini مشغولة حالياً. أعد المحاولة بعد قليل.';
    default: return `فشل الطلب إلى Gemini (${status}).`;
  }
}

export class GeminiClient {
  /**
   * @param {object} opts
   * @param {string} opts.apiKey
   * @param {string} [opts.model]
   * @param {typeof fetch} [opts.fetchImpl] يُستبدل في الاختبارات
   * @param {number} [opts.retryDelayMs]
   */
  constructor({ apiKey, model = DEFAULT_MODEL, fetchImpl = fetch, retryDelayMs = 1500 }) {
    if (!apiKey) throw new GeminiError('لم يُضبط مفتاح Gemini بعد. أضفه من صفحة الإعدادات.', 400);
    this.apiKey = apiKey;
    this.model = model;
    this.fetch = fetchImpl;
    this.retryDelayMs = retryDelayMs;
  }

  /**
   * يطلب JSON مطابقاً للمخطط. يُرجع الكائن المحلَّل.
   * @param {{system: string, user: string, schema: object, temperature?: number}} req
   */
  async generateJson({ system, user, schema, temperature = 0.2 }) {
    const body = {
      systemInstruction: { parts: [{ text: system }] },
      contents: [{ role: 'user', parts: [{ text: user }] }],
      generationConfig: {
        responseMimeType: 'application/json',
        responseSchema: schema,
        temperature,
      },
    };
    const text = await this.#post(body);
    try {
      return JSON.parse(text);
    } catch {
      throw new GeminiError('ردّ Gemini ليس JSON صالحاً. أعد المحاولة.', 502);
    }
  }

  /** اختبار سريع للمفتاح والنموذج. */
  async ping() {
    const text = await this.#post({
      contents: [{ role: 'user', parts: [{ text: 'أجب بكلمة واحدة: مرحبا' }] }],
      generationConfig: { temperature: 0 },
    });
    return text.trim().slice(0, 40);
  }

  async #post(body, retried = false) {
    const url = `${BASE_URL}/models/${encodeURIComponent(this.model)}:generateContent`;
    let res;
    try {
      res = await this.fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-goog-api-key': this.apiKey },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(90_000),
      });
    } catch (err) {
      if (err.name === 'TimeoutError') throw new GeminiError('انتهت مهلة الاتصال بـ Gemini. أعد المحاولة.', 504);
      throw new GeminiError('تعذّر الوصول إلى Gemini. تحقق من الاتصال بالإنترنت.', 502);
    }

    if (!res.ok) {
      // الأخطاء المؤقتة نعيد المحاولة مرة واحدة
      if ([500, 503].includes(res.status) && !retried) {
        await new Promise((r) => setTimeout(r, this.retryDelayMs));
        return this.#post(body, true);
      }
      throw new GeminiError(describe(res.status, this.model), res.status === 429 ? 429 : 502);
    }

    const data = await res.json();
    const parts = data?.candidates?.[0]?.content?.parts || [];
    const text = parts.map((p) => p.text || '').join('');
    if (!text) {
      const reason = data?.promptFeedback?.blockReason || data?.candidates?.[0]?.finishReason || 'غير معروف';
      throw new GeminiError(`لم يُرجع Gemini نصاً (السبب: ${reason}).`, 502);
    }
    return text;
  }
}
