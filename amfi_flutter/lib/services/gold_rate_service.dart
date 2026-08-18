import 'dart:io';
import 'package:http/io_client.dart';
import '../models/gold_rate_data.dart';

class GoldRateService {
  static const String _url = 'https://statewisebcast.dpgold.in:7768/VOTSBroadcastStreaming/Services/xml/GetLiveRateByTemplateID/dpgold';

  IOClient? _client;

  IOClient _getClient() {
    if (_client != null) return _client!;
    HttpClient httpClient = HttpClient();
    httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    _client = IOClient(httpClient);
    return _client!;
  }

  Future<List<GoldRateData>> fetchGoldRates() async {
    final client = _getClient();
    try {
      final response = await client.get(Uri.parse(_url), headers: {
        'User-Agent': 'Mozilla/5.0',
        'Accept': 'text/plain',
      });

      if (response.statusCode == 200) {
        final lines = response.body.split('\n');
        return lines
            .where((l) => l.trim().isNotEmpty)
            .map((l) => GoldRateData.fromRawLine(l))
            .toList();
      } else {
        throw Exception('Failed to fetch Gold rates: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }
}
