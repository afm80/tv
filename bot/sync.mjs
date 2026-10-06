// تشغيل: node bot/sync.mjs [--dry] [--only=SA,EG]
import fs from 'node:fs';
import { buildPlan, checkStream, reconcile } from './lib.mjs';

const cfg = JSON.parse(fs.readFileSync(new URL('./config.json', import.meta.url), 'utf8'));
const DRY = process.argv.includes('--dry');
const only = (process.argv.find(a => a.startsWith('--only=')) || '').slice(7).split(',').map(s => s.trim().toUpperCase()).filter(Boolean);
const API = 'https://iptv-org.github.io/api/';
const LOCK_TTL = 30 * 60 * 1000;      // القفل ينتهي تلقائياً إن لم يتجدد 30 دقيقة
const HEARTBEAT = 5 * 60 * 1000;      // التشغيل الحي يجدد القفل كل 5 دقائق
const UNLOCK = process.argv.includes('--unlock');

async function getJson(url, optional = false) {
  for (let i = 0; i < 3; i++) {
    try { const r = await fetch(url); if (r.ok) return await r.json(); } catch {}
    await new Promise(r => setTimeout(r, 1500 * (i + 1)));
  }
  if (optional) return [];
  throw new Error('تعذر تحميل ' + url);
}

// ── الاتصال بقاعدة البيانات (في الوضع الفعلي بصلاحيات الخدمة، وفي --dry بالقراءة العامة) ──
let db = null, admin = null;
if (!DRY) {
  ({ default: admin } = await import('firebase-admin'));
  const sa = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!sa) throw new Error('المتغير FIREBASE_SERVICE_ACCOUNT غير موجود');
  admin.initializeApp({ credential: admin.credential.cert(JSON.parse(sa)), databaseURL: cfg.databaseURL });
  db = admin.database();
}
// required: فشل القراءة يوقف التشغيل (لا نفترض أن القاعدة فارغة بسبب عطل شبكة فنُنشئ/نحذف خطأً)
const readNode = async (name, required = false) => {
  if (db) return (await db.ref(name).once('value')).val() || {};
  const j = await getJson(`${cfg.databaseURL}/${name}.json`, !required);
  return (Array.isArray(j) && !j.length && !required ? {} : j) || {};
};
const readState = async () => {
  const [cats, chans, botIgnore, botIgnoreCats] = await Promise.all([readNode('categories', true), readNode('channels', true), readNode('botIgnore'), readNode('botIgnoreCats')]);
  return { cats, chans, ignore: new Set(Object.keys(botIgnore || {})), ignoreCats: new Set(Object.keys(botIgnoreCats || {})) };
};

// قراءة طازجة لمفاتيح محددة فقط (للحفظ التدريجي): الأقسام وقوائم التجاهل صغيرة، والقنوات تُقرأ بمفاتيحها
const freshFor = async keys => {
  const [cats, botIgnore, botIgnoreCats] = await Promise.all([readNode('categories', true), readNode('botIgnore'), readNode('botIgnoreCats')]);
  let chans = {};
  if (keys.length > 300) chans = await readNode('channels', true);
  else await Promise.all(keys.map(async k => { const v = (await db.ref('channels/' + k).once('value')).val(); if (v) chans[k] = v; }));
  return { cats, chans, ignore: new Set(Object.keys(botIgnore || {})), ignoreCats: new Set(Object.keys(botIgnoreCats || {})) };
};
const applyUpdates = async updates => {
  const entries = Object.entries(updates);
  for (let i = 0; i < entries.length; i += 500) await db.ref().update(Object.fromEntries(entries.slice(i, i + 500)));
};
const totals = { catsCreated: 0, created: 0, updated: 0, deleted: 0, struck: 0, skipped: 0 };
// يُستدعى بعد المرحلة 1 ثم بعد كل دولة: دمج مع الحالة الطازجة ثم كتابة فورية
const onCommit = DRY ? null : async chunk => {
  const keys = [...new Set([...Object.keys(chunk.upserts), ...Object.keys(chunk.deletes), ...Object.keys(chunk.strikes)])];
  if (!keys.length && !Object.keys(chunk.catCreates).length && !Object.keys(chunk.catFills).length) return;
  const { updates, stats, skipped } = reconcile(chunk, await freshFor(keys));
  skipped.slice(0, 20).forEach(x => console.log(`↷ تخطّي ${x.k}: ${x.why}`));
  await applyUpdates(updates);
  for (const k of Object.keys(totals)) totals[k] += stats[k];
  const bits = [['created', 'جديدة'], ['updated', 'محدّثة'], ['deleted', 'محذوفة'], ['struck', 'تحذير']].filter(([k]) => stats[k]).map(([k, n]) => `${stats[k]} ${n}`);
  if (bits.length) console.log(`  ✓ حُفظ: ${bits.join('، ')}`);
};

// ── قفل: يمنع تشغيلين متزامنين (جدولة + يدوي أو تشغيل محلي) من التعارض ──
const runId = `${process.env.GITHUB_RUN_ID || 'local'}-${Date.now()}`;
const lockRef = db && db.ref('botMeta/lock');
let locked = false, beat = null;

