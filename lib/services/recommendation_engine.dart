import 'package:uuid/uuid.dart';

import '../models/profile.dart';
import '../models/recommendation.dart';
import '../models/route_models.dart';
import '../models/stage.dart';
import '../models/trip.dart';
import 'trip_analysis.dart';
import 'local_tour_catalog.dart';

/// Combines route, elevation, weather and packing state into
/// transparent, prioritized recommendations. Never claims a trip is
/// "safe" — only surfaces observations and suggested actions.
class RecommendationEngine {
  static const _uuid = Uuid();
  static String _id() => _uuid.v4().substring(0, 8);

  List<Recommendation> build(Trip trip, {UserProfile? profile}) {
    final out = <Recommendation>[];
    final now = DateTime.now();
    if (trip.localTourId != null) {
      final template = localTours
          .where((tour) => tour.id == trip.localTourId)
          .firstOrNull;
      out.add(
        Recommendation(
          id: _id(),
          level: RecommendationLevel.serious,
          title: 'Turmalen er ikke kontrollert',
          observation:
              'Turen er opprettet fra en brukerlevert planmal (${trip.localTourId}).',
          why:
              template?.warning ??
              'Opprinnelige rutepunkter og nøkkeltall er ikke verifisert.',
          action:
              'Kontroller faktisk trasé, høydeprofil, lokale forhold og nødvendige ferdigheter. '
              'Kartskissen og den foreløpige pakkelisten er ikke et navigasjonsgrunnlag eller en sikkerhetsvurdering.',
          sourceNote:
              'Brukerlevert planmal, ikke verifisert av NorgesKompasset',
        ),
      );
    }

    // ── Trip suitability vs. user's stated level ─────────────
    // Compares each stage's distance/ascent against conservative
    // daily limits for the self-assessed level. Honest framing:
    // an assessment, never a verdict on safety.
    final level = profile?.level;
    if (level != null && trip.stages.isNotEmpty) {
      Stage? heaviest;
      var worst = 0.0;
      for (final s in trip.stages) {
        final load = [
          (s.distanceMeters / 1000) / level.maxKmPerDay,
          s.ascent / level.maxAscentPerDay,
        ].reduce((a, b) => a > b ? a : b);
        if (load > worst) {
          worst = load;
          heaviest = s;
        }
      }
      if (heaviest != null && worst > 1.0) {
        out.add(
          Recommendation(
            id: _id(),
            level: worst > 1.5
                ? RecommendationLevel.serious
                : RecommendationLevel.caution,
            title: 'Etappe ${heaviest.number} er over nivået ditt',
            observation:
                '${(heaviest.distanceMeters / 1000).toStringAsFixed(1)} km og +${heaviest.ascent.round()} m – mot grensene dine på ~${level.maxKmPerDay.toStringAsFixed(0)} km / ${level.maxAscentPerDay.toStringAsFixed(0)} høydemeter per dag (${level.label.toLowerCase()}).',
            why: 'Etapper over komfortnivået øker risikoen for utmattelse og feilvurderinger.',
            action: 'Del turen i flere dager, velg en kortere rute eller gå med lettere oppakning. Oppdater nivået i profilen hvis det ikke stemmer.',
            stageNumber: heaviest.number,
            sourceNote: 'Profilvurdering (selvrapportert nivå)',
          ),
        );
      } else if (heaviest != null && trip.localTourId == null) {
        out.add(
          Recommendation(
            id: _id(),
            level: RecommendationLevel.info,
            title: 'Turen ligger innenfor nivået ditt',
            observation:
                'Tyngste etappe: ${(heaviest.distanceMeters / 1000).toStringAsFixed(1)} km, +${heaviest.ascent.round()} m – under grensene for ${level.label.toLowerCase()}.',
            why: 'Dagsetappene matcher det du har oppgitt at du mestrer.',
            action: 'Husk at dagsform, vær og sekkvekt kan endre bildet.',
            stageNumber: heaviest.number,
            sourceNote: 'Profilvurdering (selvrapportert nivå)',
          ),
        );
      }
      if (trip.season == TripSeason.winter && level == TourLevel.novice) {
        out.add(
          Recommendation(
            id: _id(),
            level: RecommendationLevel.caution,
            title: 'Vintertur krever ekstra erfaring',
            observation: 'Du har registrert nybegynnernivå, men turen er satt til vinter.',
            why: 'Vinterforhold stiller høyere krav til navigasjon, overnatting og kuldehåndtering.',
            action: 'Vurder å gå sammen med erfarne folk, eller velg en kortere/enklere rute først.',
            sourceNote: 'Profilvurdering (selvrapportert nivå)',
          ),
        );
      }
    }

    // ── Weather-linked recommendations per stage ─────────────
    for (final stage in trip.stages) {
      final snaps = TripAnalysis.snapshotsForStage(trip, stage);
      final (from, to) = TripAnalysis.stageWindow(stage, trip);
      if (snaps.isEmpty) continue;
      if (from.isAfter(now.add(const Duration(days: 9)))) {
        // Beyond forecast horizon — note it once per stage.
        out.add(
          Recommendation(
            id: _id(),
            level: RecommendationLevel.info,
            title: 'Etappe ${stage.number}: for langt frem for prognose',
            observation:
                'Etappen er planlagt ${from.day}.${from.month} – utover pålitelig varselhorisont.',
            why: 'Værprognoser i fjellterreng blir upålitelige etter ca. 5–9 dager.',
            action: 'Sjekk været på nytt nærmere avreise og vurder om planen fortsatt passer.',
            stageNumber: stage.number,
            sourceNote: 'MET Norway',
          ),
        );
        continue;
      }
      final c = TripAnalysis.summarize(snaps, from, to);
      if (!c.hasData) continue;
      final src =
          'MET Norway, ${snaps.first.retrievedAt.day}.${snaps.first.retrievedAt.month} kl. ${snaps.first.retrievedAt.hour.toString().padLeft(2, '0')}:${snaps.first.retrievedAt.minute.toString().padLeft(2, '0')}';

      if (c.rainExpected) {
        out.add(
          Recommendation(
            id: _id(),
            level: RecommendationLevel.caution,
            title: 'Regn ventet på etappe ${stage.number}',
            observation:
                'Varslet nedbør totalt ${c.totalPrecipMm.toStringAsFixed(1)} mm i løpet av dagen.',
            why: 'Våt sti gir lengre etappetid, glatte partier og behov for regntøy.',
            action: 'Kontroller at skalljakke og regnbukse er pakket, og beskytt innholdet i sekken med regntrekk eller vanntette poser.',
            stageNumber: stage.number,
            sourceNote: src,
          ),
        );
      }
      if (c.strongWind) {
        final exposed = (stage.highestPoint ?? 0) > 900;
        out.add(
          Recommendation(
            id: _id(),
            level: exposed
                ? RecommendationLevel.serious
                : RecommendationLevel.caution,
            title: 'Kraftig vind på etappe ${stage.number}',
            observation:
                'Vind opptil ${c.maxWind?.toStringAsFixed(0)} m/s${c.maxGust != null ? ', kast til ${c.maxGust!.toStringAsFixed(0)} m/s' : ''}.',
            why: exposed
                ? 'Etappen når ${stage.highestPoint?.round()} moh – eksponerte partier i sterk vind kan være farlige.'
                : 'Sterk vind gjør turen tyngre og øker vindkjøling.',
            action: exposed
                ? 'Vurder om det eksponerte partiet bør gås en annen dag eller med alternativ rute. Sjekk oppdatert varsel før avreise.'
                : 'Pakk vindtette plagg og hansker; regn inn ekstra tid.',
            stageNumber: stage.number,
            sourceNote: src,
          ),
        );
      }
      final (nf, nt) = TripAnalysis.nightWindow(stage, trip);
      final night = TripAnalysis.summarize(snaps, nf, nt);
      if (night.freezingTemps &&
          (trip.accommodation == AccommodationType.tent ||
              trip.accommodation == AccommodationType.mixed)) {
        out.add(
          Recommendation(
            id: _id(),
            level: RecommendationLevel.caution,
            title: 'Kalde netter ventet',
            observation:
                'Nattetemperatur kan nærme seg ${night.minTemp?.toStringAsFixed(0)}°C.',
            why: 'Sovepose og liggeunderlag må tåle temperaturene for trygg overnatting.',
            action: 'Sjekk komfortgrensen på soveposen, og pakk ekstra isolasjon og tørt nattøy.',
            stageNumber: stage.number,
            sourceNote: src,
          ),
        );
      }
      if (c.limitedVisibility) {
        out.add(
          Recommendation(
            id: _id(),
            level: RecommendationLevel.caution,
            title: 'Begrenset sikt mulig på etappe ${stage.number}',
            observation: 'Tett skyddekke kombinert med nedbør er varslet.',
            why:
                'Dårlig sikt gjør navigasjon krevende, særlig over tregrensen.',
            action: 'Ha kart og kompass lett tilgjengelig, og vurder å legge inn margin i dagsplanen.',
            stageNumber: stage.number,
            sourceNote: src,
          ),
        );
      }
    }

    // ── Official warnings (MET metalerts) ────────────────────
    final seenAlertTitles = <String>{};
    for (final a in trip.alerts) {
      if (!seenAlertTitles.add(a.title)) continue;
      out.add(
        Recommendation(
          id: _id(),
          level: a.awarenessLevel >= 3
              ? RecommendationLevel.serious
              : RecommendationLevel.caution,
          title: '${a.levelLabel}: ${a.title}',
          observation: a.area.isNotEmpty
              ? a.area
              : (a.description.isNotEmpty
                    ? a.description
                    : 'Aktivt farevarsel for området.'),
          why: a.description.isNotEmpty
              ? a.description
              : 'Offisielt farevarsel er utstedt for turens område.',
          action: a.instruction.isNotEmpty ? a.instruction : 'Følg med på oppdaterte varsler og vurder om turen bør gjennomføres som planlagt.',
          sourceNote: 'MET Norway / NVE varsling',
        ),
      );
    }

    // ── Avalanche warnings (Varsom/NVE) ──────────────────────
    // One recommendation per region at its highest warned level.
    final avByRegion = <String, int>{};
    final avText = <String, String>{};
    for (final w in trip.avalancheWarnings) {
      final prev = avByRegion[w.regionName] ?? 0;
      if (w.dangerLevel > prev) avByRegion[w.regionName] = w.dangerLevel;
      if (w.mainText.isNotEmpty && (avText[w.regionName]?.isEmpty ?? true)) {
        avText[w.regionName] = w.mainText;
      }
    }
    for (final e in avByRegion.entries) {
      if (e.value < 2) continue;
      out.add(
        Recommendation(
          id: _id(),
          level: e.value >= 3
              ? RecommendationLevel.serious
              : RecommendationLevel.caution,
          title:
              'Skredfare ${e.value == 2
                  ? "moderat"
                  : e.value == 3
                  ? "betydelig"
                  : "stor"} i ${e.key}',
          observation: avText[e.key]?.isNotEmpty == true
              ? avText[e.key]!
              : 'Varsom melder faregrad ${e.value} for ${e.key} i turens periode.',
          why: 'Skredfare gjelder terreng brattere enn ca. 30° — også under løsningssoner.',
          action: e.value >= 3
              ? 'Unngå skredterreng (>30°) og utløpsområder. Vurder omlegging av ruten og les hele varselet på varsom.no.'
              : 'Vurder terrengvalg underveis og les hele varselet på varsom.no før avreise.',
          sourceNote: 'Varsom/NVE skredvarsling',
        ),
      );
    }

