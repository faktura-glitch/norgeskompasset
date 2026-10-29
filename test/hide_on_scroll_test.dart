import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:norgeskompasset/widgets/app_shell.dart';

void main() {
  testWidgets(
    'menyene skjules ved scroll ned og kommer tilbake ved scroll opp',
    (tester) async {
      final nav = NavController();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: nav,
          child: MaterialApp(
            home: HideOnScrollScaffold(
              appBar: AppBar(title: const Text('Turer')),
              body: ListView(
                children: [
                  for (var i = 0; i < 60; i++) ListTile(title: Text('Tur $i')),
                ],
              ),
            ),
          ),
        ),
      );
      double listTop() => tester.getTopLeft(find.byType(ListView)).dy;

      expect(nav.chromeVisible.value, isTrue);
      expect(listTop(), kToolbarHeight);

      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(nav.chromeVisible.value, isFalse);
      expect(listTop(), 0);

      await tester.drag(find.byType(ListView), const Offset(0, 100));
      await tester.pumpAndSettle();
      expect(nav.chromeVisible.value, isTrue);
      expect(listTop(), kToolbarHeight);
    },
  );

  testWidgets('kort liste som ikke kan scrolles skjuler ikke menyene', (
    tester,
  ) async {
    final nav = NavController();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: nav,
        child: MaterialApp(
          home: HideOnScrollScaffold(
            appBar: AppBar(title: const Text('Pakkeliste')),
            body: ListView(children: const [ListTile(title: Text('Telt'))]),
          ),
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(nav.chromeVisible.value, isTrue);
  });

  test('tabbytte viser menyene igjen', () {
    final nav = NavController();
    nav.chromeVisible.value = false;
    nav.goTo(3);
    expect(nav.chromeVisible.value, isTrue);
  });
}
