class IndexData {
  final String name;
  final double last;
  final double variation;
  final double percentChange;

  IndexData({
    required this.name,
    required this.last,
    required this.variation,
    required this.percentChange,
  });

  factory IndexData.fromJson(Map<String, dynamic> json) {
    return IndexData(
      name: json['index'] ?? '',
      last: _toDouble(json['last']),
      variation: _toDouble(json['variation']),
      percentChange: _toDouble(json['percentChange']),
    );
  }

  static double _toDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val.replaceAll(',', '')) ?? 0.0;
    return 0.0;
  }
}