    // ── Difficulty-linked recommendations ────────────────────
    Stage? hardest;
    for (final s in trip.stages) {
      if (s.difficulty == null) continue;
      if (hardest == null || s.difficulty!.score > hardest.difficulty!.score) {
        hardest = s;
      }
    }
    if (hardest != null &&
        hardest.difficulty!.level.index >= DifficultyLevel.challenging.index) {
      out.add(
        Recommendation(
          id: _id(),
          level: RecommendationLevel.caution,
          title: 'Etappe ${hardest.number} er den mest krevende',
          observation:
              'Vurdert som "${hardest.difficulty!.level.label}" – ${hardest.difficulty!.factors.join('; ').toLowerCase()}.',
          why: 'Denne etappen kombinerer faktorer som gjør dagen tung.',
          action: 'Start tidlig, planlegg pauser, og vurder tempoet underveis. Ha en realistisk utvielselsplan.',
          stageNumber: hardest.number,
          sourceNote: 'Egenvurdering basert på rutedata',
        ),
      );
    }

    // ── Packing-linked checks ────────────────────────────────
    final packed = trip.packingList;
    bool hasItem(String needle) =>
        packed.any((i) => i.name.toLowerCase().contains(needle));
    if (packed.isNotEmpty) {
      if (trip.hikingDays > 1 && !hasItem('hodelykt')) {
        out.add(
          Recommendation(
            id: _id(),
            level: RecommendationLevel.caution,
            title: 'Hodelykt mangler i pakkelisten',
            observation:
                'Pakkelisten har ingen hodelykt for en fler dagers tur.',
            why: 'Hodelykt er nødvendig ved overnatting og er viktig sikkerhetsutstyr.',
            action: 'Legg til hodelykt med reservebatterier i pakkelisten.',
            sourceNote: 'Pakkeliste-sjekk',
          ),
        );
      }
      if (!hasItem('kart') || !hasItem('kompass')) {
        out.add(
          Recommendation(
            id: _id(),
            level: RecommendationLevel.caution,
            title: 'Kart og kompass bør være med',
            observation: 'Navigasjonsutstyr mangler eller er ufullstendig.',
            why: 'Elektronikk kan svikte – papirkart og kompass er standard backup.',
            action: 'Legg til papirkart og kompass i pakkelisten.',
            sourceNote: 'Pakkeliste-sjekk',
          ),
        );
      }
    }

