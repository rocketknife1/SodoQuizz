# Link-uri Sodo Quizz

## Joacă direct din browser (Android, iPhone, PC)

https://rocketknife1.github.io/SodoQuizz/

Se actualizează automat la fiecare push pe `main` (vezi
`.github/workflows/flutter_web.yml`).

## Descarcă pentru Android

https://github.com/rocketknife1/SodoQuizz/releases/download/v1.0.0-preview.3/app-release.apk

APK semnat de release (upload keystore) — instalează manual, permite
"surse necunoscute" dacă telefonul cere. **~147MB** (era 647MB până la
conversia pozelor în WebP).

Varianta mai mică, **~115MB**, pentru telefoanele moderne (orice telefon
de după ~2017, procesor pe 64 de biți):

https://github.com/rocketknife1/SodoQuizz/releases/download/v1.0.0-preview.3/app-arm64-v8a-release.apk

Dacă nu ești sigur, ia-l pe primul — merge pe orice telefon.

Ultimul build: economia v3 (vezi `docs/economie_v3.md`) — XP decuplat de
puncte, cost de hint proporțional cu averea, pariuri la multiplayer, balon
de BETA și contor de reîncărcare a vieților.

## Cum se construiește (reclame reale vs. de test)

APK-ul public de mai sus se construiește **fără** flag, deci folosește
unitățile oficiale de test AdMob:

```
flutter build apk --release
```

Nu produce venit, dar nici nu poate fi raportat drept trafic invalid,
indiferent câți prieteni îl testează și de câte ori se uită la reclame.

Build-ul care chiar câștigă bani (doar pentru încărcarea în Google Play):

```
flutter build appbundle --release --dart-define=REAL_ADS=true
```

Vezi `lib/core/ads_service.dart` pentru detalii. Reclamele reale nu vor
servi oricum până când aplicația nu e publicată în Play, legată în AdMob și
trecută prin review-ul lor.

## iOS

Nu există momentan un link de instalare directă — Apple nu permite asta
în afara App Store/TestFlight, iar proiectul nu are încă un cont de
Apple Developer configurat. Varianta de browser de mai sus merge și pe
iPhone.
