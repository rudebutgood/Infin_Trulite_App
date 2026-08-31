import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:csv/csv.dart';

class PortfolioService {
  static final PortfolioService _instance = PortfolioService._internal();
  factory PortfolioService() => _instance;
  PortfolioService._internal();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, 'nav.db');
    // Using same version as NavRepository to avoid conflicts
    _db = await openDatabase(path, version: 9, onCreate: (d, v) async {
       await _createPortfolioTables(d);
    }, onUpgrade: (d, oldV, newV) async {
       if (oldV < 6) {
         await _createPortfolioTables(d);
       }
       // Other migrations are handled by NavRepository
    });
    await _ensureTables();
    return _db!;
  }

  Future<void> _createPortfolioTables(Database d) async {
    await d.execute('''
      CREATE TABLE IF NOT EXISTS portfolio_imports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_name TEXT,
        investor_name TEXT,
        imported_at TEXT
      );
    ''');
    await d.execute('''
      CREATE TABLE IF NOT EXISTS portfolio (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        import_id INTEGER,
        fund_name TEXT,
        isin TEXT,
        total_units REAL,
        invested_value REAL,
        folio_number TEXT,
        raw_data TEXT,
        FOREIGN KEY (import_id) REFERENCES portfolio_imports (id) ON DELETE CASCADE
      );
    ''');
    await d.execute('''
      CREATE TABLE IF NOT EXISTS portfolio_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        import_id INTEGER,
        fund_name TEXT,
        isin TEXT,
        transaction_date TEXT,
        transaction_type TEXT,
        units REAL,
        nav REAL,
        amount REAL,
        folio_number TEXT,
        raw_data TEXT,
        FOREIGN KEY (import_id) REFERENCES portfolio_imports (id) ON DELETE CASCADE
      );
    ''');
    await d.execute('CREATE INDEX IF NOT EXISTS idx_portfolio_isin ON portfolio(isin)');
    await d.execute('CREATE INDEX IF NOT EXISTS idx_portfolio_import_id ON portfolio(import_id)');
  }

  Future<void> _ensureTables() async {
    final d = await db;
    await _createPortfolioTables(d);
    // Ensure import_id column exists (for older installs) safely
    try {
      final tableInfo = await d.rawQuery("PRAGMA table_info(portfolio)");
      final hasImportId = tableInfo.any((col) => col['name'] == 'import_id');
      if (!hasImportId) {
        await d.execute('ALTER TABLE portfolio ADD COLUMN import_id INTEGER');
      }
    } catch(_) {}
  }

  Future<int> importXlsxFile(String filePath) async {
    final extension = p.extension(filePath).toLowerCase();
    final bytes = await File(filePath).readAsBytes();
    final fileName = p.basename(filePath);
    
    if (extension == '.csv') {
      return await _importCsv(bytes, fileName);
    } else {
      return await _importExcel(bytes, fileName);
    }
  }

  Future<int> _importCsv(List<int> bytes, String fileName) async {
    final csvString = utf8.decode(bytes);
    final rows = const CsvToListConverter().convert(csvString);
    if (rows.isEmpty) return 0;
    const headerIdx = 9;
    if (rows.length <= headerIdx) return 0;

    final d = await db;
    final importId = await d.insert('portfolio_imports', {
      'file_name': fileName,
      'imported_at': DateTime.now().toIso8601String(),
    });

    final header = rows[headerIdx].map((e) => e.toString().trim()).toList();
    int count = 0;
    for (var i = headerIdx + 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < header.length) continue;
      final map = <String, dynamic>{};
      for (var j = 0; j < header.length && j < row.length; j++) {
        map[header[j]] = row[j];
      }
      if (await _processRow(map, d, importId)) count++;
    }
    return count;
  }

  Future<int> _importExcel(List<int> bytes, String fileName) async {
    final excel = Excel.decodeBytes(bytes);
    int totalImported = 0;
    final d = await db;

    for (final sheetName in excel.tables.keys) {
      final sheet = excel.tables[sheetName]!;
      String? investorName;
      if (sheet.maxRows > 2) {
        final row3 = sheet.rows[2];
        if (row3.length > 1) {
          final label = _getVal(row3[0]);
          if (label?.toString().toLowerCase().contains('name') ?? false) {
            investorName = _getVal(row3[1])?.toString();
          }
        }
      }

      final importId = await d.insert('portfolio_imports', {
        'file_name': fileName,
        'investor_name': investorName,
        'imported_at': DateTime.now().toIso8601String(),
      });

      const headerIdx = 9;
      if (sheet.maxRows <= headerIdx) continue;
      
      final header = sheet.rows[headerIdx].map((c) => _getVal(c)?.toString().trim() ?? '').toList();
      for (var r = headerIdx + 1; r < sheet.maxRows; r++) {
        final row = sheet.rows[r];
        if (row.every((c) => c == null || (_getVal(c)?.toString() ?? '').trim().isEmpty)) continue;
        
        final map = <String, dynamic>{};
        for (var i = 0; i < header.length && i < row.length; i++) {
          map[header[i]] = _getVal(row[i]);
        }
        if (await _processRow(map, d, importId)) totalImported++;
      }
    }
    return totalImported;
  }

  Future<bool> _processRow(Map<String, dynamic> map, Database d, int importId) async {
    final fundName = map['Fund Name']?.toString();
    if (fundName == null || fundName.isEmpty) return false;

    await d.insert('portfolio', {
      'import_id': importId,
      'fund_name': fundName,
      'isin': map['ISIN']?.toString(),
      'total_units': _parseNum(map['Total Units']),
      'invested_value': _parseNum(map['Invested Value']),
      'folio_number': map['Folio Number']?.toString(),
      'raw_data': json.encode(map),
    });
    return true;
  }

  dynamic _getVal(Data? cell) {
    if (cell == null) return null;
    final val = cell.value;
    if (val == null) return null;
    if (val is TextCellValue) return val.toString();
    if (val is DoubleCellValue) return val.value;
    if (val is IntCellValue) return val.value;
    if (val is BoolCellValue) return val.value;
    return val.toString();
  }

  double? _parseNum(dynamic v) {
    if (v == null) return null;
    try {
      return double.parse(v.toString().replaceAll(',', ''));
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> listImports() async {
    final d = await db;
    return await d.query('portfolio_imports', orderBy: 'imported_at DESC');
  }

  Future<void> deleteImport(int id) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('portfolio', where: 'import_id = ?', whereArgs: [id]);
      await txn.delete('portfolio_imports', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<String>> getPortfolioCompanies() async {
    final d = await db;
    final sql = '''
      SELECT DISTINCT n.mf_name 
      FROM portfolio p
      INNER JOIN (
        SELECT isin_div_payout as isin, mf_name FROM nav
        UNION ALL
        SELECT isin_reinvestment as isin, mf_name FROM nav
      ) n ON p.isin = n.isin
      WHERE n.mf_name IS NOT NULL
      ORDER BY n.mf_name ASC
    ''';
    final res = await d.rawQuery(sql);
    return res.map((m) => m['mf_name'] as String).toList();
  }

  Future<List<Map<String, dynamic>>> listPortfolio({String? amc, String? orderBy, List<int>? importIds, String? targetDate}) async {
    final d = await db;
    
    // If no targetDate provided, find the global latest date in nav table
    if (targetDate == null || targetDate.isEmpty) {
      final latestDateRes = await d.rawQuery('SELECT MAX(nav_date) as max_date FROM nav');
      if (latestDateRes.isNotEmpty && latestDateRes[0]['max_date'] != null) {
        targetDate = latestDateRes[0]['max_date'] as String;
      }
    }

    String orderSql = 'p.invested_value DESC'; // Default sort by invested value desc
    if (orderBy != null) {
      if (orderBy == 'invested_desc') orderSql = 'p.invested_value DESC';
      else if (orderBy == 'invested_asc') orderSql = 'p.invested_value ASC';
      else if (orderBy == 'current_desc') orderSql = '(n.nav_value * p.total_units) DESC';
      else if (orderBy == 'current_asc') orderSql = '(n.nav_value * p.total_units) ASC';
      else if (orderBy == 'return_desc') orderSql = '((n.nav_value * p.total_units - p.invested_value) / p.invested_value) DESC';
      else if (orderBy == 'return_asc') orderSql = '((n.nav_value * p.total_units - p.invested_value) / p.invested_value) ASC';
      else if (orderBy == '1d_desc') orderSql = '((n.nav_value - (SELECT nav_value FROM (SELECT isin_div_payout as isin, nav_value, nav_date FROM nav UNION ALL SELECT isin_reinvestment as isin, nav_value, nav_date FROM nav) pn WHERE pn.isin = p.isin AND pn.nav_date < n.nav_date ORDER BY pn.nav_date DESC LIMIT 1)) / (SELECT nav_value FROM (SELECT isin_div_payout as isin, nav_value, nav_date FROM nav UNION ALL SELECT isin_reinvestment as isin, nav_value, nav_date FROM nav) pn WHERE pn.isin = p.isin AND pn.nav_date < n.nav_date ORDER BY pn.nav_date DESC LIMIT 1)) DESC';
      else if (orderBy == '1d_asc') orderSql = '((n.nav_value - (SELECT nav_value FROM (SELECT isin_div_payout as isin, nav_value, nav_date FROM nav UNION ALL SELECT isin_reinvestment as isin, nav_value, nav_date FROM nav) pn WHERE pn.isin = p.isin AND pn.nav_date < n.nav_date ORDER BY pn.nav_date DESC LIMIT 1)) / (SELECT nav_value FROM (SELECT isin_div_payout as isin, nav_value, nav_date FROM nav UNION ALL SELECT isin_reinvestment as isin, nav_value, nav_date FROM nav) pn WHERE pn.isin = p.isin AND pn.nav_date < n.nav_date ORDER BY pn.nav_date DESC LIMIT 1)) ASC';
      else if (orderBy == 'name_desc') orderSql = 'p.fund_name DESC';
      else if (orderBy == 'name_asc') orderSql = 'p.fund_name ASC';
    }

    final filters = <String>[];
    final List<dynamic> queryArgs = [targetDate ?? ''];

    if (amc != null && amc != 'All Companies') {
      filters.add('n.mf_name = ?');
      queryArgs.add(amc);
    }
    
    if (importIds != null && importIds.isNotEmpty) {
      final placeholders = List.filled(importIds.length, '?').join(',');
      filters.add('p.import_id IN ($placeholders)');
      queryArgs.addAll(importIds);
    } else if (importIds != null && importIds.isEmpty) {
      return [];
    }

    final whereClause = filters.isNotEmpty ? 'WHERE ${filters.join(' AND ')}' : '';

    // Advanced SQL to find latest NAV <= targetDate AND the one strictly before it for each ISIN
    final sql = '''
      SELECT 
        p.*, 
        i.investor_name,
        n.nav_value as latest_nav,
        n.nav_date as latest_nav_date,
        n.mf_name,
        n.scheme_code,
        (
          SELECT nav_value FROM (
            SELECT isin_div_payout as isin, nav_value, nav_date FROM nav
            UNION ALL
            SELECT isin_reinvestment as isin, nav_value, nav_date FROM nav
          ) pn 
          WHERE pn.isin = p.isin AND pn.nav_date < n.nav_date
          ORDER BY pn.nav_date DESC LIMIT 1
        ) as prev_nav
      FROM portfolio p
      LEFT JOIN portfolio_imports i ON p.import_id = i.id
      LEFT JOIN (
        SELECT isin, nav_value, nav_date, mf_name, scheme_code FROM (
          SELECT isin_div_payout as isin, nav_value, nav_date, mf_name, scheme_code FROM nav
          UNION ALL
          SELECT isin_reinvestment as isin, nav_value, nav_date, mf_name, scheme_code FROM nav
        ) all_navs
        WHERE nav_date <= ?
        GROUP BY isin
        HAVING nav_date = MAX(nav_date)
      ) n ON p.isin = n.isin
      $whereClause
      GROUP BY p.id
      ORDER BY $orderSql
    ''';
    
    return await d.rawQuery(sql, queryArgs);
  }

  Future<List<MapEntry<String, double>>> getHistoricalValue({String? amc, List<int>? importIds, List<String>? specificDates}) async {
    final d = await db;
    
    List<String> dates;
    if (specificDates != null && specificDates.isNotEmpty) {
      dates = specificDates;
    } else {
      // Get last 7 unique dates in the DB
      final datesRes = await d.rawQuery('SELECT DISTINCT nav_date FROM nav ORDER BY nav_date DESC LIMIT 7');
      dates = datesRes.map((r) => r['nav_date'] as String).toList().reversed.toList();
    }
    
    final history = <MapEntry<String, double>>[];
    
    final List<String> filters = [];
    final List<dynamic> baseArgs = [];
    
    if (amc != null && amc != 'All Companies') {
      filters.add('n.mf_name = ?');
      baseArgs.add(amc);
    }
    
    if (importIds != null && importIds.isNotEmpty) {
      final placeholders = List.filled(importIds.length, '?').join(',');
      filters.add('p.import_id IN ($placeholders)');
      baseArgs.addAll(importIds);
    }

    for (var date in dates) {
      final List<dynamic> queryArgs = [date];
      queryArgs.addAll(baseArgs);

      final whereClause = filters.isNotEmpty ? 'AND ${filters.join(' AND ')}' : '';

      final sql = '''
        SELECT SUM(p.total_units * n.nav_value) as total_val
        FROM portfolio p
        JOIN (
           SELECT isin, nav_value, mf_name FROM (
             SELECT isin_div_payout as isin, nav_value, nav_date, mf_name FROM nav
             UNION ALL
             SELECT isin_reinvestment as isin, nav_value, nav_date, mf_name FROM nav
           ) WHERE nav_date = ?
           GROUP BY isin
        ) n ON p.isin = n.isin
        WHERE 1=1 $whereClause
      ''';
      final res = await d.rawQuery(sql, queryArgs);
      final val = (res.first['total_val'] as num? ?? 0.0).toDouble();
      if (val > 0) {
        history.add(MapEntry(date, val));
      }
    }
    return history;
  }
}
