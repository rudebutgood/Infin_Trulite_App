import 'package:http/io_client.dart';
import 'dart:io';
import 'dart:convert';

void main() async {
  HttpClient httpClient = HttpClient();
  httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  IOClient client = IOClient(httpClient);

  const String _mainUrl = 'https://www.nseindia.com/';
  const String _nseUrl = 'https://www.nseindia.com/api/allIndices';

  try {
    final initialResp = await client.get(Uri.parse(_mainUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
    });

    String? cookies = initialResp.headers['set-cookie'];

    final response = await client.get(Uri.parse(_nseUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
      if (cookies != null) 'Cookie': cookies,
    });

    if (response.statusCode == 200) {
      final Map<String, dynamic> body = json.decode(response.body);
      final List<dynamic> data = body['data'] ?? [];
      for (var item in data) {
        if (item['index'] == 'NIFTY 50') {
           print('Keys for NIFTY 50: ' + item.keys.toList().toString());
           print('Data for NIFTY 50: ' + item.toString());
        }
        if (item['index'] == 'NIFTY200 MOMENTUM 30') {
           print('Keys for NIFTY200 MOMENTUM 30: ' + item.keys.toList().toString());
           print('Data for NIFTY200 MOMENTUM 30: ' + item.toString());
        }
      }
    }
  } catch (e) {
    print('Error: ' + e.toString());
  }
}
