import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../core/progression.dart' show levelForXp;
import '../core/theme.dart';
import '../data/moderation_service.dart';
import '../data/multiplayer_activity_service.dart';
import '../data/player_profile_service.dart';
import '../data/shop.dart' show starterGemGrant;
import '../data/storage_service.dart';
import '../models/moderation.dart';
import '../models/multiplayer_activity.dart';
import '../models/multiplayer_models.dart' show pickAvatarColor;
import '../models/player_profile.dart';
import '../widgets/avatar.dart';
import '../widgets/category_unlock_animation.dart';
import '../widgets/coin_reward_overlay.dart';
import 'test_images_screen.dart';

/// Panou vizibil DOAR pentru contul de admin (vezi profile_screen.dart,
/// randul care navigheaza aici, ascuns pentru oricine altcineva). Sase
/// taburi: gestionare jucatori (interzicere + trimitere de resurse),
/// jucatorii inregistrati azi, raportarile trimise de jucatori, camerele de
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
  late final TabController _tabController = TabController(length: 6, vsync: this);

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
                Tab(text: 'Noi azi'),
                Tab(text: 'Raportări'),
                Tab(text: 'Camere'),
                Tab(text: 'Debug'),
                Tab(text: 'Statistici'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [_PlayersTab(), _NewTodayTab(), _ReportsTab(), _RoomsTab(), _DebugTab(), _StatsTab()],
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
        '${p.name} dispare din leaderboard și din listele de prieteni ale altora și nu-și mai poate recrea profilul. Nu poate fi anulat.',
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

/// Rând de jucător pentru AdminScreen — variantă a `_PlayerRow` din
/// leaderboard_screen.dart, cu acțiuni de grant/ban în loc de scor.
class _AdminPlayerRow extends StatelessWidget {
  final PlayerProfile profile;
  final VoidCallback onGrant;
  final VoidCallback onBan;
  final VoidCallback onPurge;

  /// Reîmprospătarea listei după ce ecranul de detaliu a schimbat ceva
  /// (ban/ștergere pornite de acolo).
  final Future<void> Function() onChanged;

  const _AdminPlayerRow({
    required this.profile,
    required this.onGrant,
    required this.onBan,
    required this.onPurge,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final changed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => _PlayerDetailScreen(profile: profile)),
        );
        if (changed == true) await onChanged();
      },
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white.withAlpha(12), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white24)),
      child: Row(
        children: [
          Avatar(size: 36, label: profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?', accentColor: pickAvatarColor(profile.avatarSeed), photoUrl: profile.photoUrl, style: avatarStyleFromId(profile.avatarStyle)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(profile.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                Text(
                  profile.hasGoogleAccount ? 'Cont Google · ${profile.leaguePoints} pct' : 'Guest · ${profile.leaguePoints} pct',
                  style: TextStyle(color: profile.hasGoogleAccount ? AppColors.play : Colors.white38, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onGrant,
            icon: const Icon(Icons.card_giftcard_rounded, color: AppColors.teal, size: 20),
            tooltip: 'Trimite resurse',
          ),
          IconButton(onPressed: onBan, icon: const Icon(Icons.block_rounded, color: AppColors.danger, size: 20), tooltip: 'Interzice'),
          IconButton(
            onPressed: onPurge,
            icon: const Icon(Icons.delete_forever_rounded, color: AppColors.danger, size: 21),
            tooltip: 'Șterge complet',
          ),
        ],
      ),
      ),
    );
  }
}

/// Roster complet, cu acțiuni de admin — copiat după `_AllPlayersTab` din
/// leaderboard_screen.dart (același `fetchAllPlayers`), plus grant/ban.
class _PlayersTab extends StatefulWidget {
  const _PlayersTab();

  @override
  State<_PlayersTab> createState() => _PlayersTabState();
}

class _PlayersTabState extends State<_PlayersTab> {
  late Future<List<PlayerProfile>> _future = PlayerProfileService.instance.fetchAllPlayers();

  Future<void> _refresh() async {
    setState(() => _future = PlayerProfileService.instance.fetchAllPlayers());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PlayerProfile>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.orange));
        }
        final players = snap.data!;
        if (players.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.orange,
            child: ListView(
              children: const [
                SizedBox(height: 120),
                Center(child: Text('Niciun jucător înregistrat momentan.', style: TextStyle(color: Colors.white38, fontSize: 13))),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.orange,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            // +1 pentru butonul de anunț global, primul din listă.
            itemCount: players.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) return _buildBroadcastButton(context, players.length);
              final p = players[index - 1];
              return _AdminPlayerRow(
                profile: p,
                onChanged: _refresh,
                onGrant: () => _openGrantSheet(context, p),
                onBan: () async {
                  if (await _confirmBan(context, p)) await _refresh();
                },
                onPurge: () async {
                  if (await _confirmAndPurge(context, p)) await _refresh();
                },
              );
            },
          ),
        );
      },
    );
  }

  /// Anunț către toți — stă în capul listei de jucători fiindcă e o acțiune
  /// asupra listei întregi, nu asupra unui rând anume.
  Widget _buildBroadcastButton(BuildContext context, int playerCount) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: AppColors.bg,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
          builder: (_) => const _MessageSheet(),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.orange.withAlpha(28),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.orange.withAlpha(110)),
          ),
          child: Row(
            children: [
              const Icon(Icons.campaign_rounded, color: AppColors.orange, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Anunț pentru toți',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('Ajunge la cei $playerCount jucători din listă',
                        style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

/// Jucătorii al căror profil a fost creat azi — vezi
/// PlayerProfileService.fetchNewPlayersToday.
class _NewTodayTab extends StatefulWidget {
  const _NewTodayTab();

  @override
  State<_NewTodayTab> createState() => _NewTodayTabState();
}

class _NewTodayTabState extends State<_NewTodayTab> {
  late Future<List<PlayerProfile>> _future = PlayerProfileService.instance.fetchNewPlayersToday();

  Future<void> _refresh() async {
    setState(() => _future = PlayerProfileService.instance.fetchNewPlayersToday());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PlayerProfile>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.orange));
        }
        final players = snap.data!;
        if (players.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.orange,
            child: ListView(
              children: const [
                SizedBox(height: 120),
                Center(child: Text('Niciun jucător nou azi.', style: TextStyle(color: Colors.white38, fontSize: 13))),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.orange,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            itemCount: players.length,
            itemBuilder: (context, i) {
              final p = players[i];
              return _AdminPlayerRow(
                profile: p,
                onChanged: _refresh,
                onGrant: () => _openGrantSheet(context, p),
                onBan: () async {
                  if (await _confirmBan(context, p)) await _refresh();
                },
                onPurge: () async {
                  if (await _confirmAndPurge(context, p)) await _refresh();
                },
              );
            },
          ),
        );
      },
    );
  }
}

