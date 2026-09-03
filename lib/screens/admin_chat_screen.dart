import 'package:flutter/material.dart';

import '../core/chat_filter.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/admin_chat_service.dart';
import '../models/admin_message.dart';

/// Firul de mesaje dintre un jucător și administrator.
///
/// UN SINGUR ecran pentru ambele capete, comutat de [asAdmin]: jucătorul îl
/// deschide din Setări („Mesaj către admin"), adminul din tab-ul Mesaje al
/// panoului de Admin. Conținutul e identic, doar cine e „eu" diferă — două
/// ecrane ar fi însemnat două liste de mesaje de ținut în sincron.
///
/// Nu are buton de raportare/blocare precum firul de prieteni: n-are sens să
/// raportezi adminul la admin, iar adminul are deja uneltele lui în panou.
class AdminChatScreen extends StatefulWidget {
  /// Al cui e firul. Pentru jucător e propriul uid; pentru admin, al
  /// jucătorului cu care vorbește.
  final String playerUid;

  /// Ce scrie în capul ecranului — „Administrator" la jucător, numele
  /// jucătorului la admin.
  final String title;

  /// În ce calitate scriu. Decide și ce jumătate de bulină se marchează
  /// citită, și cum se aliniază baloanele.
  final bool asAdmin;

  const AdminChatScreen({
    super.key,
    required this.playerUid,
    required this.title,
    required this.asAdmin,
  });

  @override
  State<AdminChatScreen> createState() => _AdminChatScreenState();
}

class _AdminChatScreenState extends State<AdminChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Marcat citit la deschidere; mesajele sosite cât ecranul e deschis se
    // marchează din stream (vezi [_buildMessages]) — ca la firul de prieteni,
    // altfel bulina ar reapărea pentru ce tocmai am citit cu ochii mei.
    AdminChatService.instance.markRead(widget.playerUid, asAdmin: widget.asAdmin);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final raw = _controller.text;
    if (sanitizeChatMessage(raw).isEmpty) return;
    setState(() => _sending = true);
    _controller.clear();
    if (containsProfanity(raw) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('Mesajul a fost trimis cu cuvintele nepotrivite acoperite.',
              'The message was sent with inappropriate words masked.')),
        ),
      );
    }
    final ok = await AdminChatService.instance
        .sendMessage(widget.playerUid, raw, asAdmin: widget.asAdmin);
    if (!mounted) return;
    setState(() => _sending = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('Mesajul nu a putut fi trimis.', 'The message could not be sent.')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildMessages()),
              _buildInput(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.orange.withAlpha(45),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.orange.withAlpha(140)),
            ),
            child: Icon(
              widget.asAdmin ? Icons.person_rounded : Icons.shield_moon_rounded,
              color: AppColors.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    return StreamBuilder<List<AdminMessage>>(
      stream: AdminChatService.instance.watchMessages(widget.playerUid),
      builder: (context, snap) {
        // Eroarea se trateaza EXPLICIT, nu se lasa pe seama lui `data == null`:
        // un stream Firestore respins (reguli nedeployate, offline, cont fara
        // drepturi) nu emite niciodata nimic, iar un `null` tratat doar ca
        // „se incarca" tine utilizatorul intr-un spinner infinit, fara sa afle
        // vreodata ca nu merge. Prins exact asa la proba pe web.
        if (snap.hasError) return _buildError();
        final messages = snap.data;
        if (messages == null) {
          return const Center(child: CircularProgressIndicator(color: AppColors.orange));
        }
        if (messages.isEmpty) return _buildEmpty();
        // Mesajul sosit cât ecranul e deschis e deja văzut.
        if (messages.last.fromAdmin != widget.asAdmin) {
          AdminChatService.instance.markRead(widget.playerUid, asAdmin: widget.asAdmin);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: messages.length,
          itemBuilder: (context, i) => _bubble(messages[i]),
        );
      },
    );
  }

  /// Firul nu s-a putut citi. Mesajul e deliberat lipsit de jargon: pentru
  /// jucător e o problemă de conexiune, nu una de reguli Firestore.
  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 34),
            const SizedBox(height: 12),
            Text(
              tr('Firul nu s-a putut încărca.\nVerifică conexiunea și încearcă din nou.',
                  'The thread could not be loaded.\nCheck your connection and try again.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  /// Ecranul gol e locul unde jucătorul află LA CE folosește firul — altfel
  /// „Mesaj către admin" e doar un câmp de text fără context, iar feedback-ul
  /// primit ar fi pe măsură.
  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.asAdmin ? Icons.forum_rounded : Icons.shield_moon_rounded,
                color: AppColors.orange.withAlpha(120), size: 38),
            const SizedBox(height: 14),
            Text(
              widget.asAdmin
                  ? 'Niciun mesaj în firul ăsta.\nScrie-i tu primul.'
                  : tr(
                      'Scrie-mi direct: un bug, o poză greșită, o idee de mod nou '
                      'sau orice ți se pare aiurea în joc.\n\nCitesc tot și îți răspund aici.',
                      'Write to me directly: a bug, a wrong picture, an idea for a new '
                      'mode, or anything that feels off.\n\nI read everything and reply here.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(AdminMessage m) {
    // „Al meu" = scris de partea în care mă aflu acum. NU se compară
    // `senderId` cu uid-ul meu: adminul deschide fire în care uid-ul lui nu
    // apare încă deloc (jucătorul a scris primul).
    final mine = m.fromAdmin == widget.asAdmin;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: mine ? AppColors.orange.withAlpha(190) : Colors.white.withAlpha(20),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(m.text, style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.3)),
      ),
    );
  }

  Widget _buildInput() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              maxLength: chatMessageMaxLength,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                counterText: '',
                hintText: tr('Mesaj...', 'Message...'),
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withAlpha(15),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          IconButton(
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send_rounded, color: AppColors.orange),
          ),
        ],
      ),
    );
  }
}
