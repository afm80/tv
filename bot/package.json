// تشغيل: node --test bot/   (محاكاة كاملة بلا شبكة ولا Firebase)
import test from 'node:test';
import assert from 'node:assert/strict';
import { buildPlan, reconcile, keyOf, idsOf, linkEntries, summarizeCategory } from './lib.mjs';

const CFG = () => ({
  sections: { arab: { id: '', names: ['قنوات عربية'], countries: ['SA', 'EG'], autoCreateCountries: true }, world: { id: '', names: ['قنوات عالمية'], countries: ['*'], autoCreateCountries: true } },
  maxChannelsPerCountry: 3, maxChannelsWorld: 2, maxLinksPerChannel: 2, checkLinks: true, pruneMissing: true,
  deleteAfterFailures: 2, excludeCategories: [], allowedCategories: [], blockNamePatterns: [], preferArabicNames: false, checkConcurrency: 5
});
// مصدر وهمي: channels = [[id,name,country]], كل قناة لها رابطان
const mkApi = list => ({
  channels: list.map(([id, name, country]) => ({ id, name, country, categories: [] })),
  streams: list.flatMap(([id]) => [{ channel: id, url: `https://x/${id}/a.m3u8`, quality: '720p' }, { channel: id, url: `https://x/${id}/b.m3u8`, quality: '480p' }]),
  logos: [], blocklist: []
});
const SEED_CATS = { ar: { id: 'ar', name: 'قنوات عربية', parentId: '' }, wo: { id: 'wo', name: 'قنوات عالمية', parentId: '' } };
let dead;                                       // مجموعة روابط ميتة
const check = async url => !dead.has(url);

// يحاكي تشغيلاً كاملاً: خطة ثم دمج ثم تطبيق على «القاعدة»
async function run(db, api, { cfg = CFG(), mutate, now = Date.now() } = {}) {
  const plan = await buildPlan({ api, cats: db.cats, chans: db.chans, cfg, check, ignore: new Set(Object.keys(db.botIgnore || {})), ignoreCats: new Set(Object.keys(db.botIgnoreCats || {})), now });
  if (mutate) mutate(db);                        // تعديل من اللوحة أثناء التشغيل
  const r = reconcile(plan, { chans: db.chans, cats: db.cats, ignore: new Set(Object.keys(db.botIgnore || {})), ignoreCats: new Set(Object.keys(db.botIgnoreCats || {})) }, now);
  for (const [path, val] of Object.entries(r.updates)) setPath(db, path, val);
  return { plan, ...r };
}
function setPath(db, path, val) {
  const p = path.split('/'); p[0] = { channels: 'chans', categories: 'cats' }[p[0]] || p[0];
  const last = p.pop(); let o = db;
  for (const k of p) o = (o[k] ??= {});
  if (val === null) delete o[last]; else o[last] = val;
}
const fresh = () => ({ cats: structuredClone(SEED_CATS), chans: {}, botIgnore: {}, botIgnoreCats: {} });
const botKeys = db => Object.keys(db.chans);

test('أول تشغيل: ينشئ قسم كل دولة (عربية وعالمية) ويحترم السقف', async () => {
  dead = new Set(); const db = fresh();
  const api = mkApi([['a1', 'A1', 'SA'], ['a2', 'A2', 'SA'], ['a3', 'A3', 'SA'], ['a4', 'A4', 'SA'], ['e1', 'E1', 'EG'], ['f1', 'F1', 'FR'], ['f2', 'F2', 'FR'], ['f3', 'F3', 'FR'], ['j1', 'J1', 'JP'], ['n1', 'N1', 'NZ']]);
  const r = await run(db, api);
  assert.equal(botKeys(db).filter(k => db.chans[k].country === 'SA').length, 3);   // سقف 3
  assert.equal(botKeys(db).filter(k => db.chans[k].country === 'FR').length, 2);   // سقف عالمي 2
  const catNames = Object.values(db.cats).map(c => c.name);
  for (const c of ['السعودية', 'مصر', 'فرنسا', 'اليابان', 'نيوزيلندا']) assert.ok(catNames.some(n => n.includes(c)), 'قسم ناقص: ' + c);
  assert.equal(r.plan.empty.length, 0);
});

