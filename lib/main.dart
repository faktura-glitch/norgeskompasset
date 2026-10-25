import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/trip_repository.dart';
import 'state/app_state.dart';
import 'widgets/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('nb_NO');
  var firebaseReady = false;
  if (DefaultFirebaseOptions.isConfigured) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      firebaseReady = true;
      // Crashlytics: send fatal Flutter and platform errors. It is a
      // no-op on platforms the plugin doesn't support (Windows/web).
      try {
        FlutterError.onError =
            FirebaseCrashlytics.instance.recordFlutterFatalError;
        PlatformDispatcher.instance.onError = (error, stack) {
          FirebaseCrashlytics.instance.recordError(
            error,
            stack,
            fatal: true,
          );
          return true;
        };
      } catch (_) {
        // Crash reporting is best-effort; never block startup.
      }
    } catch (_) {
      firebaseReady = false; // surface honest error on login screen
    }
  }
  final repo = TripRepository();
  final appState = AppState(repo);
  await appState.init();
  runApp(NorgesKompassetApp(appState: appState, firebaseReady: firebaseReady));
}

class NorgesKompassetApp extends StatelessWidget {
  final AppState appState;
  final bool firebaseReady;
  const NorgesKompassetApp({
    super.key,
    required this.appState,
    this.firebaseReady = false,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider(create: (_) => NavController()),
      ],
      child: Selector<AppState, (ThemeMode, bool)>(
        selector: (_, state) => (state.themeMode, state.localOnly),
        builder: (context, settings, _) => MaterialApp(
          title: 'NorgesKompasset',
          debugShowCheckedModeBanner: false,
          theme: NkTheme.build(),
          darkTheme: NkTheme.buildDark(),
          themeMode: settings.$1,
          // Surface colors live in NkColors statics — sync them with
          // the resolved brightness before the widget tree builds.
          builder: (context, child) {
            NkColors.dark = Theme.of(context).brightness == Brightness.dark;
            return child!;
          },
          locale: const Locale('nb', 'NO'),
          supportedLocales: const [Locale('nb', 'NO'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: settings.$2
              ? const _BusyWatcher(child: _OnboardingGate(child: AppShell()))
              : !firebaseReady
              ? const _BusyWatcher(
                  child: LoginScreen(
                    configError:
                        'Firebase er ikke konfigurert ennå – kjør '
                        '"flutterfire configure" eller lim inn nøklene '
                        'i lib/firebase_options.dart.',
                  ),
                )
              : StreamBuilder<User?>(
                  stream: FirebaseAuth.instance.authStateChanges(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snap.hasData) {
                      // Attach Firestore sync to this user (once).
                      return _AccountGate(
                        key: ValueKey(snap.data!.uid),
                        uid: snap.data!.uid,
                      );
                    }
                    return const _AccountGate(
                      key: ValueKey('signed-out'),
                      uid: null,
                    );
                  },
                ),
        ),
      ),
    );
  }
}

/// Shows the first-run onboarding cards once, then the app shell.
class _AccountGate extends StatefulWidget {
  final String? uid;
  const _AccountGate({super.key, required this.uid});

  @override
  State<_AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends State<_AccountGate> {
  late Future<void> _ready;

  @override
  void initState() {
    super.initState();
    _ready = context.read<AppState>().syncWithCloud(widget.uid);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _ready,
    builder: (_, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Kunne ikke åpne lokale kontodata. Ingen data er slettet.',
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _ready = context.read<AppState>().syncWithCloud(widget.uid);
                  }),
                  child: const Text('Prøv igjen'),
                ),
              ],
            ),
          ),
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return widget.uid == null
          ? const _BusyWatcher(child: LoginScreen())
          : const _BusyWatcher(child: _OnboardingGate(child: AppShell()));
    },
  );
}

class _OnboardingGate extends StatefulWidget {
  final Widget child;
  const _OnboardingGate({required this.child});

  @override
  State<_OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<_OnboardingGate> {
  late bool _seen;

  @override
  void initState() {
    super.initState();
    _seen = context.read<AppState>().onboardingSeen;
  }

  @override
  Widget build(BuildContext context) {
    if (_seen) return widget.child;
    return OnboardingScreen(
      onDone: () {
        context.read<AppState>().markOnboardingSeen();
        context.read<NavController>().goTo(2);
        setState(() => _seen = true);
      },
    );
  }
}

/// Global busy/error surface driven by AppState.
class _BusyWatcher extends StatelessWidget {
  final Widget child;
  const _BusyWatcher({required this.child});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // Surface errors once as a snackbar.
    if (state.lastError != null) {
      final msg = state.lastError!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
        state.lastError = null;
      });
    }
    return Stack(
      children: [
        child,
        if (state.busy)
          Container(
            color: Colors.black26,
            child: Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      const SizedBox(width: 14),
                      Text(state.busyLabel ?? 'Arbeider…'),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
