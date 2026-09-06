import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../core/progression.dart' show levelForXp;
import '../core/theme.dart';
import '../data/admin_chat_service.dart';
import '../core/admin_reveal.dart';
import '../core/remote_flags.dart';
import '../data/moderation_service.dart';
import '../data/multiplayer_activity_service.dart';
import '../data/player_profile_service.dart';
import '../data/shop.dart' show starterGemGrant;
import '../data/storage_service.dart';
import '../models/admin_message.dart';
import '../models/moderation.dart';
import '../models/multiplayer_activity.dart';
import '../models/multiplayer_models.dart' show pickAvatarColor;
import '../models/player_profile.dart';
import '../widgets/avatar.dart';
import '../widgets/category_unlock_animation.dart';
import '../widgets/coin_reward_overlay.dart';
import 'admin_chat_screen.dart';
import 'test_images_screen.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../core/breadcrumbs.dart';
import '../data/bug_report_service.dart';
import 'welcome_screen.dart';

part 'admin/players_tab.dart';
part 'admin/player_detail.dart';
part 'admin/reports_tab.dart';
part 'admin/bug_reports_tab.dart';
part 'admin/rooms_tab.dart';
part 'admin/messages_tab.dart';
part 'admin/debug_tab.dart';
part 'admin/stats_tab.dart';

/// Panou vizibil DOAR pentru contul de admin (vezi profile_screen.dart,
/// randul care navigheaza aici, ascuns pentru oricine altcineva). Opt
/// taburi: gestionare jucatori (interzicere + trimitere de resurse), cine a
/// INTRAT IN JOC azi (tabul implicit — vezi initialIndex), firele de mesaje
/// cu jucatorii, raportarile trimise de jucatori, conturile interzise (singurul loc de unde
/// se poate RIDICA o interdictie — un cont banat nu mai apare in lista
/// normala, fiindca banul ii sterge profilul public), camerele de
/// multiplayer terminate recent, uneltele de debug/test (mutate din
/// SettingsScreen — acolo erau vizibile oricui, fara nicio filtrare) si
/// statistici agregate.
///
/// Un tap pe randul unui jucator deschide [_PlayerDetailScreen], unde apare
/// intai id-ul unic si apoi balanta/prietenii — vezi comentariul de acolo
/// pentru de ce id-ul, si nu numele, e cheia dupa care se opereaza.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
    /// Se deschide pe „Azi", nu pe „Jucători": prima intrebare cand intru in
  /// panou e daca a intrat cineva in joc azi. Rosterul complet e la un tap
  /// distanta, in stanga.
  late final TabController _tabController = TabController(length: 9, initialIndex: 1, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70)),
                  const SizedBox(width: 4),
                  const Text('Admin', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: AppColors.orange,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(text: 'Jucători'),
                Tab(text: 'Azi'),
                Tab(text: 'Mesaje'),
                Tab(text: 'Raportări'),
                Tab(text: 'Bug-uri'),
                Tab(text: 'Banați'),
                Tab(text: 'Camere'),
                Tab(text: 'Debug'),
                Tab(text: 'Statistici'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [_PlayersTab(), _NewTodayTab(), _MessagesTab(), _ReportsTab(), _BugReportsTab(), _BannedTab(), _RoomsTab(), _DebugTab(), _StatsTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirmă și execută interzicerea unui cont — comun taburilor Jucători/Noi
/// azi. Întoarce true doar dacă chiar s-a șters (apelantul decide dacă
/// reîmprospătează lista).
Future<bool> _confirmBan(BuildContext context, PlayerProfile p) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Interzici acest cont?', style: TextStyle(color: Colors.white)),
      content: Text(
        '${p.name} dispare din leaderboard și din listele de prieteni ale altora și nu-și mai poate recrea profilul. Se poate anula din tab-ul „Banați".',
        style: const TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Renunță')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Interzice', style: TextStyle(color: AppColors.danger))),
      ],
    ),
  );
  if (confirmed != true) return false;
  final ok = await PlayerProfileService.instance.banPlayer(p.uid, name: p.name);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '${p.name} a fost interzis.' : 'Nu am putut interzice acest cont.')),
    );
  }
  return ok;
}

/// Ștergere totală a unui cont, din tab-ul Jucători. Spre deosebire de ban
/// (care doar scoate profilul din leaderboard și blochează recrearea lui),
/// asta șterge tot ce ține de cont — vezi [PlayerProfileService.purgePlayer]
/// pentru lista exactă. Dialogul spune explicit și ce NU se întâmplă imediat,
/// ca să nu pară că butonul a lăsat treaba pe jumătate.
Future<bool> _confirmAndPurge(BuildContext context, PlayerProfile p) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Ștergi complet acest cont?', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${p.name} dispare definitiv. Se șterg:',
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          const Text(
            '• profilul public și locul din clasament\n'
            '• prietenii, în ambele sensuri\n'
            '• cererile de prietenie primite\n'
            '• salvarea din cloud (monede, XP, progres)\n'
            '• grant-urile de resurse în așteptare',
            style: TextStyle(color: Colors.white60, fontSize: 12.5, height: 1.5),
          ),
          const SizedBox(height: 10),
          const Text(
            'Contul din Authentication se șterge la următoarea rulare a '
            'scriptului de întreținere — până atunci rămâne gol, fără nicio '
            'dată legată de el.',
            style: TextStyle(color: Colors.white38, fontSize: 11.5, height: 1.35),
          ),
          const SizedBox(height: 10),
          const Text('Nu poate fi anulat.',
              style: TextStyle(color: AppColors.danger, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Renunță')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Șterge tot', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  final ok = await PlayerProfileService.instance.purgePlayer(p.uid, name: p.name);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok
          ? '${p.name} a fost șters complet.'
          : 'Nu am putut șterge acest cont.')),
    );
  }
  return ok;
}

