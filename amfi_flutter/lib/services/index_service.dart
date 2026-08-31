import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
        throw Exception('Failed to fetch Indices: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, String>> fetchIndexMapping() async {
    final client = _getClient();
    const String url = 'https://www.nseindia.com/api/NextApi/apiClient/marketWatchApi?functionName=getIndexList';
    try {
      final initialResp = await client.get(Uri.parse(_mainUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
      });
      String? cookies = initialResp.headers['set-cookie'];

      final response = await client.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
        'Accept': 'application/json, text/javascript, */*; q=0.01',
        'Referer': 'https://www.nseindia.com/market-data/live-equity-market',
        if (cookies != null) 'Cookie': cookies,
      });

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = json.decode(response.body);
        final Map<String, dynamic> data = body['data'] ?? {};
        Map<String, String> mapping = {};
        data.forEach((category, list) {
          if (list is List) {
            for (var item in list) {
              if (item['indexName'] != null && item['index'] != null) {
                mapping[item['indexName'].toString().toUpperCase().trim()] = item['index'].toString().trim();
              }
            }
          }
        });
        return mapping;
      }
    } catch (e) {
      debugPrint('Error fetching index mapping: $e');
    }
    return {};
  }

  Future<List<Map<String, dynamic>>> fetchIndexHistory(String indexName) async {
    final client = _getClient();
    
    String queryName = indexName.toUpperCase().trim();
    
    // Use getIndexList API for accurate mapping
    final mapping = await fetchIndexMapping();
    if (mapping.containsKey(queryName)) {
      queryName = mapping[queryName]!;
      debugPrint('Mapped $indexName to $queryName using getIndexList');
    } else {
      // Fallback to allIndices if not found in mapping
      try {
        final allIndices = await fetchIndices();
        final match = allIndices.firstWhere(
          (element) => element.name.toUpperCase().trim() == queryName || 
                       (element.rawData['indexSymbol']?.toString().toUpperCase().trim() == queryName),
          orElse: () => allIndices.firstWhere((e) => e.name.toUpperCase().contains(queryName), orElse: () => allIndices.first)
        );
        if (match.rawData['indexSymbol'] != null) {
          queryName = match.rawData['indexSymbol'].toString().trim();
          debugPrint('Mapped $indexName to $queryName using allIndices fallback');
        }
      } catch (e) {
        debugPrint('Fallback mapping failed for $indexName: $e');
      }
    }

    final url = 'https://www.nseindia.com/api/NextApi/apiClient/historicalGraph?functionName=getIndexChart&&index=${Uri.encodeComponent(queryName)}&flag=5Y';
    
    try {
      final initialResp = await client.get(Uri.parse(_mainUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
      });
      String? cookies = initialResp.headers['set-cookie'];

      final response = await client.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
        'Accept': 'application/json, text/javascript, */*; q=0.01',
        'Referer': 'https://www.nseindia.com/get-quotes/indices?index=${Uri.encodeComponent(queryName)}',
        'X-Requested-With': 'XMLHttpRequest',
        if (cookies != null) 'Cookie': cookies,
      });

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = json.decode(response.body);
        // NSE API historical graph response nested data under 'data' key
        final Map<String, dynamic> dataObj = body['data'] ?? {};
        // NSE API sometimes uses 'grapthData' (with a 'th') and sometimes 'graphData'
        final List<dynamic> graphData = dataObj['grapthData'] ?? dataObj['graphData'] ?? body['grapthData'] ?? body['graphData'] ?? [];
        
        if (graphData.isNotEmpty) {
          debugPrint('NSE History data points found: ${graphData.length}');
        } else {
          debugPrint('NSE History API returned empty list for $queryName');
        }
        return graphData.map((e) => {'timestamp': e[0], 'value': e[1]}).toList();
      } else {
        debugPrint('NSE History API failed: ${response.statusCode} for $queryName');
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching history for $indexName: $e');
      rethrow;
    }
  }
}