/// Raportările trimise de jucători din chat (vezi ModerationService).
///
/// Aici se închide bucla pornită de butonul „Raportează": mesajul reclamat se
/// vede ca text, iar de pe card se poate deschide direct fișa celui reclamat,
/// de unde există deja ban și ștergere completă. Fără pasul ăsta, raportarea
/// ar fi fost un buton care nu duce nicăieri — adică exact ce nu se poate
/// declara la Content rating.
///
/// Cele rezolvate NU se șterg singure: un jucător reclamat de cinci ori,
/// fiecare „rezolvată" la timpul ei, arată altfel decât unul reclamat o dată,
/// și doar istoricul păstrat face diferența vizibilă.
class _ReportsTab extends StatefulWidget {
  const _ReportsTab();

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  late Future<List<PlayerReport>> _future = ModerationService.instance.fetchReports();

  Future<void> _refresh() async {
    setState(() => _future = ModerationService.instance.fetchReports());
    await _future;
  }

  /// Deschide fișa celui reclamat — profilul se citește după uid, nu se
  /// reconstruiește din numele copiat în raportare: numele e doar cum se
  /// chema atunci, uid-ul e cine e.
  Future<void> _openTarget(PlayerReport report) async {
    final profile = await PlayerProfileService.instance.getProfile(report.targetUid);
    if (!mounted) return;
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jucătorul nu mai există (cont șters sau banat).')),
      );
      return;
    }
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _PlayerDetailScreen(profile: profile)),
    );
    if (changed == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PlayerReport>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.orange));
        }
        final reports = snap.data!;
        if (reports.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.orange,
            child: ListView(
              children: const [
                SizedBox(height: 100),
                Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      'Nicio raportare.\n\nAici ajung reclamațiile trimise de jucători din chatul '
                      'camerelor sau din firele private de prieteni.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.orange,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            itemCount: reports.length,
            itemBuilder: (context, i) => _ReportCard(
              report: reports[i],
              onOpenTarget: () => _openTarget(reports[i]),
              onToggleHandled: () async {
                await ModerationService.instance.markReportHandled(reports[i].id, handled: !reports[i].handled);
                await _refresh();
              },
              onDelete: () async {
                await ModerationService.instance.deleteReport(reports[i].id);
                await _refresh();
              },
            ),
          ),
        );
      },
    );
  }
}

class _ReportCard extends StatelessWidget {
  final PlayerReport report;
  final VoidCallback onOpenTarget;
  final VoidCallback onToggleHandled;
  final VoidCallback onDelete;

