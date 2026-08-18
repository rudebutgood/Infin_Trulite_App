class GiftNiftyData {
  final String symbol;
  final String expiryDate;
  final double lastPrice;
  final double dayChange;
  final double percentChange;
  final String timestamp;
  final Map<String, dynamic> rawData;

  GiftNiftyData({
    required this.symbol,
    required this.expiryDate,
    required this.lastPrice,
    required this.dayChange,
    required this.percentChange,
    required this.timestamp,
    required this.rawData,
  });

  factory GiftNiftyData.fromJson(Map<String, dynamic> json) {
    return GiftNiftyData(
      symbol: json['SYMBOL'] ?? '',
      expiryDate: json['EXPIRYDATE'] ?? '',
      lastPrice: _toDouble(json['LASTPRICE']),
      dayChange: _toDouble(json['DAYCHANGE_1'] ?? json['DAYCHANGE']),
      percentChange: _toDouble(json['PERCHANGE']),
      timestamp: json['TIMESTMP'] ?? '',
      rawData: json,
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
