import 'package:flutter/material.dart';

import '../core/theme.dart';

/// First-run intro — four cards walking through the
/// PLAN → PREPARE → HIKE → LEARN flow. Shown once per install;
/// the flag lives in the settings box via AppState.onboardingSeen.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _ctrl = PageController();
  int _page = 0;

  static const _pages = [
    (
      icon: Icons.map_outlined,
      title: 'Planlegg ruten',
      text:
          'Legg rute direkte på kartet, søk etter steder i Norge, '
          'eller importer en GPX-fil. Du får distanse, stigning, '
          'etapper og tidsestimat – og appen skiller ærlig mellom '
          'stier og estimerte strekk.',
    ),
    (
      icon: Icons.backpack_outlined,
      title: 'Gjør deg klar',
      text:
          'Velg sesong, bæring (sekk, pulk eller kano) og overnatting. '
          'Pakkeliste, matplan og kaloribehov skaleres etter deltakere, '
          'dager og din egen profil. Last ned offline kart før avreise.',
    ),
    (
      icon: Icons.navigation_outlined,
      title: 'Gå tur trygt',
      text:
          'Følg vær- og skredvarsler fra MET og Varsom, del turkortet '
          'med en kontakt, og bruk aktiv tur-modus med GPS-sporing og '
          'varsel hvis du kommer ut av ruten.',
    ),
    (
      icon: Icons.school_outlined,
      title: 'Lær av turen',
      text:
          'Evaluer turen etterpå – det som fungerte, det som manglet. '
          'Erfaringene dine gjør neste pakkeliste og anbefalingene '
          'enda bedre.',
    ),
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onDone,
                child: Text(
                  'Hopp over',
                  style: TextStyle(color: NkColors.textSecondary),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _ctrl,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _pages.length,
                itemBuilder: (_, i) {
                  final p = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: NkColors.primaryBlue.withValues(
                                alpha: 0.10,
                              ),
                            ),
                            child: Icon(
                              p.icon,
                              size: 44,
                              color: NkColors.primaryBlue,
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            p.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            ['PLANLEGG', 'GJØR KLAR', 'GÅ TUR', 'LÆR'][i],
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 2,
                              color: NkColors.forestGreen,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            p.text,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: NkColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.all(4),
                    width: i == _page ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: i == _page
                          ? NkColors.primaryBlue
                          : NkColors.border,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: last
                      ? widget.onDone
                      : () => _ctrl.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        ),
                  child: Text(last ? 'Planlegg første tur' : 'Neste'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
