import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:norgeskompasset/models/trip.dart';
import 'package:norgeskompasset/screens/trips_screen.dart';
import 'package:norgeskompasset/services/trip_repository.dart';
import 'package:norgeskompasset/state/app_state.dart';
import 'package:norgeskompasset/widgets/app_shell.dart';
import 'package:provider/provider.dart';

void main() {
  /// Pump a bounded number of frames — avoids pumpAndSettle hanging on
  /// the snackbar's own timer.
  Future<void> pumpFrames(WidgetTester tester, [int frames = 15]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('undo restores a deleted trip and the snackbar goes away', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final state = AppState(TripRepository())
      ..trips = [Trip(id: 'a', name: 'Helgetur')];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider(create: (_) => NavController()),
        ],
        child: const MaterialApp(home: TripsScreen()),
      ),
    );
    await pumpFrames(tester);
    expect(find.text('Helgetur'), findsOneWidget);

    // Open the trip menu, confirm deletion.
    await tester.tap(find.text('Flere valg'));
    await pumpFrames(tester);
    await tester.tap(find.text('Slett tur'));
    await pumpFrames(tester);
    await tester.tap(find.text('Slett'));
    await pumpFrames(tester);

    expect(state.trips, isEmpty);
    expect(find.text('«Helgetur» er slettet'), findsOneWidget);

    // Pressing Angre restores the trip and dismisses the snackbar.
    await tester.tap(find.text('Angre'));
    await pumpFrames(tester);

    expect(state.trips.map((t) => t.id), contains('a'));
    expect(find.text('Helgetur'), findsOneWidget);
    expect(find.text('«Helgetur» er slettet'), findsNothing);
    expect(find.text('Angre'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the undo snackbar is shown even after the tile unmounts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final state = AppState(TripRepository())
      ..trips = [Trip(id: 'a', name: 'Helgetur')];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider(create: (_) => NavController()),
        ],
        child: const MaterialApp(home: TripsScreen()),
      ),
    );
    await pumpFrames(tester);

    await tester.tap(find.text('Flere valg'));
    await pumpFrames(tester);
    await tester.tap(find.text('Slett tur'));
    await pumpFrames(tester);
    await tester.tap(find.text('Slett'));
    // Let the rebuild run — the deleted tile is now unmounted —
    // the snackbar must still appear.
    await pumpFrames(tester);
    expect(find.text('«Helgetur» er slettet'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    await pumpFrames(tester);
    expect(find.text('Angre'), findsNothing);
    expect(find.text('«Helgetur» er slettet'), findsNothing);
    expect(state.trips, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
