import 'dart:convert';
import 'dart:io';
import 'package:http/io_client.dart';

class GlobalIndexData {
  final String country;
  final String name;
  final String fullName;
  final String symbol;
  final double last;
  final double percentChange;
  final double previousClose;
  final double open;
  final double dayHigh;
  final double dayLow;
  final String currency;
  final String exchangeName;
  final double fiftyTwoWeekHigh;
  final double fiftyTwoWeekLow;
  final int volume;
  final DateTime? latestDate;

  GlobalIndexData({
    required this.country,
    required this.name,
    required this.fullName,
    required this.symbol,
    required this.last,
    required this.percentChange,
    required this.previousClose,
    required this.open,
    required this.dayHigh,
    required this.dayLow,
    required this.currency,
    required this.exchangeName,
    required this.fiftyTwoWeekHigh,
    required this.fiftyTwoWeekLow,
    required this.volume,
    this.latestDate,
  });
}

class GlobalIndexService {
  IOClient? _client;

  IOClient _getClient() {
    if (_client != null) return _client!;
    HttpClient httpClient = HttpClient();
    httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    _client = IOClient(httpClient);
    return _client!;
  }

  /// Fetch quotes for a set of global index symbols using Yahoo Finance chart API.
  /// The quote endpoint is returning 401 for these symbols in this environment,
  /// but the chart endpoint is still available and includes the fields needed to
  /// compute returns and show detailed index information.
  Future<List<GlobalIndexData>> fetchGlobalIndices() async {
    final client = _getClient();

    final Map<String, List<Map<String, String>>> mapping = {
      'USA': [
        {'symbol': '^GSPC', 'name': 'S&P 500'},
        {'symbol': '^DJI', 'name': 'Dow Jones'},
        {'symbol': '^IXIC', 'name': 'NASDAQ'},
        {'symbol': '^RUT', 'name': 'Russell 2000'},
        {'symbol': '^NYA', 'name': 'NYSE Composite'},
      ],
      'UK': [
        {'symbol': '^FTSE', 'name': 'FTSE 100'},
        {'symbol': '^FTMC', 'name': 'FTSE 250'},
      ],
      'Japan': [
        {'symbol': '^N225', 'name': 'Nikkei 225'},
        {'symbol': '^TOPX', 'name': 'TOPIX'},
      ],
      'China': [
        {'symbol': '000001.SS', 'name': 'SSE Composite'},
        {'symbol': '399001.SZ', 'name': 'SZSE Component'},
      ],
      'Taiwan': [
        {'symbol': '^TWII', 'name': 'TAIEX'},
      ],
      'Hongkong': [
        {'symbol': '^HSI', 'name': 'Hang Seng'},
      ],
      'South Korea': [
        {'symbol': '^KS11', 'name': 'KOSPI'},
      ],
      'Germany': [
        {'symbol': '^GDAXI', 'name': 'DAX'},
      ],
      'France': [
        {'symbol': '^FCHI', 'name': 'CAC 40'},
      ],
      'Australia': [
        {'symbol': '^AORD', 'name': 'All Ordinaries'},
      ],
      'Brazil': [
        {'symbol': '^BVSP', 'name': 'IBOVESPA'},
      ],
      'South Africa': [
        {'symbol': '^J203.JO', 'name': 'JSE Top 40'},
      ],
      'Canada': [
        {'symbol': '^GSPTSE', 'name': 'S&P/TSX Composite'},
      ],
      'Russia': [
        {'symbol': 'IMOEX.ME', 'name': 'MOEX Russia'},
      ],
      'Europe': [
        {'symbol': '^STOXX50E', 'name': 'Euro Stoxx 50'},
      ],
    };

    final List<String> symbols = [];
    final Map<String, Map<String, String>> symbolToMeta = {};
    for (final entry in mapping.entries) {
      for (final item in entry.value) {
        final symbol = item['symbol']!;
        symbols.add(symbol);
        symbolToMeta[symbol] = {'country': entry.key, 'name': item['name']!};
      }
    }

    if (symbols.isEmpty) return [];

    final List<GlobalIndexData> out = [];

    for (final symbol in symbols) {
      final meta = symbolToMeta[symbol]!;
      final url = 'https://query1.finance.yahoo.com/v8/finance/chart/${Uri.encodeComponent(symbol)}?interval=1d&range=5d';

      try {
        final response = await client.get(Uri.parse(url), headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
          'Accept': 'application/json',
        });

        if (response.statusCode != 200) continue;

        final Map<String, dynamic> body = json.decode(response.body);
        final chart = body['chart'] ?? {};
        final List<dynamic> result = chart['result'] ?? [];
        if (result.isEmpty) continue;

        final Map<String, dynamic> r = result.first as Map<String, dynamic>;
        final metaMap = r['meta'] ?? {};
        final quote = ((r['indicators'] ?? {})['quote'] ?? const <dynamic>[]);
        final List<dynamic> closeSeries = quote.isNotEmpty ? (quote[0]['close'] ?? const <dynamic>[]) : const <dynamic>[];

        final double latestClose = _asDouble(metaMap['regularMarketPrice'] ?? 0);

        if (latestClose == 0) continue;

        // Find the last TWO non-null closes from the chart series
        // We need the previous day's close (second-to-last), not today's close (which might be None)
        double previousClose = 0;
        int validClosesFound = 0;
        for (int i = closeSeries.length - 1; i >= 0; i--) {
          final val = closeSeries[i];
          if (val != null) {
            validClosesFound++;
            if (validClosesFound == 2) {
              // This is the second-to-last valid close (yesterday's close)
              previousClose = _asDouble(val);
              break;
            }
          }
        }

        // Fallback to chartPreviousClose if we couldn't find two valid closes
        if (previousClose == 0) {
          previousClose = _asDouble(metaMap['chartPreviousClose'] ?? 0);
        }

        DateTime? latestDate;
        final regularMarketTime = metaMap['regularMarketTime'];
        if (regularMarketTime != null) {
          // Create DateTime in UTC first
          latestDate = DateTime.fromMillisecondsSinceEpoch((_asDouble(regularMarketTime) * 1000).toInt(), isUtc: true);
        }

        final double pct = previousClose == 0 ? 0 : ((latestClose - previousClose) / previousClose) * 100;
        final String longName = (metaMap['longName'] ?? metaMap['shortName'] ?? meta['name']).toString();

        out.add(GlobalIndexData(
          country: meta['country']!,
          name: meta['name']!,
          fullName: longName,
          symbol: symbol,
          last: latestClose,
          percentChange: pct,
          previousClose: previousClose,
          open: _asDouble(metaMap['regularMarketOpen'] ?? 0),
          dayHigh: _asDouble(metaMap['regularMarketDayHigh'] ?? latestClose),
          dayLow: _asDouble(metaMap['regularMarketDayLow'] ?? latestClose),
          currency: (metaMap['currency'] ?? 'USD').toString(),
          exchangeName: (metaMap['exchangeName'] ?? 'N/A').toString(),
          fiftyTwoWeekHigh: _asDouble(metaMap['fiftyTwoWeekHigh'] ?? latestClose),
          fiftyTwoWeekLow: _asDouble(metaMap['fiftyTwoWeekLow'] ?? latestClose),
          volume: _asInt(metaMap['regularMarketVolume'] ?? 0),
          latestDate: latestDate,
        ));
      } catch (_) {
        // Skip any symbol that fails so the page can still render the rest.
      }
    }

