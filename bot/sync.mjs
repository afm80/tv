// تشغيل: node bot/sync.mjs [--dry] [--only=SA,EG]
import fs from 'node:fs';
import { buildPlan, checkStream } from './lib.mjs';

const cfg = JSON.parse(fs.readFileSync(new URL('./config.json', import.meta.url), 'utf8'));
const DRY = process.argv.includes('--dry');
const only = (process.argv.find(a => a.startsWith('--only=')) || '').slice(7).split(',').map(s => s.trim().toUpperCase()).filter(Boolean);
const API = 'https://iptv-org.github.io/api/';

async function getJson(url, optional = false) {
  for (let i = 0; i < 3; i++) {
    try { const r = await fetch(url); if (r.ok) return await r.json(); } catch {}
    await new Promise(r => setTimeout(r, 1500 * (i + 1)));
  }
  if (optional) return [];
  throw new Error('تعذر تحميل ' + url);
}

// القراءة عبر REST العام (نفس ما يفعله موقعك) فلا تحتاج مفاتيح في وضع --dry
const readNode = async name => (await getJson(`${cfg.databaseURL}/${name}.json`, true)) || {};

const [channels, streams, logos, blocklist, cats, chans] = await Promise.all([
  getJson(API + 'channels.json'), getJson(API + 'streams.json'),
  getJson(API + 'logos.json', true), getJson(API + 'blocklist.json', true),
  readNode('categories'), readNode('channels')
]);
console.log(`المصدر: ${channels.length} قناة، ${streams.length} رابط`);

const check = url => checkStream(url, { origin: cfg.siteOrigin, requireCors: cfg.requireCors !== false });

const plan = await buildPlan({ api: { channels, streams, logos, blocklist }, cats, chans, cfg, check, only });

plan.log.forEach(l => console.log(l));
console.table(plan.summary);
console.log(`أقسام جديدة: ${Object.keys(plan.catCreates).length} | قنوات للكتابة: ${Object.keys(plan.writes).length} | للحذف: ${plan.deletes.length}`);

if (DRY) { console.log('وضع التجربة: لم يتم تغيير شيء.'); process.exit(0); }

const { default: admin } = await import('firebase-admin');
const sa = process.env.FIREBASE_SERVICE_ACCOUNT;
if (!sa) throw new Error('المتغير FIREBASE_SERVICE_ACCOUNT غير موجود');
admin.initializeApp({ credential: admin.credential.cert(JSON.parse(sa)), databaseURL: cfg.databaseURL });
const db = admin.database();

const updates = {};
for (const [id, v] of Object.entries(plan.catCreates)) updates[`categories/${id}`] = v;
for (const [k, v] of Object.entries(plan.writes)) updates[`channels/${k}`] = v;
for (const k of plan.deletes) updates[`channels/${k}`] = null;
const entries = Object.entries(updates);
for (let i = 0; i < entries.length; i += 100) await db.ref().update(Object.fromEntries(entries.slice(i, i + 100)));
console.log('تم التحديث ✓');
process.exit(0);