test('التشغيل المتكرر بلا تغيير في المصدر = صفر كتابة', async () => {
  dead = new Set(); const db = fresh();
  const api = mkApi([['a1', 'A1', 'SA'], ['a2', 'A2', 'SA'], ['f1', 'F1', 'FR']]);
  await run(db, api);
  const before = structuredClone(db);
  const r = await run(db, api, { now: Date.now() + 1e6 });
  assert.deepEqual(r.updates, {});
  assert.deepEqual(db, before);
});

test('قناة جديدة تسبق أبجدياً لا تُزيح قناة شغالة عند السقف', async () => {
  dead = new Set(); const db = fresh();
  const base = [['b1', 'B1', 'SA'], ['b2', 'B2', 'SA'], ['b3', 'B3', 'SA']];
  await run(db, mkApi(base));
  const keys = botKeys(db).sort();
  const r = await run(db, mkApi([['a0', 'A0', 'SA'], ...base]), { now: Date.now() + 1e6 });
  assert.deepEqual(botKeys(db).sort(), keys);                 // لم يُحذف أي شيء ولم تدخل A0
  assert.equal(Object.keys(r.plan.deletes).length, 0);
});

test('رابط ميت يُستبدل برابط شغال جديد والبقية تبقى', async () => {
  dead = new Set(); const db = fresh();
  const mk = extra => { const a = mkApi([['c1', 'C1', 'SA']]); a.streams.push(...extra); return a; };
  await run(db, mk([]));
  assert.equal(Object.keys(db.chans[keyOf('c1')].links).length, 2);
  dead = new Set(['https://x/c1/a.m3u8']);
  await run(db, mk([{ channel: 'c1', url: 'https://x/c1/new.m3u8', quality: '1080p' }]), { now: Date.now() + 1e6 });
  const urls = Object.values(db.chans[keyOf('c1')].links);
  assert.ok(!urls.includes('https://x/c1/a.m3u8'));
  assert.ok(urls.includes('https://x/c1/b.m3u8'));            // الشغال بقي
  assert.ok(urls.includes('https://x/c1/new.m3u8'));          // البديل أُضيف
});

test('قناة ماتت كل روابطها: تحذير أول ثم حذف في الثاني، وتعافيها يمسح العداد', async () => {
  dead = new Set(); const db = fresh();
  const api = mkApi([['d1', 'D1', 'SA'], ['d2', 'D2', 'SA']]);
  await run(db, api);
  const all = u => [`https://x/d1/a.m3u8`, `https://x/d1/b.m3u8`];
  dead = new Set(all());
  await run(db, api, { now: 1e12 });
  assert.equal(db.chans[keyOf('d1')].fails, 1);               // لم تُحذف بعد
  dead = new Set();                                          // تعافت
  await run(db, api, { now: 2e12 });
  assert.equal(db.chans[keyOf('d1')].fails, undefined);
  dead = new Set(all());
  await run(db, api, { now: 3e12 }); await run(db, api, { now: 4e12 });
  assert.ok(!db.chans[keyOf('d1')], 'يجب أن تُحذف بعد فشلين متتاليين');
  assert.ok(db.chans[keyOf('d2')], 'الشغالة تبقى');
});

test('انقطاع شبكة (≥50% فاشل) لا يسجّل أعطالاً ولا يحذف شيئاً', async () => {
  dead = new Set(); const db = fresh();
  const list = Array.from({ length: 24 }, (_, i) => [`z${i}`, `Z${i}`, 'SA']);
  const cfg = CFG(); cfg.maxChannelsPerCountry = 0;
  const api = mkApi(list);
  await run(db, api, { cfg });
  assert.equal(botKeys(db).length, 24);
  dead = new Set(api.streams.map(s => s.url));
  for (let i = 0; i < 3; i++) await run(db, api, { cfg, now: (i + 1) * 1e12 });
  assert.equal(botKeys(db).length, 24);
  assert.ok(botKeys(db).every(k => !db.chans[k].fails));
});

