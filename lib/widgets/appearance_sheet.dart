import 'package:flutter/material.dart';

import '../core/cosmetics.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import 'avatar.dart';

/// Alegerea aspectului: avatar, ramă, titlu. Deschis prin apăsare pe avatar în
/// Profil. Salvare pe loc la tap, fără buton de confirmare — la fel ca vechea
/// alegere de avatar. Itemele blocate apar gri, cu textul cerinței.
Future<void> showAppearanceSheet(
  BuildContext context, {
  required int level,
  required int leaguePoints,
  required Set<String> achievements,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1a1a2e),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _AppearanceSheet(
      level: level,
      leaguePoints: leaguePoints,
      achievements: achievements,
    ),
  );
}

class _AppearanceSheet extends StatefulWidget {
  final int level;
  final int leaguePoints;
  final Set<String> achievements;
  const _AppearanceSheet({
    required this.level,
    required this.leaguePoints,
    required this.achievements,
  });

  @override
  State<_AppearanceSheet> createState() => _AppearanceSheetState();
}

class _AppearanceSheetState extends State<_AppearanceSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(
              controller: _tabs,
              indicatorColor: AppColors.play,
              tabs: [
                Tab(text: tr('Avatar', 'Avatar')),
                Tab(text: tr('Ramă', 'Frame')),
                Tab(text: tr('Titlu', 'Title')),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 320,
              child: TabBarView(
                controller: _tabs,
                children: [
                  const _AvatarGrid(),
                  _FrameGrid(
                      level: widget.level, leaguePoints: widget.leaguePoints),
                  _TitleGrid(
                      level: widget.level, achievements: widget.achievements),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarGrid extends StatelessWidget {
  const _AvatarGrid();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AvatarStyle>(
      valueListenable: myAvatarStyle,
      builder: (_, current, __) => SingleChildScrollView(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final style in AvatarStyle.values)
              GestureDetector(
                onTap: () => setMyAvatarStyle(style),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: style == current
                              ? AppColors.play
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: style == AvatarStyle.poza
                          ? const MyPhotoPreview(size: 58)
                          : AvatarArt(style: style, size: 58),
                    ),
                    const SizedBox(height: 4),
                    Text(style.label,
                        style: TextStyle(
                            color: style == current
                                ? Colors.white
                                : Colors.white54,
                            fontSize: 11)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FrameGrid extends StatelessWidget {
  final int level;
  final int leaguePoints;
  const _FrameGrid({required this.level, required this.leaguePoints});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Frame>(
      valueListenable: myFrame,
      builder: (_, current, __) => SingleChildScrollView(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 16,
          children: [
            for (final f in Frame.values)
              _CosmeticCell(
                selected: f == current,
                owned: ownsFrame(f, level: level, leaguePoints: leaguePoints),
                requirement: frameRequirement(f),
                onTap: () => setMyFrame(f),
                preview: Avatar(size: 58, label: '★', frame: f),
                label: f == Frame.none ? tr('Fără', 'None') : '',
              ),
          ],
        ),
      ),
    );
  }
}

class _TitleGrid extends StatelessWidget {
  final int level;
  final Set<String> achievements;
  const _TitleGrid({required this.level, required this.achievements});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayerTitle>(
      valueListenable: myTitle,
      builder: (_, current, __) => SingleChildScrollView(
        child: Column(
          children: [
            for (final t in PlayerTitle.values)
              _CosmeticCell(
                selected: t == current,
                owned:
                    ownsTitle(t, level: level, achievements: achievements),
                requirement: titleRequirement(t),
                onTap: () => setMyTitle(t),
                preview: const SizedBox.shrink(),
                label: tr(titleLabel(t).$1, titleLabel(t).$2),
              ),
          ],
        ),
      ),
    );
  }
}

/// Un item din grilă: preview + etichetă. Blocat = gri + textul cerinței,
/// tap-ul nu face nimic.
class _CosmeticCell extends StatelessWidget {
  final bool selected;
  final bool owned;
  final String requirement;
  final VoidCallback onTap;
  final Widget preview;
  final String label;

  const _CosmeticCell({
    required this.selected,
    required this.owned,
    required this.requirement,
    required this.onTap,
    required this.preview,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: owned ? onTap : null,
      child: Opacity(
        opacity: owned ? 1 : 0.35,
        child: Container(
          width: 96,
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.play : Colors.white12,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              preview,
              if (label.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 11)),
                ),
              if (!owned && requirement.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(requirement,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 9)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
