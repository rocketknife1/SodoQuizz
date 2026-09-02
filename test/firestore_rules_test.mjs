// Teste pe regulile Firestore, rulate pe EMULATORUL LOCAL — nicio scriere in
// productie. Verifica exact gaura raportata: profilul public e documentul dupa
// care se face clasamentul, iar pana la 2026-09-02 proprietarul putea scrie in
// el orice valoare.
//
// Fiecare caz porneste de la o stare cunoscuta, scrisa cu drepturi de admin
// (withSecurityRulesDisabled), ca sa nu depinda de ordinea rularii — un caz
// picat inainte nu mai lasa starea "murdara" peste urmatorul.
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { readFileSync } from 'fs';
import { doc, setDoc } from 'firebase/firestore';

const env = await initializeTestEnvironment({
  projectId: 'sodoquizz-test',
  firestore: { rules: readFileSync('firestore.rules', 'utf8'), host: '127.0.0.1', port: 8080 },
});

let pass = 0, fail = 0;
const check = async (nume, fn) => {
  try { await fn(); console.log('  OK   ' + nume); pass++; }
  catch (e) { console.log('  PICA ' + nume + '  -> ' + e.message.split('\n')[0]); fail++; }
};

const eu = env.authenticatedContext('jucator1').firestore();
const P = (db, id) => doc(db, 'player_profiles', id);

const BASE = {
  name: 'Eu', leaguePoints: 100, seasonPoints: 50,
  matchesPlayed: 5, wins: 3, losses: 2,
  currentStreak: 2, longestStreak: 2, seasonKey: '2026-09',
};
// reincarca profilul 'jucator1' la BASE (+ suprascrieri), fara reguli
const reset = (over = {}) => env.withSecurityRulesDisabled((ctx) =>
  setDoc(P(ctx.firestore(), 'jucator1'), { ...BASE, ...over }));

// scriere de owner, cu merge — exact ca in app (SetOptions(merge: true))
const write = (fields) => setDoc(P(eu, 'jucator1'), fields, { merge: true });

console.log('\nCE TREBUIE SA MEARGA (joc normal):');

await reset();
await check('un meci castigat: +20 puncte, +1 meci, +1 victorie, streak 2->3', () => assertSucceeds(
  write({ leaguePoints: 120, seasonPoints: 70, matchesPlayed: 6, wins: 4, currentStreak: 3, longestStreak: 3 })));

await reset();
await check('un meci pierdut: -8 puncte, streak cade la 0', () => assertSucceeds(
  write({ leaguePoints: 92, seasonPoints: 42, matchesPlayed: 6, losses: 3, currentStreak: 0 })));

await reset();
await check('heartbeat (merge, doar nume + lastActive): nu atinge clasamentul', () => assertSucceeds(
  write({ name: 'AltNume' })));

await reset({ seasonKey: '2026-08' }); // ultima scriere a fost luna trecuta
await check('sezon nou: seasonPoints reincepe de la delta unui meci castigat', () => assertSucceeds(
  write({ leaguePoints: 120, seasonPoints: 20, matchesPlayed: 6, wins: 4, seasonKey: '2026-09' })));

await reset();
await check('o infrangere poate scadea leaguePoints oricat (scaderea nu e trisat)', () => assertSucceeds(
  write({ leaguePoints: 0, seasonPoints: 0 })));

console.log('\nCE TREBUIE SA FIE REFUZAT (trisat):');

await reset();
await check('nu-si poate seta 999999 puncte', () => assertFails(
  write({ leaguePoints: 999999 })));

await reset();
await check('nu poate lua 21 de puncte dintr-o scriere (peste winPoints=20)', () => assertFails(
  write({ leaguePoints: 121 })));

await reset();
await check('nu poate umfla seasonPoints', () => assertFails(
  write({ seasonPoints: 50000 })));

await reset();
await check('nu poate declara 500 de meciuri jucate deodata', () => assertFails(
  write({ matchesPlayed: 505 })));

await reset();
await check('nu poate declara victorii care n-au existat', () => assertFails(
  write({ wins: 99 })));

await reset();
await check('nu poate sari longestStreak cu mai mult de 1', () => assertFails(
  write({ longestStreak: 20 })));

console.log('\nPROFIL NOU:');
const nou = env.authenticatedContext('jucatorNou').firestore();
await check('se poate crea de la zero', () => assertSucceeds(
  setDoc(P(nou, 'jucatorNou'), { name: 'Nou', leaguePoints: 0, seasonPoints: 0, matchesPlayed: 0, wins: 0 })));
const nou2 = env.authenticatedContext('jucatorNou2').firestore();
await check('NU se poate crea direct cu punctaj', () => assertFails(
  setDoc(P(nou2, 'jucatorNou2'), { name: 'Smecher', leaguePoints: 50000, seasonPoints: 50000, matchesPlayed: 0, wins: 0 })));

console.log('\nPROFILUL ALTUIA:');
await check('nu poate scrie in profilul altcuiva', () => assertFails(
  setDoc(P(eu, 'jucator1_altcineva'), { name: 'x', leaguePoints: 0, seasonPoints: 0, matchesPlayed: 0, wins: 0 })));

console.log(`\n=== ${pass} trec, ${fail} pica ===`);
await env.cleanup();
process.exit(fail === 0 ? 0 : 1);
