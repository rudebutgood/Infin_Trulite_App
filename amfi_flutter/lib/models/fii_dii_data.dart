class FiiDiiData {
  final String date;
  final String category;
  final double buyValue;
  final double sellValue;
  final double netValue;

  FiiDiiData({
    required this.date,
    required this.category,
    required this.buyValue,
    required this.sellValue,
    required this.netValue,
  });

  factory FiiDiiData.fromJson(Map<String, dynamic> json) {
    return FiiDiiData(
      date: json['date'] ?? '',
      category: json['category'] ?? '',
      buyValue: _toDouble(json['buyValue']),
      sellValue: _toDouble(json['sellValue']),
      netValue: _toDouble(json['netValue']),
    );
  }

  static double _toDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) {
      return double.tryParse(val.replaceAll(',', '')) ?? 0.0;
    }
    return 0.0;
  }
}
