import 'package:flutter_test/flutter_test.dart';
import 'package:norgeskompasset/models/stage.dart';

void main() {
  test('shared tours use a three-step grade: Lett / Middels / Krevende', () {
    expect(DifficultyLevel.easy.gradeLabel, 'Lett');
    expect(DifficultyLevel.moderate.gradeLabel, 'Middels');
    expect(DifficultyLevel.challenging.gradeLabel, 'Krevende');
    expect(DifficultyLevel.demanding.gradeLabel, 'Krevende');
  });
}
