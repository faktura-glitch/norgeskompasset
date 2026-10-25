import 'dart:io';

/// True when running under `flutter test` — the test runner sets the
/// FLUTTER_TEST environment variable. Used to swap network map tiles
/// for inert placeholders, since tests must not hit tile servers.
bool isFlutterTest() => Platform.environment.containsKey('FLUTTER_TEST');