/// Confirmă și execută resetarea unui cont — vezi
/// [PlayerProfileService.resetPlayer] pentru ce se întâmplă imediat și ce
/// abia la următoarea deschidere a jocului de către jucător. Merge identic
/// pentru Guest și pentru conturi Google.
Future<bool> _confirmReset(BuildContext context, PlayerProfile p) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Resetezi acest cont?', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${p.name} o ia de la capăt, ca un jucător nou.',
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 10),
          const Text('PE LOC:',
              style: TextStyle(color: AppColors.teal, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
          const SizedBox(height: 4),
          const Text(
            '• puncte de ligă, meciuri, victorii și serii → 0',
            style: TextStyle(color: Colors.white60, fontSize: 12.5, height: 1.5),
          ),
          const SizedBox(height: 10),
          const Text('LA URMĂTOAREA LUI DESCHIDERE A JOCULUI:',
              style: TextStyle(color: AppColors.teal, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
          const SizedBox(height: 4),
          Text(
            '• XP/nivel, întrebări răspunse, quest-uri, realizări și categorii deblocate → de la zero\n'
            '• balanța → zestrea de start (${StorageService.startingCoinsDefault} monede, '
            '$starterGemGrant gems, ${StorageService.startingLivesDefault} inimi, '
            '${StorageService.startingHintsDefault} hint-uri)\n'
            '• resursele trimise de tine și neridicate încă se anulează',
            style: const TextStyle(color: Colors.white60, fontSize: 12.5, height: 1.5),
          ),
          const SizedBox(height: 10),
          const Text(
            'Rămân: numele, prietenii, codul de prieten și setările lui (sunet, '
            '"fără reclame"). Contul nu dispare, doar o ia de la început.',
            style: TextStyle(color: Colors.white38, fontSize: 11.5, height: 1.35),
          ),
          const SizedBox(height: 10),
          const Text('Nu poate fi anulat.',
              style: TextStyle(color: AppColors.danger, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Renunță')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Resetează', style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  final ok = await PlayerProfileService.instance.resetPlayer(p.uid);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok
          ? '${p.name} a fost resetat — balanța lui revine la start la următoarea deschidere a jocului.'
          : 'Nu am putut reseta acest cont.')),
    );
  }
  return ok;
}

/// Deschide sheet-ul de trimitere resurse. Merge pentru orice cont, Guest
/// inclusiv — cutia poștală e legată de uid, nu de contul Google (vezi
/// CloudSyncService.consumePendingGrant).
void _openGrantSheet(BuildContext context, PlayerProfile p) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1a1a2e),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _GrantSheet(profile: p),
  );
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatCard({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: color.withAlpha(40), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Detaliul unui jucător
// ─────────────────────────────────────────────────────────────────────────

/// Formatare scurtă de dată/oră, fără dependențe (proiectul nu folosește
/// `intl`). Ex: "3 aug, 15:42".
String _shortDate(DateTime d) {
  const luni = ['ian', 'feb', 'mar', 'apr', 'mai', 'iun', 'iul', 'aug', 'sep', 'oct', 'nov', 'dec'];
  final h = d.hour.toString().padLeft(2, '0');
  final m = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${luni[d.month - 1]}, $h:$m';
}

/// "acum 3 min" / "acum 2 h" / "acum 5 zile" — pentru lastActive, unde
/// vechimea relativă spune mai mult decât ora exactă.
String _relative(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'chiar acum';
  if (diff.inMinutes < 60) return 'acum ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'acum ${diff.inHours} h';
  if (diff.inDays == 1) return 'ieri';
  return 'acum ${diff.inDays} zile';
}

/// Dacă (și când) contul intră singur la curățarea automată a Guest-ilor
/// abandonați — vezi PlayerProfileService.guestSweepInactivity pentru
/// criteriul complet. Răspunsul e aproape mereu "nu": e de ajuns un singur
/// semn de activitate ca profilul să fie păstrat definitiv.
String _autoDeleteLabel(PlayerProfile p) {
  if (p.hasGoogleAccount) return 'Nu — cont Google';
  if (p.matchesPlayed > 0) return 'Nu — a jucat meciuri';
  if (p.activityEvents > 0) return 'Nu — are activitate';
  if (p.lastActive == null) return '—';
  final due = p.lastActive!.toDate().add(PlayerProfileService.guestSweepInactivity);
  final left = due.difference(DateTime.now());
  if (left.isNegative) return 'Da — eligibil acum';
  return 'Da — peste ${left.inDays + 1} zile';
}

/// Numere lizibile pentru sume mari: 18750 → "18.750".
String _grouped(int n) {
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return '${n < 0 ? '-' : ''}$buf';
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2),
        ),
      );
}

class _BalanceTile extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final IconData icon;
  const _BalanceTile({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: color.withAlpha(24),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withAlpha(70)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  Text(_grouped(value),
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  final bool highlight;
  const _DetailRow({required this.label, required this.value, this.mono = false, this.highlight = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ),
            Expanded(
              flex: 5,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: highlight ? AppColors.orange : Colors.white,
                  fontSize: highlight ? 16 : 13,
                  fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
                  fontFamily: mono ? 'monospace' : null,
                ),
              ),
            ),
          ],
        ),
      );
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white38, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: const TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.4)),
            ),
          ],
        ),
      );
}

/// Buton de acțiune lat, în stilul pastilelor din meniul principal — nu chip
/// mic în colț, ca restul butoanelor reale din joc.
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  const _ActionButton({required this.label, required this.icon, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
          label: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────
//  Camere de multiplayer terminate
// ─────────────────────────────────────────────────────────────────────────