test('القناة المحمية/المحذوفة/اليدوية لا يلمسها البوت ولا يكررها', async () => {
  dead = new Set(); const db = fresh();
  const api = mkApi([['m1', 'M1', 'SA'], ['m2', 'M2', 'SA'], ['m3', 'Mine Channel', 'SA']]);
  db.chans.mine = { id: 'mine', name: 'Mine Channel', links: { رابط: 'https://my/stream.m3u8' }, categoryIds: ['x'] };
  await run(db, api);
  assert.ok(!botKeys(db).some(k => db.chans[k].sourceId === 'm3'), 'لا تكرار للقناة اليدوية');
  db.chans[keyOf('m1')].manual = true; db.chans[keyOf('m1')].name = 'اسمي';
  dead = new Set(['https://x/m1/a.m3u8', 'https://x/m1/b.m3u8']);
  await run(db, api, { now: 1e12 }); await run(db, api, { now: 2e12 });
  assert.equal(db.chans[keyOf('m1')].name, 'اسمي');
  assert.ok(db.chans[keyOf('m1')], 'المحمية لا تُحذف');
  delete db.chans[keyOf('m2')]; db.botIgnore[keyOf('m2')] = true;
  dead = new Set();
  await run(db, api, { now: 3e12 });
  assert.ok(!db.chans[keyOf('m2')], 'المحذوفة من اللوحة لا تعود');
});

test('تعديل من اللوحة أثناء تشغيل البوت لا يُطغى عليه', async () => {
  dead = new Set(); const db = fresh();
  const api = mkApi([['p1', 'P1', 'SA'], ['p2', 'P2', 'SA'], ['p3', 'P3', 'SA']]);
  await run(db, api);
  const k1 = keyOf('p1'), k2 = keyOf('p2'), k3 = keyOf('p3');
  dead = new Set(['https://x/p1/a.m3u8']);                    // سيحاول البوت تعديل p1 (استبدال رابط)
  await run(db, api, {
    now: 1e12,
    mutate: d => { d.chans[k1].name = 'عدّلتها'; delete d.chans[k2]; d.chans[k3].categoryIds = [...d.chans[k3].categoryIds, 'extra']; }
  });
  assert.equal(db.chans[k1].name, 'عدّلتها');
  assert.equal(db.chans[k1].manual, true);                    // أصبحت محمية
  assert.ok(!db.chans[k2]);                                   // لم يُعد البوت المحذوفة
  assert.ok(idsOf(db.chans[k3]).includes('extra'));           // القسم الإضافي بقي
});

test('الحقول الأخرى للقناة (غير حقول البوت) تبقى سليمة بعد التحديث', async () => {
  dead = new Set(); const db = fresh();
  const api = mkApi([['q1', 'Q1', 'SA']]);
  await run(db, api);
  const k = keyOf('q1');
  db.chans[k].customNote = 'ملاحظة'; db.chans[k].views = 77;
  dead = new Set(['https://x/q1/a.m3u8']);
  await run(db, api, { now: 1e12 });
  assert.equal(db.chans[k].customNote, 'ملاحظة'); assert.equal(db.chans[k].views, 77);
});

test('قراءة الحقول القديمة: categories وlinks ككائنات وحقول mainLink', async () => {
  assert.deepEqual(idsOf({ categories: { 0: 'a', 1: 'b' } }), ['a', 'b']);
  assert.deepEqual(idsOf({ categoryId: 'z' }), ['z']);
  assert.deepEqual(linkEntries({ links: { x: { url: 'https://u', label: 'L' } }, mainLink: 'https://m' }).map(l => l.url), ['https://u', 'https://m']);
  dead = new Set(); const db = fresh();
  db.chans.old = { id: 'old', name: 'Legacy', mainLink: 'https://x/l1/a.m3u8', categories: ['x'] };
  const r = await run(db, mkApi([['l1', 'Legacy One', 'SA'], ['l2', 'Other', 'SA']]));
  assert.ok(!botKeys(db).some(k => db.chans[k].sourceId === 'l1'), 'تكرار برابط قديم يُمنع');
  assert.ok(db.chans.old.mainLink);
});

