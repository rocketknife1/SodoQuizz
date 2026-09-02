# Teste pe regulile Firestore

`firestore_rules_test.mjs` verifică limitele anti-trișare din
`firestore.rules` (secțiunea `player_profiles`): ce trebuie să meargă în joc
normal, ce trebuie refuzat. 14 cazuri, fiecare pornind de la o stare curată
(scrisă cu `withSecurityRulesDisabled`), deci ordinea rulării nu contează.

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

Ultima rulare verde: 2026-09-02, 14/14 (`firestore.rules` @ 195461f).