  const _ReportCard({
    required this.report,
    required this.onOpenTarget,
    required this.onToggleHandled,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final handled = report.handled;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        // Nerezolvatele ies în evidență; cele bifate se retrag vizual, dar
        // rămân în listă ca istoric.
        color: handled ? Colors.white.withAlpha(8) : AppColors.danger.withAlpha(22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: handled ? Colors.white12 : AppColors.danger.withAlpha(110)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(handled ? Icons.check_circle_rounded : Icons.flag_rounded,
                  color: handled ? AppColors.play : AppColors.danger, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  report.reason.label,
                  style: TextStyle(
                    color: handled ? Colors.white54 : Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                _reportTime(report.createdAt),
                style: const TextStyle(color: Colors.white38, fontSize: 10.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: report.reporterName,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const TextSpan(text: '  l-a reclamat pe  ', style: TextStyle(color: Colors.white38, fontSize: 12)),
                TextSpan(
                  text: report.targetName,
                  style: const TextStyle(color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          if (report.messageText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: Colors.black.withAlpha(60), borderRadius: BorderRadius.circular(10)),
              child: Text(
                report.messageText,
                style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.35, fontStyle: FontStyle.italic),
              ),
            ),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onOpenTarget,
                child: const Text('Fișa lui', style: TextStyle(color: AppColors.blue, fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
              TextButton(
                onPressed: onToggleHandled,
                child: Text(handled ? 'Redeschide' : 'Rezolvat',
                    style: const TextStyle(color: AppColors.play, fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 19),
                tooltip: 'Șterge raportarea',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _reportTime(Timestamp? ts) {
  if (ts == null) return '';
  final dt = ts.toDate().toLocal();
  final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  final now = DateTime.now();
  if (dt.year == now.year && dt.month == now.month && dt.day == now.day) return 'azi $time';
  return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} $time';
}

/// Sheet cu 5 câmpuri numerice (delta cu semn) — scrie în `admin_grants/{uid}`
/// cu `increment()`, ca grant-uri succesive netransmise încă să se adune,
/// nu să se suprascrie. Ridicat de telefonul jucătorului la următoarea
/// pornire, vezi CloudSyncService.consumePendingGrant.
class _GrantSheet extends StatefulWidget {
  final PlayerProfile profile;
  const _GrantSheet({required this.profile});

  @override
  State<_GrantSheet> createState() => _GrantSheetState();
}

class _GrantSheetState extends State<_GrantSheet> {
  final _hearts = TextEditingController();
  final _hints = TextEditingController();
  final _coins = TextEditingController();
  final _gems = TextEditingController();
  final _xp = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _hearts.dispose();
    _hints.dispose();
    _coins.dispose();
    _gems.dispose();
    _xp.dispose();
    super.dispose();
  }

  int _parse(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  Future<void> _send() async {
    final hearts = _parse(_hearts);
    final hints = _parse(_hints);
    final coins = _parse(_coins);
    final gems = _parse(_gems);
    final xp = _parse(_xp);
    if (hearts == 0 && hints == 0 && coins == 0 && gems == 0 && xp == 0) {
      Navigator.pop(context);
      return;
    }
    setState(() => _sending = true);
    try {
      await FirebaseFirestore.instance.collection('admin_grants').doc(widget.profile.uid).set({
        if (hearts != 0) 'hearts': FieldValue.increment(hearts),
        if (hints != 0) 'hints': FieldValue.increment(hints),
        if (coins != 0) 'coins': FieldValue.increment(coins),
        if (gems != 0) 'gems': FieldValue.increment(gems),
        if (xp != 0) 'xp': FieldValue.increment(xp),
        // Momentul ultimei trimiteri — din el se face id-ul notificării de
        // „ai primit X" de pe telefonul jucătorului. Fără el, două cadouri
        // identice trimise la zile distanță ar fi arătat ca același cadou și
        // al doilea n-ar mai fi produs nicio notificare (vezi
        // CloudSyncService.consumePendingGrant).
        'sentAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Trimis către ${widget.profile.name} — se aplică la următoarea deschidere a jocului lui.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nu am putut trimite resursele.')));
    }
  }

  Widget _field(TextEditingController c, String label, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(signed: true),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: color, size: 20),
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54),
          hintText: 'ex: 50 sau -20',
          hintStyle: const TextStyle(color: Colors.white24),
          filled: true,
          fillColor: AppColors.card,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Resurse pentru ${widget.profile.name}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Numere negative = luare. Se aplică data viitoare când deschide jocul.', style: TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 16),
          _field(_hearts, 'Inimi', Icons.favorite_rounded, AppColors.life),
          _field(_hints, 'Hint-uri', Icons.tips_and_updates_rounded, AppColors.hint),
          _field(_coins, 'Monede', Icons.monetization_on_rounded, AppColors.coin),
          _field(_gems, 'Gems', Icons.diamond_rounded, const Color(0xFF5EC8F2)),
          _field(_xp, 'XP', Icons.star_rounded, AppColors.purple),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _sending ? null : _send,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.teal, padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Trimite'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Scrierea unui anunț — către un jucător anume ([profile] dat) sau către
/// toți ([profile] null, din tab-ul Jucători).
///
/// Ajunge la jucător la următoarea deschidere a jocului, nu instant: fără
/// Cloud Functions (plan gratuit) nu există notificări push, deci anunțul stă
/// într-o cutie poștală pe care telefonul lui o golește la pornire — vezi
/// NotificationService.pullFromCloud.
class _MessageSheet extends StatefulWidget {
  /// null = anunț pentru toți jucătorii.
  final PlayerProfile? profile;
  const _MessageSheet({this.profile});

  @override
  State<_MessageSheet> createState() => _MessageSheetState();
}

class _MessageSheetState extends State<_MessageSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _sending = false;

  bool get _isBroadcast => widget.profile == null;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty && body.isEmpty) {
      Navigator.pop(context);
      return;
    }
    // Un anunț către toți scrie un document pentru fiecare jucător și nu se
    // poate lua înapoi din aplicație — de-aia se confirmă, spre deosebire de
    // mesajul către o singură persoană.
    if (_isBroadcast) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Trimiți către toți?', style: TextStyle(color: Colors.white)),
          content: const Text(
            'Anunțul ajunge la toți jucătorii activi (max. 300), la următoarea '
            'deschidere a jocului. Nu poate fi retras după trimitere.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Renunță')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Trimite')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _sending = true);
    final String message;
    if (_isBroadcast) {
      final count = await PlayerProfileService.instance.broadcastNotification(title: title, body: body);
      message = count > 0 ? 'Anunț trimis către $count jucători.' : 'Nu am putut trimite anunțul.';
    } else {
      final ok = await PlayerProfileService.instance
          .sendNotification(widget.profile!.uid, title: title, body: body);
      message = ok
          ? 'Mesaj trimis către ${widget.profile!.name} — îl vede la următoarea deschidere a jocului.'
          : 'Nu am putut trimite mesajul.';
    }
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isBroadcast ? 'Anunț pentru toți jucătorii' : 'Mesaj pentru ${widget.profile!.name}',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Apare în clopoțelul de notificări, la următoarea deschidere a jocului.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.title_rounded, color: AppColors.blue, size: 20),
              labelText: 'Titlu',
              labelStyle: const TextStyle(color: Colors.white54),
              hintText: 'ex: Actualizare nouă',
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: AppColors.card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _body,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.sentences,
            maxLines: 4,
            maxLength: 400,
            decoration: InputDecoration(
              labelText: 'Mesaj',
              labelStyle: const TextStyle(color: Colors.white54),
              hintStyle: const TextStyle(color: Colors.white24),
              counterStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: AppColors.card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _sending ? null : _send,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isBroadcast ? AppColors.orange : AppColors.blue,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_isBroadcast ? 'Trimite tuturor' : 'Trimite'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Unelte de debug/test — mutate 1:1 din SettingsScreen (acolo erau vizibile
/// oricui, fără nicio filtrare de cont). TEST verifică doar pozele
/// înlocuite manual (TestImagesScreen.testQuestionIds), fără să afecteze
/// scorul real; UNLIMITED umple resursele la maxim, pentru testare rapidă.
class _DebugTab extends StatefulWidget {
  const _DebugTab();

  @override
  State<_DebugTab> createState() => _DebugTabState();
}

class _DebugTabState extends State<_DebugTab> {
  final _coinPreviewKey = GlobalKey();
  final _xpPreviewKey = GlobalKey();
  final _livesPreviewKey = GlobalKey();
  final _hintsPreviewKey = GlobalKey();
  final _gemsPreviewKey = GlobalKey();

  bool _noBlur = false;
  bool _noBlurLoaded = false;

  @override
  void initState() {
    super.initState();
    StorageService.getNoBlurMode().then((value) {
      if (!mounted) return;
      setState(() {
        _noBlur = value;
        _noBlurLoaded = true;
      });
    });
  }

  Future<void> _toggleNoBlur(bool value) async {
    setState(() => _noBlur = value);
    await StorageService.setNoBlurMode(value);
  }

  /// Rulează, pe rând, aceeași animație de zbor (CoinRewardOverlay) folosită
  /// la colectarea reală de monede/XP/vieți/hints/gems — dar fără să scrie
  /// nimic în storage, doar ca previzualizare vizuală rapidă.
  Future<void> _previewRewardAnimations(BuildContext context) async {
    Future<void> stage({
      required int amount,
      required IconData icon,
      required Color color,
      required GlobalKey targetKey,
    }) async {
      final impactCompleter = Completer<void>();
      CoinRewardOverlay.show(
        context,
        amount: amount,
        targetKey: targetKey,
        icon: icon,
        color: color,
        onImpact: () {
          if (!impactCompleter.isCompleted) impactCompleter.complete();
        },
      );
      await impactCompleter.future;
      await Future.delayed(const Duration(milliseconds: 280));
    }

    await stage(amount: 25, icon: Icons.monetization_on_rounded, color: AppColors.coin, targetKey: _coinPreviewKey);
    if (!context.mounted) return;
    await stage(amount: 40, icon: Icons.star_rounded, color: AppColors.purple, targetKey: _xpPreviewKey);
    if (!context.mounted) return;
    await stage(amount: 4, icon: Icons.favorite_rounded, color: AppColors.life, targetKey: _livesPreviewKey);
    if (!context.mounted) return;
    await stage(amount: 3, icon: Icons.tips_and_updates_rounded, color: AppColors.hint, targetKey: _hintsPreviewKey);
    if (!context.mounted) return;
    await stage(amount: 3, icon: Icons.diamond_rounded, color: const Color(0xFF5EC8F2), targetKey: _gemsPreviewKey);
  }

  Widget _buildPreviewBadge(GlobalKey key, IconData icon, Color color) {
    return Container(
      key: key,
      width: 34,
      height: 34,
      decoration: BoxDecoration(color: color.withAlpha(50), shape: BoxShape.circle, border: Border.all(color: color)),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 17),
    );
  }

  Future<void> _grantUnlimited(BuildContext context) async {
    await StorageService.setLives(999);
    final currentHints = await StorageService.getHints();
    if (currentHints < 999) await StorageService.addHintsUncapped(999 - currentHints);
    await StorageService.addCoins(99999);
    await StorageService.addGems(9999);
    await StorageService.debugUnlockAllQuestsAndAchievements();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('999 vieți, 999 hint-uri, +99999 monede, +9999 gems, toate quest-urile + realizările gata de revendicat (test)'),
          duration: Duration(milliseconds: 2200)),
    );
  }

  /// Butoane de test — la fel de vizibile ca butoanele de meniu (culoare
  /// solidă + iconiță), nu chip-uri mici de colț.
  Widget _buildDevToolButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color, color.withAlpha(210)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: color.withAlpha(100), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildDevToolButton(
                  icon: Icons.image_search_rounded,
                  label: 'TEST',
                  color: AppColors.blue,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TestImagesScreen())),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDevToolButton(
                  icon: Icons.all_inclusive_rounded,
                  label: 'UNLIMITED',
                  color: AppColors.orange,
                  onTap: () => _grantUnlimited(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDevToolButton(
            icon: Icons.lock_open_rounded,
            label: 'PREVIEW ANIMAȚIE DEBLOCARE',
            color: AppColors.purple,
            onTap: () => CategoryUnlockAnimation.show(
              context,
              categoryTitle: 'Categorie de test',
              unlockedCount: 15,
              color: AppColors.teal,
              icon: Icons.public_rounded,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPreviewBadge(_coinPreviewKey, Icons.monetization_on_rounded, AppColors.coin),
              _buildPreviewBadge(_xpPreviewKey, Icons.star_rounded, AppColors.purple),
              _buildPreviewBadge(_livesPreviewKey, Icons.favorite_rounded, AppColors.life),
              _buildPreviewBadge(_hintsPreviewKey, Icons.tips_and_updates_rounded, AppColors.hint),
              _buildPreviewBadge(_gemsPreviewKey, Icons.diamond_rounded, const Color(0xFF5EC8F2)),
            ],
          ),
          const SizedBox(height: 8),
          _buildDevToolButton(
            icon: Icons.auto_awesome_rounded,
            label: 'PREVIEW RECOMPENSE',
            color: AppColors.teal,
            onTap: () => _previewRewardAnimations(context),
          ),
          const SizedBox(height: 16),
          _buildNoBlurCard(),
        ],
      ),
    );
  }

  /// „Fără blur" — mutat aici din SettingsScreen, unde îl vedea orice
  /// jucător. Acolo nu era o setare de accesibilitate, ci un buton care
  /// desființa jocul: pozele apăreau clare din prima, deci nu mai era nimic
  /// de ghicit. Ca unealtă de verificat pozele adăugate manual, în schimb,
  /// e exact ce trebuie — de-aia stă lângă TEST.
  Widget _buildNoBlurCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppColors.purple.withAlpha(40),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.blur_off_rounded, color: AppColors.purple, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fără blur', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                SizedBox(height: 2),
                Text('Pozele apar 100% clare, din prima — pentru verificarea lor',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _noBlurLoaded
              ? CupertinoSwitch(
                  value: _noBlur,
                  activeTrackColor: AppColors.play,
                  onChanged: _toggleNoBlur,
                )
              : const SizedBox(width: 51, height: 31),
        ],
      ),
    );
  }
}

