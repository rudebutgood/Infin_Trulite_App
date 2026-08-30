import 'index_data.dart';

class FactorPerformanceData {
  final String factorName;
  final String indexName;
  final double dayReturn;
  final double weekReturn;
  final double oneMonthReturn;
  final double oneYearReturn;
  final double? pe;
  final double? pb;
  final double? dy;
  final double? yearHigh;
  final double? yearLow;
  final double last;
  final double variation;
  final Map<String, dynamic> rawData;
  final String description;

  FactorPerformanceData({
    required this.factorName,
    required this.indexName,
    required this.dayReturn,
    required this.weekReturn,
    required this.oneMonthReturn,
    required this.oneYearReturn,
    this.pe,
    this.pb,
    this.dy,
    this.yearHigh,
    this.yearLow,
    required this.last,
    required this.variation,
    required this.rawData,
    required this.description,
  });

  factory FactorPerformanceData.fromIndexData(IndexData data, String factorName, String description) {
    final last = data.last;
    final oneWeekAgoVal = _toDouble(data.rawData['oneWeekAgoVal']);
    final weekReturn = (oneWeekAgoVal > 0) ? ((last - oneWeekAgoVal) / oneWeekAgoVal * 100) : 0.0;
    
    return FactorPerformanceData(
      factorName: factorName,
      indexName: data.name,
      dayReturn: data.percentChange,
      weekReturn: weekReturn,
      oneMonthReturn: data.perChange30d ?? 0.0,
      oneYearReturn: data.perChange365d ?? 0.0,
      pe: data.pe,
      pb: data.pb,
      dy: _toDoubleOrNull(data.rawData['dy']),
      yearHigh: data.yearHigh,
      yearLow: data.yearLow,
      last: data.last,
      variation: data.variation,
      rawData: data.rawData,
      description: description,
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

  static String normalize(String s) => s.toUpperCase().replaceAll(RegExp(r'\s+'), '');

  static final Map<String, Map<String, String>> factorMapping = {
    normalize('NIFTY 200 MOMENTUM 30'): {
      'name': 'Momentum (Top 200)',
      'desc': 'Tracks performance of top 30 stocks with high momentum in Nifty 200.'
    },
    normalize('NIFTY200 MOMENTUM 30'): {
      'name': 'Momentum (Top 200)',
      'desc': 'Tracks performance of top 30 stocks with high momentum in Nifty 200.'
    },
    normalize('NIFTY MIDCAP150 MOMENTUM 50'): {
      'name': 'Momentum (Midcap)',
      'desc': 'Tracks performance of top 50 stocks with high momentum in Midcap 150.'
    },
    normalize('NIFTY 500 MOMENTUM 50'): {
      'name': 'Momentum (Nifty 500)',
      'desc': 'Tracks performance of top 50 stocks with high momentum in Nifty 500.'
    },
    normalize('NIFTY 500 VALUE 50'): {
      'name': 'Value (Top 500)',
      'desc': 'Focuses on 50 undervalued stocks from Nifty 500 based on P/E, P/B, and Dividend Yield.'
    },
    normalize('NIFTY500 VALUE 50'): {
      'name': 'Value (Top 500)',
      'desc': 'Focuses on 50 undervalued stocks from Nifty 500 based on P/E, P/B, and Dividend Yield.'
    },
    normalize('NIFTY 50 VALUE 20'): {
      'name': 'Value (Nifty 50)',
      'desc': 'Focuses on 20 undervalued stocks from Nifty 50.'
    },
    normalize('NIFTY50 VALUE 20'): {
      'name': 'Value (Nifty 50)',
      'desc': 'Focuses on 20 undervalued stocks from Nifty 50.'
    },
    normalize('NIFTY 200 VALUE 30'): {
      'name': 'Value (Nifty 200)',
      'desc': 'Tracks 30 value stocks within the Nifty 200 universe.'
    },
    normalize('NIFTY200 VALUE 30'): {
      'name': 'Value (Nifty 200)',
      'desc': 'Tracks 30 value stocks within the Nifty 200 universe.'
    },
    normalize('NIFTY 100 QUALITY 30'): {
      'name': 'Quality (Largecap)',
      'desc': 'Tracks 30 companies with high ROE, low Debt/Equity, and consistent profit growth.'
    },
    normalize('NIFTY100 QUALITY 30'): {
      'name': 'Quality (Largecap)',
      'desc': 'Tracks 30 companies with high ROE, low Debt/Equity, and consistent profit growth.'
    },
    normalize('NIFTY MIDCAP150 QUALITY 50'): {
      'name': 'Quality (Midcap)',
      'desc': 'Tracks 50 companies in Midcap 150 with strong balance sheets and consistency.'
    },
    normalize('NIFTY SMALLCAP250 QUALITY 50'): {
      'name': 'Quality (Smallcap)',
      'desc': 'Tracks 50 companies in Smallcap 250 with high quality metrics.'
    },
    normalize('NIFTY 100 LOW VOLATILITY 30'): {
      'name': 'Low Volatility',
      'desc': 'Tracks stocks that have lower price fluctuations than the broader market.'
    },
    normalize('NIFTY100 LOW VOLATILITY 30'): {
      'name': 'Low Volatility',
      'desc': 'Tracks stocks that have lower price fluctuations than the broader market.'
    },
    normalize('NIFTY ALPHA 50'): {
      'name': 'Alpha',
      'desc': 'Tracks 50 stocks with high Jensen Alpha (excess return over market).'
    },
    normalize('NIFTY DIVIDEND OPPORTUNITIES 50'): {
      'name': 'Dividend Yield',
      'desc': 'Focuses on 50 stocks with high dividend yield relative to their price.'
    },
    normalize('NIFTY SMALLCAP 250'): {
      'name': 'Size (Small Cap)',
      'desc': 'Tracks the performance of companies with smaller market capitalization.'
    },
    normalize('NIFTY MICROCAP 250'): {
      'name': 'Size (Micro Cap)',
      'desc': 'Tracks the performance of companies with micro market capitalization.'
    },
    normalize('NIFTY ALPHA QUALITY LOW-VOLATILITY 30'): {
      'name': 'Alpha Quality Low-Vol',
      'desc': 'A multi-factor index combining Alpha, Quality, and Low Volatility.'
    },
    normalize('NIFTY QUALITY LOW-VOLATILITY 30'): {
      'name': 'Quality Low-Vol',
      'desc': 'A multi-factor index combining Quality and Low Volatility.'
    },
    normalize('NIFTY500 MULTIFACTOR MQVLV 50'): {
      'name': 'Multi-Factor (MQVLV)',
      'desc': 'Combines Momentum, Quality, Value, and Low Volatility factors.'
    },
    normalize('NIFTY HIGH BETA 50'): {
      'name': 'High Beta',
      'desc': 'Focuses on stocks that are more sensitive to market movements.'
    },
    normalize('NIFTY MIDSMALLCAP 400'): {
      'name': 'Mid-Small Cap',
      'desc': 'Tracks the performance of combined mid and small cap companies.'
    },
  };
}
