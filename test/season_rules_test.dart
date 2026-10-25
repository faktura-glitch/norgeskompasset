import 'package:flutter_test/flutter_test.dart';
import 'package:norgeskompasset/models/profile.dart';
import 'package:norgeskompasset/models/trip.dart';
import 'package:norgeskompasset/models/weather.dart';
import 'package:norgeskompasset/services/planning_context.dart';

Trip _trip(DateTime start, int days) => Trip(
  id: 't',
  startDate: start,
  endDate: start.add(Duration(days: days - 1)),
)..accommodation = AccommodationType.tent;

void main() {
  test('fire ban and leash law notes follow the trip dates', () {
    final july = _trip(DateTime(2026, 7, 10), 3)..withDog = true;
    final checks = PlanningContextBuilder.forTrip(
      july,
      UserProfile(),
    ).userChecks;
    expect(checks.any((c) => c.contains('bålforbud')), isTrue);
    expect(checks.any((c) => c.contains('Båndtvang')), isTrue);

    final february = _trip(DateTime(2026, 2, 10), 3)..withDog = true;
    final winter = PlanningContextBuilder.forTrip(
      february,
      UserProfile(),
    ).userChecks;
    expect(winter.any((c) => c.contains('bålforbud')), isFalse);
    expect(winter.any((c) => c.contains('Båndtvang')), isFalse);

    // A trip straddling the start of the ban still gets the note.
    expect(
      tripOverlapsPeriod(
        _trip(DateTime(2026, 4, 13), 4),
        startMonth: 4,
        startDay: 15,
        endMonth: 9,
        endDay: 15,
      ),
      isTrue,
    );
    // Day hikes without a dog get neither.
    final dayHike = _trip(DateTime(2026, 7, 10), 1)
      ..accommodation = AccommodationType.dayHike;
    final dayChecks = PlanningContextBuilder.forTrip(
      dayHike,
      UserProfile(),
    ).userChecks;
    expect(dayChecks.any((c) => c.contains('bålforbud')), isFalse);
    // No dates → no rule is asserted.
    expect(
      tripOverlapsPeriod(
        Trip(id: 'x'),
        startMonth: 4,
        startDay: 15,
        endMonth: 9,
        endDay: 15,
      ),
      isFalse,
    );
  });

  test('feels-like uses the wind-chill formula only when it applies', () {
    // -5 °C at 10 m/s (36 km/h) ≈ -13.7 °C.
    expect(feelsLikeC(-5, 10), closeTo(-13.7, 0.2));
    // Warm or calm: unchanged.
    expect(feelsLikeC(15, 10), 15);
    expect(feelsLikeC(-5, 0.5), -5);
    expect(feelsLikeC(null, 5), isNull);
  });
}
