import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:norgeskompasset/services/tile_cache.dart';

void main() {
  test('tile prefetch only reports progress after caching the tile', () async {
    final directory = await Directory.systemTemp.createTemp('nk-tiles-');
    try {
      Hive.init(directory.path);
      await TileCache.init();
      final urls = [
        'https://tiles.test/first.png',
        'https://tiles.test/second.png',
      ];
      final progress = <int>[];
      final client = MockClient((request) async {
        return http.Response.bytes([1, 2, 3], 200);
      });
      try {
        final fetched = await TileCache.prefetch(
          urls,
          client: client,
          onProgress: (done, total) {
            progress.add(done);
            expect(total, 2);
            expect(
              urls.where(TileCache.isCached).length,
              greaterThanOrEqualTo(done),
              reason: 'reported progress must represent persisted tiles',
            );
          },
        );
        expect(fetched, 2);
        expect(progress, [1, 2]);
      } finally {
        client.close();
      }
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
}