test('دولة بلا أي قناة شغالة: لا قسم فارغ ويُذكر السبب في التقرير', async () => {
  dead = new Set(['https://x/g1/a.m3u8', 'https://x/g1/b.m3u8']); const db = fresh();
  const r = await run(db, mkApi([['g1', 'G1', 'JP'], ['h1', 'H1', 'FR']]));
  assert.ok(!Object.values(db.cats).some(c => c.name.includes('اليابان')));
  assert.ok(r.plan.empty.some(e => e.code === 'JP'));
  const cfg = CFG(); cfg.createEmptyCountries = true;
  const db2 = fresh(); await run(db2, mkApi([['g1', 'G1', 'JP']]), { cfg });
  assert.ok(Object.values(db2.cats).some(c => c.name.includes('اليابان')));
});

test('قسم دولة حذفته من اللوحة (botIgnoreCats) لا يُعاد إنشاؤه', async () => {
  dead = new Set(); const db = fresh();
  await run(db, mkApi([['h1', 'H1', 'FR'], ['i1', 'I1', 'IT']]));
  const frCat = Object.values(db.cats).find(c => c.name.includes('فرنسا')).id;
  for (const k of botKeys(db)) if (db.chans[k].country === 'FR') delete db.chans[k];
  delete db.cats[frCat]; db.botIgnoreCats[frCat] = true;
  await run(db, mkApi([['h1', 'H1', 'FR'], ['i1', 'I1', 'IT']]), { now: 1e12 });
  assert.ok(!Object.values(db.cats).some(c => c.name.includes('فرنسا')));
  assert.ok(!botKeys(db).some(k => db.chans[k].country === 'FR'));
});

test('excludeCountries يستثني دولة بالكامل', async () => {
  dead = new Set(); const db = fresh(); const cfg = CFG(); cfg.excludeCountries = ['FR'];
  await run(db, mkApi([['h1', 'H1', 'FR'], ['i1', 'I1', 'IT']]), { cfg });
  assert.ok(!botKeys(db).some(k => db.chans[k].country === 'FR'));
  assert.ok(botKeys(db).some(k => db.chans[k].country === 'IT'));
});

// ───────── الحفظ التدريجي ─────────
async function runInc(db, api, { cfg = CFG(), failAfter = Infinity, now = Date.now() } = {}) {
  let n = 0;
  const ign = () => new Set(Object.keys(db.botIgnore || {})), igc = () => new Set(Object.keys(db.botIgnoreCats || {}));
  const onCommit = async chunk => {
    if (++n > failAfter) throw new Error('انقطاع');
    const r = reconcile(chunk, { chans: db.chans, cats: db.cats, ignore: ign(), ignoreCats: igc() }, now);
    for (const [path, val] of Object.entries(r.updates)) setPath(db, path, val);
  };
  return buildPlan({ api, cats: db.cats, chans: db.chans, cfg, check, ignore: ign(), ignoreCats: igc(), now, onCommit });
}

test('الحفظ التدريجي يعطي نفس نتيجة الحفظ الدفعي', async () => {
  dead = new Set(['https://x/f2/a.m3u8', 'https://x/f2/b.m3u8']);
  const api = mkApi([['a1', 'A1', 'SA'], ['a2', 'A2', 'SA'], ['f1', 'F1', 'FR'], ['f2', 'F2', 'FR'], ['j1', 'J1', 'JP'], ['n1', 'N1', 'NZ']]);
  const a = fresh(), b = fresh();
  await run(a, api, { now: 5 });
  await runInc(b, api, { now: 5 });
  assert.deepEqual(Object.keys(b.chans).sort(), Object.keys(a.chans).sort());
  assert.deepEqual(Object.values(b.cats).map(c => c.name).sort(), Object.values(a.cats).map(c => c.name).sort());
});

test('انقطاع التشغيل في المنتصف: ما حُفظ يبقى ويكمل التشغيل التالي الباقي', async () => {
  dead = new Set(); const db = fresh();
  const api = mkApi([['a1', 'A1', 'SA'], ['f1', 'F1', 'FR'], ['i1', 'I1', 'IT'], ['j1', 'J1', 'JP'], ['n1', 'N1', 'NZ']]);
  await assert.rejects(() => runInc(db, api, { failAfter: 3 }), /انقطاع/);
  const saved = Object.keys(db.chans).length;
  assert.ok(saved > 0 && saved < 5, 'حُفظ جزء فقط: ' + saved);
  await runInc(db, api, { now: Date.now() + 1e6 });
  assert.equal(Object.keys(db.chans).length, 5);          // اكتمل دون تكرار
});

