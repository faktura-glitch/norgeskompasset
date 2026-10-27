import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_info.dart';
import '../core/theme.dart';
import '../models/profile.dart';
import '../models/trip.dart';
import '../services/auth_service.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'hiking_screen.dart';
import 'meals_screen.dart';
import 'packing_screen.dart' show showOwnedGearSheet;
import 'recommendations_screen.dart';
import 'review_screen.dart';
import 'safety_screen.dart';
import 'weather_screen.dart';

/// Opens the mail app with version and platform pre-filled so bug
/// reports arrive with the context needed to reproduce them.
Future<void> _sendFeedback(BuildContext context) async {
  final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
  final subject = Uri.encodeQueryComponent(
    'Tilbakemelding NorgesKompasset $kAppVersion',
  );
  final body = Uri.encodeQueryComponent(
    'Hva skjedde, eller hva ønsker du deg?\n\n\n—\nApp $kAppVersion · $platform',
  );
  final uri = Uri.parse('mailto:$kFeedbackEmail?subject=$subject&body=$body');
  var ok = false;
  try {
    ok = await launchUrl(uri);
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) {
    nkToast(context, 'Fant ingen e-postapp. Skriv til $kFeedbackEmail.');
  }
}

/// Compact two-column shortcut grid. (Wrap, not GridView: the parent
/// ListView must stay the only scrollable.) An item without a screen
/// calls [onTapNoScreen].
class _ToolGrid extends StatelessWidget {
  final List<(IconData, String, String, Widget?)> items;
  final VoidCallback? onTapNoScreen;
  const _ToolGrid({required this.items, this.onTapNoScreen});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final cellWidth = (constraints.maxWidth - 8) / 2;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (icon, title, subtitle, screen) in items)
            SizedBox(
              width: items.length == 1 ? constraints.maxWidth : cellWidth,
              child: NkCard(
                onTap: screen == null
                    ? onTapNoScreen
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => screen),
                      ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: NkColors.primaryBlue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (items.length == 1)
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 11,
                                color: NkColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final trip = state.currentTrip;
    final wide = context.isWide;

    // Three groups: tools for the trip, safety, and the personal
    // things that follow the user between trips.
    final tools = [
      (
        Icons.cloud_outlined,
        'Vær langs ruten',
        'Prognose for etapper og punkter',
        const WeatherScreen(),
      ),
      (
        Icons.restaurant_outlined,
        'Matplan',
        'Måltider, matvekt og handleliste',
        const MealsScreen(),
      ),
      (
        Icons.lightbulb_outline,
        'Smarte anbefalinger',
        'Vær, terreng og forberedelser',
        const RecommendationsScreen(),
      ),
      (
        Icons.navigation_outlined,
        'Turmodus / GPS-sporing',
        'GPS-posisjon og etappefremdrift',
        const HikingScreen(),
      ),
    ];
    final safety = [
      (
        Icons.shield_outlined,
        'Del tur og sikkerhet',
        'Turkort til pårørende, nødnumre og innsjekking',
        const SafetyScreen(),
      ),
    ];
    final ownedCount = state.profile.gear.length;

    User? user;
    try {
      user = FirebaseAuth.instance.currentUser;
    } catch (_) {}

    return Scaffold(
      appBar: AppBar(title: const Text('Mer')),
      body: ListView(
        padding: EdgeInsets.all(wide ? 28 : 16),
        children: [
          if (state.localOnly)
            NkCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Lokal modus · turer lagres på denne enheten'),
                  TextButton(
                    onPressed: () => state.useLocalMode(false),
                    child: const Text('Logg inn for synkronisering og deling'),
                  ),
                ],
              ),
            ),
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: NkCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.account_circle_outlined,
                      color: NkColors.primaryBlue,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        user.email ?? 'Innlogget',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      child: const Text(
                        'Logg ut',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (user != null)
            NkCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ValueListenableBuilder(
                    valueListenable: state.repo.syncStatus,
                    builder: (_, status, _) => Text(status.label),
                  ),
                  const Text(
                    'Eldre enhetsdata er beholdt i lokal modus og tilordnes ikke automatisk kontoen. '
                    'Logg ut og velg lokal modus for å åpne dem.',
                  ),
                  if (state.cloudRefreshError != null)
                    Text(state.cloudRefreshError!),
                  TextButton.icon(
                    onPressed: state.cloudSyncing ? null : state.syncNow,
                    icon: const Icon(Icons.sync),
                    label: const Text('Oppdater fra skyen'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (trip != null)
            NkCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(
                    Icons.backpack_outlined,
                    color: NkColors.primaryBlue,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Aktiv tur',
                          style: TextStyle(
                            fontSize: 11,
                            color: NkColors.textSecondary,
                          ),
                        ),
                        Text(
                          trip.name.isEmpty ? 'Tur uten navn' : trip.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusPill(trip.status.label, NkColors.primaryBlue),
                ],
              ),
            )
          else
            NkCard(
              padding: EdgeInsets.all(14),
              child: Text(
                'Ingen aktiv tur – opprett en tur fra Turer-fanen.',
                style: TextStyle(fontSize: 13, color: NkColors.textSecondary),
              ),
            ),
          const SizedBox(height: 14),
          const SectionHeader('Turverktøy', icon: Icons.hiking_outlined),
          const SizedBox(height: 10),
          _ToolGrid(items: tools),
          const SizedBox(height: 14),
          const SectionHeader('Sikkerhet', icon: Icons.shield_outlined),
          const SizedBox(height: 10),
          _ToolGrid(items: safety),
          const SizedBox(height: 14),
          const SectionHeader('Personlig', icon: Icons.person_outline),
          const SizedBox(height: 10),
          _ProfileCard(state: state),
          const SizedBox(height: 12),
          _ToolGrid(
            items: [
              (
                Icons.backpack_outlined,
                ownedCount == 0 ? 'Mitt utstyr' : 'Mitt utstyr ($ownedCount)',
                'Utstyr du har lagret med vekt',
                null,
              ),
              (
                Icons.rate_review_outlined,
                'Turevaluering',
                'Registrer erfaringer etter turen',
                const ReviewScreen(),
              ),
            ],
            onTapNoScreen: () {
              if (trip == null) {
                nkToast(
                  context,
                  'Velg en tur først – utstyret legges på turen.',
                );
                return;
              }
              showOwnedGearSheet(context, trip);
            },
          ),
          const SizedBox(height: 14),
          const SectionHeader('Innstillinger', icon: Icons.tune),
          const SizedBox(height: 10),
          _ThemeCard(state: state),
          const SizedBox(height: 12),
          _StorageCard(state: state),
          const SizedBox(height: 14),
          const SectionHeader('Om appen', icon: Icons.info_outline),
          const SizedBox(height: 10),
          NkCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    'assets/branding/logo.jpg',
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'NorgesKompasset',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Turplanlegging for norske forhold · norgeskompasset.no',
                        style: TextStyle(
                          fontSize: 12,
                          color: NkColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          NkCard(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Data og personvern')),
                  body: const SingleChildScrollView(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _DataSection(),
                        SizedBox(height: 12),
                        _DeleteAccountCard(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.privacy_tip_outlined),
              title: Text('Data og personvern'),
              trailing: Icon(Icons.chevron_right),
            ),
          ),
          const SizedBox(height: 12),
          NkCard(
            onTap: () => _sendFeedback(context),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.mail_outline),
              title: Text('Gi tilbakemelding'),
              subtitle: Text(
                'Feil, ønsker eller ros – åpner e-post til $kFeedbackEmail',
              ),
              trailing: Icon(Icons.chevron_right),
            ),
          ),
          const SizedBox(height: 12),
          NkCard(
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'NorgesKompasset',
              applicationVersion: kAppVersion,
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: NkColors.primaryBlue),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Lisenser',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: NkColors.textSecondary,
                  size: 18,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Theme preference — System / Light / Dark, persisted via the
/// settings box and applied app-wide through [AppState.themeMode].
class _ThemeCard extends StatelessWidget {
  final AppState state;
  const _ThemeCard({required this.state});

  @override
  Widget build(BuildContext context) {
    return NkCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.contrast_outlined,
                size: 18,
                color: NkColors.primaryBlue,
              ),
              SizedBox(width: 10),
              Text(
                'Utseende',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.settings_suggest_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Lys'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Mørk'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
              ],
              selected: {state.themeMode},
              onSelectionChanged: (s) => state.setThemeMode(s.first),
            ),
          ),
        ],
      ),
    );
  }
}

