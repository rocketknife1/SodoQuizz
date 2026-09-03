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
import { doc, setDoc, updateDoc, deleteDoc, arrayUnion, getDoc, getDocs, collection } from 'firebase/firestore';

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


// --- matches/{id}: doar cei de la masa pot scrie -----------------------------
console.log('MECIURI - cine poate scrie in documentul meciului:');

const M = (db, id) => doc(db, 'matches', id);
const eu2 = env.authenticatedContext('jucator1').firestore();
const strain = env.authenticatedContext('strain').firestore();
const nou3 = env.authenticatedContext('jucatorNou3').firestore();

const seedMatch = (over = {}) => env.withSecurityRulesDisabled((ctx) =>
  setDoc(M(ctx.firestore(), 'm1'), {
    status: 'playing', roundIndex: 3, playerIds: ['jucator1', 'coleg'], ...over,
  }));

await seedMatch();
await check('un participant scrie runda', () => assertSucceeds(
  setDoc(M(eu2, 'm1'), { roundIndex: 4 }, { merge: true })));

await seedMatch();
await check('un STRAIN nu poate vandaliza meciul', () => assertFails(
  setDoc(M(strain, 'm1'), { roundIndex: 999, status: 'finished' }, { merge: true })));

await seedMatch();
await check('un STRAIN nu poate sterge meciul', () => assertFails(
  deleteDoc(M(strain, 'm1'))));

await seedMatch();
await check('cine intra in camera se adauga singur (arrayUnion)', () => assertSucceeds(
  updateDoc(M(nou3, 'm1'), { playerIds: arrayUnion('jucatorNou3') })));

await seedMatch();
await check('NU poate adauga pe altcineva in lista', () => assertFails(
  updateDoc(M(nou3, 'm1'), { playerIds: arrayUnion('cineva-random') })));

await seedMatch();
await check('NU poate rescrie lista ca sa ramana singur', () => assertFails(
  updateDoc(M(nou3, 'm1'), { playerIds: ['jucatorNou3'] })));

await seedMatch();
await check('NU poate strecura si alte campuri odata cu intrarea', () => assertFails(
  updateDoc(M(nou3, 'm1'), { playerIds: arrayUnion('jucatorNou3'), roundIndex: 999 })));

// Meciurile ramase de la versiunea dinainte de `playerIds` n-au campul deloc
// si trebuie sa mearga mai departe, altfel s-ar rupe in mana jucatorilor chiar
// in clipa actualizarii.
await env.withSecurityRulesDisabled((ctx) =>
  setDoc(M(ctx.firestore(), 'm_vechi'), { status: 'playing', roundIndex: 1 }));
await check('meci VECHI, fara playerIds: scrierea merge mai departe', () => assertSucceeds(
  setDoc(M(strain, 'm_vechi'), { roundIndex: 2 }, { merge: true })));

// --- Firul admin <-> jucator (admin_threads) -------------------------------
// Miza reala aici e IMPERSONAREA: aplicatia deseneaza baloanele strict dupa
// campul `fromAdmin` (vezi AdminMessage), deci daca un jucator ar putea scrie
// `fromAdmin: true` si-ar fabrica singur un mesaj care pare al administratorului.

console.log('\nFIRUL CU ADMINUL:');

const adminCtx = env.authenticatedContext('adminUid', { email: 'dragosssx@gmail.com' }).firestore();
const jucator = env.authenticatedContext('jucatorX').firestore();
const altul = env.authenticatedContext('jucatorY').firestore();

const T = (db, uid) => doc(db, 'admin_threads', uid);
const MSG = (db, uid, id) => doc(db, 'admin_threads', uid, 'messages', id);

await check('jucatorul isi scrie in propriul fir (fromAdmin: false)', () => assertSucceeds(
  setDoc(MSG(jucator, 'jucatorX', 'm1'), { senderId: 'jucatorX', fromAdmin: false, text: 'salut' })));

await check('IMPERSONARE: jucatorul NU poate scrie fromAdmin: true', () => assertFails(
  setDoc(MSG(jucator, 'jucatorX', 'm2'), { senderId: 'jucatorX', fromAdmin: true, text: 'sunt adminul' })));

await check('jucatorul NU poate scrie in numele altui senderId', () => assertFails(
  setDoc(MSG(jucator, 'jucatorX', 'm3'), { senderId: 'altcineva', fromAdmin: false, text: 'x' })));

await check('un STRAIN nu poate scrie in firul altui jucator', () => assertFails(
  setDoc(MSG(altul, 'jucatorX', 'm4'), { senderId: 'jucatorY', fromAdmin: false, text: 'x' })));

await check('un STRAIN nu poate citi firul altui jucator', () => assertFails(
  getDoc(T(altul, 'jucatorX'))));

await check('jucatorul isi citeste propriul fir', () => assertSucceeds(
  getDoc(T(jucator, 'jucatorX'))));

await check('adminul raspunde in firul oricui (fromAdmin: true)', () => assertSucceeds(
  setDoc(MSG(adminCtx, 'jucatorX', 'a1'), { senderId: 'adminUid', fromAdmin: true, text: 'am notat' })));

await check('adminul NU poate scrie in numele jucatorului', () => assertFails(
  setDoc(MSG(adminCtx, 'jucatorX', 'a2'), { senderId: 'jucatorX', fromAdmin: false, text: 'x' })));

await check('adminul citeste firul oricui', () => assertSucceeds(
  getDoc(T(adminCtx, 'jucatorX'))));

await check('adminul LISTEAZA toate firele (tab-ul Mesaje)', () => assertSucceeds(
  getDocs(collection(adminCtx, 'admin_threads'))));

await check('un jucator NU poate lista firele tuturor', () => assertFails(
  getDocs(collection(jucator, 'admin_threads'))));

console.log(`\n=== ${pass} trec, ${fail} pica ===`);
await env.cleanup();
process.exit(fail === 0 ? 0 : 1);
