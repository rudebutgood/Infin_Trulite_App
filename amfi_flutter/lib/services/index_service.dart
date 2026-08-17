import 'dart:convert';
import 'dart:io';
import 'package:http/io_client.dart';
import '../models/index_data.dart';

class IndexService {
  static const String _nseUrl = 'https://www.nseindia.com/api/allIndices';
  static const String _mainUrl = 'https://www.nseindia.com/';

  IOClient? _client;

  IOClient _getClient() {
    if (_client != null) return _client!;
    HttpClient httpClient = HttpClient();
    httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    _client = IOClient(httpClient);
    return _client!;
  }

  Future<List<IndexData>> fetchIndices() async {
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
        'Referer': 'https://www.nseindia.com/market-data/live-equity-market',
        'X-Requested-With': 'XMLHttpRequest',
        if (cookies != null) 'Cookie': cookies,
      });

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = json.decode(response.body);
        final List<dynamic> data = body['data'] ?? [];
        return data.map((json) => IndexData.fromJson(json)).toList();
      } else {
        throw Exception('Failed to fetch Indices: \${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }
}
