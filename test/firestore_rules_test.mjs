// Teste pe regulile Firestore, rulate pe EMULATORUL LOCAL — nicio scriere in
// productie. Verifica exact gaura raportata: profilul public e documentul dupa
// care se face clasamentul, iar pana la 2026-09-02 proprietarul putea scrie in
// el orice valoare.
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { readFileSync } from 'fs';
import { doc, setDoc, getDoc } from 'firebase/firestore';

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

// pornim de la un profil existent, scris cu drepturi de admin (fara reguli)
await env.withSecurityRulesDisabled(async (ctx) => {
  await setDoc(P(ctx.firestore(), 'jucator1'), {
    name: 'Eu', leaguePoints: 100, seasonPoints: 50, matchesPlayed: 5, wins: 3, longestStreak: 2,
  });
});

console.log('\nCE TREBUIE SA MEARGA (joc normal):');
await check('un meci castigat: +20 puncte, +1 meci, +1 victorie', () => assertSucceeds(
  setDoc(P(eu, 'jucator1'), { name: 'Eu', leaguePoints: 120, seasonPoints: 70, matchesPlayed: 6, wins: 4, longestStreak: 3 })));
await check('un meci pierdut: -8 puncte', () => assertSucceeds(
  setDoc(P(eu, 'jucator1'), { name: 'Eu', leaguePoints: 92, seasonPoints: 42, matchesPlayed: 6, wins: 3, longestStreak: 0 })));
await check('heartbeat: nu schimba nimic din clasament', () => assertSucceeds(
  setDoc(P(eu, 'jucator1'), { name: 'AltNume', leaguePoints: 100, seasonPoints: 50, matchesPlayed: 5, wins: 3, longestStreak: 2 })));
await check('sezon nou: seasonPoints cade la 20', () => assertSucceeds(
  setDoc(P(eu, 'jucator1'), { name: 'Eu', leaguePoints: 120, seasonPoints: 20, matchesPlayed: 6, wins: 4, longestStreak: 2 })));

console.log('\nCE TREBUIE SA FIE REFUZAT (trisat):');
await check('nu-si poate seta 999999 puncte', () => assertFails(
  setDoc(P(eu, 'jucator1'), { name: 'Eu', leaguePoints: 999999, seasonPoints: 50, matchesPlayed: 5, wins: 3 })));
await check('nu poate lua 21 de puncte dintr-o scriere (peste winPoints)', () => assertFails(
  setDoc(P(eu, 'jucator1'), { name: 'Eu', leaguePoints: 121, seasonPoints: 50, matchesPlayed: 5, wins: 3 })));
await check('nu poate umfla seasonPoints', () => assertFails(
  setDoc(P(eu, 'jucator1'), { name: 'Eu', leaguePoints: 100, seasonPoints: 50000, matchesPlayed: 5, wins: 3 })));
await check('nu poate declara 500 de meciuri jucate deodata', () => assertFails(
  setDoc(P(eu, 'jucator1'), { name: 'Eu', leaguePoints: 100, seasonPoints: 50, matchesPlayed: 505, wins: 3 })));
await check('nu poate declara victorii care n-au existat', () => assertFails(
  setDoc(P(eu, 'jucator1'), { name: 'Eu', leaguePoints: 100, seasonPoints: 50, matchesPlayed: 6, wins: 99 })));

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
