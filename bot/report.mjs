// تقرير قراءة فقط عن فئة في المصدر (لا اتصال بقاعدتك ولا كتابة ولا روابط)
// تشغيل: node bot/report.mjs [الفئة=xxx] [--names]
import { summarizeCategory, arName } from './lib.mjs';

const API = 'https://iptv-org.github.io/api/';
const category = process.argv.slice(2).find(a => !a.startsWith('--')) || 'xxx';
const showNames = process.argv.includes('--names');

async function getJson(url) {
  for (let i = 0; i < 3; i++) {
    try { const r = await fetch(url); if (r.ok) return await r.json(); } catch {}
    await new Promise(r => setTimeout(r, 1500 * (i + 1)));
  }
  throw new Error('تعذر تحميل ' + url);
}

const [channels, streams] = await Promise.all([getJson(API + 'channels.json'), getJson(API + 'streams.json')]);
const r = summarizeCategory(channels, streams, category);
console.log(`فئة "${category}" في المصدر: ${r.total} قناة، منها ${r.playable} لها رابط https على الأقل (قبل فحص عمل الرابط وCORS).`);
const rows = Object.entries(r.byCountry).sort((a, b) => b[1].total - a[1].total);
console.log('حسب الدولة:');
rows.forEach(([code, e]) => console.log(`  ${arName(code)} (${code}): ${e.total} قناة، ${e.playable} بروابط`));
if (showNames) { console.log('الأسماء:'); r.list.forEach(x => console.log(`  - ${x.name} [${x.country}]${x.playable ? '' : ' (بلا رابط)'}`)); }
console.log('تقرير فقط: لم يُكتب شيء ولم يُعرض أي رابط.');
