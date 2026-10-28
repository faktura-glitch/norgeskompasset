# NorgesKompasset – forbedringsplan for SWE-2

Gjennomgang 25.10.2026 av koden i `C:\Users\stubb\tur planlegger` (siste commit `d2528ec`).
Hver oppgave er selvstendig. Gjør én oppgave per commit, i rekkefølgen under.

## Regler for alle oppgaver
- All tekst i appen skal være på norsk (bokmål). Bruk `fmtCount()` fra `lib/core/format.dart` for entall/flertall.
- Ikke finn på vær-, høyde-, GPS- eller rutedata. Merk estimater tydelig som estimater.
- Eksterne HTTP-kall skal bruke `kUserAgent` fra `lib/core/http_identity.dart` (ikke på web).
- Kjør `flutter analyze` (0 problemer) og `flutter test` (alle grønne) før hver commit. Legg til tester for ny logikk.
- Ikke publiser `firestore.rules` (`firebase deploy`) uten at Magnus godkjenner det.
- Ikke push eller merge uten at Magnus ber om det.

---

## A. Må på plass før lansering

### A1. Slett konto i appen
**Hvorfor:** Google Play og App Store krever at brukere kan slette kontoen sin i appen. I dag finnes bare «Logg ut».
**Filer:** `lib/services/auth_service.dart`, `lib/services/trip_repository.dart`, `lib/state/app_state.dart`, `lib/screens/more_screen.dart` (seksjonen «Data og personvern»).
**Gjør:**
1. Legg til «Slett konto» under «Data og personvern». Vis en bekreftelsesdialog som forklarer at alle turer i skyen, delte turer og publiserte katalogturer slettes.
2. Slett i denne rekkefølgen: `users/{uid}/trips/*`, `sharedTrips` og `catalogTrips` der brukeren er eier, `users/{uid}`, og til slutt `FirebaseAuth.currentUser.delete()`.
3. Feilen `requires-recent-login`: be brukeren skrive inn passordet på nytt (`reauthenticateWithCredential`), og prøv igjen.
4. Spør om lokale turer på enheten skal beholdes (lokal modus) eller slettes.
**Ferdig når:** En testkonto kan slettes helt, ingen dokumenter blir liggende igjen i Firestore, og appen går tilbake til innloggingsskjermen.

### A2. «Ute av rute»-varsel som faktisk varsler
**Hvorfor:** Introduksjonen lover «få varsel hvis du kommer ut av ruten». Avviket sjekkes i dag bare i `hiking_screen.dart` (`_offRouteMeters = 80`), og varselet er bare et rødt banner. Det virker ikke når skjermen er av eller brukeren er i en annen fane.
**Filer:** `lib/services/tracking_controller.dart`, `lib/screens/hiking_screen.dart`, `pubspec.yaml`.
**Gjør:**
1. Flytt avviksberegningen inn i `TrackingController`, som allerede kjører med forgrunnstjeneste på Android.
2. Ved avvik (2 målinger på rad over 80 m): vibrer og vis en lokal varsling (`flutter_local_notifications`) med teksten «Du ser ut til å være ute av ruten (X m)». Maks ett varsel per 5 minutter. Banneret i turmodus beholdes.
3. Legg til en av/på-bryter for varselet i turmodus.
4. Er dette ikke mulig på en plattform (web eller iOS uten bakgrunnstillatelse), skal introduksjonsteksten i `onboarding_screen.dart` ikke love varsel der.
**Ferdig når:** Enhetstest av avvikslogikken i `TrackingController` med syntetiske posisjoner, og manuell test på Android med skjermen av.

### A3. Turkatalogen: moderering eller skjul
**Hvorfor:** `catalogTrips` kan leses av alle innloggede og publiseres av alle. Det finnes ingen rapportering, moderering eller grense på feltene. Det gir risiko for støtende innhold og for at noen publiserer startpunkt ved hjemmet sitt.
**Filer:** `lib/screens/trips_screen.dart` («Publiser i turkatalogen»), `lib/state/app_state.dart` (`publishTripToCatalog`), `firestore.rules`.
**Gjør (anbefalt minimum):**
1. Vis en advarsel før publisering: «Ruten og startpunktet blir synlig for alle brukere.»
2. Legg til «Rapporter tur» på katalogturer, som skriver til en ny samling `reports` (bare `create` tillatt).
3. Valider feltene i reglene (lengde på navn og beskrivelse, maks antall punkter, påkrevde felt).
**Alternativ:** Skjul «Publiser i turkatalogen» bak et flagg til moderering finnes.

### A4. Krasjrapportering
**Gjør:** Legg til Firebase Crashlytics (bare Android og iOS). Nevn det i «Data og personvern» med en av/på-bryter.
**Ferdig når:** En testkrasj vises i Firebase-konsollen for `norges-kompasset-pro`.

