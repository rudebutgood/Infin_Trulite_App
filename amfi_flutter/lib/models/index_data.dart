class IndexData {
  final String name;
  final double last;
  final double variation;
  final double percentChange;
  final double? perChange30d;
  final double? perChange365d;
  final double? yearHigh;
  final double? yearLow;
  final double? pe;
  final double? pb;
  final Map<String, dynamic> rawData;

  IndexData({
    required this.name,
    required this.last,
    required this.variation,
    required this.percentChange,
    this.perChange30d,
    this.perChange365d,
    this.yearHigh,
    this.yearLow,
    this.pe,
    this.pb,
    required this.rawData,
  });

  double? get diffFromYearHigh {
    if (yearHigh == null || yearHigh == 0) return null;
    return ((last - yearHigh!) / yearHigh!) * 100;
  }

  factory IndexData.fromJson(Map<String, dynamic> json) {
    return IndexData(
      name: json['index'] ?? '',
      last: _toDouble(json['last']),
      variation: _toDouble(json['variation']),
      percentChange: _toDouble(json['percentChange']),
      perChange30d: _toDoubleOrNull(json['perChange30d']),
      perChange365d: _toDoubleOrNull(json['perChange365d']),
      yearHigh: _toDoubleOrNull(json['yearHigh']),
      yearLow: _toDoubleOrNull(json['yearLow']),
      pe: _toDoubleOrNull(json['pe']),
      pb: _toDoubleOrNull(json['pb']),
      rawData: json,
    );
  }

  static double _toDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val.replaceAll(',', '')) ?? 0.0;
    return 0.0;
  }

  static double? _toDoubleOrNull(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val.replaceAll(',', ''));
    return null;
  }
}
