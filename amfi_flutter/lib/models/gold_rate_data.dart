class GoldRateData {
  final String symbol;
  final double bid;
  final double ask;
  final double high;
  final double low;
  final String info;

  GoldRateData({
    required this.symbol,
    required this.bid,
    required this.ask,
    required this.high,
    required this.low,
    required this.info,
  });

  factory GoldRateData.fromRawLine(String line) {
    // Split by tabs or multiple spaces
    final parts = line.trim().split(RegExp(r'\s{2,}|\t'));
    if (parts.length < 6) {
      // Fallback for smaller lines
      final simpleParts = line.trim().split(RegExp(r'\s+'));
      if (simpleParts.length >= 6) {
         // ID is first, Symbol might be multiple words if split by single space
         // This is tricky. Let's try to be smart.
      }
    }

    // Based on the observed output:
    // ID [tab] Symbol [tab] Bid [tab] Ask [tab] High [tab] Low [tab] Info
    String sym = parts.length > 1 ? parts[1] : 'Unknown';
    double b = parts.length > 2 ? _toDouble(parts[2]) : 0;
    double a = parts.length > 3 ? _toDouble(parts[3]) : 0;
    double h = parts.length > 4 ? _toDouble(parts[4]) : 0;
    double l = parts.length > 5 ? _toDouble(parts[5]) : 0;
    String inf = parts.length > 6 ? parts[6] : '';

    return GoldRateData(symbol: sym, bid: b, ask: a, high: h, low: l, info: inf);
  }

  static double _toDouble(String val) {
    return double.tryParse(val.replaceAll(',', '')) ?? 0;
  }
}
