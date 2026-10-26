/// An arrangement from the NorgesKompasset tour calendar (Wix Events on
/// norgeskompasset.no), delivered by the `events` Cloud Function.
enum EventKind { tur, treff, camp }

extension EventKindX on EventKind {
  String get label => switch (this) {
    EventKind.tur => 'Tur',
    EventKind.treff => 'Treff',
    EventKind.camp => 'Camp',
  };
}

class CalendarEvent {
  final String id;
  final String title;
  final String description;
  final DateTime start;
  final DateTime? end;
  final String? formatted;
  final String? locationName;
  final String? address;
  final double? lat;
  final double? lon;
  final String? image;
  final String url;
  final double? price;
  final String? currency;
  final bool soldOut;
  final bool? registrationOpen;

  const CalendarEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.start,
    required this.url,
    this.end,
    this.formatted,
    this.locationName,
    this.address,
    this.lat,
    this.lon,
    this.image,
    this.price,
    this.currency,
    this.soldOut = false,
    this.registrationOpen,
  });

  bool get multiDay =>
      end != null &&
      DateTime(end!.year, end!.month, end!.day) !=
          DateTime(start.year, start.month, start.day);

  bool get isPast => (end ?? start).isBefore(DateTime.now());

  /// Rough grouping for the filter chips — inferred from the title so
  /// the website needs no extra fields.
  EventKind get kind {
    final t = title.toLowerCase();
    if (t.contains('treff') ||
        t.contains('tacobuffet') ||
        t.contains('sauna')) {
      return EventKind.treff;
    }
    if (t.contains('camp') || t.contains('samling')) return EventKind.camp;
    return EventKind.tur;
  }

  String get priceLabel {
    if (price == null) return '';
    if (price == 0) return 'Gratis';
    final rounded = price!.round();
    return 'fra $rounded ${currency == null || currency == 'NOK' ? 'kr' : currency}';
  }

  String get place => [
    if (locationName != null && locationName!.isNotEmpty) locationName!,
    if (address != null && address!.isNotEmpty) address!,
  ].join(', ');

  static CalendarEvent? fromJson(Map<String, dynamic> j) {
    final start = DateTime.tryParse(j['start'] as String? ?? '');
    if (start == null) return null;
    double? toD(dynamic v) => v is num ? v.toDouble() : null;
    return CalendarEvent(
      id: j['id'] as String? ?? j['url'] as String? ?? '',
      title: j['title'] as String? ?? '',
      description: j['description'] as String? ?? '',
      start: start.toLocal(),
      end: DateTime.tryParse(j['end'] as String? ?? '')?.toLocal(),
      formatted: j['formatted'] as String?,
      locationName: j['locationName'] as String?,
      address: j['address'] as String?,
      lat: toD(j['lat']),
      lon: toD(j['lon']),
      image: j['image'] as String?,
      url: j['url'] as String? ?? 'https://www.norgeskompasset.no/turer',
      price: toD(j['price']),
      currency: j['currency'] as String?,
      soldOut: j['soldOut'] == true,
      registrationOpen: j['registrationOpen'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'start': start.toUtc().toIso8601String(),
    if (end != null) 'end': end!.toUtc().toIso8601String(),
    if (formatted != null) 'formatted': formatted,
    if (locationName != null) 'locationName': locationName,
    if (address != null) 'address': address,
    if (lat != null) 'lat': lat,
    if (lon != null) 'lon': lon,
    if (image != null) 'image': image,
    'url': url,
    if (price != null) 'price': price,
    if (currency != null) 'currency': currency,
    'soldOut': soldOut,
    if (registrationOpen != null) 'registrationOpen': registrationOpen,
  };
}
