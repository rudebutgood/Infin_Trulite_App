import 'package:http/io_client.dart';
import 'dart:io';
import 'dart:convert';

void main() async {
  HttpClient httpClient = HttpClient();
  httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  IOClient client = IOClient(httpClient);

  const String _mainUrl = 'https://www.nseindia.com/';
  String indexName = 'NIFTY BANK';
  String url = 'https://www.nseindia.com/api/NextApi/apiClient/historicalGraph?functionName=getIndexChart&&index=${Uri.encodeComponent(indexName)}&flag=5Y';

  try {
    print('Fetching cookies from $_mainUrl...');
    final initialResp = await client.get(Uri.parse(_mainUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
    });

    String? cookies = initialResp.headers['set-cookie'];
    print('Cookies: $cookies');

    print('Fetching history from $url...');
    final response = await client.get(Uri.parse(url), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
      'Accept': 'application/json, text/javascript, */*; q=0.01',
      'Referer': 'https://www.nseindia.com/get-quotes/indices?index=${Uri.encodeComponent(indexName)}',
      'X-Requested-With': 'XMLHttpRequest',
      if (cookies != null) 'Cookie': cookies,
    });

    print('Status: ${response.statusCode}');
    if (response.statusCode == 200) {
      print('Body: ${response.body.substring(0, 500)}...');
      final Map<String, dynamic> body = json.decode(response.body);
      print('Keys: ${body.keys.toList()}');
      final List<dynamic> graphData = body['grapthData'] ?? body['graphData'] ?? [];
      print('Points found: ${graphData.length}');
    } else {
      print('Failed: ${response.statusCode}');
      print('Headers: ${response.headers}');
    }
  } catch (e) {
    print('Error: $e');
  }
}
