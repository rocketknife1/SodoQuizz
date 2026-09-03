# Reguli R8/ProGuard pentru build-ul de release.
#
# DE CE EXISTA FISIERUL ASTA: Flutter porneste R8 automat la `--release`, iar
# R8 sterge tot ce pare nefolosit — inclusiv informatia de TIPURI GENERICE, pe
# care nimeni n-o "foloseste" vizibil in cod, dar de care depinde orice
# biblioteca ce citeste tipuri prin reflectie (Gson & co.).
#
# Bug-ul real care a dus la fisierul asta (3 septembrie 2026): notificarile
# programate nu apareau NICIODATA in build-ul de release, desi alarma se
# programa corect si canalul exista. In debug mergeau. Cauza, gasita in
# logcat exact in clipa in care trebuia sa sune alarma:
#
#   java.lang.IllegalStateException: TypeToken must be created with a type
#   argument: new TypeToken<...>() {}; When using code shrinkers (ProGuard,
#   R8, ...) make sure that generic signatures are preserved.
#     at com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver.onReceive
#
# flutter_local_notifications isi serializeaza notificarea programata cu Gson;
# fara `-keepattributes Signature`, TypeToken ramane fara tip si receiverul
# crapa in tacere, cu aplicatia inchisa. Nimic din `flutter analyze` sau
# `flutter test` nu poate prinde asta — se vede DOAR pe un build de release,
# pe telefon.

# Semnaturile generice si adnotarile: fara ele, orice reflectie pe tipuri
# parametrizate (Gson, serializare) se rupe.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Pluginul de notificari locale, cu tot cu clasele lui de model serializate.
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

# Gson: subclasele anonime de TypeToken sunt exact lucrul pe care R8 il
# considera "nefolosit" si il curata.
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
