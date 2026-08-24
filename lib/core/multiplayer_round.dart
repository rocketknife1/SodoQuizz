/// Timpul de răspuns comun tuturor modurilor multiplayer cu rundă
/// sincronizată (Higher & Lower, Quizz Tanks, Obby, Scaunul Electric).
///
/// ÎNAINTE fiecare mod își ținea propria constantă, ajunse din întâmplare la
/// aceeași valoare (12s) prin ajustări separate în timp — Higher & Lower
/// rămăsese în urmă la 15s. Userul a cerut explicit ca toate modurile să aibă
/// ACELAȘI timp per rundă; de-aia există o singură sursă de adevăr aici,
/// nu patru constante care întâmplător coincid și pot diverge din nou la
/// prima modificare izolată.
///
/// NU acoperă fazele secundare (țintire/alegere/scaun) — alea rămân proprii
/// fiecărui mod, fiindcă fac lucruri diferite (Tanks alege o victimă, Scaunul
/// Electric alege victimă ȘI întrebare, Obby alege o placă).
library;

const int sharedRoundAnswerSeconds = 12;
