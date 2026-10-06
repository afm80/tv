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
const NAME_OVERRIDE = { UK: 'المملكة المتحدة' }; // iptv-org يستخدم UK بدل GB
export const arName = code => NAME_OVERRIDE[code] || (() => { try { return dn && dn.of(code); } catch { return null; } })() || code;

// توحيد النص العربي للمقارنة (يتجاهل التشكيل والهمزات والـ "ال" والرموز/الإيموجي)
export const norm = s => String(s || '').toLowerCase()
  .replace(/[\u064B-\u065F\u0670\u0640]/g, '')
  .replace(/[أإآ]/g, 'ا').replace(/ى/g, 'ي').replace(/ة/g, 'ه')
  .replace(/[^\p{L}\p{N}\s]/gu, ' ').replace(/\s+/g, ' ').trim();
const key = s => norm(s).split(' ').map(w => w.replace(/^ال/, '')).join(' ');

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

// فحص الرابط: يعمل (200) + يسمح بالتشغيل من موقعك (CORS) + ملف HLS صالح
export async function checkStream(url, { timeoutMs = 8000, origin = '', requireCors = true } = {}, fetchImpl = fetch) {
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
}

export async function buildPlan({ api, cats, chans, cfg, check, only = [], now = Date.now() }) {
  const log = [], summary = {};
  const catList = Object.entries(cats || {}).map(([k, v]) => ({ id: v.id || k, name: v.name || '', parentId: String(v.parentId || v.parent || '') }));
  const top = catList.filter(c => !c.parentId);
  const pick = codes => only.length ? codes.filter(c => only.includes(c)) : codes;
  const findSection = s => {
    if (s.id && catList.some(c => c.id === s.id)) return s.id;
    const names = s.names.map(norm);
    return top.find(c => names.includes(norm(c.name)))?.id || null;
  };
  const catCreates = {}, jobs = [];
  const aliases = cfg.countryAliases || {};

  // القسم العربي: الأقسام الفرعية جاهزة عندك، نطابقها فقط ولا ننشئ شيئاً
  const arabCodes = pick(cfg.sections.arab.countries || ARAB);
  const arabSec = findSection(cfg.sections.arab);
  if (!arabSec) log.push(`⚠ لم أجد القسم العربي. الأقسام الرئيسية الموجودة: ${top.map(c => c.name).join('، ')}`);
  else {
    const kids = catList.filter(c => c.parentId === arabSec);
    const m = matchAll(arabCodes, kids, aliases);
    for (const code of arabCodes) m[code] ? jobs.push({ code, catId: m[code], arabic: true }) : log.push(`⚠ لا يوجد قسم فرعي لـ ${arName(code)} (${code}) داخل القسم العربي`);
  }

  // القسم العالمي: ننشئه وأقسام دوله تلقائياً إذا لم تكن موجودة
  const worldCodes = pick(cfg.sections.world.countries || []);
  let worldSec = findSection(cfg.sections.world);
  if (!worldSec && worldCodes.length) {
    worldSec = 'bot_sec_world';
    catCreates[worldSec] = { id: worldSec, name: cfg.sections.world.names[0], img: '', parentId: '', link: '', order: now, source: 'bot' };
    log.push(`＋ سيُنشأ القسم الرئيسي: ${cfg.sections.world.names[0]}`);
  }
  if (worldSec) {
    const kids = catList.filter(c => c.parentId === worldSec);
    const m = matchAll(worldCodes, kids, aliases);
    worldCodes.forEach((code, i) => {
      if (m[code]) return jobs.push({ code, catId: m[code], arabic: false });
      if (cfg.sections.world.autoCreateCountries === false) return log.push(`⚠ لا يوجد قسم فرعي لـ ${arName(code)} (${code}) في القسم العالمي`);
      const id = `bot_cat_${code}`;
      catCreates[id] = { id, name: arName(code), img: '', parentId: worldSec, link: '', order: now + i, source: 'bot' };
      jobs.push({ code, catId: id, arabic: false });
    });
  }

  const elig = groupEligible({ ...cfg, channels: api.channels, blocklist: api.blocklist, countries: jobs.map(j => j.code) });
  const streamsBy = new Map();
  for (const s of api.streams) if (s.channel) (streamsBy.get(s.channel) || streamsBy.set(s.channel, []).get(s.channel)).push(s);
  const logosBy = new Map();
  for (const l of api.logos || []) if (l.channel) (logosBy.get(l.channel) || logosBy.set(l.channel, []).get(l.channel)).push(l);

  const writes = {}, max = cfg.maxChannelsPerCountry, maxLinks = cfg.maxLinksPerChannel;
  let seq = 0;
  for (const job of jobs) {
    const list = (elig[job.code] || [])
      .map(c => ({ c, cands: candidateStreams(streamsBy.get(c.id) || [], maxLinks * 2) }))
      .filter(x => x.cands.length)
      .sort((a, b) => a.c.name.localeCompare(b.c.name));
    const kept = [];
    for (let i = 0; i < list.length && kept.length < max; i += 20) {
      const res = await Promise.all(list.slice(i, i + 20).map(async x => {
        const ok = [];
        for (const s of x.cands) {
          if (ok.length >= maxLinks) break;
          if (!cfg.checkLinks || await check(s.url)) ok.push(s);
        }
        return ok.length ? { ...x, ok } : null;
      }));
      for (const r of res) if (r && kept.length < max) kept.push(r);
    }
    let skippedManual = 0;
    for (const { c, ok } of kept) {
      const k = keyOf(c.id), old = chans?.[k];
      if (old?.manual) { skippedManual++; continue; }
      const ar = job.arabic && cfg.preferArabicNames ? (c.alt_names || []).find(n => /[\u0600-\u06FF]/.test(n)) : null;
      const links = {};
      ok.forEach((s, i) => { links[linkLabel(i, s.quality)] = s.url; });
      writes[k] = {
        id: k, name: ar || c.name, img: pickLogo(c, logosBy.get(c.id)),
        categoryIds: [job.catId], categories: [job.catId], links,
        order: old?.order ?? now + (seq++), source: 'bot', sourceId: c.id, country: job.code, updatedAt: now
      };
    }
    summary[job.code] = { name: arName(job.code), candidates: list.length, added: kept.length - skippedManual, skippedManual };
  }

  // حذف قنوات البوت التي لم تعد صالحة (فقط للدول التي عالجناها)
  const deletes = [];
  const done = new Set(jobs.map(j => j.code));
  const oldBot = Object.entries(chans || {}).filter(([, v]) => v?.source === 'bot' && !v.manual && done.has(v.country));
  if (cfg.pruneMissing && !only.length) {
    const gone = oldBot.filter(([k]) => !writes[k]).map(([k]) => k);
    if (oldBot.length >= 10 && Object.keys(writes).length < oldBot.length * 0.5) log.push('⚠ النتائج أقل من نصف القنوات الحالية — تم إلغاء الحذف احتياطاً (ربما المصدر معطل).');
    else deletes.push(...gone);
  }
  return { catCreates, writes, deletes, summary, log };
}
