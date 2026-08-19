import 'dart:convert';
import 'dart:io';
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/amfi_aum_data.dart';

class AmfiAumService {
  static const String _baseUrl = 'https://www.amfiindia.com/api/average-aum-schemewise?strType=Categorywise&MF_ID=0';

  IOClient? _client;

  IOClient _getClient() {
    if (_client != null) return _client!;
    HttpClient httpClient = HttpClient();
    httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    _client = IOClient(httpClient);
    return _client!;
  }

  Future<AmfiAumData> fetchAumData(int fyId, int periodId, {bool ignoreCache = false}) async {
    final client = _getClient();
    final url = '$_baseUrl&fyId=$fyId&periodId=$periodId';
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'aum_cache_${fyId}_$periodId';
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Check cache (valid for 24 hours) if not ignored
    if (!ignoreCache) {
      final cachedData = prefs.getString(cacheKey);
      final cacheTime = prefs.getInt('${cacheKey}_time') ?? 0;

      if (cachedData != null && (now - cacheTime) < 24 * 60 * 60 * 1000) {
        try {
          return _parseAumResponse(json.decode(cachedData));
        } catch (_) {
          // Cache corrupted, fetch fresh
        }
      }
    }

    try {
      final response = await client.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
        'Accept': 'application/json, text/javascript, */*; q=0.01',
      });

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        await prefs.setString(cacheKey, response.body);
        await prefs.setInt('${cacheKey}_time', now);
        return _parseAumResponse(body);
      } else {
        throw Exception('Failed to fetch AUM data: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  AmfiAumData _parseAumResponse(Map<String, dynamic> data) {
    final List<dynamic> list = data['data'] ?? [];
    final String period = data['selectedPeriod'] ?? '';

    Map<String, double> catAumMap = {};
    Map<String, List<AmfiSchemeDetail>> catSchemeMap = {};
    
    Map<String, double> amcAumMap = {};
    Map<String, List<AmfiSchemeDetail>> amcSchemeMap = {};

    Map<String, double> amcCatAumMap = {};
    Map<String, List<AmfiSchemeDetail>> amcCatSchemeMap = {};
    
    double grandTotal = 0;

    for (var item in list) {
      final cat = item['SchemeCat_Desc'] ?? 'Unknown';
      final amc = item['Mfname'] ?? 'Unknown';
      final aumObj = item['totalAUM'];
      
      double valExcl = _toDouble(aumObj?['ExcludingFundOfFundsDomesticButIncludingFundOfFundsOverseas']);
      double valFoF = _toDouble(aumObj?['FundOfFundsDomestic']);
      double total = valExcl + valFoF;

      if (amc == 'Grand Total') {
        grandTotal = total;
      } else if (cat != 'Total') {
        // Build scheme details from the schemes list in the API
        final List<dynamic> apiSchemes = item['schemes'] ?? [];
        List<AmfiSchemeDetail> schemeDetails = apiSchemes.map((s) {
          final sAumObj = s['AverageAumForTheMonth'];
          double sExcl = _toDouble(sAumObj?['ExcludingFundOfFundsDomesticButIncludingFundOfFundsOverseas']);
          double sFoF = _toDouble(sAumObj?['FundOfFundsDomestic']);
          return AmfiSchemeDetail(
            schemeName: s['SchemeNAVName'] ?? 'Unknown',
            amfiCode: s['AMFI_Code'] ?? 0,
            aumExclFoF: sExcl,
            aumFoF: sFoF,
            totalAum: sExcl + sFoF,
          );
        }).toList();

        // Category grouping
        catAumMap[cat] = (catAumMap[cat] ?? 0) + total;
        catSchemeMap.putIfAbsent(cat, () => []).addAll(schemeDetails);
        
        // AMC grouping
        if (!amc.endsWith(' Total')) {
          amcAumMap[amc] = (amcAumMap[amc] ?? 0) + total;
          amcSchemeMap.putIfAbsent(amc, () => []).addAll(schemeDetails);

          // Combined AMC + Category grouping
          final amcCatKey = "$amc - $cat";
          amcCatAumMap[amcCatKey] = (amcCatAumMap[amcCatKey] ?? 0) + total;
          amcCatSchemeMap.putIfAbsent(amcCatKey, () => []).addAll(schemeDetails);
        }
      }
    }

    List<AmfiAumGroup> categories = catAumMap.entries.map((e) {
      final schemes = catSchemeMap[e.key] ?? [];
      schemes.sort((a, b) => b.totalAum.compareTo(a.totalAum));
      return AmfiAumGroup(name: e.key, aum: e.value, schemes: schemes);
    }).toList()..sort((a, b) => b.aum.compareTo(a.aum));

    List<AmfiAumGroup> amcs = amcAumMap.entries.map((e) {
      final schemes = amcSchemeMap[e.key] ?? [];
      schemes.sort((a, b) => b.totalAum.compareTo(a.totalAum));
      return AmfiAumGroup(name: e.key, aum: e.value, schemes: schemes);
    }).toList()..sort((a, b) => b.aum.compareTo(a.aum));

    List<AmfiAumGroup> amcCatGroups = amcCatAumMap.entries.map((e) {
      final schemes = amcCatSchemeMap[e.key] ?? [];
      schemes.sort((a, b) => b.totalAum.compareTo(a.totalAum));
      return AmfiAumGroup(name: e.key, aum: e.value, schemes: schemes);
    }).toList()..sort((a, b) => b.aum.compareTo(a.aum));

    return AmfiAumData(
      period: period, 
      totalAum: grandTotal, 
      categories: categories, 
      amcs: amcs, 
      amcCategories: amcCatGroups
    );
  }

  Future<AmfiAumComparison> fetchAumComparison({
    bool ignoreCache = false,
    int? compFyId,
    int? compPeriodId,
  }) async {
    final current = await fetchAumData(1, 1, ignoreCache: ignoreCache);
    
    AmfiAumData? target;
    if (compFyId != null && compPeriodId != null) {
      try {
        target = await fetchAumData(compFyId, compPeriodId, ignoreCache: ignoreCache);
      } catch (_) {}
    }

    if (target == null || target.totalAum == 0) {
      // Default fallback logic
      try {
        target = await fetchAumData(1, 2, ignoreCache: ignoreCache);
      } catch (_) {}

      if (target == null || target.totalAum == 0) {
        target = await fetchAumData(2, 1, ignoreCache: ignoreCache);
      }
    }
    
    return AmfiAumComparison(current: current, previous: target!);
  }

  double _toDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) {
      return double.tryParse(val.replaceAll(',', '')) ?? 0.0;
    }
    return 0.0;
  }
}
