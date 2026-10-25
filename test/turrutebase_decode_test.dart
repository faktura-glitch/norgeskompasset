import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:norgeskompasset/services/turrutebase_service.dart';

void main() {
  test('decodes Geonorge responses despite the odd GML content-type', () {
    const xml = '<?xml version="1.0" encoding="UTF-8"?><a>Skiløype</a>';
    final res = http.Response.bytes(
      utf8.encode(xml),
      200,
      headers: {'content-type': 'text/xml; subtype=gml/3.2.1;charset=UTF-8'},
    );
    // The stock accessor chokes on `subtype=gml/3.2.1`.
    expect(() => res.body, throwsFormatException);
    expect(TurrutebaseService.bodyText(res), xml);
  });
}
