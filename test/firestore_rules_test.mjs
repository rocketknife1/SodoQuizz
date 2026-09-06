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
import { doc, setDoc, updateDoc, deleteDoc, arrayUnion, getDoc, getDocs, collection, addDoc } from 'firebase/firestore';

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

await reset({ rating: 1000 });
await check('ratingul se poate misca <= 30 intr-un meci', () => assertSucceeds(
  write({ rating: 1024 })));

await reset({ rating: 1000 });
await check('ratingul NU poate sari cu > 30', () => assertFails(
  write({ rating: 1200 })));

await reset({ rating: 1000 });
await check('ratingul NU poate cadea cu > 30', () => assertFails(
  write({ rating: 500 })));

console.log('\nCOSMETICE (equippedFrame / equippedTitle / level):');

await reset();
await check('owner-ul isi poate scrie cosmeticele + nivelul', () => assertSucceeds(
  write({ equippedFrame: 'gold', equippedTitle: 'veteran', level: 12 })));

await reset();
await check('cosmeticele nu pacalesc garda anti-cheat de clasament (delta legala)', () => assertSucceeds(
  write({ equippedFrame: 'diamond', equippedTitle: 'titan', level: 50, leaguePoints: 110 })));

await reset();
await check('cosmeticele nu deblocheaza un salt ilegal de leaguePoints', () => assertFails(
  write({ equippedFrame: 'gold', leaguePoints: 999999 })));

console.log('\nPROVOCAREA ZILEI (daily_challenges/{data}/scores/{uid}):');

const DC = (db, uid) => doc(db, 'daily_challenges', '2026-09-06', 'scores', uid);

await check('owner-ul isi scrie scorul cu monede consistente (4/5)', () => assertSucceeds(
  setDoc(DC(eu, 'jucator1'), { name: 'Eu', correct: 4, coins: 160, level: 3 })));

await check('scor perfect: 5 corecte = 350 monede (40*5 + 150)', () => assertSucceeds(
  setDoc(DC(eu, 'jucator1'), { name: 'Eu', correct: 5, coins: 350, level: 3 })));

await check('NU poate umfla monedele peste formula', () => assertFails(
  setDoc(DC(eu, 'jucator1'), { name: 'Eu', correct: 3, coins: 99999, level: 3 })));

await check('NU poate declara mai mult de 5 corecte', () => assertFails(
  setDoc(DC(eu, 'jucator1'), { name: 'Eu', correct: 8, coins: 470, level: 3 })));

await check('NU poate scrie scorul altcuiva', () => assertFails(
  setDoc(DC(eu, 'altcineva'), { name: 'X', correct: 5, coins: 350, level: 1 })));

const strainDC = env.authenticatedContext('strain2').firestore();
await check('oricine autentificat poate CITI clasamentul de azi', () => assertSucceeds(
  getDoc(DC(strainDC, 'jucator1'))));

await check('jucatorul NU-si poate STERGE scorul (nu rejoaca)', () => assertFails(
  deleteDoc(DC(eu, 'jucator1'))));

console.log('\nCLASAMENT DE EVENIMENT (events/{id}/scores/{uid}):');

const EV = (db, uid) => doc(db, 'events', 'halloween-2026', 'scores', uid);

await check('owner-ul isi creeaza scorul de eveniment (<= 50)', () => assertSucceeds(
  setDoc(EV(eu, 'jucator1'), { name: 'Eu', points: 30, level: 3 })));

await check('poate acumula (35 + 40 = 75, delta 40 <= 50)', () => assertSucceeds(
  setDoc(EV(eu, 'jucator1'), { name: 'Eu', points: 70, level: 3 })));

await check('NU poate sari cu mai mult de 50 intr-o scriere', () => assertFails(
  setDoc(EV(eu, 'jucator1'), { name: 'Eu', points: 999, level: 3 })));

await check('NU poate SCADEA scorul', () => assertFails(
  setDoc(EV(eu, 'jucator1'), { name: 'Eu', points: 10, level: 3 })));

await check('NU poate scrie scorul altcuiva', () => assertFails(
  setDoc(EV(eu, 'altul'), { name: 'X', points: 20, level: 1 })));

await check('oricine autentificat citeste clasamentul evenimentului', () => assertSucceeds(
  getDoc(EV(env.authenticatedContext('strain3').firestore(), 'jucator1'))));

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

// config/admin: uid-ul adminului, publicat de propria lui aplicatie ca sa-l
// poata citi Cloud Function-ul. Nimeni nu-l citeste din client.