/// Personal profile — sharpens packing lists and meal plans, and
/// adds name/contact/medical info to the shared safety card.
class _ProfileCard extends StatelessWidget {
  final AppState state;
  const _ProfileCard({required this.state});

  Future<void> _edit(BuildContext context) async {
    final p = state.profile;
    final name = TextEditingController(text: p.name);
    final phone = TextEditingController(text: p.phone);
    final weight = TextEditingController(
      text: p.weightKg > 0 ? p.weightKg.toStringAsFixed(0) : '',
    );
    final packLimit = TextEditingController(
      text: p.packLimitKg > 0 ? p.packLimitKg.toStringAsFixed(0) : '',
    );
    final medical = TextEditingController(text: p.medicalNotes);
    final iceName = TextEditingController(text: p.iceName);
    final icePhone = TextEditingController(text: p.icePhone);
    var cold = p.coldSensitive;
    var veg = p.vegetarian;
    var vegan = p.vegan;
    var glutenFree = p.glutenFree;
    var lactoseFree = p.lactoseFree;
    var nutAllergy = p.nutAllergy;
    var prefersDehydrated = p.prefersDehydrated;
    var lightPacker = p.lightPacker;
    var extraComfort = p.extraComfort;
    var withDog = p.withDog;
    var ownsTent = p.ownsTent;
    var ownsStove = p.ownsStove;
    var preferredSeason = p.preferredSeason;
    var level = p.level;

    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: NkColors.primaryBlue,
          ),
        ),
      ),
    );

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setD) {
            Widget chip(String label, bool value, void Function(bool) set) =>
                FilterChip(
                  label: Text(label, style: const TextStyle(fontSize: 11)),
                  selected: value,
                  visualDensity: VisualDensity.compact,
                  onSelected: (v) => setD(() => set(v)),
                );
            return Scaffold(
              appBar: AppBar(
                title: const Text('Min profil'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text(
                      'Lagre',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Profilen tilpasser nye forslag. Generer pakkeliste og matplan på nytt '
                        'for å bruke endringene på en eksisterende tur. Nødkontakt og medisinsk info '
                        'deles bare når du velger det på turkortet.',
                      ),
                      section('Person'),
                      TextField(
                        controller: name,
                        decoration: const InputDecoration(labelText: 'Navn'),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: phone,
                              decoration: const InputDecoration(
                                labelText: 'Telefon',
                              ),
                              keyboardType: TextInputType.phone,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: weight,
                              decoration: const InputDecoration(
                                labelText: 'Vekt (kg)',
                                hintText: 'For energiberegning',
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      // Optional tailoring stays behind a closed
                      // section so the form opens with only Person
                      // and Sikkerhet visible.
                      Theme(
                        data: Theme.of(ctx)
                            .copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          title: const Text(
                            'Mer tilpasning – turstil, kosthold og utstyr',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: const Text(
                            'Valgfritt – åpne for å tilpasse forslagene',
                            style: TextStyle(fontSize: 11),
                          ),
                          children: [
                            section('Turstil'),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  chip(
                                    'Lett pakking (gramjeger)',
                                    lightPacker,
                                    (v) => lightPacker = v,
                                  ),
                                  chip(
                                    'Ekstra komfort',
                                    extraComfort,
                                    (v) => extraComfort = v,
                                  ),
                                  chip(
                                    'Går med hund',
                                    withDog,
                                    (v) => withDog = v,
                                  ),
                                  chip('Fryser lett', cold, (v) => cold = v),
                                ],
                              ),
                            ),
                            section('Mat og kosthold'),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  chip('Vegetar', veg, (v) {
                                    veg = v;
                                    if (v) vegan = false;
                                  }),
                                  chip('Vegansk', vegan, (v) {
                                    vegan = v;
                                    if (v) veg = true;
                                  }),
                                  chip(
                                    'Glutenfri',
                                    glutenFree,
                                    (v) => glutenFree = v,
                                  ),
                                  chip(
                                    'Laktosefri',
                                    lactoseFree,
                                    (v) => lactoseFree = v,
                                  ),
                                  chip(
                                    'Nøtteallergi',
                                    nutAllergy,
                                    (v) => nutAllergy = v,
                                  ),
                                  chip(
                                    'Rehydrert turmat',
                                    prefersDehydrated,
                                    (v) => prefersDehydrated = v,
                                  ),
                                ],
                              ),
                            ),
                            section('Utstyr jeg eier'),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  chip(
                                    'Eier telt',
                                    ownsTent,
                                    (v) => ownsTent = v,
                                  ),
                                  chip(
                                    'Eier brenner/kokeapparat',
                                    ownsStove,
                                    (v) => ownsStove = v,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: packLimit,
                              decoration: const InputDecoration(
                                labelText: 'Maks sekkvekt (kg)',
                                hintText: 'Valgfritt – pakkelisten sier fra når du er over',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Foretrukket sesong',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: NkColors.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final s in TripSeason.values)
                                    chip(
                                      s.label,
                                      preferredSeason == s,
                                      (v) => preferredSeason = v ? s : null,
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              'Brukes som standard på nye turer',
                              style: TextStyle(
                                fontSize: 10,
                                color: NkColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      section('Sikkerhet'),
                      TextField(
                        controller: iceName,
                        decoration: const InputDecoration(
                          labelText: 'Nødkontakt (navn)',
                          hintText: 'Nærmeste pårørende',
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: icePhone,
                        decoration: const InputDecoration(
                          labelText: 'Nødkontakt (telefon)',
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: medical,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Medisinsk info (allergier, medisiner)',
                          hintText:
                              'Kan tas med på turkortet når du selv velger det',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Turnivå',
                          style: TextStyle(
                            fontSize: 12,
                            color: NkColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.maxFinite,
                        child: SegmentedButton<TourLevel>(
                          showSelectedIcon: false,
                          segments: [
                            for (final l in TourLevel.values)
                              ButtonSegment(
                                value: l,
                                label: Text(
                                  l.label,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                          ],
                          selected: {if (level != null) level!},
                          emptySelectionAllowed: true,
                          onSelectionChanged: (s) =>
                              setD(() => level = s.isEmpty ? null : s.first),
                        ),
                      ),
                      Text(
                        'Brukes til å vurdere om etappene passer for deg',
                        style: TextStyle(
                          fontSize: 10,
                          color: NkColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => Navigator.pop(ctx, true),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Lagre profil'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    if (saved == true && context.mounted) {
      await context.read<AppState>().updateProfile(
        UserProfile(
          name: name.text.trim(),
          phone: phone.text.trim(),
          coldSensitive: cold,
          vegetarian: veg,
          vegan: vegan,
          glutenFree: glutenFree,
          lactoseFree: lactoseFree,
          nutAllergy: nutAllergy,
          prefersDehydrated: prefersDehydrated,
          lightPacker: lightPacker,
          extraComfort: extraComfort,
          withDog: withDog,
          ownsTent: ownsTent,
          ownsStove: ownsStove,
          preferredSeason: preferredSeason,
          iceName: iceName.text.trim(),
          icePhone: icePhone.text.trim(),
          medicalNotes: medical.text.trim(),
          weightKg: double.tryParse(weight.text.replaceAll(',', '.')) ?? 0,
          level: level,
          packLimitKg:
              (double.tryParse(packLimit.text.replaceAll(',', '.')) ?? 0)
                  .clamp(0, 100)
                  .toDouble(),
          gear: state.profile.gear,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = state.profile;
    final traits = [
      if (p.level != null) p.level!.label.toLowerCase(),
      if (p.coldSensitive) 'fryser lett',
      if (p.lightPacker) 'lett pakking',
      if (p.extraComfort) 'komfort',
      if (p.withDog) 'hund',
      ...p.dietTags.map((t) => t.toLowerCase()),
      if (p.iceName.isNotEmpty) 'nødkontakt',
      if (p.medicalNotes.isNotEmpty) 'medisinsk info',
    ];
    return NkCard(
      onTap: () => _edit(context),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(
            Icons.person_outline,
            size: 20,
            color: NkColors.primaryBlue,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name.isEmpty ? 'Min profil' : p.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  p.isEmpty
                      ? 'Navn, kontaktinfo og preferanser — spisser pakkeliste, matplan og turkort'
                      : traits.isEmpty
                      ? 'Profil lagret'
                      : traits.join(' · '),
                  style: TextStyle(fontSize: 11, color: NkColors.textSecondary),
                ),
              ],
            ),
          ),
          Icon(Icons.edit_outlined, size: 16, color: NkColors.textSecondary),
        ],
      ),
    );
  }
}

/// Offline tile-cache management — count + a way to reclaim space.
class _StorageCard extends StatelessWidget {
  final AppState state;
  const _StorageCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final cached = state.mapTilesCached;
    return NkCard(
      child: Row(
        children: [
          const Icon(
            Icons.storage_outlined,
            size: 18,
            color: NkColors.primaryBlue,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$cached kartfliser i hurtiglageret',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (cached > 0)
            TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Tøm kartbuffer?'),
                    content: const Text(
                      'Alle nedlastede kartfliser slettes – kartet krever nett igjen til områder er sett på nytt.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Avbryt'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Tøm'),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  await context.read<AppState>().clearMapCache();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Kartbufferen er tømt')),
                    );
                  }
                }
              },
              child: const Text('Tøm', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _DataSection extends StatelessWidget {
  const _DataSection();

  @override
  Widget build(BuildContext context) {
    return NkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader('Data og personvern', icon: Icons.lock_outline),
          const SizedBox(height: 8),
          Text(
            '• Innlogging skjer via Firebase – e-post/passord lagres hos Google, ikke lokalt.\n'
            '• Turer, pakkelister og evalueringer lagres lokalt og synkroniseres til din private Firestore samling når du er innlogget.\n'
            '• Vær hentes fra MET Norway; høyder fra OpenTopoData; stedsøk fra OpenStreetMap/Nominatim; stiruter fra BRouter (OSM-data); tursteder (hytter, gapahuker, bålplasser m.m.) fra OpenStreetMap via Overpass; turruter fra Kartverkets Turrutebase (NLOD).\n'
            '• Ingen posisjon deles automatisk – kun når du selv deler turkortet.\n'
            '• Turkartdata: © Kartverket / © OpenStreetMap contributors · skiløyper: OpenSnowMap.',
            style: TextStyle(
              fontSize: 12,
              color: NkColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'NorgesKompasset v1.0',
            style: TextStyle(
              fontSize: 11,
              color: NkColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

/// Play Store and App Store require in-app account deletion. The cloud
/// data goes first, then the Firebase account — if cloud deletion
/// fails the account is left untouched so nothing is orphaned.
class _DeleteAccountCard extends StatefulWidget {
  const _DeleteAccountCard();

  @override
  State<_DeleteAccountCard> createState() => _DeleteAccountCardState();
}

class _DeleteAccountCardState extends State<_DeleteAccountCard> {
  bool _busy = false;

  Future<void> _confirm() async {
    bool keepLocal = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Slett konto?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Kontoen din og alle dataene dine i skyen slettes for '
                'godt: turer, delte turer og publiserte katalogturer. '
                'Dette kan ikke angres.',
              ),
              CheckboxListTile(
                value: keepLocal,
                onChanged: (v) => setDlg(() => keepLocal = v ?? true),
                title: const Text(
                  'Behold turene på denne enheten',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: const Text(
                  'De lagres lokalt, uten konto',
                  style: TextStyle(fontSize: 12),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: NkColors.dangerRed,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Slett konto'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) await _runDelete(keepLocal);
  }

  Future<String?> _askPassword() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Bekreft med passord'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Passord',
            hintText: 'Skriv inn passordet ditt',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Bekreft'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _runDelete(bool keepLocal) async {
    setState(() => _busy = true);
    try {
      await context.read<AppState>().deleteAccount(keepLocalTrips: keepLocal);
      // On success the auth stream signs out and the app shows the
      // login screen — nothing more to do here.
    } on AuthException catch (e) {
      if (e.code != 'requires-recent-login' || !mounted) rethrow;
      // Social accounts (Google/Apple) re-authenticate through the
      // provider flow; only password accounts get the prompt.
      final auth = AuthService();
      String? password;
      var wantsReauth = true;
      if (auth.usesPasswordProvider) {
        password = await _askPassword();
        wantsReauth = password != null;
      }
      if (wantsReauth && mounted) {
        try {
          await auth.reauthenticate(password);
          if (mounted) {
            await context.read<AppState>().deleteAccount(
              keepLocalTrips: keepLocal,
            );
          }
        } catch (e2) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Kunne ikke slette kontoen: $e2')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke slette kontoen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    User? user;
    try {
      user = FirebaseAuth.instance.currentUser;
    } catch (_) {}
    if (user == null) return const SizedBox.shrink();
    return NkCard(
      onTap: _busy ? null : _confirm,
      child: Row(
        children: [
          Icon(
            Icons.delete_forever_outlined,
            size: 18,
            color: NkColors.dangerRed,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Slett kontoen min',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: NkColors.dangerRed,
              ),
            ),
          ),
          if (_busy)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(Icons.chevron_right, color: NkColors.textSecondary, size: 18),
        ],
      ),
    );
  }
}