---

## B. Forenkle og ta bort

### B1. Bjella på Hjem er misvisende
I `home_screen.dart` (rundt linje 117) viser `Icons.notifications_outlined` en bjelle, men den åpner `RecommendationsScreen`. Brukere forventer varsler når de ser en bjelle.
**Gjør:** Fjern knappen. Anbefalingene vises allerede under «Viktige endringer og oppgaver» med lenken «Se alle anbefalinger». Alternativt kan du bytte til `Icons.lightbulb_outline`.

### B2. Én liste med oppgaver, ikke tre
Det samme vises i dag tre steder: kort under «Viktige endringer og oppgaver», punktlisten under (Pakk sekken, Hent værprognose …) og skjermen «Smarte anbefalinger».
**Gjør:** Slå kortene og punktlisten sammen til én liste sortert etter viktighet. Vis maks 3 på Hjem og resten bak «Se alle». Et punkt som er det samme som hovedknappen på turkortet (for eksempel «Sett datoer»), skal ikke vises i listen.

### B3. Rydd i Mer-fanen
Under «Turverktøy» ligger Vær, Smarte anbefalinger, Matplan, Del tur og sikkerhet, Turmodus og Turevaluering. Alle hører til den valgte turen.
**Gjør:** Vis disse som snarveier på turkortet på Hjem (en rad med ikoner). La Mer bare inneholde konto, profil, innstillinger, kartbuffer og «Data og personvern».

### B4. Kortere meny under «Flere valg» på Turer
`trips_screen.dart` har opptil 8 valg i én meny.
**Gjør:** Del menyen i grupper med skillelinje: **Del** (Del med turkode / Slutt å dele, Turkort og sikkerhet), **Tur** (Dupliser, Evaluer) og **Farlig** (Slett tur, i rødt nederst).

### B5. Sperr tur der start og mål er samme punkt
I dag lages en tur på «0.0 km», og steget «Rute» blir markert som ferdig.
**Gjør:** I `map_planner_screen.dart` `_calculateRoute()`: hvis start og mål ligger under 30 m fra hverandre og det ikke finnes via-punkter, vis «Start og mål er samme sted – velg et mål et annet sted, eller legg til via-punkter for en rundtur.» Ikke lag noen tur. I `home_screen.dart` skal «Rute» bare regnes som ferdig når `distanceMeters > 0`.

### B6. Kortere profilskjema
«Min profil» i `more_screen.dart` har 7 seksjoner på én side.
**Gjør:** Vis bare Navn, Turnivå og Nødkontakt først. Legg resten (kosthold, utstyr, sesong, turstil) under «Mer om deg (valgfritt)», som er lukket til brukeren åpner den.

---

## C. Legge til

### C1. «Beste dag å gå»
Bruk MET-prognosen (finnes allerede i `weather_service.dart`) for de neste dagene ved høyeste punkt på ruten. Ranger dagene etter vind, nedbør og temperatur.
**Vis:** «Tirsdag ser best ut: 4 m/s, opphold, 6 °C på toppen.» Vis bare det prognosen faktisk dekker, og skriv at prognoser lenger fram enn 2–3 dager er usikre.
**Ferdig når:** Det finnes enhetstest av rangeringen med faste prognosedata.

### C2. Forventet hjemkomst og påminnelse
1. Legg til feltet «Hjemme senest» (dato og klokkeslett) på turen. Ta det med i turkortet som deles fra `safety_screen.dart`.
2. Hvis turmodus fortsatt er aktivt 30 min etter dette tidspunktet: vis en lokal varsling til brukeren selv: «Er du trygt hjemme? Gi beskjed til de som venter.»
**Ikke** send automatisk varsel til nødkontakt. Det krever en server og må avklares med Magnus først.

### C3. Del tur som lenke
Turkode krever at mottakeren har appen. Lag en enkel nettside (Firebase Hosting) som viser rute, datoer og forventet hjemkomst for en turkode. Turkortet deler da en lenke som også fungerer for pårørende uten appen. Krever at reglene for `sharedTrips` vurderes på nytt, siden lesing i dag krever innlogging. Avklar med Magnus før du starter.

### C4. Logg inn med Google (og Apple på iOS)
I dag finnes bare e-post og passord (`auth_service.dart`). Innlogging med Google gir mindre friksjon. Apple-innlogging er påkrevd på iOS hvis Google tilbys der.

### C5. Dagslys i tidsestimatet
Sjekk først om dette finnes fra før. Hvis ikke: vis solnedgang for startdatoen og varsle hvis estimert sluttid er etter solnedgang: «Du er beregnet ferdig 19:40 – sola går ned 18:05.»

---

## Foreslått rekkefølge
A1 → B5 → B1 → B2 → A2 → B3 → B4 → B6 → C1 → C2 → A3 → A4 → C4 → C5 → C3