await check('adminul isi publica uid-ul in config/admin', () => assertSucceeds(
  setDoc(doc(adminCtx, 'config', 'admin'), { uid: 'adminUid' })));

await check('adminul NU poate publica alt uid decat al lui', () => assertFails(
  setDoc(doc(adminCtx, 'config', 'admin'), { uid: 'altcineva' })));

await check('un jucator NU poate scrie config/admin', () => assertFails(
  setDoc(doc(jucator, 'config', 'admin'), { uid: 'jucatorX' })));

await check('nimeni nu citeste config/admin din client (nici adminul)', () => assertFails(
  getDoc(doc(adminCtx, 'config', 'admin'))));

// security_flags: salturile de balanta notate de Cloud Function
// `onBalanceAudit`. Scrie DOAR Admin SDK-ul (caruia regulile nu i se aplica);
// din client nu scrie nimeni, altfel un trisor si-ar sterge propriul semnal.

await env.withSecurityRulesDisabled((ctx) => setDoc(
  doc(ctx.firestore(), 'security_flags', 'jucatorUid'),
  { flagCount: 2, lastReason: 'coins: +9000000 intr-o scriere' }));

await check('adminul citeste semnalul de balanta', () => assertSucceeds(
  getDoc(doc(adminCtx, 'security_flags', 'jucatorUid'))));

await check('jucatorul NU-si vede propriul semnal', () => assertFails(
  getDoc(doc(jucator, 'security_flags', 'jucatorUid'))));

await check('jucatorul NU-si poate sterge semnalul', () => assertFails(
  deleteDoc(doc(jucator, 'security_flags', 'jucatorUid'))));

await check('nici adminul nu scrie semnale din client', () => assertFails(
  setDoc(doc(adminCtx, 'security_flags', 'altul'), { flagCount: 1 })));

// bug_reports: rapoartele trimise din aplicatie. Oricine logat poate CREA
// (raportul are sens tocmai cand ceva e rupt), dar numai in numele lui, si
// numai adminul citeste.

const RAPORT = (uid) => ({
  uid, versiune: '1.0.1+6', platforma: 'android', ecran: 'Joc',
  eroare: 'ceva a crapat', stiva: 'linia 1\nlinia 2', firimituri: ['[0:01] intra: Joc'],
  rezolvat: false,
});

await check('un jucator isi trimite propriul raport', () => assertSucceeds(
  addDoc(collection(jucator, 'bug_reports'), RAPORT('jucatorX'))));

await check('NU poate trimite un raport in numele altuia', () => assertFails(
  addDoc(collection(jucator, 'bug_reports'), RAPORT('altcineva'))));

await check('un raport urias e refuzat (ar umple baza)', () => assertFails(
  addDoc(collection(jucator, 'bug_reports'), {
    ...RAPORT('jucatorX'),
    firimituri: Array.from({ length: 500 }, (_, i) => `linia ${i}`),
  })));

await check('adminul citeste rapoartele', () => assertSucceeds(
  getDocs(collection(adminCtx, 'bug_reports'))));

await check('un jucator NU citeste rapoartele (nici pe ale lui)', () => assertFails(
  getDocs(collection(jucator, 'bug_reports'))));

// Stergerea unui profil de catre ADMIN ("Sterge complet" din panou).
// A fost stricata tacit intre 2026-09-02 si 2026-09-03: despartirea lui
// `allow write` in create+update a lasat `delete` doar cu regula de curatare a
// Guest-ilor abandonati de 15 zile.

console.log('\nSTERGEREA UNUI CONT DE CATRE ADMIN:');

await env.withSecurityRulesDisabled((ctx) => setDoc(P(ctx.firestore(), 'deSters'), {
  name: 'DeSters', hasGoogleAccount: true, matchesPlayed: 7, activityEvents: 3,
}));
await check('adminul sterge un cont ACTIV cu cont Google', () => assertSucceeds(
  deleteDoc(P(adminCtx, 'deSters'))));

await env.withSecurityRulesDisabled((ctx) => setDoc(P(ctx.firestore(), 'deSters2'), {
  name: 'DeSters2', hasGoogleAccount: false, matchesPlayed: 0, activityEvents: 0,
}));
await check('un jucator oarecare NU poate sterge profilul altuia', () => assertFails(
  deleteDoc(P(jucator, 'deSters2'))));

console.log(`\n=== ${pass} trec, ${fail} pica ===`);
await env.cleanup();
process.exit(fail === 0 ? 0 : 1);
