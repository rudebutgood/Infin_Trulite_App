import 'dart:convert';
import 'dart:io';
import 'package:http/io_client.dart';
import '../models/fii_dii_data.dart';

class FiiDiiService {
  static const String _nseUrl = 'https://www.nseindia.com/api/fiidiiTradeNse';
  static const String _mainUrl = 'https://www.nseindia.com/';

  IOClient? _client;

  IOClient _getClient() {
    if (_client != null) return _client!;
    HttpClient httpClient = HttpClient();
    httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    _client = IOClient(httpClient);
    return _client!;
  }

  Future<List<FiiDiiData>> fetchFiiDiiData() async {
    final client = _getClient();
    try {
      final initialResp = await client.get(Uri.parse(_mainUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
      });

      String? cookies = initialResp.headers['set-cookie'];

      final response = await client.get(Uri.parse(_nseUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
        'Accept': 'application/json, text/javascript, */*; q=0.01',
        'Referer': 'https://www.nseindia.com/reports/fii-dii',
        'X-Requested-With': 'XMLHttpRequest',
        if (cookies != null) 'Cookie': cookies,
      });

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => FiiDiiData.fromJson(json)).toList();
      } else {
        throw Exception('Failed to fetch FII/DII data: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }
}