/// Datele agregate ale tabului Statistici — jucătorii (primii 300, pentru
/// total/Google-vs-Guest) și numărul REAL de meciuri încheiate (agregare
/// server-side, fără plafon — vezi PlayerProfileService.fetchCompletedMatchesCount).
class _StatsData {
  final List<PlayerProfile> players;
  final int completedMatches;

  /// Conturile care asteapta stergerea din Authentication — pe nume, nu doar
  /// numarate, ca sa se vada cine e in coada inainte de a rula scriptul.
  final List<PendingAuthDeletion> pendingAuthDeletions;
  const _StatsData({
    required this.players,
    required this.completedMatches,
    required this.pendingAuthDeletions,
  });
}

class _StatsTab extends StatefulWidget {
  const _StatsTab();

  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  late Future<_StatsData> _future = _load();

  Future<_StatsData> _load() async {
    final results = await Future.wait([
      PlayerProfileService.instance.fetchAllPlayers(),
      PlayerProfileService.instance.fetchCompletedMatchesCount(),
      PlayerProfileService.instance.fetchPendingAuthDeletions(),
    ]);
    return _StatsData(
      players: results[0] as List<PlayerProfile>,
      completedMatches: results[1] as int,
      pendingAuthDeletions: results[2] as List<PendingAuthDeletion>,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StatsData>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.orange));
        }
        final players = snap.data!.players;
        final total = players.length;
        final google = players.where((p) => p.hasGoogleAccount).length;
        return RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.orange,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            children: [
              _StatCard(icon: Icons.groups_rounded, label: 'Total jucători', value: '$total', color: AppColors.orange),
              const SizedBox(height: 12),
              _StatCard(icon: Icons.verified_user_rounded, label: 'Google / Guest', value: '$google / ${total - google}', color: AppColors.play),
              const SizedBox(height: 12),
              _StatCard(
                icon: Icons.sports_esports_rounded,
                label: 'Meciuri multiplayer jucate',
                value: '${snap.data!.completedMatches}',
                color: AppColors.blue,
              ),
              // Conturile sterse din joc care mai asteapta stergerea din
              // Firebase Authentication — pasul care cere cheia de service
              // account, deci scriptul de pe calculator (vezi
              // PendingAuthDeletion pentru de ce). Apar pe nume, nu doar
              // numarate: coada se goleste cu o stergere DEFINITIVA, iar
              // inainte de asa ceva trebuie sa se vada exact cine e in ea.
              // Sectiunea intreaga lipseste cand nu e nimic de facut.
              if (snap.data!.pendingAuthDeletions.isNotEmpty) ...[
                const SizedBox(height: 22),
                _SectionTitle('De șters din Auth (${snap.data!.pendingAuthDeletions.length})'),
                ...snap.data!.pendingAuthDeletions.map(
                  (p) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withAlpha(20),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.danger.withAlpha(70)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.delete_sweep_rounded, color: AppColors.danger, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(p.name,
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                                  overflow: TextOverflow.ellipsis),
                              Text(
                                p.uid,
                                style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          p.requestedAt == null ? '—' : _relative(p.requestedAt!.toDate()),
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
                const _InfoCard(
                  icon: Icons.desktop_windows_rounded,
                  text: 'Datele lor din joc sunt deja șterse; a rămas doar identitatea din '
                      'Firebase Authentication, inertă. Se curăță de pe calculator, cu '
                      '"Curata conturi Auth.bat" — ștergerea cere o cheie de administrator, '
                      'care n-are ce căuta în aplicație.',
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Meciuri: total real, încheiate normal, cu minim 2 jucători. Total jucători/Google-Guest: calculate din primii 300, ordonați după puncte de ligă.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }
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

/// Fișa completă a unui jucător, deschisă cu tap pe rândul din tab-urile
/// Jucători / Noi azi.
///
/// ORDINEA E INTENȚIONATĂ: primul lucru afișat, înaintea oricărei statistici,
/// e **id-ul unic**. Numele se poate schimba și se poate repeta între
/// jucători; uid-ul nu. Tot ce operează sistemul — grant-urile de resurse
/// (`admin_grants/{uid}`), banarea, ștergerea, legăturile de prietenie,
/// cloud-save-ul — se leagă de uid, niciodată de nickname. Butonul de copiere
/// e acolo tocmai ca id-ul să poată fi lipit într-o discuție de suport sau
/// într-un script, fără să fie transcris de mână.
///
/// Întoarce `true` prin Navigator.pop dacă a schimbat ceva (ban/ștergere), ca
/// lista din spate să se reîmprospăteze.
class _PlayerDetailScreen extends StatefulWidget {
  final PlayerProfile profile;
  const _PlayerDetailScreen({required this.profile});

  @override
  State<_PlayerDetailScreen> createState() => _PlayerDetailScreenState();
}

class _PlayerDetailScreenState extends State<_PlayerDetailScreen> {
  late Future<_PlayerDetail> _future = _load();
  bool _changed = false;

  /// Numele nou, cât timp titlul de sus încă îl arată pe cel primit de la
  /// listă ([widget.profile] nu se poate schimba, e final).
  String? _renamedTo;

  /// Profilul recitit de pe server (vezi [_load]) — din el se știe dacă
  /// jucătorul are un nume impus de admin, ceea ce rândul primit de la listă
  /// n-avea de unde să spună.
  PlayerProfile? _fresh;

  /// Profilul se recitește, nu se folosește cel primit de la listă: după un
  /// reset (sau după orice a mai făcut jucătorul între timp) cifrele din
  /// rândul pe care s-a dat tap sunt deja vechi. Dacă recitirea eșuează,
  /// rămâne cel vechi — mai bine cifre învechite decât un ecran gol.
  Future<_PlayerDetail> _load() async {
    final results = await Future.wait([
      PlayerProfileService.instance.fetchFriendsOf(widget.profile.uid),
      PlayerProfileService.instance.fetchCloudSaveAsAdmin(widget.profile.uid),
      PlayerProfileService.instance.getProfile(widget.profile.uid),
    ]);
    final fresh = results[2] as PlayerProfile? ?? widget.profile;
    _fresh = fresh;
    return _PlayerDetail(
      friends: results[0] as List<PlayerProfile>,
      cloudSave: results[1] as Map<String, dynamic>?,
      profile: fresh,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  /// Cererea pleacă de pe contul cu care e logat adminul — nu e o „cerere de
  /// sistem", ci una obișnuită, de la un jucător anume. Rezultatul se spune
  /// pe față, inclusiv cazul în care cererea s-a transformat în prietenie pe
  /// loc (pentru că exista deja una în sens invers).
  Future<void> _sendFriendRequest(BuildContext context, PlayerProfile p) async {
    final outcome = await PlayerProfileService.instance.sendFriendRequestToUid(p.uid);
    if (!context.mounted) return;
    final (text, color) = switch (outcome) {
      FriendRequestOutcome.sent => ('Cerere trimisă către ${p.name}. Îi apare în clopoțel.', AppColors.play),
      FriendRequestOutcome.autoAccepted => ('${p.name} îți trimisese deja cerere — sunteți prieteni acum.', AppColors.play),
      FriendRequestOutcome.alreadyFriends => ('Sunteți deja prieteni.', AppColors.blue),
      FriendRequestOutcome.isSelf => ('Ăsta e chiar contul tău.', AppColors.orange),
      FriendRequestOutcome.notFound => ('Nu am putut trimite cererea.', AppColors.danger),
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        content: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  /// Redenumirea jucătorului. Singura acțiune din fișa asta care schimbă ceva
  /// ce vede TOATĂ lumea imediat (clasament, prieteni, camere), de-aia scrie
  /// pe față și cât durează până ajunge pe telefonul lui: numele public se
  /// schimbă pe loc, dar propriul lui joc îl adoptă abia la următoarea
  /// deschidere a aplicației (vezi PlayerProfileService.renamePlayerAsAdmin).
  Future<void> _editName(PlayerProfile p) async {
    // profilul proaspăt, dacă a apucat să se încarce: el știe dacă numele e
    // deja unul impus, deci dacă are rost butonul de deblocare
    final target = _fresh ?? p;
    final controller = TextEditingController(text: _renamedTo ?? target.name);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Schimbă numele', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              maxLength: 16,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(counterStyle: TextStyle(color: Colors.white54)),
            ),
            const SizedBox(height: 6),
            // Redenumirea NU mai blochează nimic: oricine își poate schimba
            // singur numele din Profil/Multiplayer. Textul spune doar ce se
            // întâmplă acum și că jucătorul poate reveni oricând.
            Text(
              target.forcedName.isEmpty
                  ? 'Numele public se schimbă imediat. În jocul lui apare la următoarea '
                      'deschidere a aplicației. Poate reveni oricând singur la un nume ales de el.'
                  : 'Numele lui e acum pus de tine. Poate reveni oricând singur la unul ales de '
                      'el, din Profil. „Anulează redenumirea" îi șterge numele impus fără să mai aștepți.',
              style: const TextStyle(color: Colors.white54, fontSize: 11.5, height: 1.3),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Anulează')),
          // Singura cale de a anula o redenumire fără să știi numele original
          // al jucătorului. Numele impus rămâne public până la primul
          // heartbeat al telefonului lui, care îl înlocuiește cu al lui.
          if (target.forcedName.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, _unlockSentinel),
              child: const Text('Anulează redenumirea', style: TextStyle(color: AppColors.orange)),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Salvează'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;

    final unlock = result == _unlockSentinel;
    final ok = unlock
        ? await PlayerProfileService.instance.clearForcedNameAsAdmin(target.uid)
        : await PlayerProfileService.instance.renamePlayerAsAdmin(target.uid, result);
    if (!mounted) return;
    if (ok) {
      _changed = true;
      setState(() {
        if (!unlock) _renamedTo = result;
        _future = _load();
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: ok ? AppColors.play : AppColors.danger,
        content: Text(
          ok
              ? (unlock
                  ? 'Își poate alege din nou numele. Îi revine al lui când redeschide jocul.'
                  : 'Redenumit în „$result".')
              : 'Nu am putut schimba numele.',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  /// Răspunsul butonului „Anulează redenumirea", ca dialogul să întoarcă tot un
  /// String. Nu se poate confunda cu un nume tastat: butonul „Salvează"
  /// întoarce mereu textul cu `trim()`, deci nimic din câmp nu poate ieși cu
  /// spații la capete.
  static const _unlockSentinel = ' ::unlock:: ';

  void _copyUid() {
    Clipboard.setData(ClipboardData(text: widget.profile.uid));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ID copiat.'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context, _changed),
                      icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                    ),
                    const SizedBox(width: 4),
                    // Numele + creionul: tot rândul e apăsabil, nu doar
                    // iconița — o țintă de 20px lățime, lipită de un text
                    // lung, se ratează des pe telefon.
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _editName(p),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                _renamedTo ?? p.name,
                                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.edit_rounded, color: AppColors.orange, size: 19),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<_PlayerDetail>(
                  future: _future,
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator(color: AppColors.orange));
                    }
                    return RefreshIndicator(
                      onRefresh: _refresh,
                      color: AppColors.orange,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                        children: _body(snap.data!.profile, snap.data!),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(PlayerProfile p, _PlayerDetail d) {
    final save = d.cloudSave;
    final xp = (save?['xp'] as num?)?.toInt() ?? 0;
    return [
      // ── ID-ul unic, primul lucru pe ecran ──
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.teal.withAlpha(90)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Avatar(
                  size: 44,
                  label: p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                  accentColor: pickAvatarColor(p.avatarSeed),
                  photoUrl: p.photoUrl,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(p.name,
                          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                          overflow: TextOverflow.ellipsis),
                      Text(
                        p.hasGoogleAccount ? 'Cont Google' : 'Guest',
                        style: TextStyle(
                          color: p.hasGoogleAccount ? AppColors.play : Colors.white38,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('ID UNIC',
                style: TextStyle(color: AppColors.teal, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    p.uid,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace', height: 1.35),
                  ),
                ),
                IconButton(
                  onPressed: _copyUid,
                  icon: const Icon(Icons.copy_rounded, color: AppColors.teal, size: 20),
                  tooltip: 'Copiază ID-ul',
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              'Resursele, banarea și ștergerea se leagă de acest ID, nu de nume. '
              'Numele se poate schimba și se poate repeta; ID-ul nu.',
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),

      // ── Balanța ──
      const _SectionTitle('Balanță'),
      if (save == null)
        const _InfoCard(
          icon: Icons.lock_outline_rounded,
          text: 'Nu a urcat încă nimic în cloud. Prima sincronizare se face '
              'când trimite aplicația în fundal — până atunci nu există '
              'balanță de arătat aici, indiferent de felul contului.',
        )
      else ...[
        // ATENȚIE la valorile implicite: `exportAll` urcă doar cheile chiar
        // scrise în SharedPreferences, deci la un cont nou `coins`/`gems`/
        // `lives`/`hints` LIPSESC din cloud-save până când jucătorul câștigă
        // sau cheltuie ceva. Lipsa înseamnă "încă la valoarea de start", nu
        // zero — cu `?? 0` fișa arăta 0 monede unui jucător care avea 173.
        Row(
          children: [
            Expanded(
                child: _BalanceTile(
                    label: 'Monede',
                    value: (save['coins'] as num?)?.toInt() ?? StorageService.startingCoinsDefault,
                    color: AppColors.coin,
                    icon: Icons.monetization_on_rounded)),
            const SizedBox(width: 10),
            Expanded(
                child: _BalanceTile(
                    label: 'Gems',
                    value: (save['gems'] as num?)?.toInt() ?? starterGemGrant,
                    color: AppColors.gem,
                    icon: Icons.diamond_rounded)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: _BalanceTile(
                    label: 'Inimi',
                    value: (save['lives'] as num?)?.toInt() ?? StorageService.startingLivesDefault,
                    color: AppColors.life,
                    icon: Icons.favorite_rounded)),
            const SizedBox(width: 10),
            Expanded(
                child: _BalanceTile(
                    label: 'Hints',
                    value: (save['hints_balance'] as num?)?.toInt() ?? StorageService.startingHintsDefault,
                    color: AppColors.hint,
                    icon: Icons.lightbulb_rounded)),
          ],
        ),
        const SizedBox(height: 10),
        // XP-ul brut e o cifră lungă și fără înțeles la prima vedere; nivelul
        // e ce înseamnă ea de fapt (vezi core/progression.dart).
        _DetailRow(label: 'Nivel', value: '${levelForXp(xp)}', highlight: true),
        _DetailRow(label: 'XP total', value: _grouped(xp)),
        const SizedBox(height: 8),
        const _InfoCard(
          icon: Icons.cloud_sync_rounded,
          text: 'Cifrele vin din ultima sincronizare cu cloud-ul, care se face '
              'când jucătorul trimite aplicația în fundal. Pot fi în urma față '
              'de ce are pe telefon chiar acum.',
        ),
      ],
      const SizedBox(height: 22),

      // ── Prietenii ──
      _SectionTitle('Prieteni (${d.friends.length})'),
      if (d.friends.isEmpty)
        const _InfoCard(icon: Icons.person_off_rounded, text: 'No friends — nu are nicio legătură de prietenie.')
      else
        ...d.friends.map((f) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  Avatar(
                    size: 30,
                    label: f.name.isNotEmpty ? f.name[0].toUpperCase() : '?',
                    accentColor: pickAvatarColor(f.avatarSeed),
                    photoUrl: f.photoUrl,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(f.name,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text('${f.leaguePoints} pct', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            )),
      const SizedBox(height: 22),

      // ── Restul datelor esențiale ──
      const _SectionTitle('Detalii'),
      _DetailRow(label: 'Cod de prieten', value: p.friendCode ?? 'încă negenerat', mono: p.friendCode != null),
      _DetailRow(label: 'Ultima activitate', value: p.lastActive == null ? '—' : _relative(p.lastActive!.toDate())),
      _DetailRow(label: 'Cont creat', value: p.createdAt == null ? '—' : _shortDate(p.createdAt!.toDate())),
      _DetailRow(label: 'Puncte de ligă', value: _grouped(p.leaguePoints)),
      _DetailRow(label: 'Meciuri', value: '${p.matchesPlayed}  (${p.wins}V / ${p.losses}Î)'),
      _DetailRow(
        label: 'Winrate',
        value: p.matchesPlayed == 0 ? '—' : '${(p.winrate * 100).toStringAsFixed(0)}%',
      ),
      _DetailRow(label: 'Serie curentă', value: '${p.currentStreak}  (record ${p.longestStreak})'),
      // Cifra care decide soarta unui cont Guest lăsat în pace: roți învârtite
      // + mișcări de balanță, urcate de telefonul lui la fiecare pornire.
      _DetailRow(label: 'Semne de activitate', value: _grouped(p.activityEvents)),
      _DetailRow(label: 'Se șterge automat?', value: _autoDeleteLabel(p)),
      const SizedBox(height: 26),

      // ── Acțiuni ──
      const _SectionTitle('Acțiuni'),
      _ActionButton(
        label: 'Trimite resurse',
        icon: Icons.card_giftcard_rounded,
        color: AppColors.teal,
        onPressed: () => _openGrantSheet(context, p),
      ),
      const SizedBox(height: 10),
      // Notificarea de „ai primit X" se scrie singură când resursele ajung la
      // el (vezi CloudSyncService); asta e pentru un mesaj scris de mână.
      _ActionButton(
        label: 'Trimite mesaj',
        icon: Icons.campaign_rounded,
        color: AppColors.blue,
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: AppColors.bg,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
          builder: (_) => _MessageSheet(profile: p),
        ),
      ),
      const SizedBox(height: 10),
      // Cererea pleacă pe UID, nu pe codul de prieten: un jucător care n-a
      // deschis niciodată ecranul de Prieteni n-are încă un cod generat, și
      // tocmai pe ăia vrei să-i poți contacta din panou. Îi apare în
      // clopoțel ca orice altă cerere (NotificationService.fetchLive).
      _ActionButton(
        label: 'Trimite cerere de prietenie',
        icon: Icons.person_add_rounded,
        color: AppColors.purple,
        onPressed: () => _sendFriendRequest(context, p),
      ),
      const SizedBox(height: 10),
      // Resetul stă lângă ban/ștergere fiindcă e tot ireversibil, dar nu e
      // distructiv la fel: contul rămâne, doar o ia de la capăt — de-aia e
      // portocaliu, nu roșu.
      _ActionButton(
        label: 'Resetează contul',
        icon: Icons.restart_alt_rounded,
        color: AppColors.orange,
        onPressed: () async {
          if (await _confirmReset(context, p)) {
            _changed = true;
            await _refresh();
          }
        },
      ),
      const SizedBox(height: 10),
      _ActionButton(
        label: 'Interzice contul',
        icon: Icons.block_rounded,
        color: AppColors.danger,
        onPressed: () async {
          if (await _confirmBan(context, p)) {
            _changed = true;
            if (mounted) Navigator.pop(context, true);
          }
        },
      ),
      const SizedBox(height: 10),
      _ActionButton(
        label: 'Șterge complet',
        icon: Icons.delete_forever_rounded,
        color: AppColors.danger,
        onPressed: () async {
          if (await _confirmAndPurge(context, p)) {
            _changed = true;
            if (mounted) Navigator.pop(context, true);
          }
        },
      ),
    ];
  }
}

class _PlayerDetail {
  final List<PlayerProfile> friends;

  /// null = încă n-a urcat nimic în cloud (vezi
  /// PlayerProfileService.fetchCloudSaveAsAdmin) — nu mai înseamnă "Guest".
  final Map<String, dynamic>? cloudSave;

  /// Profilul public recitit acum, nu cel din listă — vezi [_load].
  final PlayerProfile profile;
  const _PlayerDetail({required this.friends, required this.cloudSave, required this.profile});
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

/// Numele lizibil al unui mod de joc, din `gameModeId`-ul salvat.
String _modeLabel(String id) {
  switch (id) {
    case 'classic':
      return 'Clasic';
    case 'higherLower':
      return 'Higher or Lower';
    default:
      return id;
  }
}

/// "se șterge în 7 min" — cât mai are camera până dispare singură.
String _expiryLabel(RoomActivity r) {
  final left = r.timeLeft;
  if (left == null) return 'se șterge acum';
  if (left.inMinutes < 1) return 'se șterge în ${left.inSeconds}s';
  return 'se șterge în ${left.inMinutes + 1} min';
}

/// Camerele terminate în ultimele [roomActivityRetention] — vezi
/// MultiplayerActivityService pentru de ce dispar singure și cum.
///
/// La fiecare încărcare se mătură întâi camerele expirate rămase de la
/// jucători care n-au mai deschis aplicația (clienții și le șterg singuri pe
/// ale lor, dar numai când mai pornesc jocul).
class _RoomsTab extends StatefulWidget {
  const _RoomsTab();

  @override
  State<_RoomsTab> createState() => _RoomsTabState();
}

class _RoomsTabState extends State<_RoomsTab> {
  late Future<List<RoomActivity>> _future = _load();

  Future<List<RoomActivity>> _load() async {
    await MultiplayerActivityService.instance.sweepExpiredAsAdmin();
    return MultiplayerActivityService.instance.fetchRooms();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RoomActivity>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.orange));
        }
        final rooms = snap.data!;
        if (rooms.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.orange,
            child: ListView(
              children: const [
                SizedBox(height: 100),
                Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      'Nicio cameră activă.\n\nAici apar meciurile multiplayer terminate, '
                      'cu ce a pus și ce a luat fiecare jucător. Fiecare cameră se șterge '
                      'singură la 10 minute după terminarea meciului.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.orange,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            itemCount: rooms.length,
            itemBuilder: (context, i) => _RoomCard(
              room: rooms[i],
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => _RoomDetailScreen(room: rooms[i])),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RoomCard extends StatelessWidget {
  final RoomActivity room;
  final VoidCallback onTap;
  const _RoomCard({required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.purple.withAlpha(40),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.meeting_room_rounded, color: AppColors.purple, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Cameră de ${room.playerCount} jucători',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_modeLabel(room.gameModeId)} · pot ${_grouped(room.pool)}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _expiryLabel(room),
                    style: const TextStyle(color: AppColors.orange, fontSize: 10.5, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

/// Tabloul complet al unei camere: id-ul camerei sus, apoi fiecare jucător cu
/// id-ul lui unic și cu cât a intrat / cu cât a ieșit.
class _RoomDetailScreen extends StatelessWidget {
  final RoomActivity room;
  const _RoomDetailScreen({required this.room});

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
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Cameră de ${room.playerCount} jucători',
                    style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.purple.withAlpha(90)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ID CAMERĂ',
                            style: TextStyle(
                                color: AppColors.purple,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                room.roomId,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13, fontFamily: 'monospace', height: 1.35),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: room.roomId));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('ID cameră copiat.'), duration: Duration(seconds: 2)),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, color: AppColors.purple, size: 20),
                              tooltip: 'Copiază ID-ul camerei',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _SectionTitle('Meciul'),
                  _DetailRow(label: 'Mod de joc', value: _modeLabel(room.gameModeId)),
                  _DetailRow(
                      label: 'Terminat',
                      value: room.finishedAt == null ? '—' : _shortDate(room.finishedAt!.toDate())),
                  _DetailRow(label: 'Se șterge', value: _expiryLabel(room)),
                  _DetailRow(label: 'Pot total', value: _grouped(room.pool)),
                  _DetailRow(label: 'Miza camerei', value: _grouped(room.stake)),
                  const SizedBox(height: 22),
                  _SectionTitle('Jucători (${room.playerCount})'),
                  ...room.players.map((p) => _RoomPlayerCard(player: p)),
                  const SizedBox(height: 16),
                  const _InfoCard(
                    icon: Icons.info_outline_rounded,
                    text: 'Intrat = taxa fixă de intrare plus miza pusă. Ieșit = câștigul din pot '
                        'plus surplusul returnat de plafonul mesei. Diferența dintre ele e '
                        'câștigul sau pierderea reală.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomPlayerCard extends StatelessWidget {
  final RoomActivityPlayer player;
  const _RoomPlayerCard({required this.player});

  @override
  Widget build(BuildContext context) {
    final net = player.net;
    final netColor = net > 0 ? AppColors.play : (net < 0 ? AppColors.danger : Colors.white54);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: player.place == 1 ? AppColors.coin.withAlpha(50) : Colors.white12,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${player.place}',
                  style: TextStyle(
                    color: player.place == 1 ? AppColors.coin : Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(player.name,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
              ),
              Text('${player.score} p', style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          // Id-ul jucătorului, la fel de vizibil ca numele — el e cheia prin
          // care se leagă rândul ăsta de restul bazei de date.
          SelectableText(
            player.uid,
            style: const TextStyle(color: Colors.white38, fontSize: 10.5, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Intrat cu', style: TextStyle(color: Colors.white38, fontSize: 10.5)),
                    Text('−${_grouped(player.entry)}',
                        style: const TextStyle(color: AppColors.danger, fontSize: 14, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ieșit cu', style: TextStyle(color: Colors.white38, fontSize: 10.5)),
                    Text('+${_grouped(player.exit)}',
                        style: const TextStyle(color: AppColors.play, fontSize: 14, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Net', style: TextStyle(color: Colors.white38, fontSize: 10.5)),
                    Text('${net >= 0 ? '+' : ''}${_grouped(net)}',
                        style: TextStyle(color: netColor, fontSize: 14, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
