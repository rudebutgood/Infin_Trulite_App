import 'package:http/io_client.dart';
import 'dart:io';
import 'dart:convert';

void main() async {
  HttpClient httpClient = HttpClient();
  httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  IOClient client = IOClient(httpClient);

  const String _mainUrl = 'https://www.nseindia.com/';
  const String _indexListUrl = 'https://www.nseindia.com/api/NextApi/apiClient/marketWatchApi?functionName=getIndexList';

  try {
    print('Syncing with NSE...');
    final initialResp = await client.get(Uri.parse(_mainUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
    });

    String? cookies = initialResp.headers['set-cookie'];

    final response = await client.get(Uri.parse(_indexListUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
      'Accept': 'application/json, text/javascript, */*; q=0.01',
      'Referer': 'https://www.nseindia.com/market-data/live-equity-market',
      if (cookies != null) 'Cookie': cookies,
    });

    if (response.statusCode == 200) {
      final Map<String, dynamic> body = json.decode(response.body);
      final Map<String, dynamic> data = body['data'] ?? {};
      
      data.forEach((cat, list) {
        if (list is List && list.isNotEmpty) {
          final item = list.first as Map;
          print('Category: $cat, Keys: ${item.keys.toList()}');
          print('  indexName: ${item['indexName']}, index: ${item['index']}');
        }
      });
    }
  } catch (e) {
    print('Error: $e');
  }
}
