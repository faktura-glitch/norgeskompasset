import '../models/local_tour.dart';
import '../models/trip.dart';

const localTours = <LocalTour>[
  LocalTour(
    id: 'local-galdhopiggen-juvass',
    name: 'Galdhøpiggen fra Juvasshytta',
    municipality: 'Lom',
    region: 'Jotunheimen',
    activity: TripActivity.foot,
    season: TripSeason.summer,
    months: [6, 7, 8, 9],
    durationDays: 1,
    accommodation: AccommodationType.dayHike,
    reportedDistanceKm: 12,
    reportedElevationGainMeters: 650,
    description: 'Planmal for en topptur fra Juvasshytta via Styggebreen.',
    warning:
        'Brekryssing: avtal kvalifisert breføring. En vanlig pakkeliste '
        'erstatter ikke brekompetanse, fører eller spesialutstyr. '
        'Brekantpunktet er ikke verifisert. Returen er her tegnet via de samme punktene.',
    returnSameWay: true,
    stops: [
      (name: 'Juvasshytta (oppgitt)', lat: 61.6738, lon: 8.3695),
      (name: 'Styggebreen, brekant (oppgitt)', lat: 61.6491, lon: 8.3412),
      (name: 'Galdhøpiggen (oppgitt)', lat: 61.6365, lon: 8.3124),
    ],
  ),
  LocalTour(
    id: 'local-besseggen',
    name: 'Besseggen',
    municipality: 'Vågå',
    region: 'Jotunheimen',
    activity: TripActivity.foot,
    season: TripSeason.summer,
    months: [6, 7, 8, 9, 10],
    durationDays: 1,
    accommodation: AccommodationType.dayHike,
    reportedDistanceKm: 14,
    reportedElevationGainMeters: 1100,
    description:
        'Planmal mellom Gjendesheim og Memurubu med oppgitte ryggpunkter.',
    warning:
        'Punktene må kontrolleres mot et godt turkart; dette er ikke et '
        'kontrollert Besseggen-spor. Malen går Gjendesheim → Memurubu, '
        'ikke båt inn og gange ut. Avklar retning, båttransport og billetter. '
        'Bratt og eksponert terreng; snø og is kan gjøre turen vesentlig vanskeligere.',
    stops: [
      (name: 'Gjendesheim (oppgitt)', lat: 61.4932, lon: 8.8145),
      (name: 'Veslfjellet (oppgitt)', lat: 61.5054, lon: 8.7412),
      (name: 'Besseggen (oppgitt)', lat: 61.5121, lon: 8.7180),
      (name: 'Memurubu (oppgitt)', lat: 61.4889, lon: 8.6315),
    ],
  ),
  LocalTour(
    id: 'local-finse-raggsteindalen',
    name: 'Finse til Raggsteindalen',
    municipality: 'Ulvik / Hol',
    region: 'Hallingskarvet',
    activity: TripActivity.ski,
    season: TripSeason.winter,
    months: [1, 2, 3, 4],
    durationDays: 1,
    accommodation: AccommodationType.dayHike,
    reportedDistanceKm: 16,
    reportedElevationGainMeters: 400,
    description: 'Planmal for fjellski mellom Finse og Raggsteindalen.',
    warning:
        'Ikke en kontrollert vintertrasé. Avklar aktuell kvisting, '
        'skredterreng, snøforhold og transport i begge ender. '
        'Oppgitte måneder er ikke en bekreftelse på trygge forhold.',
    stops: [
      (name: 'Finse stasjon (oppgitt)', lat: 60.6019, lon: 7.5036),
      (name: 'Finsefetene (oppgitt)', lat: 60.6212, lon: 7.5410),
      (name: 'Flakavassnutane, sadel (oppgitt)', lat: 60.6721, lon: 7.6250),
      (name: 'Raggsteindalen (oppgitt)', lat: 60.7045, lon: 7.7214),
    ],
  ),
  LocalTour(
    id: 'local-femunden-pulk',
    name: 'Femunden nord til sør',
    municipality: 'Røros / Engerdal',
    region: 'Femunden',
    activity: TripActivity.ski,
    carry: CarryMode.pulk,
    season: TripSeason.winter,
    months: [2, 3, 4],
    durationDays: 4,
    accommodation: AccommodationType.tent,
    reportedDistanceKm: 60,
    description: 'Planmal for en flerdagers skitur med pulk og telt.',
    warning:
        'Linjen kan krysse islagt vann. Appen vurderer ikke bæreevne '
        'eller trygg is, og årstid er ingen garanti. Innhent lokale is- og '
        'værforhold og planlegg alternativer på land. Camp-punktene og '
        'varigheten må kontrolleres; leirplassene er ikke anbefalte eller bekreftede.',
    stops: [
      (name: 'Synnervika (oppgitt)', lat: 62.4335, lon: 11.8741),
      (name: 'Camp 1, Røa (oppgitt)', lat: 62.3312, lon: 11.9610),
      (name: 'Camp 2, Elgå (oppgitt)', lat: 62.1678, lon: 11.9321),
      (name: 'Femundsenden (oppgitt)', lat: 61.8954, lon: 11.9124),
    ],
  ),
  LocalTour(
    id: 'local-fjorda-kano',
    name: 'Vannveien i Fjorda',
    municipality: 'Gran',
    region: 'Fjorda',
    activity: TripActivity.paddle,
    carry: CarryMode.canoe,
    season: TripSeason.summer,
    months: [5, 6, 7, 8, 9, 10],
    durationDays: 2,
    accommodation: AccommodationType.tent,
    reportedDistanceKm: 22,
    reportedElevationGainMeters: 0,
    description: 'Planmal for padling med overnatting. To dager er et foreslått planvalg.',
    warning:
        'Oppgitt som rundtur, men start og slutt er forskjellige. '
        'Linjen er ikke kontrollert mot vannveier og kan gå over land. '
        'Avklar bæringer, isett, tilgang, leirplasser og transport; '
        'leirplassene og utleiepunktet er ikke bekreftet.',
    stops: [
      (name: 'Vestland, isett (oppgitt)', lat: 60.4431, lon: 10.2745),
      (name: 'Bortøya (oppgitt)', lat: 60.4567, lon: 10.2912),
      (name: 'Flatøya (oppgitt)', lat: 60.4712, lon: 10.3150),
      (name: 'Velund (oppgitt)', lat: 60.4489, lon: 10.2612),
    ],
  ),

  // ── Nordmarka (Oslo) — kurerte forslag, punkter fra OSM ─────
  LocalTour(
    id: 'local-sognsvann-ullevalseter',
    name: 'Sognsvann – Ullevålseter',
    municipality: 'Oslo',
    region: 'Nordmarka',
    activity: TripActivity.foot,
    season: TripSeason.summer,
    months: [4, 5, 6, 7, 8, 9, 10],
    durationDays: 1,
    accommodation: AccommodationType.dayHike,
    reportedDistanceKm: 12,
    reportedElevationGainMeters: 150,
    provenance: LocalTour.curatedProvenance,
    description:
        'Planmal for den klassiske hytteturen fra Sognsvann T-bane til '
        'Ullevålseter, tur-retur. Turisthytta har kioskdrift i sesongen.',
    warning:
        'Punktene er verifisert mot OpenStreetMap, men linjen er rette '
        'strekninger mellom dem — ikke et sti-spor. Sjekk faktisk stinett '
        'og åpningstider på hytta selv.',
    returnSameWay: true,
    stops: [
      (name: 'Sognsvann stasjon (OSM)', lat: 59.9671, lon: 10.7340),
      (name: 'Ullevålseter (OSM)', lat: 60.0094, lon: 10.7113),
    ],
  ),
  LocalTour(
    id: 'local-frognerseteren-ullevalseter',
    name: 'Frognerseteren – Ullevålseter',
    municipality: 'Oslo',
    region: 'Nordmarka',
    activity: TripActivity.foot,
    season: TripSeason.summer,
    months: [4, 5, 6, 7, 8, 9, 10],
    durationDays: 1,
    accommodation: AccommodationType.dayHike,
    reportedDistanceKm: 8,
    reportedElevationGainMeters: 150,
    provenance: LocalTour.curatedProvenance,
    description:
        'Planmal for hytte-til-hytte-tur fra Frognerseteren via '
        'Skjennungstua og Tryvannstua til Ullevålseter.',
    warning:
        'Punktene er verifisert mot OpenStreetMap, men linjen er rette '
        'strekninger — ikke et sti-spor. Flere alternative stivalg finnes; '
        'velg trasé etter turkart.',
    stops: [
      (name: 'Frognerseteren stasjon (OSM)', lat: 59.9791, lon: 10.6766),
      (name: 'Tryvannstua (OSM)', lat: 59.9981, lon: 10.6683),
      (name: 'Skjennungstua (OSM)', lat: 60.0025, lon: 10.6911),
      (name: 'Ullevålseter (OSM)', lat: 60.0094, lon: 10.7113),
    ],
  ),
  LocalTour(
    id: 'local-vettakollen',
    name: 'Vettakollen utsiktspunkt',
    municipality: 'Oslo',
    region: 'Nordmarka',
    activity: TripActivity.foot,
    season: TripSeason.summer,
    months: [4, 5, 6, 7, 8, 9, 10],
    durationDays: 1,
    accommodation: AccommodationType.dayHike,
    reportedDistanceKm: 5,
    reportedElevationGainMeters: 200,
    provenance: LocalTour.curatedProvenance,
    description:
        'Planmal for en kort topptur til Vettakollen med utsikt over '
        'Oslo og fjorden, fra Sognsvann T-bane.',
    warning:
        'Kort, men delvis bratt tur. Linjen er rette strekninger mellom '
        'to punkter — følg merkede stier, ikke linjen.',
    returnSameWay: true,
    stops: [
      (name: 'Sognsvann stasjon (OSM)', lat: 59.9671, lon: 10.7340),
      (name: 'Vettakollen (OSM)', lat: 59.9765, lon: 10.6990),
    ],
  ),
  LocalTour(
    id: 'local-sognsvann-kikutstua',
    name: 'Sognsvann – Kikutstua (helg)',
    municipality: 'Oslo',
    region: 'Nordmarka',
    activity: TripActivity.foot,
    season: TripSeason.summer,
    months: [5, 6, 7, 8, 9],
    durationDays: 2,
    accommodation: AccommodationType.tent,
    reportedDistanceKm: 30,
    reportedElevationGainMeters: 400,
    provenance: LocalTour.curatedProvenance,
    description:
        'Planmal for en helgetur: Sognsvann via Bjørnholt til Kikutstua '
        'med teltovernatting, og retur samme vei.',
    warning:
        'Punktene er verifisert mot OpenStreetMap, men linjen er rette '
        'strekninger — ikke et sti-spor. Sjekk regler for telting i '
        'Nordmarka og om Kikutstua har servering når du drar.',
    returnSameWay: true,
    stops: [
      (name: 'Sognsvann stasjon (OSM)', lat: 59.9671, lon: 10.7340),
      (name: 'Bjørnholt (OSM)', lat: 60.0513, lon: 10.6888),
      (name: 'Kikutstua (OSM)', lat: 60.0764, lon: 10.6553),
    ],
  ),
  LocalTour(
    id: 'local-kikut-katnosdammen',
    name: 'Kikutstua – Katnosdammen',
    municipality: 'Oslo / Lunner',
    region: 'Nordmarka',
    activity: TripActivity.foot,
    season: TripSeason.summer,
    months: [5, 6, 7, 8, 9],
    durationDays: 2,
    accommodation: AccommodationType.tent,
    reportedDistanceKm: 15,
    reportedElevationGainMeters: 300,
    provenance: LocalTour.curatedProvenance,
    description:
        'Planmal for todagers tur fra Kikutstua via Sandungen til '
        'Katnosdammen i nordre Nordmarka.',
    warning:
        'Punktene er verifisert mot OpenStreetMap, men linjen er rette '
        'strekninger — ikke et sti-spor. Terrenget i nordre Nordmarka er '
        'myrlendt; regn med våte partier og planlegg teltplass nær vann.',
    stops: [
      (name: 'Kikutstua (OSM)', lat: 60.0764, lon: 10.6553),
      (name: 'Sandungen (OSM)', lat: 60.1208, lon: 10.6158),
      (name: 'Katnosdammen (OSM)', lat: 60.1474, lon: 10.5917),
    ],
  ),

  // ── Jotunheimen — kurerte tillegg ───────────────────────────
  LocalTour(
    id: 'local-glittertind-spiterstulen',
    name: 'Glittertind fra Spiterstulen',
    municipality: 'Lom',
    region: 'Jotunheimen',
    activity: TripActivity.foot,
    season: TripSeason.summer,
    months: [6, 7, 8, 9],
    durationDays: 1,
    accommodation: AccommodationType.cabin,
    reportedDistanceKm: 17,
    reportedElevationGainMeters: 1300,
    provenance: LocalTour.curatedProvenance,
    description:
        'Planmal for topptur til Glittertind (2457 moh) fra '
        'Spiterstulen, tur-retur. Ingen brekryssing på normalruta.',
    warning:
        'Punktene er verifisert mot OpenStreetMap, men linjen er rette '
        'strekninger — ikke et sti-spor. Lang dag i høyfjellet; vær kan '
        'endre raskt. Rute over breene mot toppen er steinete — kontroller '
        'aktuelle forhold.',
    returnSameWay: true,
    stops: [
      (name: 'Spiterstulen (OSM)', lat: 61.6258, lon: 8.4046),
      (name: 'Glittertind (OSM)', lat: 61.6513, lon: 8.5575),
    ],
  ),
  LocalTour(
    id: 'local-knutshoe',
    name: 'Knutshøe',
    municipality: 'Vågå',
    region: 'Jotunheimen',
    activity: TripActivity.foot,
    season: TripSeason.summer,
    months: [6, 7, 8, 9, 10],
    durationDays: 1,
    accommodation: AccommodationType.dayHike,
    reportedDistanceKm: 12,
    reportedElevationGainMeters: 550,
    provenance: LocalTour.curatedProvenance,
    description:
        'Planmal for ryggtraversen over Knutshøe ved Gjende — den '
        '"andre ryggen" i området, mindre trafikkert enn Besseggen.',
    warning:
        'Topppunktet er verifisert mot OpenStreetMap; startpunktet ved '
        'fv. 51 er omtrentlig plassert (ca.). Eksponert rygg, ikke egnet '
        'ved vått fjell eller sterk vind. Ikke for barn uten fjellvane.',
    returnSameWay: true,
    stops: [
      (name: 'Parkering fv. 51 (ca.)', lat: 61.4586, lon: 8.7518),
      (name: 'Knutshøe (OSM)', lat: 61.4800, lon: 8.7549),
    ],
  ),
  LocalTour(
    id: 'local-memurubu-gjendebu',
    name: 'Memurubu – Gjendebu',
    municipality: 'Vågå / Lom',
    region: 'Jotunheimen',
    activity: TripActivity.foot,
    season: TripSeason.summer,
    months: [6, 7, 8, 9],
    durationDays: 1,
    accommodation: AccommodationType.cabin,
    reportedDistanceKm: 10,
    reportedElevationGainMeters: 200,
    provenance: LocalTour.curatedProvenance,
    description:
        'Planmal for etappen langs nordsiden av Gjende fra Memurubu til '
        'Gjendebu, hytte til hytte.',
    warning:
        'Punktene er verifisert mot OpenStreetMap, men linjen er rette '
        'strekninger — ikke et sti-spor. Etappen går langs vannet og er '
        'utsatt for vær; sjekk båt/logistikk i begge ender (Gjendebåten).',
    stops: [
      (name: 'Memurubu (OSM)', lat: 61.4908, lon: 8.6310),
      (name: 'Gjendebu (OSM)', lat: 61.4514, lon: 8.4886),
    ],
  ),
];
