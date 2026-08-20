import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/nav_item.dart';

const String NAV_API_URL = 'https://www.amfiindia.com/api/nav-history?query_type=all_for_date&from_date=';

class NavRepository {
  static final NavRepository _instance = NavRepository._internal();
  factory NavRepository() => _instance;
  NavRepository._internal();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, 'nav.db');
    _db = await openDatabase(path, version: 7, onCreate: (d, v) async {
      await d.execute('''
        CREATE TABLE nav (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          scheme_code TEXT,
          isin_div_payout TEXT,
          isin_reinvestment TEXT,
          scheme_name TEXT,
          nav_value REAL,
          nav_date TEXT,
          imported_at TEXT,
          api_timestamp TEXT,
          mf_name TEXT,
          category_name TEXT
        );
      ''');
      await d.execute('CREATE INDEX idx_nav_date ON nav(nav_date)');
      await d.execute('CREATE INDEX idx_nav_scheme_code ON nav(scheme_code)');
      await d.execute('CREATE INDEX idx_nav_mf_name ON nav(mf_name)');
      await d.execute('CREATE INDEX idx_nav_isin_payout ON nav(isin_div_payout)');
      await d.execute('CREATE INDEX idx_nav_isin_reinvest ON nav(isin_reinvestment)');

      await d.execute('''
        CREATE TABLE favorites (
          scheme_code TEXT PRIMARY KEY
        );
      ''');
      await d.execute('''
        CREATE TABLE sync_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          start_time TEXT,
          end_time TEXT,
          duration_ms INTEGER,
          rows_fetched INTEGER,
          dates_fetched TEXT,
          status TEXT,
          api_url TEXT
        );
      ''');
      await d.execute('''
        CREATE TABLE app_apis (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT UNIQUE,
          url TEXT,
          description TEXT
        );
      ''');
      await _insertDefaultApis(d);
    }, onUpgrade: (d, oldV, newV) async {
      if (oldV < 6) {
        await d.execute('CREATE TABLE IF NOT EXISTS app_apis (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, url TEXT, description TEXT)');
        try { await d.execute('ALTER TABLE sync_logs ADD COLUMN api_url TEXT'); } catch(_) {}
      }
      if (oldV < 7) {
        await d.execute('CREATE TABLE IF NOT EXISTS app_apis (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, url TEXT, description TEXT)');
        await _insertDefaultApis(d);
      }
    },
onOpen: (d) async {
      try {
        await d.rawQuery('PRAGMA journal_mode=WAL');
        await d.rawQuery('PRAGMA synchronous=NORMAL');
      } catch (e) {
        debugPrint('Pragma error: $e');
      }
    });
    return _db!;
  }

  Future<void> _insertDefaultApis(Database d) async {
    final apis = [
      {'name': 'daily_refresh', 'url': 'https://www.amfiindia.com/api/nav-history?query_type=all_for_date&from_date=', 'description': 'Main AMFI NAV daily refresh API'},
      {'name': 'historical', 'url': 'https://www.amfiindia.com/api/nav-history?query_type=historical_period&from_date={from}&to_date={to}&sd_id={sd_id}', 'description': 'Historical NAV data per scheme'},
      {'name': 'news', 'url': 'https://economictimes.indiatimes.com/markets/stocks/rssfeeds/2146842.cms', 'description': 'Economic Times Markets RSS feed'},
      {'name': 'fii_dii', 'url': 'https://www.nseindia.com/api/fiidiiTradeNse', 'description': 'NSE FII/DII daily trade data'},
      {'name': 'indices', 'url': 'https://www.nseindia.com/api/allIndices', 'description': 'NSE Real-time indices data'},
      {'name': 'aum', 'url': 'https://www.amfiindia.com/api/average-aum-schemewise?strType=Categorywise&MF_ID=0', 'description': 'AMFI Average AUM data'},
      {'name': 'gift_nifty', 'url': 'https://www.nseix.com/api/market-rate?type=derivatives', 'description': 'Gift Nifty (NSEIX) live derivatives'},
      {'name': 'gold', 'url': 'https://statewisebcast.dpgold.in:7768/VOTSBroadcastStreaming/Services/xml/GetLiveRateByTemplateID/dpgold', 'description': 'DP Gold real-time spot rates'},
    ];
    for (var api in apis) {
      await d.insert('app_apis', api, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<String> _getApiUrl(String name, {String fallback = ''}) async {
    final database = await db;
    final res = await database.query('app_apis', where: 'name = ?', whereArgs: [name], limit: 1);
    if (res.isNotEmpty) return res.first['url'] as String;
    return fallback;
  }

  Future<int> fetchAndImport({int businessDays = 3, List<String>? specificDates, int timeoutSeconds = 40, bool force = false}) async {
    final startTime = DateTime.now();
    HttpClient httpClient = HttpClient();
    httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    final ioClient = IOClient(httpClient);
    int totalRows = 0;
    List<String> fetchedDates = [];
    String status = 'Success';
    String lastUrlCalled = '';

    try {
      final List<String> allTargetDates = specificDates ?? _lastNBusinessDays(businessDays);
      final database = await db;
      final baseUrl = await _getApiUrl('daily_refresh', fallback: NAV_API_URL);
      
      List<String> datesToFetch;
      if (force) {
        datesToFetch = allTargetDates;
      } else {
        final existingDatesRes = await database.rawQuery(
          'SELECT DISTINCT nav_date FROM nav WHERE nav_date IN (${List.filled(allTargetDates.length, '?').join(',')})', 
          allTargetDates
        );
        final existingDates = existingDatesRes.map((r) => r['nav_date'] as String).toSet();
        datesToFetch = allTargetDates.where((d) => !existingDates.contains(d)).toList();
      }
      
      if (datesToFetch.isEmpty) return 0;

      final results = <List<Map<String, dynamic>>>[];
      for (var i = 0; i < datesToFetch.length; i += 10) {
        final chunk = datesToFetch.sublist(i, min(i + 10, datesToFetch.length));
        final chunkResults = await Future.wait(chunk.map((d) async {
          final url = baseUrl + d;
          lastUrlCalled = url; 
          try {
            final resp = await ioClient.get(Uri.parse(url), headers: {
              'User-Agent': 'Mozilla/5.0',
              'Accept': 'application/json',
            }).timeout(Duration(seconds: timeoutSeconds));

            if (resp.statusCode != 200) return <Map<String, dynamic>>[];
            final body = resp.body;
            if (body.isEmpty || body.trim() == "null") return <Map<String, dynamic>>[];
            
            final j = json.decode(body);
            final rows = <Map<String, dynamic>>[];
            
            if (j is List) {
              for (final item in j) if (item is Map<String, dynamic>) rows.add(_mapFromApiJson(item, d));
            } else if (j is Map<String, dynamic> && j.containsKey('data')) {
              for (final mf in j['data']) {
                if (mf is Map<String, dynamic> && mf.containsKey('schemes')) {
                  for (final scheme in mf['schemes']) {
                    if (scheme is Map<String, dynamic> && scheme.containsKey('navs')) {
                      for (final nav in scheme['navs']) {
                        if (nav is Map<String, dynamic>) {
                          rows.add(_mapFromApiJson(nav, d, mfName: mf['mfName']?.toString(), category: scheme['schemeName']?.toString()));
                        }
                      }
                    }
                  }
                }
              }
            }
            if (rows.isNotEmpty) fetchedDates.add(d);
            return rows;
          } catch (e) {
            debugPrint('Error fetching for date $d: $e');
            return <Map<String, dynamic>>[];
          }
        }));
        results.addAll(chunkResults);
      }

      final allRows = results.expand((r) => r).toList();
      totalRows = allRows.length;
      if (allRows.isEmpty) return 0;
      
      final nowStr = DateTime.now().toIso8601String();
      await database.transaction((txn) async {
        for (final dd in datesToFetch) {
          await txn.delete('nav', where: 'nav_date = ?', whereArgs: [dd]);
        }
        final batch = txn.batch();
        for (final r in allRows) {
          batch.insert('nav', {
            'scheme_code': r['scheme_code'],
            'isin_div_payout': r['isin_div_payout'],
            'isin_reinvestment': r['isin_reinvestment'],
            'scheme_name': r['scheme_name'],
            'nav_value': r['nav_value'],
            'nav_date': r['nav_date'],
            'imported_at': nowStr,
            'api_timestamp': r['api_timestamp'],
            'mf_name': r['mf_name'],
            'category_name': r['category_name'],
          });
        }
        await batch.commit(noResult: true);
      });
      return totalRows;
    } catch (e) {
      status = 'Error: $e';
      rethrow;
    } finally {
      ioClient.close();
      final endTime = DateTime.now();
      final database = await db;
      await database.insert('sync_logs', {
        'start_time': startTime.toIso8601String(),
        'end_time': endTime.toIso8601String(),
        'duration_ms': endTime.difference(startTime).inMilliseconds,
        'rows_fetched': totalRows,
        'dates_fetched': fetchedDates.join(','),
        'status': status,
        'api_url': lastUrlCalled,
      });
    }
  }

  Future<Map<String, dynamic>?> getLastSyncLog() async {
    final database = await db;
    final res = await database.query('sync_logs', orderBy: 'id DESC', limit: 1);
    return res.isNotEmpty ? res.first : null;
  }

  Future<List<String>> getAvailableDates() async {
    final database = await db;
    final res = await database.rawQuery('SELECT DISTINCT nav_date FROM nav ORDER BY nav_date DESC');
    return res.map((m) => m['nav_date'] as String).toList();
  }

  Future<List<NavItem>> queryLatestWithChange({String? q, String? fundType, String? amc, int limit = 200, String? orderBy, String? date, bool prioritizeHeldAndFav = true}) async {
    final database = await db;
    
    String latest;
    if (date != null && date.isNotEmpty) {
      latest = date;
    } else {
      final latestRes = await database.rawQuery('SELECT MAX(nav_date) as latest FROM nav');
      if (latestRes.isEmpty || latestRes.first['latest'] == null) return [];
      latest = latestRes.first['latest'] as String;
    }

    final prevRes = await database.rawQuery('SELECT MAX(nav_date) as prev FROM nav WHERE nav_date < ?', [latest]);
    final prev = (prevRes.isNotEmpty && prevRes.first['prev'] != null) ? prevRes.first['prev'] as String : null;

    final filters = <String>[];
    final args = <dynamic>[];
    filters.add('n.nav_date = ?');
    args.add(latest);

    if (q != null && q.isNotEmpty) {
      filters.add('UPPER(n.scheme_name) LIKE ?');
      args.add('%${q.toUpperCase()}%');
    }
    
    if (amc != null && amc.isNotEmpty && amc != 'All Companies') {
      filters.add('n.mf_name = ?');
      args.add(amc);
    }

    if (fundType != null && fundType.isNotEmpty && fundType != 'All') {
      final ft = fundType.toLowerCase();
      if (ft == 'direct') {
        filters.add("UPPER(n.scheme_name) LIKE ? AND NOT (UPPER(n.scheme_name) LIKE ? OR UPPER(n.scheme_name) LIKE ?)");
        args.addAll(['%DIRECT%', '%REGULAR%', '%IDCW%']);
      } else if (ft == 'regular') {
        filters.add("UPPER(n.scheme_name) LIKE ? AND NOT (UPPER(n.scheme_name) LIKE ? OR UPPER(n.scheme_name) LIKE ?)");
        args.addAll(['%REGULAR%', '%DIRECT%', '%IDCW%']);
      } else if (ft == 'idcw') {
        filters.add('UPPER(n.scheme_name) LIKE ?');
        args.add('%IDCW%');
      } else if (ft == 'others') {
        filters.add('NOT (UPPER(n.scheme_name) LIKE ? OR UPPER(n.scheme_name) LIKE ? OR UPPER(n.scheme_name) LIKE ?)');
        args.addAll(['%DIRECT%', '%REGULAR%', '%IDCW%']);
      }
    }

    final whereClause = 'WHERE ' + filters.join(' AND ');
    final joinPrev = prev != null ? 'LEFT JOIN nav p ON n.scheme_code = p.scheme_code AND p.nav_date = ?' : 'LEFT JOIN nav p ON 1=0';
    final joinFav = 'LEFT JOIN favorites f ON n.scheme_code = f.scheme_code';
    final joinHold = 'LEFT JOIN portfolio h ON n.isin_div_payout = h.isin OR n.isin_reinvestment = h.isin';
    
    final finalArgs = <dynamic>[];
    if (prev != null) finalArgs.add(prev);
    finalArgs.addAll(args);
    finalArgs.add(limit);

    String prefixOrder = prioritizeHeldAndFav ? 'h.id IS NOT NULL DESC, f.scheme_code IS NOT NULL DESC, ' : '';
    String orderClause = '${prefixOrder}LOWER(n.scheme_name) ASC';
    if (orderBy != null && orderBy.isNotEmpty) {
      String subOrder = 'LOWER(n.scheme_name) ASC';
      switch (orderBy) {
        case 'name_desc': subOrder = 'LOWER(n.scheme_name) DESC'; break;
        case 'return_desc': subOrder = "CASE WHEN p.nav_value IS NULL OR p.nav_value = 0 THEN 1 ELSE 0 END, ((n.nav_value - p.nav_value)/p.nav_value) DESC"; break;
        case 'return_asc': subOrder = "CASE WHEN p.nav_value IS NULL OR p.nav_value = 0 THEN 1 ELSE 0 END, ((n.nav_value - p.nav_value)/p.nav_value) ASC"; break;
        case 'date_desc': subOrder = "CASE WHEN n.nav_date IS NULL THEN 1 ELSE 0 END, n.nav_date DESC"; break;
        case 'date_asc': subOrder = "CASE WHEN n.nav_date IS NULL THEN 1 ELSE 0 END, n.nav_date ASC"; break;
        case 'timestamp_desc': subOrder = "CASE WHEN n.api_timestamp IS NULL THEN 1 ELSE 0 END, n.api_timestamp DESC"; break;
        case 'timestamp_asc': subOrder = "CASE WHEN n.api_timestamp IS NULL THEN 1 ELSE 0 END, n.api_timestamp ASC"; break;
      }
      orderClause = '$prefixOrder$subOrder';
    }

    final sql = 'SELECT n.*, (f.scheme_code IS NOT NULL) as is_favorite, (h.id IS NOT NULL) as is_held, p.nav_value as prev_nav_value, p.nav_date as prev_nav_date FROM nav n $joinPrev $joinFav $joinHold $whereClause GROUP BY n.scheme_code ORDER BY $orderClause LIMIT ?';
    final res = await database.rawQuery(sql, finalArgs);
    return res.map((m) => NavItem.fromMap(m)).toList();
  }

  Future<String?> lastImportedAt() async {
    final database = await db;
    final res = await database.rawQuery('SELECT MAX(imported_at) as last FROM nav');
    if (res.isNotEmpty && res.first['last'] != null) return res.first['last'] as String;
    return null;
  }

  Future<String?> lastApiTimestamp() async {
    final database = await db;
    final res = await database.rawQuery('SELECT api_timestamp FROM nav WHERE api_timestamp IS NOT NULL AND api_timestamp != "" ORDER BY nav_date DESC LIMIT 1');
    if (res.isNotEmpty && res.first['api_timestamp'] != null) return res.first['api_timestamp'] as String;
    return null;
  }
  
  Future<List<String>> getFundCompanies() async {
    final database = await db;
    final res = await database.rawQuery('SELECT DISTINCT mf_name FROM nav WHERE mf_name IS NOT NULL AND mf_name != "" ORDER BY mf_name ASC');
    return res.map((m) => m['mf_name'] as String).toList();
  }

  Future<int> clearDataInRange(String from, String to) async {
    final database = await db;
    return await database.delete('nav', where: 'nav_date BETWEEN ? AND ?', whereArgs: [from, to]);
  }

  Future<int> clearDataOlderThan(String date) async {
    final database = await db;
    return await database.delete('nav', where: 'nav_date < ?', whereArgs: [date]);
  }

  Future<void> toggleFavorite(String schemeCode, bool isFavorite) async {
    final database = await db;
    if (isFavorite) {
      await database.insert('favorites', {'scheme_code': schemeCode}, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await database.delete('favorites', where: 'scheme_code = ?', whereArgs: [schemeCode]);
    }
  }

  List<String> _lastNBusinessDays(int n) {
    final out = <String>[];
    var dt = DateTime.now();
    while (out.length < n) {
      if (dt.weekday != DateTime.saturday && dt.weekday != DateTime.sunday) {
        out.add(_formatDate(dt));
      }
      dt = dt.subtract(const Duration(days: 1));
    }
    return out;
  }

  String _formatDate(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Future<Map<String, dynamic>> fetchHistoricalForSchemes(List<String> schemeCodes, List<String> dates, {int timeoutSeconds = 40}) async {
    if (schemeCodes.isEmpty || dates.isEmpty) return {'count': 0, 'dates': []};

    final startTime = DateTime.now();
    HttpClient httpClient = HttpClient();
    httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    final ioClient = IOClient(httpClient);
    int totalImported = 0;
    Set<String> successfulDates = {};
    String lastUrlCalled = '';
    String status = 'Success';

    try {
      final database = await db;
      final template = await _getApiUrl('historical', fallback: 'https://www.amfiindia.com/api/nav-history?query_type=historical_period&from_date={from}&to_date={to}&sd_id={sd_id}');

      final tasks = <_FetchTask>[];
      for (final code in schemeCodes) {
        for (final date in dates) {
          tasks.add(_FetchTask(code, date));
        }
      }

      const int maxConcurrency = 20;
      for (var i = 0; i < tasks.length; i += maxConcurrency) {
        final chunk = tasks.sublist(i, min(i + maxConcurrency, tasks.length));

        final chunkResults = await Future.wait(chunk.map((task) async {
          final exist = await database.rawQuery(
            'SELECT 1 FROM nav WHERE scheme_code = ? AND nav_date = ? LIMIT 1',
            [task.code, task.date]
          );
          if (exist.isNotEmpty) {
            successfulDates.add(task.date);
            return <Map<String, dynamic>>[];
          }

          final url = template.replaceAll('{from}', task.date).replaceAll('{to}', task.date).replaceAll('{sd_id}', task.code);
          lastUrlCalled = url;
          try {
            final resp = await ioClient.get(Uri.parse(url), headers: {
              'User-Agent': 'Mozilla/5.0',
              'Accept': 'application/json',
            }).timeout(Duration(seconds: timeoutSeconds));

            if (resp.statusCode != 200) return <Map<String, dynamic>>[];
            final body = resp.body;
            if (body.isEmpty || body.trim() == "null") return <Map<String, dynamic>>[];

            final j = json.decode(body);
            if (j is Map<String, dynamic> && j.containsKey('data')) {
              final data = j['data'];
              final navGroups = data['nav_groups'];
              if (navGroups is List) {
                final List<Map<String, dynamic>> schemeRows = [];
                Map<String, dynamic>? localInfo;

                for (final group in navGroups) {
                  final records = group['historical_records'];
                  if (records is List) {
                    for (final rec in records) {
                      final navVal = rec['nav'];
                      final dateVal = rec['date'];
                      if (navVal != null && dateVal != null) {
                        if (localInfo == null) {
                          final localInfoRes = await database.rawQuery(
                            'SELECT isin_div_payout, isin_reinvestment, mf_name, category_name, scheme_name FROM nav WHERE scheme_code = ? LIMIT 1',
                            [task.code]
                          );
                          localInfo = localInfoRes.isNotEmpty ? localInfoRes.first : {};
                        }

                        schemeRows.add({
                          'scheme_code': task.code,
                          'isin_div_payout': group['isin_payout'] ?? localInfo['isin_div_payout'],
                          'isin_reinvestment': group['isin_reinvest'] ?? localInfo['isin_reinvestment'],
                          'scheme_name': data['scheme_name'] ?? localInfo['scheme_name'],
                          'nav_value': double.tryParse(navVal.toString()),
                          'nav_date': dateVal.toString(),
                          'api_timestamp': DateTime.now().toIso8601String(),
                          'mf_name': data['mf_name'] ?? localInfo['mf_name'],
                          'category_name': data['category_name'] ?? group['nav_name'] ?? localInfo['category_name'],
                        });
                        successfulDates.add(task.date);
                      }
                    }
                  }
                }
                return schemeRows;
              }
            }
          } catch (e) {
            debugPrint('Error fetching historical for ${task.code} on ${task.date}: $e');
          }
          return <Map<String, dynamic>>[];
        }));

        final allBatchRows = chunkResults.expand((r) => r).toList();
        if (allBatchRows.isNotEmpty) {
          final nowStr = DateTime.now().toIso8601String();
          await database.transaction((txn) async {
            final batch = txn.batch();
            for (final r in allBatchRows) {
              batch.insert('nav', {
                'scheme_code': r['scheme_code'],
                'isin_div_payout': r['isin_div_payout'],
                'isin_reinvestment': r['isin_reinvestment'],
                'scheme_name': r['scheme_name'],
                'nav_value': r['nav_value'],
                'nav_date': r['nav_date'],
                'imported_at': nowStr,
                'api_timestamp': r['api_timestamp'],
                'mf_name': r['mf_name'],
                'category_name': r['category_name'],
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            }
            await batch.commit(noResult: true);
          });
          totalImported += allBatchRows.length;
        }
      }
      return {
        'count': totalImported,
        'dates': successfulDates.toList()..sort(),
      };
    } catch (e) {
      status = 'Error: $e';
      rethrow;
    } finally {
      ioClient.close();
      final endTime = DateTime.now();
      final database = await db;
      await database.insert('sync_logs', {
        'start_time': startTime.toIso8601String(),
        'end_time': endTime.toIso8601String(),
        'duration_ms': endTime.difference(startTime).inMilliseconds,
        'rows_fetched': totalImported,
        'dates_fetched': successfulDates.join(','),
        'status': status,
        'api_url': lastUrlCalled,
      });
    }
  }

  Future<List<String>> getSchemeCodesForIsins(List<String> isins) async {
    if (isins.isEmpty) return [];
    final database = await db;
    final placeholders = List.filled(isins.length, '?').join(',');
    final res = await database.rawQuery(
      'SELECT DISTINCT scheme_code FROM nav WHERE isin_div_payout IN ($placeholders) OR isin_reinvestment IN ($placeholders)',
      [...isins, ...isins]
    );
    return res.map((m) => m['scheme_code'] as String).toList();
  }

  Map<String, dynamic> _mapFromApiJson(Map<String, dynamic> item, String date, {String? mfName, String? category, String? forcedSdId}) {
    final schemeCode = item['SD_ID']?.toString() ?? forcedSdId;
    final isinDiv = item['ISIN_PO']?.toString();
    final isinReinv = item['ISIN_RI']?.toString();
    final schemeName = item['NAV_Name']?.toString();
    final navRaw = item['hNAV_Amt'];

    double? navValue;
    if (navRaw != null) {
      try { navValue = double.parse(navRaw.toString()); } catch (_) {
        try { navValue = double.parse(navRaw.toString().replaceAll(',', '')); } catch (_) {}
      }
    }

    final dateStr = item['hNAV_Date']?.toString();
    final tsStr = item['hNAV_Dtstamp']?.toString();
    final displayStr = item['hNAV_Upload_display']?.toString();

    String finalDate = date;
    if (dateStr != null && dateStr.contains('T')) finalDate = dateStr.split('T').first;
    final String? apiTs = tsStr ?? displayStr ?? dateStr;

    return {
      'scheme_code': schemeCode,
      'isin_div_payout': isinDiv,
      'isin_reinvestment': isinReinv,
      'scheme_name': schemeName,
      'nav_value': navValue,
      'nav_date': finalDate,
      'api_timestamp': apiTs,
      'mf_name': mfName,
      'category_name': category,
    };
  }
}

class _FetchTask {
  final String code;
  final String date;
  _FetchTask(this.code, this.date);
}