test('الحفظ التدريجي: دولة بلا قناة شغالة لا يُنشأ لها قسم', async () => {
  dead = new Set(['https://x/g1/a.m3u8', 'https://x/g1/b.m3u8']); const db = fresh();
  await runInc(db, mkApi([['g1', 'G1', 'JP'], ['h1', 'H1', 'FR']]));
  assert.ok(!Object.values(db.cats).some(c => c.name.includes('اليابان')));
  assert.ok(Object.values(db.cats).some(c => c.name.includes('فرنسا')));
});

// ───────── أقسام حسب الفئة (أخبار، رياضة...) ─────────
const SECS = () => [
  { key: 'news', names: ['قنوات أخبار'], categories: ['news'], scope: 'all' },
  { key: 'sports_arab', names: ['الرياضة العربية'], categories: ['sports'], scope: 'arab' },
  { key: 'sports_world', names: ['الرياضة العالمية'], categories: ['sports'], scope: 'world' },
  { key: 'kids', names: ['قنوات أطفال'], categories: ['kids', 'animation'], scope: 'all' }
];
const mkCatApi = list => {                         // [id,name,country,[categories]]
  const a = mkApi(list.map(([id, n, c]) => [id, n, c]));
  a.channels.forEach((ch, i) => { ch.categories = list[i][3]; });
  return a;
};
const catCfg = () => { const c = CFG(); c.maxChannelsPerCountry = 0; c.maxChannelsWorld = 0; c.categorySections = SECS(); return c; };
const secByName = (db, n) => Object.values(db.cats).find(c => c.name === n);

test('أقسام الفئة: القناة نفسها في قسم دولتها وقسم فئتها بسجل واحد، والرياضة تنفصل بدولة القناة', async () => {
  dead = new Set(); const db = fresh();
  const api = mkCatApi([['n1', 'N1', 'SA', ['news']], ['s1', 'S1', 'SA', ['sports']], ['s2', 'S2', 'FR', ['sports']], ['k1', 'K1', 'JP', ['animation']], ['g1', 'G1', 'FR', ['general']]]);
  await run(db, api, { cfg: catCfg() });
  assert.equal(botKeys(db).length, 5);                                           // لا تكرار للسجلات
  const news = secByName(db, 'قنوات أخبار'), sa = secByName(db, 'الرياضة العربية'), sw = secByName(db, 'الرياضة العالمية'), kids = secByName(db, 'قنوات أطفال');
  assert.ok(news && sa && sw && kids, 'يجب إنشاء أقسام الفئات');
  const ids = id => idsOf(db.chans[keyOf(id)]);
  assert.ok(ids('n1').includes(news.id) && ids('n1').length === 2);              // قسم السعودية + الأخبار
  assert.ok(ids('s1').includes(sa.id) && !ids('s1').includes(sw.id));            // سعودية → رياضة عربية
  assert.ok(ids('s2').includes(sw.id) && !ids('s2').includes(sa.id));            // فرنسا → رياضة عالمية
  assert.ok(ids('k1').includes(kids.id));
  assert.equal(ids('g1').length, 1);                                             // فئة غير مضافة: قسم الدولة فقط
  assert.deepEqual(db.chans[keyOf('s1')].categories, db.chans[keyOf('s1')].categoryIds);
});

test('أقسام الفئة: لا يُنشأ قسم لفئة لا توجد لها قناة، ويُستخدم القسم الموجود بالاسم', async () => {
  dead = new Set(); const db = fresh();
  db.cats.nw = { id: 'nw', name: 'قنوات اخبار', parentId: '' };                  // موجود بكتابة مختلفة (همزة)
  const api = mkCatApi([['n1', 'N1', 'EG', ['news']]]);
  await run(db, api, { cfg: catCfg() });
  assert.ok(idsOf(db.chans[keyOf('n1')]).includes('nw'));
  assert.equal(Object.values(db.cats).filter(c => c.name.includes('أخبار') || c.name.includes('اخبار')).length, 1);
  assert.ok(!secByName(db, 'الرياضة العربية') && !secByName(db, 'قنوات أطفال'));
});

