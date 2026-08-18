# Cum se construiește aplicația

Notițe de dezvoltare. Partea publică, de postat, e în [LINKS.md](../LINKS.md).

## Reclame reale vs. de test

Unitatea AdMob se alege la COMPILARE, nu la runtime — vezi
`lib/core/ads_service.dart`.

### Build public (GitHub release, prieteni care testează)

```
flutter build apk --release
flutter build apk --release --split-per-abi     # variantele mai mici, pe arhitectură
```

Fără niciun flag, aplicația cere unitățile **oficiale de test** ale Google.
Nu produc venit, dar nici nu pot fi raportate vreodată drept trafic invalid,
indiferent câți oameni testează și de câte ori se uită la reclame.

Ăsta e singurul build care are voie să ajungă în linkul public. Lista de
device-uri de test din cod acoperă doar telefonul de dezvoltare, nu și pe ale
celorlalți — de-aia comutatorul e implicit pe "test", nu pe "real".

### Build pentru Google Play (singurul care face bani)

```
flutter build appbundle --release --dart-define=REAL_ADS=true
```

Reclamele reale nu vor servi oricum până când aplicația nu e publicată în
Play, legată de listare în AdMob și trecută prin review-ul lor — vezi
[../play_store/ghid_consola.md](../play_store/ghid_consola.md).

## App Check (dovada că binarul e cel autentic)

Vezi `lib/core/app_check_service.dart` pentru ce face și, mai ales, pentru
capcana de la „Enforce". Două flag-uri de compilare:

```
--dart-define=APPCHECK_DEBUG=true              # doar pentru testele mele pe telefon
--dart-define=APPCHECK_RECAPTCHA_KEY=6Lc...    # doar pentru build-ul web
```

`APPCHECK_DEBUG` **nu se pune niciodată pe build-ul de Play** — acolo trebuie
Play Integrity, altfel App Check nu apără nimic. E doar pentru APK-urile
construite local: ele sunt semnate cu cheia de upload, nu cu cea cu care Play
redistribuie, deci Play Integrity le refuză din principiu. Tokenul tipărit în
logcat la prima pornire se înregistrează o dată în Firebase Console →
App Check → Apps → Manage debug tokens.

Fără `APPCHECK_RECAPTCHA_KEY`, varianta web pornește normal, doar că sare
peste App Check (vezi `activateAppCheck`).

## Publicarea unei versiuni noi

```
gh release create vX.Y.Z build/app/outputs/flutter-apk/app-release.apk \
                          build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
   --title "..." --notes "..."
```

Linkurile din LINKS.md folosesc `/releases/latest/download/<fisier>`, deci
**nu trebuie actualizate la fiecare versiune** — cât timp numele fișierelor
rămân aceleași, ele arată automat spre ultima versiune.

## Pagina web

Se reconstruiește și se publică singură la fiecare push pe `main`, prin
`.github/workflows/flutter_web.yml`. Local:

```
flutter build web --release
```

## Verificări înainte de release

```
flutter analyze
flutter test
python tools/firestore_cleanup.py     # doar raportează; --sterge ca să aplice
```
