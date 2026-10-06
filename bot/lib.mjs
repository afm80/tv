// منطق البوت (دوال نقية بدون اتصال بالشبكة) — يسهل اختباره
export const ARAB = ['DZ','BH','KM','DJ','EG','IQ','JO','KW','LB','LY','MR','MA','OM','PS','QA','SA','SO','SD','SY','TN','AE','YE'];

const ALIASES = {
  SA: ['السعودية', 'المملكة العربية السعودية'], AE: ['الإمارات', 'الإمارات العربية المتحدة'],
  EG: ['مصر'], IQ: ['العراق'], JO: ['الأردن'], KW: ['الكويت'], LB: ['لبنان'], LY: ['ليبيا'],
  MA: ['المغرب'], DZ: ['الجزائر'], TN: ['تونس'], OM: ['عمان', 'سلطنة عمان'], QA: ['قطر'],
  BH: ['البحرين'], SY: ['سوريا'], YE: ['اليمن'], SD: ['السودان'], PS: ['فلسطين'],
  MR: ['موريتانيا'], SO: ['الصومال'], DJ: ['جيبوتي'], KM: ['جزر القمر'],
  US: ['أمريكا', 'الولايات المتحدة'], GB: ['بريطانيا', 'المملكة المتحدة'], UK: ['بريطانيا', 'المملكة المتحدة'], DE: ['ألمانيا'],
  FR: ['فرنسا'], ES: ['إسبانيا', 'اسبانيا'], IT: ['إيطاليا', 'ايطاليا'], TR: ['تركيا'], RU: ['روسيا'],
  IN: ['الهند'], BR: ['البرازيل'], CA: ['كندا'], AU: ['أستراليا', 'استراليا'], JP: ['اليابان'], KR: ['كوريا الجنوبية', 'كوريا']
};

let dn = null;
try { dn = new Intl.DisplayNames(['ar'], { type: 'region' }); } catch {}
const NAME_OVERRIDE = { UK: 'المملكة المتحدة', INT: 'قنوات دولية' }; // iptv-org يستخدم UK بدل GB
// صورة علم الدولة (فارغة إن لم يكن الرمز دولة حقيقية مثل INT)
export const flagUrl = code => { const c = code === 'UK' ? 'GB' : String(code || '').toUpperCase(); return /^[A-Z]{2}$/.test(c) ? `https://flagcdn.com/w320/${c.toLowerCase()}.png` : ''; };
export const arName = code => NAME_OVERRIDE[code] || (() => { try { return dn && dn.of(code); } catch { return null; } })() || code;

// توحيد النص العربي للمقارنة (يتجاهل التشكيل والهمزات والـ "ال" والرموز/الإيموجي)
export const norm = s => String(s || '').toLowerCase()
  .replace(/[\u064B-\u065F\u0670\u0640]/g, '')
  .replace(/[أإآ]/g, 'ا').replace(/ى/g, 'ي').replace(/ة/g, 'ه')
  .replace(/[^\p{L}\p{N}\s]/gu, ' ').replace(/\s+/g, ' ').trim();
const key = s => norm(s).split(' ').map(w => w.replace(/^ال/, '')).join(' ');

// مفتاح مقارنة الأسماء (يتجاهل tv/hd/قناة والمسافات)
export const nameKey = s => norm(s).split(' ').filter(w => !['tv', 'hd', 'channel', 'قناه'].includes(w)).join('');

// ───────── قراءة الحقول بنفس طريقة الموقع (index.html) ولوحة التحكم (admin.html) بالضبط ─────────
// أقسام القناة: categoryIds ثم categories ثم categoryId ثم catId (مصفوفة أو كائن)
export const idsOf = v => {
  const x = v?.categoryIds ?? v?.categories ?? (v?.categoryId ? [v.categoryId] : (v?.catId ? [v.catId] : []));
  if (typeof x === 'string') return x ? [x] : [];
  return (Array.isArray(x) ? x : Object.values(x || {})).map(String).filter(id => id && id !== 'undefined');
};
const LEGACY_LINK_PROPS = ['mainLink', 'hdLink', 'sdLink', 'backupLink', 'url', 'stream', 'src', 'play', 'link', 'video', 'm3u8', 'mp4'];
// روابط القناة: links (نص أو {url,label}) + الحقول القديمة. legacy:false = links فقط (حقول البوت)
export function linkEntries(ch, { legacy = true } = {}) {
  const out = [], L = ch?.links;
  if (L && typeof L === 'object') for (const [k, e] of Object.entries(L)) {
    if (e && typeof e === 'object' && e.url) out.push({ key: k, label: e.label || k, url: String(e.url) });
    else if (typeof e === 'string' && e) out.push({ key: k, label: k, url: e });
  }
  if (legacy) for (const p of LEGACY_LINK_PROPS) {
    const u = ch?.[p];
    if (typeof u === 'string' && u && !out.some(l => l.url === u)) out.push({ key: null, label: p, url: u });
  }
  return out;
}

