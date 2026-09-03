# Teste pe regulile Firestore

`firestore_rules_test.mjs` verifică limitele anti-trișare din
`firestore.rules`: clasamentul (`player_profiles`), scrierea în meciuri
(`matches`) și firul cu adminul (`admin_threads`) — ce trebuie să meargă în
joc normal, ce trebuie refuzat. 33 de cazuri, fiecare pornind de la o stare
curată (scrisă cu `withSecurityRulesDisabled`), deci ordinea rulării nu
contează.

Cazul care contează cel mai mult la `admin_threads` e IMPERSONAREA: aplicația
desenează baloanele strict după câmpul `fromAdmin`, deci regula trebuie să
refuze un jucător care ar scrie `fromAdmin: true` în propriul fir.

**Rulează** (emulatorul cere JDK 21+; mașina are Temurin JDK 25 la
`C:\Program Files\Eclipse Adoptium\jdk-25.0.3.9-hotspot`, dar shim-ul
`java8path` e primul pe PATH — trebuie pus JAVA_HOME explicit):

```bash
export JAVA_HOME="/c/Program Files/Eclipse Adoptium/jdk-25.0.3.9-hotspot"
export PATH="$JAVA_HOME/bin:$PATH" && hash -r

cd test
npm init -y && npm install @firebase/rules-unit-testing firebase
cp ../firestore.rules .
firebase emulators:exec --only firestore --project sodoquizz-test "node firestore_rules_test.mjs"
```

Rulează pe emulatorul LOCAL — nicio scriere în producție.

Ultima rulare verde: 2026-09-03, 33/33 (după adăugarea `admin_threads`).