    return out;
  }

  Future<List<Map<String, dynamic>>> fetchGlobalHistory(String symbol) async {
    final client = _getClient();
    final url = 'https://query1.finance.yahoo.com/v8/finance/chart/${Uri.encodeComponent(symbol)}?interval=1d&range=1y';

    final response = await client.get(Uri.parse(url), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
      'Accept': 'application/json',
    });

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch global index history: ${response.statusCode}');
    }

    final Map<String, dynamic> body = json.decode(response.body);
    final chart = body['chart'] ?? {};
    final List<dynamic> result = chart['result'] ?? [];
    if (result.isEmpty) return [];

    final Map<String, dynamic> r = result.first as Map<String, dynamic>;
    final List<dynamic> timestamps = r['timestamp'] ?? [];
    final List<dynamic> closes = ((r['indicators'] ?? {})['quote'] ?? [])[0]['close'] ?? [];

    final List<Map<String, dynamic>> data = [];
    for (int i = 0; i < timestamps.length; i++) {
      final ts = timestamps[i];
      final val = closes[i];
      if (ts == null || val == null) continue;
      data.add({
        'timestamp': (ts as num).toInt() * 1000,
        'value': (val as num).toDouble(),
      });
    }
    return data;
  }

  double _asDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', '')) ?? 0.0;
    return 0.0;
  }

  int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.replaceAll(',', '')) ?? 0;
    return 0;
  }
}
