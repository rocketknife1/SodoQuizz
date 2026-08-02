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
