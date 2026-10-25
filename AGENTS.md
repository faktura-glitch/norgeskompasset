# NorgesKompasset — agent notes

Flutter app (Dart 3.13 / Flutter 3.47). Targets: Windows desktop + Web.

## Commands
- Analyze: `flutter analyze`
- Test:    `flutter test`
- Run:     `flutter run -d windows` (desktop) or `flutter run -d chrome` (web)
- Build:   `flutter build windows --release` / `flutter build web --release`

## External services (all free, no keys)
- Weather: MET Norway Locationforecast 2.0 compact (`api.met.no`) — needs
  User-Agent on native; ~9-day horizon, code handles beyond-horizon honestly.
- Elevation: OpenTopoData `mapzen` dataset (100 pts/req, ~1 req/s).
- Trail routing: BRouter public instance (`brouter.de`,
  `hiking-mountain` profile) → GeoJSON; falls back to straight-line
  `RouteSource.estimated`. Never present estimated routes as verified.
- Place search: OSM Nominatim (`countrycodes=no`).
- Tiles: Kartverket topo cache + OpenTopoMap + OSM fallbacks.
- Avalanche: Varsom/NVE (`api01.nve.no` v6.3.0,
  `AvalancheWarningByCoordinates/Simple/{lat}/{lon}/1/{from}/{to}` —
  lat first, langkey 1 = Norwegian). Returns literal `null` outside
  the warning season; attribution to varsom.no is required.

## Architecture
- `lib/models/` — plain-Dart models with toJson/fromJson.
- `lib/models/gear.dart` + `lib/services/gear_catalog.dart` — rule-based
  packing matrix: each catalog entry carries strict include/exclude rules
  (activity, carry, accommodation, season, temperature gates, weather,
  dog/comfort). `PackingEngine` derives `TripConditions` and filters the
  catalog; `packingPresets` only set trip parameters.
- `lib/services/` — external APIs + packing/meal/recommendation engines.
- `lib/state/app_state.dart` — Provider ChangeNotifier; all screens mutate
  the shared `currentTrip`; persistence via Hive (`TripRepository`).
- `lib/screens/` — one file per screen; responsive via `context.isWide`.
- Navigation: AppShell with 5 tabs (Hjem/Turer/Kart/Pakking/Mer); detail
  screens pushed on the root navigator.

## Conventions
- Norwegian UI strings (nb_NO locale).
- Safety rule: never fabricate weather/elevation/GPS/route data; label
  estimates; recommendations must cite observed data and stay honest about
  forecast limits.
