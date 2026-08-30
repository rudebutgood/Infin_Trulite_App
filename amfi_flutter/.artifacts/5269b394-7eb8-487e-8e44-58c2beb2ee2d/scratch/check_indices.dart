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
    print('Fetching cookies...');
    final initialResp = await client.get(Uri.parse(_mainUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
    });

    String? cookies = initialResp.headers['set-cookie'];

    print('Fetching indices...');
    final response = await client.get(Uri.parse(_nseUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
      if (cookies != null) 'Cookie': cookies,
    });

    if (response.statusCode == 200) {
      final Map<String, dynamic> body = json.decode(response.body);
      final List<dynamic> data = body['data'] ?? [];
      for (var item in data) {
        print(item['index']);
      }
    } else {
      print('Failed: \${response.statusCode}');
    }
  } catch (e) {
    print('Error: \$e');
  }
}
