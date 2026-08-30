import 'dart:convert';
import 'dart:io';
import 'package:http/io_client.dart';
import '../models/gift_nifty_data.dart';

class GiftNiftyService {
  static const String _url = 'https://www.nseix.com/api/market-rate?type=derivatives';

  IOClient? _client;

  IOClient _getClient() {
    if (_client != null) return _client!;
    HttpClient httpClient = HttpClient();
    httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    _client = IOClient(httpClient);
    return _client!;
  }

  Future<List<GiftNiftyData>> fetchGiftNiftyData() async {
    final client = _getClient();
    try {
      final response = await client.get(Uri.parse(_url), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
        'Accept': 'application/json',
      });

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = json.decode(response.body);
        final List<dynamic> data = body['data'] ?? [];
        final List<GiftNiftyData> list = data.map((json) => GiftNiftyData.fromJson(json)).toList();

        // Deduplicate by Symbol + ExpiryDate to prevent duplicate rows
        final Map<String, GiftNiftyData> uniqueMap = {};
        for (var item in list) {
          final key = '${item.symbol}_${item.expiryDate}';
          if (!uniqueMap.containsKey(key)) {
            uniqueMap[key] = item;
          }
        }
        return uniqueMap.values.toList();
      } else {
        throw Exception('Failed to fetch Gift Nifty data: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }
}
