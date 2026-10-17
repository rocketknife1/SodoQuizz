// Verifică fișierele intrebari_en.json față de intrebari.json: JSON valid,
// fiecare id există, variantele traduse sunt 4 și distincte, 3 indicii.
// Rulare: node tools/check_translations.js
const fs = require('fs'), path = require('path');
const root = 'assets/continut';
let bad = 0;
for (const cat of fs.readdirSync(root).sort()) {
  const ro = path.join(root, cat, 'intrebari.json');
  const en = path.join(root, cat, 'intrebari_en.json');
  if (!fs.existsSync(ro)) continue;
  const roData = JSON.parse(fs.readFileSync(ro, 'utf8'));
  const byId = {};
  for (const c of Object.values(roData.categorii)) for (const q of c.intrebari || []) byId[q.id] = q;
  if (!fs.existsSync(en)) { console.log(`${cat}: fără traducere (0/${Object.keys(byId).length})`); continue; }
  let enData;
  try { enData = JSON.parse(fs.readFileSync(en, 'utf8')); } catch (e) { console.log(`${cat}: JSON INVALID — ${e.message}`); bad++; continue; }
  const items = enData.q || {};
  for (const key of Object.keys(roData.categorii)) if (!(enData.descrieri || {})[key]) { console.log(`${cat}: lipsește descrierea pentru ${key}`); bad++; }
  for (const [id, t] of Object.entries(items)) {
    const q = byId[id];
    if (!q) { console.log(`${cat}/${id}: id inexistent`); bad++; continue; }
    if (t.v) {
      if (t.v.length !== (q.variante || []).length) { console.log(`${cat}/${id}: ${t.v.length} variante în loc de ${q.variante.length}`); bad++; }
      if (new Set(t.v).size !== t.v.length) { console.log(`${cat}/${id}: variante EN duplicate`); bad++; }
    }
    if (!Array.isArray(t.h) || t.h.length !== 3 || t.h.some(x => !x || !x.trim())) { console.log(`${cat}/${id}: indiciile nu sunt 3`); bad++; }
  }
  const missing = Object.keys(byId).filter(id => !items[id]);
  console.log(`${cat}: ${Object.keys(items).length}/${Object.keys(byId).length}${missing.length ? ' — lipsesc: ' + missing.slice(0, 8).join(', ') + (missing.length > 8 ? '…' : '') : ''}`);
}
process.exit(bad ? 1 : 0);