// تحرير يدوي للقفل العالق: node bot/sync.mjs --unlock
if (UNLOCK) {
  if (!db) throw new Error('--unlock يحتاج FIREBASE_SERVICE_ACCOUNT وبدون --dry');
  await lockRef.remove();
  console.log('تم تحرير القفل ✓');
  process.exit(0);
}

if (db) {
  const tx = await lockRef.transaction(cur => (cur && Date.now() - cur.at < LOCK_TTL ? undefined : { runId, at: Date.now() }));
  if (!tx.committed) {
    const cur = tx.snapshot.val();
    console.log('تشغيل آخر للبوت قيد التنفيذ — تم الإيقاف دون تغيير.' + (cur ? ` (آخر نشاط للقفل قبل ${Math.round((Date.now() - cur.at) / 60000)} دقيقة)` : ''));
    process.exit(0);
  }
  locked = true;
  // نبضة: طالما التشغيل حيّ يبقى القفل صالحاً، وإذا مات التشغيل ينتهي القفل وحده
  beat = setInterval(() => { lockRef.transaction(cur => (cur && cur.runId !== runId ? undefined : { runId, at: Date.now() })).catch(() => {}); }, HEARTBEAT);
  beat.unref();
}
// ملاحظة: دالة المعاملة تُستدعى أول مرة بقيمة null قبل أن تصلها القيمة الحقيقية من الخادم،
// لذلك لا نُرجع undefined عند null (كان ذلك يُلغي التحرير دائماً ويُبقي القفل عالقاً).
const unlock = async () => {
  clearInterval(beat);
  if (!locked) return;
  locked = false;
  try { await lockRef.transaction(cur => (cur && cur.runId !== runId ? undefined : null)); } catch {}
};
// عند إلغاء التشغيل من GitHub تصل إشارة إيقاف: نحرر القفل قبل الخروج
for (const sig of ['SIGTERM', 'SIGINT']) process.on(sig, async () => { await unlock(); process.exit(1); });

try {
  const state = await readState();
  const [channels, streams, logos, blocklist] = await Promise.all([
    getJson(API + 'channels.json'), getJson(API + 'streams.json'), getJson(API + 'logos.json', true), getJson(API + 'blocklist.json', true)
  ]);
  console.log(`المصدر: ${channels.length} قناة، ${streams.length} رابط`);
  if (!Array.isArray(channels) || channels.length < 1000 || !Array.isArray(streams) || streams.length < 500) throw new Error('بيانات المصدر ناقصة أو تالفة — أُلغي التشغيل لحماية قنواتك.');

  const countriesApi = await getJson(API + 'countries.json', true);
  const countryNames = Object.fromEntries((Array.isArray(countriesApi) ? countriesApi : []).map(c => [c.code, c.name]));
  const baseOpts = { origin: cfg.siteOrigin, requireCors: cfg.requireCors !== false, timeoutMs: cfg.checkTimeoutMs || 8000 };
  // retry: يُستعمل لروابط القنوات الموجودة فقط (لا نحكم على قناة شغالة بفشل عابر واحد)
  const check = (url, o = {}) => checkStream(url, { ...baseOpts, retries: o.retry ? (cfg.checkRetries ?? 1) : 0 });

  const plan = await buildPlan({ api: { channels, streams, logos, blocklist }, cats: state.cats, chans: state.chans, cfg, check, only, countryNames, ignore: state.ignore, ignoreCats: state.ignoreCats, onCommit });
  plan.log.forEach(l => console.log(l));
  console.table(plan.summary);
  if (plan.empty.length) {
    console.log(`دول بلا أي قناة شغالة حالياً (${plan.empty.length}) — لا تُنشأ لها أقسام فارغة:`);
    plan.empty.forEach(e => console.log(`  • ${e.name} (${e.code}): ${e.reason}`));
  }

  if (DRY) {
    const { stats, skipped } = reconcile(plan, state);
    skipped.slice(0, 50).forEach(x => console.log(`↷ تخطّي ${x.k}: ${x.why}`));
    console.log(`أقسام جديدة: ${stats.catsCreated} | قنوات جديدة: ${stats.created} | محدّثة: ${stats.updated} | محذوفة (ميتة): ${stats.deleted} | تحذيرات أعطال: ${stats.struck} | متخطّاة: ${stats.skipped}`);
    console.log('وضع التجربة: لم يتم تغيير شيء.');
  } else {
    // الكتابة تمت تدريجياً أثناء التشغيل (دولة بعد دولة) مع قراءة طازجة قبل كل دفعة
    console.log(`الإجمالي — أقسام جديدة: ${totals.catsCreated} | قنوات جديدة: ${totals.created} | محدّثة: ${totals.updated} | محذوفة (ميتة): ${totals.deleted} | تحذيرات أعطال: ${totals.struck} | متخطّاة: ${totals.skipped}`);
    await db.ref('botMeta/lastRun').set({ at: Date.now(), ...totals, countries: Object.keys(plan.summary).length });
    console.log('تم التحديث ✓');
  }
} finally { await unlock(); }
process.exit(0);