export const keyOf = id => 'bot_' + String(id).replace(/[.$#\[\]\/]/g, '_');
const cleanKey = s => String(s).replace(/[.$#\[\]\/]/g, '');

// مطابقة الدول بالأقسام الفرعية: أولاً تطابق تام، ثم احتواء
export function matchAll(codes, cats, extraAliases = {}) {
  const cand = c => [arName(c), ...(ALIASES[c] || []), ...(extraAliases[c] || [])].map(key);
  const result = {}, used = new Set();
  for (const code of codes) {
    const c = cats.find(x => !used.has(x.id) && cand(code).includes(key(x.name)));
    if (c) { result[code] = c.id; used.add(c.id); }
  }
  for (const code of codes) {
    if (result[code]) continue;
    const c = cats.find(x => !used.has(x.id) && cand(code).some(a => a && (' ' + key(x.name) + ' ').includes(' ' + a + ' ')));
    if (c) { result[code] = c.id; used.add(c.id); }
  }
  return result;
}

export function groupEligible({ channels, blocklist, excludeCategories, allowedCategories, blockNamePatterns, countries }) {
  const blocked = new Set((blocklist || []).map(b => b.channel));
  const ex = new Set(excludeCategories || []), al = new Set(allowedCategories || []);
  const pats = (blockNamePatterns || []).map(p => new RegExp(p, 'i'));
  const want = new Set(countries), out = {};
  for (const c of channels) {
    if (!want.has(c.country) || c.is_nsfw || c.closed || c.replaced_by || blocked.has(c.id)) continue;
    const cats = c.categories || [];
    if (cats.some(x => ex.has(x))) continue;
    if (al.size && !cats.some(x => al.has(x))) continue;
    const names = [c.name, ...(c.alt_names || [])].join(' | ');
    if (pats.some(p => p.test(names))) continue;
    (out[c.country] ||= []).push(c);
  }
  return out;
}

const qn = q => parseInt(String(q || '').replace(/\D/g, ''), 10) || 0;

// روابط https فقط، بدون شروط User-Agent/Referrer (المتصفح لا يستطيع إرسالها)
export function candidateStreams(list, max) {
  const seen = new Set();
  return list.filter(s => {
    if (!s.url || !/^https:\/\//i.test(s.url) || s.user_agent || s.referrer || seen.has(s.url)) return false;
    seen.add(s.url); return true;
  }).sort((a, b) => qn(b.quality) - qn(a.quality)).slice(0, max);
}

export const linkLabel = (i, q) => `رابط ${i + 1}${q ? ' ' + cleanKey(q) : ''}`;

export function pickLogo(channel, logos) {
  const own = (logos || []).filter(l => l.url && /^https:\/\//i.test(l.url));
  own.sort((a, b) => (a.feed ? 1 : 0) - (b.feed ? 1 : 0) || (b.width || 0) - (a.width || 0));
  const l = own[0]?.url || channel.logo || '';
  return /^https:\/\//i.test(l) ? l : '';
}

const sleep = ms => new Promise(r => setTimeout(r, ms));

// فحص الرابط: يعمل (200) + يسمح بالتشغيل من موقعك (CORS) + ملف HLS صالح
// retries: إعادة المحاولة عند الفشل (لتفادي الأعطال العابرة قبل الحكم على الرابط بأنه ميت)
export async function checkStream(url, { timeoutMs = 8000, origin = '', requireCors = true, retries = 0 } = {}, fetchImpl = fetch) {
  const once = async () => {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), timeoutMs);
    try {
      const headers = { 'User-Agent': 'Mozilla/5.0 (AlfahamBot)' };
      if (origin) headers.Origin = origin;
      const r = await fetchImpl(url, { signal: ctrl.signal, headers });
      if (!r.ok) return false;
      if (requireCors) {
        const a = r.headers.get('access-control-allow-origin');
        if (!a || (origin && a !== '*' && a !== origin)) return false;
      }
      if (/\.m3u8/i.test(url)) return (await r.text()).slice(0, 400).includes('#EXTM3U');
      try { await r.body?.cancel(); } catch {}
      return true;
    } catch { return false; } finally { clearTimeout(t); }
  };
  for (let a = 0; a <= retries; a++) {
    if (await once()) return true;
    if (a < retries) await sleep(700);
  }
  return false;
}

// تشغيل دالة غير متزامنة على عناصر بعدد متوازٍ محدود
export async function mapLimit(items, limit, fn) {
  const res = new Array(items.length); let i = 0;
  await Promise.all(Array.from({ length: Math.min(Math.max(1, limit), items.length) }, async () => {
    for (;;) { const idx = i++; if (idx >= items.length) return; res[idx] = await fn(items[idx], idx); }
  }));
  return res;
}

// بصمة الحقول التي يملكها البوت/اللوحة معاً؛ إن تغيّرت أثناء التشغيل فهذا تعديل من اللوحة
const sigOf = v => JSON.stringify([
  v?.name || '', v?.img || '', idsOf(v).slice().sort(),
  linkEntries(v, { legacy: false }).map(l => [l.key, l.url]).sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
]);
const sameList = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
const asList = x => (x == null ? [] : (Array.isArray(x) ? x : Object.values(x)).map(String));
const linksObj = ents => Object.fromEntries(ents.map(l => [l.key, l.url]));
const stable = o => JSON.stringify(Object.entries(o || {}).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));

// ═════════════════════════════════════════════════════════════════════════════════════════════
// خطة المزامنة. المبادئ:
//  1) قنوات البوت الموجودة تُفحص أولاً: الرابط الشغال يبقى، الميت يُستبدل برابط شغال من المصدر.
//  2) القناة لا تُحذف إلا إذا ماتت كل روابطها (وبعد deleteAfterFailures تشغيلات متتالية) أو سحبها المصدر.
//  3) السقف لا يُخرج قناة شغالة أبداً: القنوات الجديدة فقط تملأ الخانات الفارغة.
//  4) لا كتابة هنا؛ الخطة تُدمج لاحقاً مع حالة القاعدة الطازجة عبر reconcile().
// ═════════════════════════════════════════════════════════════════════════════════════════════
export async function buildPlan({ api, cats, chans, cfg, check, only = [], ignore = new Set(), ignoreCats = new Set(), countryNames = {}, now = Date.now(), onCommit = null }) {
  const log = [], summary = {}, empty = [];
  cats = cats || {}; chans = chans || {};
  const catList = Object.entries(cats).filter(([, v]) => v).map(([k, v]) => ({ id: v.id || k, name: v.name || '', parentId: String(v.parentId || v.parent || '') }));
  const top = catList.filter(c => !c.parentId);
  const excluded = new Set((cfg.excludeCountries || []).map(s => String(s).toUpperCase()));
  const pick = codes => codes.filter(c => !excluded.has(c) && (!only.length || only.includes(c)));
  const findSection = s => {
    if (s.id && catList.some(c => c.id === s.id)) return s.id;
    const names = s.names.map(norm);
    return top.find(c => names.includes(norm(c.name)))?.id || null;
  };
  const catCreates = {}, catFills = {}, jobs = [];
  const nm = code => { const a = arName(code); return a && a !== code ? a : (countryNames[code] || code); };
  const aliases = cfg.countryAliases || {};
  const addJob = (code, catId, arabic) => {
    if (ignoreCats.has(catId)) return log.push(`⏭ تجاهل ${nm(code)}: حذفتَ قسمها من لوحة التحكم`);
    jobs.push({ code, catId, arabic });
  };

  // القسم العربي: نطابق الأقسام الفرعية الموجودة ونُنشئ الناقص فقط
  const arabCodes = pick(cfg.sections.arab.countries || ARAB);
  const arabSec = findSection(cfg.sections.arab);
  if (!arabSec) log.push(`⚠ لم أجد القسم العربي. الأقسام الرئيسية الموجودة: ${top.map(c => c.name).join('، ')}`);
  else {
    const kids = catList.filter(c => c.parentId === arabSec);
    const m = matchAll(arabCodes, kids, aliases);
    arabCodes.forEach((code, i) => {
      if (m[code]) return addJob(code, m[code], true);
      const id = `bot_cat_${code}`;
      if (catList.some(c => c.id === id)) return addJob(code, id, true);
      if (ignoreCats.has(id)) return addJob(code, id, true);
      if (cfg.sections.arab.autoCreateCountries === false) return log.push(`⚠ لا يوجد قسم فرعي لـ ${nm(code)} (${code}) داخل القسم العربي`);
      catCreates[id] = { id, name: nm(code), img: flagUrl(code), parentId: arabSec, link: '', order: now + i, source: 'bot' };
      addJob(code, id, true);
    });
  }

  // القسم العالمي: كل دول المصدر ما عدا العربية والمستثناة
  let worldList = cfg.sections.world.countries || [];
  if (worldList.includes('*')) {
    const arabSet = new Set(cfg.sections.arab.countries || ARAB);
    const fromSource = [...new Set(api.channels.map(c => c.country).filter(Boolean))].filter(c => !arabSet.has(c));
    worldList = [...new Set([...worldList.filter(c => c !== '*'), ...fromSource])].sort((a, b) => nm(a).localeCompare(nm(b), 'ar'));
  }
  const worldCodes = pick(worldList);
  let worldSec = findSection(cfg.sections.world);
  if (!worldSec && worldCodes.length) {
    worldSec = 'bot_sec_world';
    if (!ignoreCats.has(worldSec)) {
      catCreates[worldSec] = { id: worldSec, name: cfg.sections.world.names[0], img: '', parentId: '', link: '', order: now, source: 'bot' };
      log.push(`＋ سيُنشأ القسم الرئيسي: ${cfg.sections.world.names[0]}`);
    } else worldSec = null;
  }
  if (worldSec) {
    const kids = catList.filter(c => c.parentId === worldSec);
    const m = matchAll(worldCodes, kids, aliases);
    worldCodes.forEach((code, i) => {
      if (m[code]) return addJob(code, m[code], false);
      const id = `bot_cat_${code}`;
      if (catList.some(c => c.id === id)) return addJob(code, id, false); // موجود: لا نعيد كتابته
      if (ignoreCats.has(id)) return addJob(code, id, false);
      if (cfg.sections.world.autoCreateCountries === false) return log.push(`⚠ لا يوجد قسم فرعي لـ ${nm(code)} (${code}) في القسم العالمي`);
      catCreates[id] = { id, name: nm(code), img: flagUrl(code), parentId: worldSec, link: '', order: now + i, source: 'bot' };
      addJob(code, id, false);
    });
  }

  // ── أقسام حسب الفئة (أخبار، وثائقية، رياضة...): نفس القناة تُربط بقسم دولتها وبقسم فئتها دون تكرار السجل ──
  // scope: all = كل الدول | arab = دول القسم العربي فقط | world = ما عداها. تُطابَق الأقسام الموجودة بالاسم، وتُنشأ الناقصة.
  const arabSetAll = new Set(cfg.sections.arab.countries || ARAB);
  const secDefs = [], secCreate = {};
  (cfg.categorySections || []).forEach((def, i) => {
    if (!def || def.enabled === false || !def.key || !(def.categories || []).length || !(def.names || []).length) return;
    const id = findSection(def) || `bot_sec_${def.key}`;
    if (ignoreCats.has(id)) return log.push(`⏭ تجاهل قسم ${def.names[0]}: حذفتَه من لوحة التحكم`);
    if (!catList.some(c => c.id === id) && !secCreate[id]) secCreate[id] = { id, name: def.names[0], img: '', parentId: '', link: '', order: now + 1000 + i, source: 'bot' };
    secDefs.push({ id, name: def.names[0], cats: new Set(def.categories), scope: def.scope || 'all' });
  });
  const secIdsFor = c => {
    const isArab = arabSetAll.has(c.country), cs = c.categories || [];
    return [...new Set(secDefs.filter(d => (d.scope === 'arab' ? isArab : d.scope === 'world' ? !isArab : true) && cs.some(x => d.cats.has(x))).map(d => d.id))];
  };
  const secIdSet = new Set(secDefs.map(d => d.id)), secUsed = {};

  // أقسام أنشأها البوت سابقاً بلا صورة: نضع العلم فقط (ولا نلمس أي صورة وضعتها أنت)
  for (const j of jobs) {
    const old = cats[j.catId] || Object.values(cats).find(v => v && v.id === j.catId);
    if (old && old.source === 'bot' && !old.img && flagUrl(j.code)) catFills[j.catId] = flagUrl(j.code);
  }

  const botCats = new Set([...jobs.map(j => j.catId), ...secIdSet]);
  // حفظ تدريجي: onCommit تُستدعى بعد المرحلة 1 ثم بعد كل دولة، فإذا انقطع التشغيل يبقى ما أُنجز
  const sectionCreates = Object.fromEntries(Object.entries(catCreates).filter(([id]) => !jobs.some(j => j.catId === id)));
  const commit = async chunk => {
    const need = {};
    for (const u of Object.values(chunk.upserts || {})) for (const id of (u.isNew ? u.data.categoryIds : u.catIds) || []) if (secCreate[id] && !secUsed[id]) { secUsed[id] = secCreate[id]; need[id] = secCreate[id]; }
    if (onCommit) await onCommit({ catCreates: {}, catFills: {}, upserts: {}, deletes: {}, strikes: {}, ...chunk, catCreates: { ...(chunk.catCreates || {}), ...need }, botCats });
  };
  const elig = groupEligible({ ...cfg, channels: api.channels, blocklist: api.blocklist, countries: jobs.map(j => j.code) });
  const eligByKey = new Map();
  for (const list of Object.values(elig)) for (const c of list) eligByKey.set(keyOf(c.id), c);
  const srcById = new Map(api.channels.map(c => [c.id, c]));
  const streamsBy = new Map();
  for (const s of api.streams) if (s.channel) (streamsBy.get(s.channel) || streamsBy.set(s.channel, []).get(s.channel)).push(s);
  const logosBy = new Map();
  for (const l of api.logos || []) if (l.channel) (logosBy.get(l.channel) || logosBy.set(l.channel, []).get(l.channel)).push(l);

  // فهرس القنوات اليدوية (وقنوات البوت المحمية) لتجنب التكرار — يقرأ الحقول القديمة أيضاً
  const manualIdx = { names: new Set(), urls: new Set() };
  for (const v of Object.values(chans)) {
    if (!v || (v.source === 'bot' && !v.manual)) continue;
    const n = nameKey(v.name); if (n.length >= 3) manualIdx.names.add(n);
    for (const l of linkEntries(v)) manualIdx.urls.add(l.url);
  }
  const isDupOfManual = (c, urls) => {
    const names = [c?.name, ...(c?.alt_names || [])].map(nameKey).filter(n => n.length >= 3);
    return names.some(n => manualIdx.names.has(n)) || urls.some(u => manualIdx.urls.has(u));
  };

  const maxLinks = cfg.maxLinksPerChannel || 3, conc = cfg.checkConcurrency || 20;
  const checkOn = cfg.checkLinks !== false;
  const prune = cfg.pruneMissing !== false && !only.length;
  const failLimit = Math.max(1, cfg.deleteAfterFailures ?? 2);
  const arName2 = (job, c) => (job.arabic && cfg.preferArabicNames ? (c.alt_names || []).find(n => /[\u0600-\u06FF]/.test(n)) : null);
  const st = {};
  for (const j of jobs) st[j.code] = { name: nm(j.code), existing: 0, kept: 0, replaced: 0, added: 0, removed: 0, struck: 0, capped: 0, manual: 0, ignored: 0, dups: 0 };

  // ── المرحلة 1: فحص قنوات البوت الموجودة (الشغال يبقى، الميت يُستبدل، لا حذف إلا للميت فعلاً) ──
  const jobByCode = new Map(jobs.map(j => [j.code, j])), jobByCat = new Map(jobs.map(j => [j.catId, j]));
  const tasks = [];
  for (const [k, v] of Object.entries(chans)) {
    if (!v || v.source !== 'bot') continue;
    const job = jobByCode.get(v.country) || idsOf(v).map(id => jobByCat.get(id)).find(Boolean);
    if (!job) continue;
    st[job.code].existing++;
    if (v.manual) { st[job.code].manual++; continue; }
    tasks.push({ job, k, v });
  }

  const verify = async ({ job, k, v }) => {
    const c = eligByKey.get(k);
    const old = linkEntries(v, { legacy: false });
    const hasExtras = idsOf(v).some(id => !botCats.has(id));
    const base = { job, k, v, c, hasExtras, basisSig: sigOf(v) };
    if (!c && srcById.has(v.sourceId)) return { ...base, kind: 'withdrawn' };                 // المصدر سحبها (مغلقة/محظورة/مستثناة)
    if (isDupOfManual(c || v, old.map(l => l.url))) return { ...base, kind: 'dup' };           // أضفتَ مثلها يدوياً
    const alive = [], dead = [];
    for (const l of old) (!checkOn || await check(l.url, { retry: true }) ? alive : dead).push(l);
    const fresh = [];
    if (c && alive.length < maxLinks) {                                                         // استبدال الميت بروابط شغالة من المصدر
      const have = new Set(old.map(l => l.url));
      const cands = candidateStreams(streamsBy.get(c.id) || [], maxLinks * 2).filter(s => !have.has(s.url));
      for (const s of cands) {
        if (alive.length + fresh.length >= maxLinks) break;
        if (!checkOn || await check(s.url)) fresh.push(s);
      }
    }
    return { ...base, kind: alive.length + fresh.length ? 'ok' : 'dead', alive, dead, fresh };
  };
  const results = await mapLimit(tasks, conc, verify);

  const verified = results.filter(r => r.kind === 'ok' || r.kind === 'dead');
  const failed = verified.filter(r => r.kind === 'dead');
  const outage = verified.length >= 20 && failed.length / verified.length >= 0.5;
  if (outage) log.push(`⚠ فشل ${failed.length} من ${verified.length} قناة موجودة (≥50%) — يبدو أن المشكلة في الشبكة/المصدر، فلن تُسجَّل أعطال ولن يُحذف شيء.`);

  const upserts = {}, deletes = {}, strikes = {};
  for (const r of results) {
    const { job, k, v, c, hasExtras, basisSig } = r, s = st[job.code];
    if (r.kind === 'withdrawn' || r.kind === 'dup') {
      if (prune && !hasExtras) { deletes[k] = { reason: r.kind, basisSig }; s.removed++; } else s.kept++;
      continue;
    }
    if (r.kind === 'dead') {
      s.kept++;
      if (outage || !prune) continue;
      const n = (v.fails || 0) + 1;
      if (n >= failLimit && !hasExtras) { deletes[k] = { reason: 'dead', basisSig }; s.removed++; s.kept--; }
      else { strikes[k] = { n, basisSig }; s.struck++; }
      continue;
    }
    // ok: نبقي الروابط الشغالة بأسمائها، ونضيف البدائل بأسماء جديدة غير مستخدمة
    const links = {}; r.alive.forEach(l => { links[l.key] = l.url; });
    let n = r.alive.length;
    for (const x of r.fresh) { let lab = linkLabel(n++, x.quality); while (lab in links) lab = linkLabel(n++, x.quality); links[lab] = x.url; }
    if (r.dead.length || r.fresh.length) s.replaced++;
    s.kept++;
    const secIds = c ? secIdsFor(c) : idsOf(v).filter(id => secIdSet.has(id));
    upserts[k] = {
      isNew: false, catId: job.catId, catIds: [job.catId, ...secIds], links, basisSig,
      name: c ? (arName2(job, c) || c.name) : null,
      img: c ? pickLogo(c, logosBy.get(c.id)) : '',
      sourceId: v.sourceId || c?.id || '', country: job.code
    };
  }

  await commit({ catCreates: sectionCreates, catFills, upserts: { ...upserts }, deletes, strikes });

  // ── المرحلة 2: قنوات جديدة تملأ الخانات الفارغة فقط (لا تُزيح شغالاً) ──
  let seq = 0;
  for (const job of jobs) {
    const s = st[job.code], jobUp = {};
    const capCfg = job.arabic ? cfg.maxChannelsPerCountry : (cfg.maxChannelsWorld ?? cfg.maxChannelsPerCountry);
    const room = capCfg > 0 ? Math.max(0, capCfg - (s.kept - s.manual)) : Infinity; // 0 أو فارغ = بلا سقف
    const list = [];
    let eligCount = 0, withStreams = 0;
    for (const c of elig[job.code] || []) {
      eligCount++;
      const k = keyOf(c.id);
      if (chans[k]) { if (candidateStreams(streamsBy.get(c.id) || [], 1).length) withStreams++; continue; }   // موجودة (عولجت أعلاه أو محمية)
      if (ignore.has(k)) { s.ignored++; continue; }
      const cands = candidateStreams(streamsBy.get(c.id) || [], maxLinks * 2);
      if (!cands.length) continue;
      withStreams++;
      if (isDupOfManual(c, cands.map(x => x.url))) { s.dups++; continue; }
      list.push({ c, cands });
    }
    list.sort((a, b) => a.c.name.localeCompare(b.c.name));
    if (room === 0) s.capped = list.length;
    else for (let i = 0; i < list.length && s.added < room; i += conc) {
      const res = await mapLimit(list.slice(i, i + conc), conc, async x => {
        const ok = [];
        for (const x2 of x.cands) {
          if (ok.length >= maxLinks) break;
          if (!checkOn || await check(x2.url)) ok.push(x2);
        }
        return ok.length ? { ...x, ok } : null;
      });
      for (const r of res) {
        if (!r || s.added >= room) continue;
        const k = keyOf(r.c.id), links = {};
        r.ok.forEach((x, n) => { links[linkLabel(n, x.quality)] = x.url; });
        upserts[k] = {
          isNew: true,
          data: {
            id: k, name: arName2(job, r.c) || r.c.name, img: pickLogo(r.c, logosBy.get(r.c.id)),
            categoryIds: [job.catId, ...secIdsFor(r.c)], categories: [job.catId, ...secIdsFor(r.c)], links,
            order: now + (seq++), source: 'bot', sourceId: r.c.id, country: job.code, updatedAt: now
          }
        };
        jobUp[k] = upserts[k];
        s.added++;
      }
    }
    if (s.kept + s.added === 0) {
      const reason = eligCount === 0 ? 'لا قنوات مؤهلة في المصدر' : withStreams === 0 ? 'لا روابط https صالحة للمتصفح في المصدر' : 'كل الروابط الحالية لا تعمل أو لا تسمح بـ CORS';
      empty.push({ code: job.code, name: s.name, reason });
    }
    const cc = catCreates[job.catId];
    await commit({ catCreates: cc && (s.kept + s.added > 0 || cfg.createEmptyCountries) ? { [job.catId]: cc } : {}, upserts: jobUp });
    summary[job.code] = s;
  }

  // لا ننشئ قسماً جديداً لدولة بلا أي قناة شغالة (إلا إن فعّلت createEmptyCountries)
  for (const j of jobs) {
    if (!catCreates[j.catId] || catList.some(c => c.id === j.catId)) continue;
    const s = st[j.code];
    if (s.kept + s.added > 0 || cfg.createEmptyCountries) log.push(`＋ سيُنشأ قسم: ${nm(j.code)}`);
    else delete catCreates[j.catId];
  }

  Object.assign(catCreates, secUsed);
  for (const d of secDefs) {
    const n = Object.values(upserts).filter(u => ((u.isNew ? u.data.categoryIds : u.catIds) || []).includes(d.id)).length;
    log.push(`${secCreate[d.id] && !catList.some(c => c.id === d.id) ? '＋ قسم جديد' : '▣ قسم'} ${d.name}: ${n} قناة`);
  }
  return { catCreates, catFills, upserts, deletes, strikes, botCats, summary, log, empty };
}

// ═════════════════════════════════════════════════════════════════════════════════════════════
// الدمج مع الحالة الطازجة: بعد انتهاء الفحص الطويل نقرأ القاعدة من جديد ونطبّق الخطة بحذر،
// فلا نطغى على أي شيء عدّلته أو حذفته من لوحة التحكم أثناء تشغيل البوت.
// الكتابة بمسارات الحقول (وليس باستبدال السجل) فتبقى أي حقول أخرى للقناة سليمة.
// ═════════════════════════════════════════════════════════════════════════════════════════════
export function reconcile(plan, fresh, now = Date.now()) {
  const fc = fresh.chans || {}, fcats = fresh.cats || {}, ignore = fresh.ignore || new Set(), ignoreCats = fresh.ignoreCats || new Set();
  const updates = {}, skipped = [];
  const stats = { catsCreated: 0, created: 0, updated: 0, deleted: 0, struck: 0, skipped: 0 };
  const skip = (k, why) => { skipped.push({ k, why }); stats.skipped++; };

  for (const [id, v] of Object.entries(plan.catCreates)) {
    if (ignoreCats.has(id)) continue;
    const cur = fcats[id] || Object.values(fcats).find(x => x && x.id === id);
    if (!cur) { updates[`categories/${id}`] = v; stats.catsCreated++; }
  }
  for (const [id, img] of Object.entries(plan.catFills)) {
    const cur = fcats[id];
    if (cur && cur.source === 'bot' && !cur.img) updates[`categories/${id}/img`] = img;
  }

  for (const [k, u] of Object.entries(plan.upserts)) {
    const cur = fc[k];
    if (ignore.has(k)) { skip(k, 'حذفتها من اللوحة'); continue; }
    if (u.isNew) {
      if (cur) { skip(k, 'ظهرت أثناء التشغيل'); continue; }
      updates[`channels/${k}`] = u.data; stats.created++; continue;
    }
    if (!cur) { skip(k, 'حُذفت أثناء التشغيل'); continue; }
    if (cur.manual || cur.source !== 'bot') { skip(k, 'محمية'); continue; }
    if (sigOf(cur) !== u.basisSig) {                       // عدّلتها من اللوحة أثناء التشغيل: نحميها
      updates[`channels/${k}/manual`] = true; skip(k, 'عُدّلت أثناء التشغيل'); continue;
    }
    const catIds = [...(u.catIds || [u.catId]), ...idsOf(cur).filter(id => !plan.botCats.has(id))];   // الأقسام الإضافية تبقى
    const patch = {}, set = (f, val) => { if (JSON.stringify(cur[f] ?? null) !== JSON.stringify(val)) patch[f] = val; };
    if (u.name) set('name', u.name);
    if (u.img) set('img', u.img);
    set('source', 'bot'); set('country', u.country); if (u.sourceId) set('sourceId', u.sourceId);
    if (!sameList(asList(cur.categoryIds), catIds)) patch.categoryIds = catIds;
    if (!sameList(asList(cur.categories), catIds)) patch.categories = catIds;
    if (stable(linksObj(linkEntries(cur, { legacy: false }))) !== stable(u.links)) patch.links = u.links;
    if (cur.fails) patch.fails = null;
    if (!Object.keys(patch).length) continue;               // لا تغيير = لا كتابة (يحمي المتصفحات المفتوحة من إعادة التحميل)
    patch.updatedAt = now;
    for (const [f, val] of Object.entries(patch)) updates[`channels/${k}/${f}`] = val;
    stats.updated++;
  }

  for (const [k, d] of Object.entries(plan.deletes)) {
    const cur = fc[k];
    if (!cur) continue;
    if (cur.manual || cur.source !== 'bot') { skip(k, 'محمية'); continue; }
    if (sigOf(cur) !== d.basisSig) { skip(k, 'عُدّلت أثناء التشغيل'); continue; }
    if (idsOf(cur).some(id => !plan.botCats.has(id))) { skip(k, 'لها قسم إضافي'); continue; }
    updates[`channels/${k}`] = null; stats.deleted++;
  }
  for (const [k, s] of Object.entries(plan.strikes)) {
    const cur = fc[k];
    if (!cur || cur.manual || cur.source !== 'bot' || sigOf(cur) !== s.basisSig) continue;
    if ((cur.fails || 0) !== s.n) { updates[`channels/${k}/fails`] = s.n; stats.struck++; }
  }
  return { updates, stats, skipped };
}

// تقرير قراءة فقط عن فئة معينة في المصدر (لا يكتب شيئاً ولا يعرض روابط): العدد حسب الدولة وكم منها له رابط https
export function summarizeCategory(channels, streams, category) {
  const withStream = new Set();
  for (const s of streams || []) if (s.channel && candidateStreams([s], 1).length) withStream.add(s.channel);
  const byCountry = {}, list = [];
  let total = 0, playable = 0;
  for (const c of channels || []) {
    const hit = (c.categories || []).includes(category) || (category === 'xxx' && c.is_nsfw);
    if (!hit || c.closed || c.replaced_by) continue;
    total++;
    const ok = withStream.has(c.id); if (ok) playable++;
    const code = c.country || '??';
    const e = (byCountry[code] ||= { total: 0, playable: 0 });
    e.total++; if (ok) e.playable++;
    list.push({ name: c.name, country: code, playable: ok });
  }
  return { total, playable, byCountry, list };
}