    // ── Route status honesty ─────────────────────────────────
    if (trip.route != null && trip.route!.source != RouteSource.trail) {
      out.add(
        Recommendation(
          id: _id(),
          level: RecommendationLevel.info,
          title: 'Ruten er ikke verifisert mot stidata',
          observation: trip.route!.sourceLabel,
          why: 'En estimert eller manuelt tegnet rute følger ikke nødvendigvis merkede stier.',
          action: 'Kontroller ruten mot kart før avreise, og vær forberedt på å navigere selv.',
          sourceNote: 'Ruteberegner',
        ),
      );
    }

    // Missing prep tasks
    if (trip.startDate == null) {
      out.add(
        Recommendation(
          id: _id(),
          level: RecommendationLevel.info,
          title: 'Sett datoer for turen',
          observation: 'Turen har ingen planlagte datoer ennå.',
          why: 'Datoer trengs for å hente relevant værprognose.',
          action: 'Åpne turen i kartplanleggeren og sett start- og sluttdato.',
        ),
      );
    }

    return out;
  }

  /// Merges new recommendations into the trip, preserving dismissed ones.
  void refresh(Trip trip, {UserProfile? profile}) {
    final dismissed = {
      for (final r in trip.recommendations)
        if (r.status == RecommendationStatus.dismissed) r.title,
    };
    final fresh = build(trip, profile: profile);
    for (final r in fresh) {
      if (dismissed.contains(r.title)) {
        r.status = RecommendationStatus.dismissed;
      }
    }
    trip.recommendations = fresh;
  }
}