test('أقسام الفئة: قناة موجودة سابقاً تُضاف لقسم فئتها لاحقاً، والتكرار بلا تغيير = صفر كتابة', async () => {
  dead = new Set(); const db = fresh();
  const api = mkCatApi([['n1', 'N1', 'SA', ['news']], ['x1', 'X1', 'SA', []]]);
  await run(db, api);                                                            // بلا أقسام فئات
  assert.equal(idsOf(db.chans[keyOf('n1')]).length, 1);
  const cfg = catCfg();
  await run(db, api, { cfg, now: Date.now() + 1e6 });
  assert.equal(idsOf(db.chans[keyOf('n1')]).length, 2);
  assert.equal(idsOf(db.chans[keyOf('x1')]).length, 1);
  const before = structuredClone(db);
  const r = await run(db, api, { cfg, now: Date.now() + 2e6 });
  assert.deepEqual(r.updates, {});
  assert.deepEqual(db, before);
});

test('أقسام الفئة: قسم فئة حذفته من اللوحة (botIgnoreCats) لا يعود، والقناة تبقى في قسم دولتها', async () => {
  dead = new Set(); const db = fresh();
  db.botIgnoreCats.bot_sec_news = true;
  const api = mkCatApi([['n1', 'N1', 'SA', ['news']]]);
  await run(db, api, { cfg: catCfg() });
  assert.ok(!secByName(db, 'قنوات أخبار'));
  assert.equal(idsOf(db.chans[keyOf('n1')]).length, 1);
});

test('أقسام الفئة: قناة الفئة الميتة تُحذف كالمعتاد، وقسم الفئة لا يعدّ قسماً إضافياً يحميها', async () => {
  dead = new Set(); const db = fresh();
  const api = mkCatApi([['n1', 'N1', 'SA', ['news']], ['n2', 'N2', 'SA', ['news']]]);
  const cfg = catCfg();
  await run(db, api, { cfg });
  dead = new Set(api.streams.filter(s => s.channel === 'n1').map(s => s.url));
  await run(db, api, { cfg, now: 1e12 }); await run(db, api, { cfg, now: 2e12 });
  assert.ok(!db.chans[keyOf('n1')], 'تُحذف بعد فشلين متتاليين');
  assert.ok(db.chans[keyOf('n2')]);
});

test('أقسام الفئة: قسم أضفتَه يدوياً لقناة البوت يبقى محفوظاً (الأقسام الإضافية)', async () => {
  dead = new Set(); const db = fresh();
  const api = mkCatApi([['n1', 'N1', 'SA', ['news']]]);
  const cfg = catCfg();
  await run(db, api, { cfg });
  db.chans[keyOf('n1')].categoryIds.push('mine'); db.chans[keyOf('n1')].categories.push('mine');
  await run(db, api, { cfg, now: Date.now() + 1e6 });
  assert.ok(idsOf(db.chans[keyOf('n1')]).includes('mine'));
});

test('تقرير الفئة: يعدّ حسب الدولة ويحسب الروابط الصالحة ولا يعرض روابط', () => {
  const channels = [
    { id: 'a', name: 'A', country: 'US', categories: ['xxx'] }, { id: 'b', name: 'B', country: 'US', categories: ['xxx'] },
    { id: 'c', name: 'C', country: 'FR', categories: ['xxx'], closed: '2020-01-01' }, { id: 'd', name: 'D', country: 'FR', categories: ['news'] },
    { id: 'e', name: 'E', country: 'DE', categories: [], is_nsfw: true }
  ];
  const streams = [{ channel: 'a', url: 'https://x/a.m3u8' }, { channel: 'b', url: 'http://x/b.m3u8' }, { channel: 'e', url: 'https://x/e.m3u8' }];
  const r = summarizeCategory(channels, streams, 'xxx');
  assert.equal(r.total, 3); assert.equal(r.playable, 2);
  assert.deepEqual(r.byCountry.US, { total: 2, playable: 1 });
  assert.ok(!JSON.stringify(r).includes('.m3u8'));
});
