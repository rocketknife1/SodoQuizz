# Teste pe regulile Firestore

`firestore_rules_test.mjs` verifică limitele anti-trișare din
`firestore.rules` (secțiunea `player_profiles`): ce trebuie să meargă în joc
normal, ce trebuie refuzat.

**Nu rulează încă pe mașina asta**: emulatorul Firebase cere JDK 21, iar aici
e Java 8. După un upgrade de JDK:

```
cd test
npm init -y && npm install @firebase/rules-unit-testing firebase
cp ../firestore.rules .
firebase emulators:exec --only firestore --project sodoquizz-test "node firestore_rules_test.mjs"
```

Rulează pe emulatorul LOCAL — nicio scriere în producție.
