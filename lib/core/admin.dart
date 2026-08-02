/// Emailul singurului cont cu acces la panoul de admin — folosit atât în
/// Dart (AuthService.currentUser?.email) cât și, ca literal identic, în
/// firestore.rules (request.auth.token.email). Dacă se schimbă vreodată,
/// trebuie schimbat în ambele locuri.
const kAdminEmail = 'dragosssx@gmail.com';
