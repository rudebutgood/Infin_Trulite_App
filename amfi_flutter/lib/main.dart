import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'models/nav_item.dart';
import 'models/fii_dii_data.dart';
import 'services/nav_repository.dart';
import 'services/portfolio_service.dart';
import 'services/fii_dii_service.dart';
import 'models/index_data.dart';
import 'services/index_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';
import 'package:workmanager/workmanager.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:sqflite/sqflite.dart';
import 'package:translator/translator.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/**
 * INFIN TRULITE - Main Entry Point
 *
 * This file contains the root application widget, the main screen with tabbed navigation,
 * and specialized pages for portfolio analytics, cache exploration, and database browsing.
 *
 * DESIGN SYSTEM:
 * - Primary Color: Indigo [900]
 * - Background: Grey [50] (Light Mode), System Default (Dark Mode)
 * - Typography: Inter (System Default)
 *
 * FEATURES:
 * 1. Home Tab: Portfolio synopsis, quick access tiles, and feature guide.
 * 2. NAVs Tab: Live AMFI data exploration with advanced filtering and sorting.
 * 3. Portfolio Tab: Consolidated view of imported holdings with ISIN grouping.
 * 4. Background Sync: Periodic NAV updates via Workmanager.
 * 5. Multi-language: Dynamic translation support for major Indian languages.
 */

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final repo = NavRepository();
      final prefs = await SharedPreferences.getInstance();
      final timeout = prefs.getInt('setApiTimeout') ?? 40;
      // Fetch data for last 3 business days
      await repo.fetchAndImport(businessDays: 3, timeoutSeconds: timeout);
      return true;
    } catch (e) {
      debugPrint('Background sync failed: $e');
      return false;
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Background Sync
  await Workmanager().initialize(callbackDispatcher);

  final prefs = await SharedPreferences.getInstance();
  final syncTimeStr = prefs.getString('setSyncTime') ?? "06:00";
  final parts = syncTimeStr.split(":");
  final hour = int.parse(parts[0]);
  final minute = int.parse(parts[1]);

  final now = DateTime.now();
  var scheduledTime = DateTime(now.year, now.month, now.day, hour, minute);
  if (scheduledTime.isBefore(now)) {
    scheduledTime = scheduledTime.add(const Duration(days: 1));
  }
  final delay = scheduledTime.difference(now);

  if (prefs.getBool('setEnableBackgroundSync') ?? true) {
    Workmanager().registerPeriodicTask(
      "dailySyncTask_v1",
      "dailySyncTask",
      frequency: const Duration(hours: 24),
      initialDelay: delay,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeStr = prefs.getString('setThemeMode') ?? 'system';
    if (mounted) {
      setState(() {
        _themeMode = ThemeMode.values.firstWhere(
                (e) => e.toString().split('.').last == themeStr,
            orElse: () => ThemeMode.system
        );
      });
    }
  }

  void updateTheme(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Infin Trulite',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'), Locale('hi'), Locale('mr'), Locale('gu'),
        Locale('ta'), Locale('te'), Locale('kn'), Locale('bn'),
        Locale('ml'), Locale('pa'),
      ],
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.indigo,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          primary: Colors.indigo[900]!,
          secondary: Colors.indigoAccent,
        ),
        scaffoldBackgroundColor: Colors.grey[50],
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.indigo[900],
          foregroundColor: Colors.white,
          elevation: 4,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          surfaceTintColor: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.grey[900],
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: MainScreen(onThemeChanged: updateTheme),
    );
  }
}

class MainScreen extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;
  const MainScreen({super.key, required this.onThemeChanged});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  // Controllers & Services
  late TabController _tabCtl;
  int _currentIndex = 0;
  final NavRepository _repo = NavRepository();
  final PortfolioService _portfolio = PortfolioService();
  final FiiDiiService _fiiDiiService = FiiDiiService();
  final IndexService _indexService = IndexService();
  final TextEditingController _searchCtl = TextEditingController();
  final ScrollController _scrollCtl = ScrollController();
  final ScrollController _portfolioScrollCtl = ScrollController();
  final FocusNode _searchFocus = FocusNode();
  final GoogleTranslator _translator = GoogleTranslator();

  // Cache & State
  final Map<String, String> _translationCache = {};
  List<NavItem> _items = [];
  List<String> _recentSearches = [];
  bool _loading = true;
  bool _showSuggestions = false;
  bool _showNetReturns = false;

  // NAV Filters
  final List<String> _fundTypes = ['All', 'Direct', 'Regular', 'IDCW', 'Others'];
  String _selectedFundType = 'Direct';
  String _selectedCompany = 'All Companies';
  List<String> _amcList = ['All Companies'];
  String? _lastImportedAt;
  DateTime? _lastImportedAtDt;
  Duration? _lastImportDuration;
  String? _lastApiTimestamp;
  String _sortOption = 'Return \u2193';
  Map<String, dynamic>? _lastSyncLog;
  List<FiiDiiData> _fiiDiiData = [];
  bool _fetchingFiiDii = false;
  List<IndexData> _indicesData = [];
  bool _fetchingIndices = false;

  // Portfolio State
  List<Map<String, dynamic>> _portfolioRows = [];
  Map<String, List<Map<String, dynamic>>> _groupedPortfolio = {};
  Set<String> _expandedGroups = {};
  String _selectedPortfolioCompany = 'All Companies';
  List<String> _portfolioAmcList = ['All Companies'];
  String _portfolioSortOption = 'Invested \u2193';
  String _portfolioPeriod = '1D';
  String _selectedLanguage = 'English';
  bool _fetchingHistorical = false;
  DateTimeRange? _customPortfolioRange;
  List<Map<String, dynamic>> _importedFiles = [];
  Set<int>? _selectedImportIds;
  DateTime? _selectedFilterDate;
  Map<String, double> _periodNavs = {};

  // Application Settings
  bool _setOpenPortfolioFirst = false;
  bool _setEnableBackgroundSync = true;
  bool _setCompactLayout = false;
  bool _setPrivacyMode = false;
  bool _setHideZeroHoldings = true;
  bool _setShowFolioInList = false;
  bool _setShowIconsInNav = true;
  bool _setPrioritizeHeldAndFav = true;
  int _setRefreshDays = 3;
  int _setApiTimeout = 40;
  String _setSyncTime = "06:00";
  String _setNAVDefaultSort = 'Return \u2193';
  ThemeMode _setThemeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _tabCtl = TabController(length: 3, vsync: this);
    _tabCtl.addListener(() {
      if (!_tabCtl.indexIsChanging) {
        setState(() => _currentIndex = _tabCtl.index);
      }
    });

    _searchFocus.addListener(() {
      if (mounted) {
        setState(() {
          _showSuggestions = _searchFocus.hasFocus && _recentSearches.isNotEmpty;
        });
      }
    });

    _initStateAsync();
  }

  Future<void> _initStateAsync() async {
    final prefs = await SharedPreferences.getInstance();

    // Load persisted filters
    _selectedFundType = prefs.getString('selectedFundType') ?? 'Direct';
    _selectedLanguage = prefs.getString('selectedLanguage') ?? 'English';
    _searchCtl.text = prefs.getString('lastSearch') ?? '';
    _recentSearches = prefs.getStringList('recentSearches') ?? [];

    // Load metadata from Repository
    _lastImportedAt = await _repo.lastImportedAt();
    if (_lastImportedAt != null) {
      try { _lastImportedAtDt = DateTime.parse(_lastImportedAt!); } catch (_) { _lastImportedAtDt = null; }
    }
    _lastApiTimestamp = await _repo.lastApiTimestamp();
    _amcList = ['All Companies', ...await _repo.getFundCompanies()];
    _lastSyncLog = await _repo.getLastSyncLog();

    // Load App Settings
    _setOpenPortfolioFirst = prefs.getBool('setOpenPortfolioFirst') ?? false;
    _setEnableBackgroundSync = prefs.getBool('setEnableBackgroundSync') ?? true;
    _setCompactLayout = prefs.getBool('setCompactLayout') ?? false;
    _setPrivacyMode = prefs.getBool('setPrivacyMode') ?? false;
    _setHideZeroHoldings = prefs.getBool('setHideZeroHoldings') ?? true;
    _setShowFolioInList = prefs.getBool('setShowFolioInList') ?? false;
    _setShowIconsInNav = prefs.getBool('setShowIconsInNav') ?? true;
    _setPrioritizeHeldAndFav = prefs.getBool('setPrioritizeHeldAndFav') ?? true;
    _setRefreshDays = prefs.getInt('setRefreshDays') ?? 3;
    _setApiTimeout = prefs.getInt('setApiTimeout') ?? 40;
    _setSyncTime = prefs.getString('setSyncTime') ?? "06:00";
    _setNAVDefaultSort = prefs.getString('setNAVDefaultSort') ?? 'Return \u2193';
    _sortOption = _setNAVDefaultSort;

    final themeStr = prefs.getString('setThemeMode') ?? 'system';
    _setThemeMode = ThemeMode.values.firstWhere(
            (e) => e.toString().split('.').last == themeStr,
        orElse: () => ThemeMode.system
    );
    widget.onThemeChanged(_setThemeMode);

    if (mounted) setState(() {});

    // Initial Data Load
    await _load();

    _importedFiles = await _portfolio.listImports();
    if (_selectedImportIds == null) {
      _selectedImportIds = _importedFiles.map((e) => e['id'] as int).toSet();
    }

    await _loadPortfolio();
    _fetchFiiDii();
    _fetchIndices();

    // Trigger refresh if no data is present
    if (_items.isEmpty && _portfolioRows.isEmpty) {
      _refresh();
    }

    // Navigation routing logic
    if (_setOpenPortfolioFirst && _currentIndex == 0) {
      _tabCtl.animateTo(2);
    }
  }

  // --- TRANSLATION SYSTEM ---

  Future<String> _translate(String text) async {
    if (_selectedLanguage == 'English' || text.isEmpty) return text;
    final cacheKey = '${_selectedLanguage}_$text';
    if (_translationCache.containsKey(cacheKey)) return _translationCache[cacheKey]!;

    try {
      final code = _getLangCode(_selectedLanguage);
      final translation = await _translator.translate(text, to: code);
      _translationCache[cacheKey] = translation.text;
      return translation.text;
    } catch (e) {
      debugPrint('Translation error for $text: $e');
      return text;
    }
  }

  String _getLangCode(String lang) {
    switch (lang) {
      case 'Hindi': return 'hi';
      case 'Marathi': return 'mr';
      case 'Gujarati': return 'gu';
      case 'Tamil': return 'ta';
      case 'Telugu': return 'te';
      case 'Kannada': return 'kn';
      case 'Bengali': return 'bn';
      case 'Malayalam': return 'ml';
      case 'Punjabi': return 'pa';
      default: return 'en';
    }
  }

  Widget txt(String text, {TextStyle? style, bool overflow = false, TextAlign? align}) {
    if (_selectedLanguage == 'English') {
      return Text(text, style: style, overflow: overflow ? TextOverflow.ellipsis : null, textAlign: align);
    }
    return FutureBuilder<String>(
      future: _translate(text),
      builder: (context, snapshot) => Text(
        snapshot.data ?? text,
        style: style,
        overflow: overflow ? TextOverflow.ellipsis : null,
        textAlign: align,
      ),
    );
  }

  String t(String key, {String? arg}) {
    const Map<String, Map<String, String>> staticLabels = {
      'English': {
        'navs': 'NAVs', 'portfolio': 'Portfolio', 'total': 'TOTAL', 'search': 'Search scheme...',
        'holdings': 'Holdings', 'analytics': 'Portfolio Analytics', 'returns': 'Returns',
        'matched': 'funds matched', 'net_returns': 'Viewing Net Returns',
        'period_returns': 'Viewing {} Returns', 'all_amc': 'All Companies',
        'no_data': 'No data available', 'syncing': 'Syncing data...',
        'import_hint': 'Supports Excel/CSV files', 'quick_access': 'Quick Access',
        'synopsis': 'Portfolio Synopsis', 'net_gain': 'Net Gain', 'day_gain': 'Day Gain'
      },
      'Hindi': {
        'navs': 'एनएवी', 'portfolio': 'पोर्टफोलियो', 'total': 'कुल', 'search': 'योजना खोजें...',
        'holdings': 'होल्डिंग्स', 'analytics': 'पोर्टफोलियो विश्लेषण', 'returns': 'रिटर्न',
        'matched': 'फंड मिले', 'net_returns': 'कुल रिटर्न देख रहे हैं',
        'period_returns': '{} रिटर्न देख रहे हैं', 'all_amc': 'सभी कंपनियां',
        'no_data': 'कोई डेटा उपलब्ध नहीं है', 'syncing': 'डेटा सिंक हो रहा है...',
        'import_hint': 'एक्सेल/सीएसवी फाइलों का समर्थन करता है', 'quick_access': 'त्वरित पहुँच',
        'synopsis': 'पोर्टफोलियो सारांश', 'net_gain': 'कुल लाभ', 'day_gain': 'आज का लाभ'
      },
    };
    final label = staticLabels[_selectedLanguage]?[key] ?? staticLabels['English']![key] ?? key;
    if (arg != null) return label.replaceAll('{}', arg);
    return label;
  }

  // --- DATA LOADING & BUSINESS LOGIC ---

  Future<void> _loadPortfolio() async {
    _portfolioRows = await _portfolio.listPortfolio(
        amc: _selectedPortfolioCompany,
        orderBy: _getPortfolioOrder(),
        importIds: _selectedImportIds?.toList(),
        targetDate: _selectedFilterDate != null ? DateFormat('yyyy-MM-dd').format(_selectedFilterDate!) : null
    );

    if (_setHideZeroHoldings) {
      _portfolioRows = _portfolioRows.where((r) => (r['total_units'] as num? ?? 0) > 0.001).toList();
    }

    if (!_showNetReturns && _portfolioPeriod != '1D') {
      await _loadPeriodNavs();
    }

    _groupedPortfolio = {};
    for (var r in _portfolioRows) {
      final isin = (r['isin'] as String?) ?? 'No ISIN';
      _groupedPortfolio.putIfAbsent(isin, () => []).add(r);
    }

    _portfolioAmcList = ['All Companies', ...await _portfolio.getPortfolioCompanies()];
    _importedFiles = await _portfolio.listImports();
    if (mounted) setState(() {});
  }

  Future<void> _fetchFiiDii() async {
    if (_fetchingFiiDii) return;
    setState(() => _fetchingFiiDii = true);
    try {
      _fiiDiiData = await _fiiDiiService.fetchFiiDiiData();
    } catch (e) {
      debugPrint('FII/DII Fetch Error: $e');
    } finally {
      if (mounted) setState(() => _fetchingFiiDii = false);
    }
  }

  Future<void> _fetchIndices() async {
    if (_fetchingIndices) return;
    setState(() => _fetchingIndices = true);
    try {
      final data = await _indexService.fetchIndices();
      data.sort((a, b) => b.percentChange.compareTo(a.percentChange));
      if (mounted) setState(() => _indicesData = data);
    } catch (e) {
      debugPrint('Index Fetch Error: $e');
    } finally {
      if (mounted) setState(() => _fetchingIndices = false);
    }
  }

  Future<void> _loadPeriodNavs() async {
    final milestoneDates = _getMilestoneDates(_portfolioPeriod);
    if (milestoneDates.isEmpty) return;
    final startDate = milestoneDates.first;

    final database = await _repo.db;
    final isins = _portfolioRows.map((r) => r['isin'] as String).where((i) => i != null).toSet().toList();

    if (isins.isEmpty) return;

    final placeholders = List.filled(isins.length, '?').join(',');
    final sql = '''
      SELECT isin, nav_value FROM (
        SELECT isin_div_payout as isin, nav_value, nav_date FROM nav
        UNION ALL
        SELECT isin_reinvestment as isin, nav_value, nav_date FROM nav
      ) WHERE nav_date <= ? AND isin IN ($placeholders)
      GROUP BY isin
      HAVING nav_date = MAX(nav_date)
    ''';

    final res = await database.rawQuery(sql, [startDate, ...isins]);
    _periodNavs = { for (var r in res) r['isin'] as String : (r['nav_value'] as num).toDouble() };
  }

  Future<void> _handlePeriodChange(String pVal) async {
    setState(() {
      _portfolioPeriod = pVal;
      _fetchingHistorical = true;
    });

    try {
      if (pVal == 'Custom') {
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: DateTime.now(),
        );
        if (picked != null) {
          _customPortfolioRange = picked;
        } else {
          setState(() => _fetchingHistorical = false);
          return;
        }
      }

      final isins = _portfolioRows.map((r) => r['isin'] as String).where((i) => i != null).toList();
      final schemeCodes = await _repo.getSchemeCodesForIsins(isins);

      if (schemeCodes.isNotEmpty) {
        final db = await _repo.db;
        String? latestRefDate;

        for (int i = 0; i < 5; i++) {
          final target = DateTime.now().subtract(Duration(days: i));
          if (target.weekday == DateTime.saturday || target.weekday == DateTime.sunday) continue;
          final fmt = DateFormat('yyyy-MM-dd').format(target);
          final res = await db.rawQuery('SELECT 1 FROM nav WHERE nav_date = ? LIMIT 1', [fmt]);
          if (res.isNotEmpty) {
            latestRefDate = fmt;
            break;
          }
        }

        final base = latestRefDate != null ? DateTime.parse(latestRefDate) : DateTime.now();
        final start = _getPeriodStartDate(pVal, from: base);

        final List<String> milestoneDates = [];
        milestoneDates.add(DateFormat('yyyy-MM-dd').format(base));

        for (int i = 0; i < 5; i++) {
          milestoneDates.add(DateFormat('yyyy-MM-dd').format(start.add(Duration(days: i))));
        }

        final summary = await _repo.fetchHistoricalForSchemes(schemeCodes, milestoneDates, timeoutSeconds: _setApiTimeout);
        final int count = summary['count'] ?? 0;
        if (mounted && count > 0) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Successfully loaded historical data for $pVal period.'),
          ));
        }
      }
      await _loadPortfolio();
      _fetchFiiDii();
      _fetchIndices();
    } catch (e) {
      debugPrint('Error in period change: $e');
    } finally {
      if (mounted) setState(() => _fetchingHistorical = false);
    }
  }

  String? _getPortfolioOrder() {
    switch (_portfolioSortOption) {
      case 'Invested \u2193': return 'invested_desc';
      case 'Invested \u2191': return 'invested_asc';
      case 'Value \u2193': return 'current_desc';
      case 'Value \u2191': return 'current_asc';
      case 'Return \u2193': return 'return_desc';
      case 'Return \u2191': return 'return_asc';
      case 'Name A-Z': return 'name_asc';
      case 'Name Z-A': return 'name_desc';
      default: return null;
    }
  }

  String _formatCurrency(num value) {
    if (_setPrivacyMode) return '****';
    return NumberFormat.currency(locale: 'en_IN', symbol: '', decimalDigits: 0).format(value).trim();
  }

  String _formatImportedAt(String iso) {
    try {
      DateTime dt;
      if (iso.endsWith('Z') && iso.length > 10) {
        dt = DateTime.parse(iso.substring(0, iso.length - 1));
      } else {
        dt = DateTime.parse(iso);
      }
      final local = dt.toLocal();
      return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return iso;
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      String? orderBy;
      switch (_sortOption) {
        case 'Return \u2193': orderBy = 'return_desc'; break;
        case 'Return \u2191': orderBy = 'return_asc'; break;
        case 'Name A-Z': orderBy = 'name_asc'; break;
        case 'Name Z-A': orderBy = 'name_desc'; break;
        case 'Nav Date \u2193': orderBy = 'date_desc'; break;
        case 'Nav Date \u2191': orderBy = 'date_asc'; break;
        case 'Nav report time \u2193': orderBy = 'timestamp_desc'; break;
        case 'Nav report time \u2191': orderBy = 'timestamp_asc'; break;
      }
      final list = await _repo.queryLatestWithChange(
        q: _searchCtl.text,
        fundType: _selectedFundType,
        amc: _selectedCompany,
        orderBy: orderBy,
        date: _selectedFilterDate != null ? DateFormat('yyyy-MM-dd').format(_selectedFilterDate!) : null,
        prioritizeHeldAndFav: _setPrioritizeHeldAndFav,
      );
      if (mounted) {
        setState(() {
          _items = list;
        });
      }
    } catch (e) {
      if (!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (!silent && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedFundType', _selectedFundType);
    await prefs.setString('lastSearch', _searchCtl.text);
    if (_recentSearches.length > 10) _recentSearches = _recentSearches.sublist(0, 10);
    await prefs.setStringList('recentSearches', _recentSearches);
  }

  void _updateSearchHistory(String query) {
    if (query.trim().isEmpty) return;
    setState(() {
      _recentSearches.remove(query);
      _recentSearches.insert(0, query);
      if (_recentSearches.length > 10) _recentSearches = _recentSearches.sublist(0, 10);
    });
    _savePrefs();
  }

  Future<void> _toggleFavorite(NavItem it) async {
    await _repo.toggleFavorite(it.schemeCode!, !it.isFavorite);
    _load(silent: true);
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _selectedFilterDate = null;
      });
    }
    final start = DateTime.now();
    try {
      final count = await _repo.fetchAndImport(
          businessDays: _setRefreshDays,
          timeoutSeconds: _setApiTimeout,
          force: true
      );

      final end = DateTime.now();
      _lastImportDuration = end.difference(start);

      _lastImportedAt = await _repo.lastImportedAt();
      _lastApiTimestamp = await _repo.lastApiTimestamp();
      _amcList = ['All Companies', ...await _repo.getFundCompanies()];
      _lastSyncLog = await _repo.getLastSyncLog();

      if (_lastImportedAt != null) {
        try { _lastImportedAtDt = DateTime.parse(_lastImportedAt!); } catch (_) { _lastImportedAtDt = null; }
      }
      await _savePrefs();
      await _load();
      await _loadPortfolio();
      _fetchFiiDii();
      _fetchIndices();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Successfully fetched $count records in ${end.difference(start).inSeconds}s')
        ));
      }
    } catch (e) {
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(children: [const Icon(Icons.error_outline, color: Colors.red), const SizedBox(width: 8), const Text('Update Failed')]),
            content: SingleChildScrollView(child: SelectableText(e.toString())),
            actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final List<String> availableDates = await _repo.getAvailableDates();
    if (availableDates.isEmpty) return;

    final DateTime first = DateTime.parse(availableDates.last);
    final DateTime last = DateTime.parse(availableDates.first);

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedFilterDate ?? last,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) {
      setState(() => _selectedFilterDate = picked);
      _load();
      _loadPortfolio();
    }
  }

  // --- UI WIDGETS & MODALS ---

  void _showDetails(NavItem it) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (c, s) => ListView(
          controller: s,
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(child: txt(it.schemeName ?? '-', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                IconButton(
                    icon: Icon(it.isFavorite ? Icons.star : Icons.star_border, color: Colors.amber),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _toggleFavorite(it);
                    }
                ),
              ],
            ),
            const Divider(),
            _detailRow('Scheme Code', it.schemeCode),
            _detailRow('ISIN (Payout)', it.isinDivPayout),
            _detailRow('ISIN (Reinv)', it.isinReinvestment),
            _detailRow('AMC', it.mfName),
            _detailRow('Category', it.category),
            _detailRow('NAV Value', it.navValue?.toString()),
            _detailRow('NAV Date', it.navDate),
            _detailRow('Sync Timestamp', it.apiTimestamp),
            _detailRow('Is Held', it.isHeld ? 'Yes' : 'No'),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _launchExternalUrl('https://www.google.com/search?q=${it.schemeName}'),
              icon: const Icon(Icons.search),
              label: const Text('Search on Web'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPortfolioDetails(Map<String, dynamic> r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (c, s) => ListView(
          controller: s,
          padding: const EdgeInsets.all(20),
          children: [
            txt(r['fund_name'] ?? '-', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            _detailRow('Investor', r['investor_name']),
            _detailRow('ISIN', r['isin']),
            _detailRow('Folio', r['folio_number']),
            _detailRow('Units', r['total_units']?.toString()),
            _detailRow('Invested Value', '₹${_formatCurrency(r['invested_value'] as num? ?? 0)}'),
            _detailRow('Current Value', '₹${_formatCurrency((r['total_units'] as num? ?? 0) * (r['latest_nav'] as num? ?? 0))}'),
            _detailRow('Latest NAV', r['latest_nav']?.toString()),
            _detailRow('NAV Date', r['latest_nav_date']),
            const Divider(),
            const Text('Raw Data:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
              child: SelectableText(r['raw_data'] ?? '{}', style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.6,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, sc) => ClipRRect(
          borderRadius: BorderRadius.vertical(top: const Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: StatefulBuilder(
              builder: (ctx, setLocalState) => Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.4),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: DefaultTabController(
                  length: 4,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: Column(
                          children: [
                            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2))),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.indigo[900])),
                                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))
                              ],
                            ),
                          ],
                        ),
                      ),
                      TabBar(
                        isScrollable: true,
                        labelColor: Colors.indigo[900],
                        unselectedLabelColor: Colors.grey[700],
                        indicatorColor: Colors.indigo[900],
                        tabs: [
                          const Tab(child: Text('General'), icon: Icon(Icons.settings_outlined)),
                          Tab(child: txt('Sync'), icon: const Icon(Icons.sync_outlined)),
                          Tab(child: txt('UI'), icon: const Icon(Icons.palette_outlined)),
                          Tab(child: txt('Tools'), icon: const Icon(Icons.build_outlined)),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildGeneralSettings(setLocalState, sc),
                            _buildSyncSettings(setLocalState, sc),
                            _buildUISettings(setLocalState, sc),
                            _buildToolsSettings(sc),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGeneralSettings(StateSetter setLocalState, ScrollController sc) {
    return ListView(
      controller: sc,
      padding: const EdgeInsets.all(20),
      children: [
        ListTile(
          title: const Text('App Language', style: TextStyle(fontSize: 14)),
          subtitle: Text(_selectedLanguage, style: const TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.language),
          onTap: () {
            showDialog(context: context, builder: (ctx) => AlertDialog(
              title: txt('Choose Language'),
              content: Column(mainAxisSize: MainAxisSize.min, children: ['English', 'Hindi', 'Marathi', 'Gujarati', 'Tamil', 'Telugu', 'Kannada', 'Bengali', 'Malayalam', 'Punjabi'].map((l) => RadioListTile<String>(
                  title: Text(l), value: l, groupValue: _selectedLanguage,
                  onChanged: (v) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('selectedLanguage', v!);
                    setState(() => _selectedLanguage = v);
                    Navigator.pop(ctx);
                    setLocalState(() {});
                  }
              )).toList()),
            ));
          },
        ),
        _settingSwitch('Open Portfolio First', 'Launch directly to your holdings', _setOpenPortfolioFirst, (v) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('setOpenPortfolioFirst', v);
          setState(() => _setOpenPortfolioFirst = v);
          setLocalState(() {});
        }),
        _settingSwitch('Privacy Mode', 'Mask portfolio values with asterisks', _setPrivacyMode, (v) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('setPrivacyMode', v);
          setState(() => _setPrivacyMode = v);
          setLocalState(() {});
        }),
        _settingSwitch('Hide Zero Holdings', 'Only show funds with units > 0', _setHideZeroHoldings, (v) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('setHideZeroHoldings', v);
          setState(() => _setHideZeroHoldings = v);
          await _loadPortfolio();
          _fetchFiiDii();
          _fetchIndices();
          setLocalState(() {});
        }),
      ],
    );
  }

  Widget _buildSyncSettings(StateSetter setLocalState, ScrollController sc) {
    return ListView(
      controller: sc,
      padding: const EdgeInsets.all(20),
      children: [
        _settingSwitch('Daily Auto-Refresh', 'Schedule background sync', _setEnableBackgroundSync, (v) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('setEnableBackgroundSync', v);
          setState(() => _setEnableBackgroundSync = v);
          setLocalState(() {});
        }),
        ListTile(
          title: txt('Sync Time', style: const TextStyle(fontSize: 14)),
          subtitle: Text('Refresh every day at $_setSyncTime', style: const TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.access_time),
          onTap: () async {
            final parts = _setSyncTime.split(":");
            final initialTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
            final picked = await showTimePicker(context: context, initialTime: initialTime);
            if (picked != null) {
              final newTime = "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('setSyncTime', newTime);
              setState(() => _setSyncTime = newTime);
              setLocalState(() {});
            }
          },
        ),
        ListTile(
          title: txt('API Timeout', style: const TextStyle(fontSize: 14)),
          subtitle: Text('$_setApiTimeout seconds', style: const TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.timer_outlined),
          onTap: () {
            final ctl = TextEditingController(text: _setApiTimeout.toString());
            showDialog(context: context, builder: (ctx) => AlertDialog(
              title: txt('API Timeout (s)'),
              content: TextField(controller: ctl, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Enter seconds')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: txt('Cancel')),
                TextButton(onPressed: () async {
                  final v = int.tryParse(ctl.text);
                  if (v != null && v > 0) {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt('setApiTimeout', v);
                    setState(() => _setApiTimeout = v);
                    Navigator.pop(ctx);
                    setLocalState(() {});
                  }
                }, child: txt('Save'))
              ],
            ));
          },
        ),
        ListTile(
          title: txt('Lookback Window', style: const TextStyle(fontSize: 14)),
          subtitle: Text('Fetch last $_setRefreshDays business days on refresh', style: const TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.history),
          onTap: () {
            showDialog(context: context, builder: (ctx) => AlertDialog(
              title: txt('Lookback Days'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [1, 3, 5, 7, 10, 30].map((d) => RadioListTile<int>(
                  title: Text('$d business days'), value: d, groupValue: _setRefreshDays,
                  onChanged: (v) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt('setRefreshDays', v!);
                    setState(() => _setRefreshDays = v);
                    Navigator.pop(ctx);
                    setLocalState(() {});
                  }
              )).toList()),
            ));
          },
        ),
      ],
    );
  }

  Widget _buildUISettings(StateSetter setLocalState, ScrollController sc) {
    return ListView(
      controller: sc,
      padding: const EdgeInsets.all(20),
      children: [
        _settingSwitch('Compact Layout', 'Fit more rows on screen', _setCompactLayout, (v) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('setCompactLayout', v);
          setState(() => _setCompactLayout = v);
          setLocalState(() {});
        }),
        _settingSwitch('Show Folio in List', 'Display folio numbers in portfolio', _setShowFolioInList, (v) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('setShowFolioInList', v);
          setState(() => _setShowFolioInList = v);
          setLocalState(() {});
        }),
        _settingSwitch('Show Wallet Icons', 'Highlight held funds in NAV list', _setShowIconsInNav, (v) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('setShowIconsInNav', v);
          setState(() => _setShowIconsInNav = v);
          setLocalState(() {});
        }),
        _settingSwitch('Prioritize Held & Fav', 'Always show relevant funds at top', _setPrioritizeHeldAndFav, (v) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('setPrioritizeHeldAndFav', v);
          setState(() => _setPrioritizeHeldAndFav = v);
          await _load();
          setLocalState(() {});
        }),
        ListTile(
          title: txt('Appearance', style: const TextStyle(fontSize: 14)),
          subtitle: Text(_setThemeMode.toString().split('.').last.toUpperCase(), style: const TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.palette),
          onTap: () {
            showDialog(context: context, builder: (ctx) => AlertDialog(
              title: txt('Choose Theme'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [ThemeMode.system, ThemeMode.light, ThemeMode.dark].map((m) => RadioListTile<ThemeMode>(
                  title: Text(m.toString().split('.').last.toUpperCase()), value: m, groupValue: _setThemeMode,
                  onChanged: (v) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('setThemeMode', v!.toString().split('.').last);
                    setState(() => _setThemeMode = v);
                    widget.onThemeChanged(v);
                    Navigator.pop(ctx);
                    setLocalState(() {});
                  }
              )).toList()),
            ));
          },
        ),
      ],
    );
  }

  Widget _buildToolsSettings(ScrollController sc) {
    return ListView(
      controller: sc,
      padding: const EdgeInsets.all(20),
      children: [
        _actionTile('Fetch Range of NAVs', Icons.date_range, _showFetchRangeDialog),
        _actionTile('Clear Data in Range', Icons.delete_sweep_outlined, _showClearInRange),
        _actionTile('Cache Explorer', Icons.storage, _showCacheExplorer),
        const Divider(),
        _actionTile('Manage Imports', Icons.settings, _showManageImportsDialog),
        _actionTile('App Features', Icons.info_outline, _showFeaturesDialog),
        _actionTile('Disclosures', Icons.gavel_outlined, _showDisclosuresDialog),
      ],
    );
  }

  void _showFetchRangeDialog() async {
    DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() => _loading = true);
      try {
        final dates = <String>[];
        var curr = picked.start;
        while (curr.isBefore(picked.end) || curr.isAtSameMomentAs(picked.end)) {
          if (curr.weekday != DateTime.saturday && curr.weekday != DateTime.sunday) {
            dates.add(DateFormat('yyyy-MM-dd').format(curr));
          }
          curr = curr.add(const Duration(days: 1));
        }

        if (dates.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No business days in range')));
          return;
        }

        final start = DateTime.now();
        final count = await _repo.fetchAndImport(specificDates: dates, timeoutSeconds: _setApiTimeout);
        final end = DateTime.now();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fetched $count records in ${end.difference(start).inSeconds}s')));
        await _load();
        await _loadPortfolio();
        _fetchFiiDii();
        _fetchIndices();
      } catch (e) {
        if (mounted) {
          showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Fetch Failed'), content: Text('Error: $e'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))]));
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  void _showClearInRange() async {
    DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      final from = DateFormat('yyyy-MM-dd').format(picked.start);
      final to = DateFormat('yyyy-MM-dd').format(picked.end);

      bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Clear Records?'),
          content: Text('This will delete all NAV history between $from and $to.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear', style: TextStyle(color: Colors.red))),
          ],
        ),
      );

      if (confirm == true) {
        final count = await _repo.clearDataInRange(from, to);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted $count records')));
        _load();
      }
    }
  }

  void _showCacheExplorer() {
    Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => _CacheExplorerPage(repo: _repo, txt: txt)));
  }

  void _showFeaturesDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            _InfinLogo(size: 28),
            const SizedBox(width: 12),
            txt('App Features', style: TextStyle(color: Colors.indigo[900])),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _featureItem(Icons.sync, 'Live AMFI Sync', 'Real-time NAV updates directly from the official AMFI API.'),
              _featureItem(Icons.group, 'Family Consolidation', 'Import multiple Indmoney statements to track your entire family in one view.'),
              _featureItem(Icons.trending_up, '1-Day Returns', 'Instantly toggle between total profit and today\'s market movement.'),
              _featureItem(Icons.currency_rupee, 'Indian Formatting', 'Clean display of values using the Indian numbering system (Lakhs/Crores).'),
              const SizedBox(height: 12),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text('Version 1.0.0 \u2022 Developed for high-performance financial tracking.',
                    style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic)),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: txt('Got it!'))],
      ),
    );
  }

  void _showDisclosuresDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: txt('Legal Disclosures', style: TextStyle(color: Colors.indigo[900])),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              txt('Disclaimer', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              txt(
                'Infin Trulite is a data tracking tool only. It does not provide financial, investment, or legal advice. All mutual fund investments are subject to market risks.',
                style: const TextStyle(fontSize: 11, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              txt('Data Source', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              txt(
                'All Mutual Fund NAV data is sourced from AMFI (Association of Mutual Funds in India). While we strive for accuracy, the developer is not responsible for any discrepancies in the data.',
                style: const TextStyle(fontSize: 11, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              txt('Privacy', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              txt(
                'Your portfolio data and statement imports are stored exclusively on your device. We do not upload or store your financial information on any remote server.',
                style: const TextStyle(fontSize: 11, color: Colors.black87),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: txt('Accept'))],
      ),
    );
  }

  Widget _actionTile(String title, IconData icon, Function onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.indigo, size: 20),
      title: txt(title, style: const TextStyle(fontSize: 14)),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }

  Future<void> _pickAndImportFile() async {
    const typeGroup = XTypeGroup(label: 'Excel/CSV', extensions: ['xlsx', 'csv']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;

    setState(() => _loading = true);
    try {
      final count = await _portfolio.importXlsxFile(file.path);
      await _loadPortfolio();
      _fetchFiiDii();
      _fetchIndices();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported $count portfolio items')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showManageImportsDialog() async {
    final imports = await _portfolio.listImports();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: txt('Manage Imports'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: imports.length,
            itemBuilder: (c, i) {
              final imp = imports[i];
              return ListTile(
                title: Text(imp['file_name'] ?? 'Unknown File'),
                subtitle: Text('Imported: ${imp['imported_at']}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () async {
                    await _portfolio.deleteImport(imp['id']);
                    Navigator.pop(ctx);
                    _showManageImportsDialog();
                    _loadPortfolio();
                  },
                ),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  void _showPortfolioCharts() async {
    final amcMap = <String, double>{};
    final invMap = <String, double>{};
    final typeMap = <String, double>{};
    final catMap = <String, double>{};
    final schemeMap = <String, double>{};
    final segmentFunds = <String, List<Map<String, dynamic>>>{};
    double totalVal = 0;

    for (var r in _portfolioRows) {
      final units = (r['total_units'] as num? ?? 0).toDouble();
      final nav = (r['latest_nav'] as num? ?? 0).toDouble();
      final val = units * nav;
      if (val <= 0) continue;
      totalVal += val;

      final amc = r['mf_name'] ?? 'Others';
      amcMap[amc] = (amcMap[amc] ?? 0) + val;
      segmentFunds.putIfAbsent('AMC:$amc', () => []).add({'name': r['fund_name'], 'value': val});

      final inv = r['investor_name'] ?? 'Others';
      invMap[inv] = (invMap[inv] ?? 0) + val;
      segmentFunds.putIfAbsent('INV:$inv', () => []).add({'name': r['fund_name'], 'value': val});

      final cat = r['category_name'] ?? 'Others';
      catMap[cat] = (catMap[cat] ?? 0) + val;
      segmentFunds.putIfAbsent('CAT:$cat', () => []).add({'name': r['fund_name'], 'value': val});

      final scheme = r['fund_name'] ?? 'Unknown';
      schemeMap[scheme] = (schemeMap[scheme] ?? 0) + val;
      segmentFunds.putIfAbsent('FUND:$scheme', () => []).add({'name': r['fund_name'], 'value': val});

      final type = scheme.toUpperCase().contains('DIRECT') ? 'Direct' : 'Regular';
      typeMap[type] = (typeMap[type] ?? 0) + val;
      segmentFunds.putIfAbsent('TYPE:$type', () => []).add({'name': r['fund_name'], 'value': val});
    }

    final amcData = amcMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final invData = invMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final catData = catMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final typeData = typeMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final schemeData = schemeMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final profitMap = <String, double>{};
    for (var r in _portfolioRows) {
      final units = (r['total_units'] as num? ?? 0).toDouble();
      final latestNav = (r['latest_nav'] as num? ?? 0).toDouble();
      final invested = (r['invested_value'] as num? ?? 0).toDouble();
      final profit = (units * latestNav) - invested;
      if (profit > 0) {
        profitMap[r['fund_name']] = profit;
      }
    }
    final profitableData = profitMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final hist = await _portfolio.getHistoricalValue(importIds: _selectedImportIds?.toList());

    Navigator.push(context, MaterialPageRoute(builder: (c) => _PortfolioChartsPage(
      amcData: amcData,
      investorData: invData,
      typeData: typeData,
      categoryData: catData,
      schemeData: schemeData,
      profitableData: profitableData,
      historyData: hist,
      segmentFunds: segmentFunds,
      totalValue: totalVal,
      formatCurrency: _formatCurrency,
      detailRow: _detailRow,
      txt: txt,
    )));
  }

  Future<void> _launchExternalUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  // --- TAB BUILDERS ---

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              _InfinLogo(size: 32),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Infin', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, height: 1.0)),
                  Text('Trulite', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w300, height: 1.0, color: Colors.indigo[100])),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(_selectedFilterDate == null ? Icons.calendar_today : Icons.calendar_month, size: 20),
              onPressed: () => _selectDate(context),
              tooltip: 'Select Date',
            ),
            IconButton(
              icon: Icon(_setPrivacyMode ? Icons.visibility_off : Icons.visibility, size: 20),
              tooltip: _setPrivacyMode ? 'Disable Privacy Mode' : 'Enable Privacy Mode',
              onPressed: () async {
                if (_setPrivacyMode) {
                  bool? confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: txt('Show Balances?'),
                      content: txt('Portfolio values will be visible on the screen.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: txt('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: txt('Show', style: const TextStyle(color: Colors.red))),
                      ],
                    ),
                  );
                  if (confirm != true) return;
                }

                final newVal = !_setPrivacyMode;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('setPrivacyMode', newVal);
                setState(() => _setPrivacyMode = newVal);
              },
            ),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh, tooltip: 'Sync NAVs'),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'import') _pickAndImportFile();
                else if (v == 'manage') _showManageImportsDialog();
                else if (v == 'settings') _showSettingsMenu();
                else if (v == 'clear_date') {
                  setState(() => _selectedFilterDate = null);
                  _load();
                  _loadPortfolio();
                }
              },
              itemBuilder: (ctx) => [
                if (_selectedFilterDate != null)
                  PopupMenuItem(
                      value: 'clear_date',
                      child: Row(children: [const Icon(Icons.clear, size: 20, color: Colors.red), const SizedBox(width: 8), txt('Clear Date Filter')])
                  ),
                PopupMenuItem(
                    value: 'import',
                    child: Row(
                        children: [
                          const Icon(Icons.file_upload, size: 20, color: Colors.indigo),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              txt('Import Portfolio'),
                              const Text('Excel/CSV Support', style: TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          )
                        ]
                    )
                ),
                PopupMenuItem(value: 'manage', child: Row(children: [const Icon(Icons.layers, size: 20, color: Colors.indigo), const SizedBox(width: 8), txt('Manage Imports')])),
                PopupMenuItem(value: 'settings', child: Row(children: [const Icon(Icons.tune, size: 20, color: Colors.indigo), const SizedBox(width: 8), const Text('Settings')])),
              ],
            ),
          ],
        ),
        body: TabBarView(
          controller: _tabCtl,
          children: [
            _buildHomeTab(),
            _buildNavsTab(),
            _buildPortfolioTab(),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            _tabCtl.animateTo(index);
          },
          selectedItemColor: Colors.indigo[900],
          unselectedItemColor: Colors.grey,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.show_chart), label: 'Funds'),
            BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Portfolio'),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeTab() {
    double totalInv = 0, totalCur = 0, totalDayGain = 0;
    for (var r in _portfolioRows) {
      final units = (r['total_units'] as num? ?? 0).toDouble();
      final latestNav = (r['latest_nav'] as num? ?? 0).toDouble();
      final prevNav = (r['prev_nav'] as num? ?? 0).toDouble();
      totalInv += (r['invested_value'] as num? ?? 0).toDouble();
      totalCur += units * latestNav;
      if (latestNav > 0 && prevNav > 0) {
        totalDayGain += units * (latestNav - prevNav);
      }
    }
    final netGain = totalCur - totalInv;
    final netPct = (totalInv > 0) ? (netGain / totalInv * 100) : 0;
    final dayPct = (totalCur - totalDayGain > 0) ? (totalDayGain / (totalCur - totalDayGain) * 100) : 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Portfolio Overview Card
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [Colors.indigo[900]!, Colors.indigo[700]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                txt(t('synopsis'), style: const TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                Text('₹${_formatCurrency(totalCur)}', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _synopsisItem(t('net_gain'), netGain.toDouble(), netPct.toDouble()),
                    _synopsisItem(t('day_gain'), totalDayGain.toDouble(), dayPct.toDouble()),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),
        txt(t('quick_access'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo[900])),
        const SizedBox(height: 12),

        // Grid of Quick Access Tiles
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.5,
          children: [
            _homeTile('Live NAVs', Icons.show_chart, Colors.blue, () => _tabCtl.animateTo(1)),
            _homeTile('Portfolio', Icons.account_balance_wallet, Colors.green, () => _tabCtl.animateTo(2)),
            _homeTile('Analytics', Icons.bar_chart, Colors.orange, _showPortfolioCharts),
            _homeTile('Import', Icons.file_upload, Colors.purple, _pickAndImportFile),
            _fiiDiiTile(),
            _indicesTile(),
          ],
        ),

        const SizedBox(height: 32),
        // Sync Status & Info
        if (_lastSyncLog != null) ...[
          txt('Recent Activity', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[300]!)),
            child: Column(
              children: [
                _infoRow('Last Sync', _formatImportedAt(_lastSyncLog!['end_time'])),
                _infoRow('Rows Fetched', _lastSyncLog!['rows_fetched'].toString()),
                _infoRow('Duration', '${(_lastSyncLog!['duration_ms'] / 1000).toStringAsFixed(1)}s'),
                _infoRow('Status', _lastSyncLog!['status'], color: _lastSyncLog!['status'] == 'Success' ? Colors.green : Colors.red),
              ],
            ),
          ),
        ],

        const SizedBox(height: 32),
        // App Guide / Feature Items
        txt('App Guide', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _featureItem(Icons.auto_awesome, 'Smart Grouping', 'Your holdings are automatically grouped by ISIN for better clarity.'),
        _featureItem(Icons.translate, 'Vernacular Support', 'Access the app in your preferred language via Settings.'),
        _featureItem(Icons.security, 'Privacy First', 'Enable Privacy Mode to hide balances while browsing in public.'),
        _featureItem(Icons.cloud_sync, 'Auto Updates', 'Enable background sync to keep your NAVs updated daily.'),

        const SizedBox(height: 40),
        Center(
          child: Opacity(
            opacity: 0.5,
            child: Column(
              children: [
                const Text('Infin Trulite v1.2.0', style: TextStyle(fontSize: 10)),
                const Text('\u00a9 2026 Infin Solutions', style: TextStyle(fontSize: 10)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _synopsisItem(String label, double value, double pct) {
    final color = value >= 0 ? Colors.greenAccent[400] : Colors.redAccent[100];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        txt(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          '${value >= 0 ? '+' : ''}₹${_formatCurrency(value)}',
          style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(
          '(${pct.toStringAsFixed(2)}%)',
          style: TextStyle(color: color, fontSize: 12),
        ),
      ],
    );
  }

  void _showFiiDiiDetails() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                txt('FII / DII Trade Data', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const Divider(),
            if (_fiiDiiData.isEmpty)
              const Expanded(child: Center(child: Text('No FII/DII data available.')))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _fiiDiiData.length,
                  itemBuilder: (context, index) {
                    final d = _fiiDiiData[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                txt(d.category, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text(d.date, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _tradeValueItem('Buy', d.buyValue, Colors.blue),
                                _tradeValueItem('Sell', d.sellValue, Colors.red),
                                _tradeValueItem('Net', d.netValue, d.netValue >= 0 ? Colors.green : Colors.red),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 10),
            Text('Values in Crores (₹). Data from NSE India.', style: TextStyle(fontSize: 10, color: Colors.grey[600], fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  Widget _tradeValueItem(String label, double val, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(val.toStringAsFixed(2), style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
      ],
    );
  }

  Widget _fiiDiiTile() {
    FiiDiiData? fii, dii;
    if (_fiiDiiData.isNotEmpty) {
      try {
        fii = _fiiDiiData.firstWhere((d) => d.category.contains('FII'));
      } catch (_) {}
      try {
        dii = _fiiDiiData.firstWhere((d) => d.category.contains('DII'));
      } catch (_) {}
    }

    return InkWell(
      onTap: _showFiiDiiDetails,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: _fetchingFiiDii
            ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.swap_horizontal_circle, color: Colors.indigo[700], size: 20),
                      const SizedBox(width: 6),
                      txt('FII/DII', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (fii != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('FII', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        Text('${fii.netValue > 0 ? '+' : ''}${fii.netValue.toInt()}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fii.netValue >= 0 ? Colors.green : Colors.red)),
                      ],
                    ),
                  if (dii != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('DII', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        Text('${dii.netValue > 0 ? '+' : ''}${dii.netValue.toInt()}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: dii.netValue >= 0 ? Colors.green : Colors.red)),
                      ],
                    ),
                  if (fii == null && dii == null)
                    const Text('No Data', style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
      ),
    );
  }

  void _showIndicesDetails() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                txt('Market Indices', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const Divider(),
            if (_indicesData.isEmpty)
              const Expanded(child: Center(child: Text('No index data available.')))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _indicesData.length,
                  itemBuilder: (context, index) {
                    final d = _indicesData[index];
                    return ListTile(
                      title: txt(d.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Last: ${d.last}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${d.variation > 0 ? '+' : ''}${d.variation.toStringAsFixed(2)}',
                              style: TextStyle(color: d.variation >= 0 ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                          Text('${d.percentChange > 0 ? '+' : ''}${d.percentChange.toStringAsFixed(2)}%',
                              style: TextStyle(color: d.percentChange >= 0 ? Colors.green : Colors.red, fontSize: 12)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 10),
            Text('Data from NSE India.', style: TextStyle(fontSize: 10, color: Colors.grey[600], fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  Widget _indicesTile() {
    IndexData? nifty, next50;
    if (_indicesData.isNotEmpty) {
      try {
        nifty = _indicesData.firstWhere((d) => d.name.toUpperCase().contains('NIFTY 50'));
      } catch (_) {}
      try {
        next50 = _indicesData.firstWhere((d) => d.name.toUpperCase().contains('NIFTY NEXT 50'));
      } catch (_) {}
    }

    return InkWell(
      onTap: _showIndicesDetails,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: _fetchingIndices
            ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.analytics, color: Colors.indigo[700], size: 20),
                      const SizedBox(width: 6),
                      txt('Indices', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (nifty != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('NIFTY', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        Text('${nifty.percentChange > 0 ? '+' : ''}${nifty.percentChange.toStringAsFixed(2)}%',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: nifty.percentChange >= 0 ? Colors.green : Colors.red)),
                      ],
                    ),
                  if (next50 != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('NEXT50', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        Text('${next50.percentChange > 0 ? '+' : ''}${next50.percentChange.toStringAsFixed(2)}%',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: next50.percentChange >= 0 ? Colors.green : Colors.red)),
                      ],
                    ),
                  if (_indicesData.isEmpty)
                    const Text('No Data', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  if (_indicesData.isNotEmpty && nifty == null && next50 == null)
                    Text(_indicesData.first.name.split(' ').first, style: const TextStyle(fontSize: 10, color: Colors.grey), overflow: TextOverflow.ellipsis),
                ],
              ),
      ),
    );
  }

  Widget _homeTile(String title, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            txt(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildNavsTab() {
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (_lastSyncLog != null)
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      txt('Source: ', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                      Text('AMFI India (${_formatImportedAt(_lastSyncLog!['end_time'])})',
                          style: const TextStyle(fontSize: 10, color: Colors.black54)),
                    ],
                  ),
                ),
              ),
            if (_selectedFilterDate != null)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.amber[100], borderRadius: BorderRadius.circular(4)),
                child: Text('Date: ${DateFormat('dd-MMM-yyyy').format(_selectedFilterDate!)}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber[900])),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 45,
          child: TextField(
            controller: _searchCtl,
            focusNode: _searchFocus,
            onSubmitted: (v) => _updateSearchHistory(v),
            onChanged: (v) {
              setState(() {});
              _load(silent: true);
            },
            style: const TextStyle(fontSize: 14, color: Colors.black87),
            decoration: InputDecoration(
              hintText: t('search'),
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20, color: Colors.blueGrey),
              suffixIcon: _searchCtl.text.isNotEmpty
                  ? IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.cancel, size: 20, color: Colors.grey),
                onPressed: () {
                  _searchCtl.clear();
                  setState(() {});
                  _load();
                },
              )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
        ),
        if (_showSuggestions)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, spreadRadius: 1)]
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _recentSearches.length,
              itemBuilder: (context, index) {
                final s = _recentSearches[index];
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: const Icon(Icons.history, size: 18, color: Colors.grey),
                  title: Text(s, style: const TextStyle(fontSize: 13)),
                  onTap: () {
                    _searchCtl.text = s;
                    _searchFocus.unfocus();
                    _load();
                  },
                  trailing: IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        setState(() => _recentSearches.remove(s));
                        _savePrefs();
                      }
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _fundTypes.map((tVal) {
              final selected = tVal == _selectedFundType;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: txt(tVal, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
                  selected: selected,
                  selectedColor: Colors.indigo[100],
                  checkmarkColor: Colors.indigo,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  onSelected: (vVal) async {
                    if (vVal) {
                      setState(() => _selectedFundType = tVal);
                      await _savePrefs();
                      _load();
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 5,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedCompany,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                    items: _amcList.map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s == 'All Companies' ? t('all_amc') : s, overflow: TextOverflow.ellipsis)
                    )).toList(),
                    onChanged: (vVal) {
                      if (vVal == null) return;
                      setState(() => _selectedCompany = vVal);
                      _load();
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              flex: 4,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _sortOption,
                    style: TextStyle(fontSize: 12, color: Colors.indigo[700], fontWeight: FontWeight.w600),
                    icon: Icon(Icons.sort, size: 16, color: Colors.indigo[700]),
                    items: [
                      'Return \u2193', 'Return \u2191', 'Name A-Z', 'Name Z-A',
                      'Nav Date \u2193', 'Nav Date \u2191',
                      'Nav report time \u2193', 'Nav report time \u2191'
                    ].map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (vVal) {
                      if (vVal == null) return;
                      setState(() => _sortOption = vVal);
                      _load();
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_loading) const Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: LinearProgressIndicator(minHeight: 2)),
      ],
    );

    return Scrollbar(
      controller: _scrollCtl,
      interactive: true,
      thickness: 6,
      radius: const Radius.circular(3),
      child: ListView.separated(
        controller: _scrollCtl,
        padding: const EdgeInsets.all(12.0),
        itemCount: _items.isEmpty ? 2 : _items.length + 1,
        separatorBuilder: (context, index) => index == 0 ? const SizedBox() : Divider(height: 1, thickness: 0.5, color: Colors.grey[200]),
        itemBuilder: (c, i) {
          if (i == 0) return header;
          if (_items.isEmpty) return Container(height: 300, child: Center(child: txt(t('no_data'))));

          final it = _items[i - 1];
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            visualDensity: _setCompactLayout ? VisualDensity.compact : VisualDensity.standard,
            onTap: () => _showDetails(it),
            title: txt(it.schemeName ?? '-',
                style: TextStyle(fontSize: _setCompactLayout ? 13 : 14, fontWeight: it.isFavorite ? FontWeight.w700 : FontWeight.w500, color: Colors.indigo[900])),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(child: Text('${it.navDate ?? ''}  \u2022  ${it.apiTimestamp != null ? _formatImportedAt(it.apiTimestamp!) : ''}',
                        style: TextStyle(fontSize: _setCompactLayout ? 10 : 11, color: Colors.grey[600]))),
                    if (_setShowIconsInNav) ...[
                      if (it.isHeld) Padding(padding: const EdgeInsets.only(right: 6.0), child: Icon(Icons.account_balance_wallet, size: 12, color: Colors.indigo[400])),
                      if (it.isFavorite) Icon(Icons.star, size: 12, color: Colors.amber[700]),
                    ],
                  ],
                ),
              ],
            ),
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(it.navValue?.toString() ?? '-', style: TextStyle(fontWeight: FontWeight.bold, fontSize: _setCompactLayout ? 13 : 14)),
                if (it.prevNavValue != null)
                  Builder(builder: (ctx) {
                    final diff = (it.navValue ?? 0) - (it.prevNavValue ?? 0);
                    final pct = (it.prevNavValue != null && it.prevNavValue! != 0) ? (diff / it.prevNavValue! * 100) : null;
                    final txtStr = (diff >= 0 ? '+' : '') + diff.toStringAsFixed(4) + (pct != null ? ' (${pct.toStringAsFixed(2)}%)' : '');
                    return Text(txtStr, style: TextStyle(color: diff >= 0 ? Colors.green[700] : Colors.red[700], fontSize: _setCompactLayout ? 10 : 11));
                  }),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPortfolioTab() {
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: InkWell(
                onTap: () {
                  setState(() => _showNetReturns = !_showNetReturns);
                  _loadPortfolio();
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _showNetReturns ? Colors.orange[50] : Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: (_showNetReturns ? Colors.orange[200] : Colors.green[200])!),
                  ),
                  child: Row(
                    children: [
                      Icon(
                          _showNetReturns ? Icons.pie_chart : Icons.trending_up,
                          size: 16,
                          color: _showNetReturns ? Colors.orange[800] : Colors.green[800]
                      ),
                      const SizedBox(width: 8),
                      txt(_showNetReturns ? 'Viewing Net Returns' : 'Viewing $_portfolioPeriod Returns',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _showNetReturns ? Colors.orange[900] : Colors.green[900])),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: Icon(Icons.bar_chart, color: Colors.indigo[900]),
              onPressed: _showPortfolioCharts,
              tooltip: 'Portfolio Analytics',
            ),
          ],
        ),
        if (_selectedFilterDate != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.amber[200]!)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.filter_list, size: 14, color: Colors.amber),
                  const SizedBox(width: 6),
                  Text('Showing values as of: ${DateFormat('dd-MMM-yyyy').format(_selectedFilterDate!)}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 5,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedPortfolioCompany,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                    items: _portfolioAmcList.map((s) => DropdownMenuItem(value: s, child: txt(s, overflow: true))).toList(),
                    onChanged: (vVal) {
                      if (vVal == null) return;
                      setState(() => _selectedPortfolioCompany = vVal);
                      _loadPortfolio();
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              flex: 4,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _portfolioSortOption,
                    style: const TextStyle(fontSize: 12, color: Colors.indigo, fontWeight: FontWeight.bold),
                    items: [
                      'Invested \u2193', 'Invested \u2191', 'Value \u2193', 'Value \u2191',
                      'Return \u2193', 'Return \u2191', 'Name A-Z', 'Name Z-A'
                    ].map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (vVal) {
                      if (vVal == null) return;
                      setState(() => _portfolioSortOption = vVal);
                      _loadPortfolio();
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['1D', '1W', '1M', '3M', '6M', '1Y', '2Y', '3Y', '5Y', 'Custom'].map((pVal) {
              final selected = pVal == _portfolioPeriod;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(pVal, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
                  selected: selected,
                  selectedColor: Colors.indigo[900],
                  labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  onSelected: (vVal) {
                    if (vVal) _handlePeriodChange(pVal);
                  },
                ),
              );
            }).toList(),
          ),
        ),
        if (_fetchingHistorical) const Padding(padding: EdgeInsets.only(top: 10.0), child: LinearProgressIndicator(minHeight: 2)),
        const SizedBox(height: 12),
        Row(
          children: [
            txt('My Holdings', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(' (${_groupedPortfolio.length})', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          ],
        ),
        const SizedBox(height: 6),
      ],
    );

    final groupedIsins = _groupedPortfolio.keys.toList();

    return Column(
      children: [
        Expanded(
          child: _portfolioRows.isEmpty
              ? Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(children: [header, Expanded(child: Center(child: txt('No holdings imported yet')))]),
          )
              : Scrollbar(
            controller: _portfolioScrollCtl,
            interactive: true,
            thickness: 6,
            radius: const Radius.circular(3),
            child: ListView.separated(
              controller: _portfolioScrollCtl,
              padding: const EdgeInsets.all(16.0),
              itemCount: groupedIsins.length + 1,
              separatorBuilder: (context, index) => index == 0 ? const SizedBox() : Divider(height: 1, thickness: 0.5, color: Colors.grey[300]),
              itemBuilder: (c, i) {
                if (i == 0) return header;
                final isin = groupedIsins[i - 1];
                final list = _groupedPortfolio[isin]!;
                final isExpanded = _expandedGroups.contains(isin);

                double gInv = 0, gCur = 0, gPeriodGain = 0;
                for (var r in list) {
                  final inv = (r['invested_value'] as num? ?? 0).toDouble();
                  gInv += inv;
                  final units = (r['total_units'] as num? ?? 0).toDouble();
                  final latestNav = (r['latest_nav'] as num? ?? 0).toDouble();
                  final cur = units * latestNav;
                  gCur += cur;

                  if (latestNav > 0) {
                    double refPrevNav;
                    if (_portfolioPeriod == '1D') {
                      final prevNav = (r['prev_nav'] as num? ?? 0).toDouble();
                      refPrevNav = prevNav > 0 ? prevNav : latestNav;
                    } else {
                      refPrevNav = _periodNavs[r['isin']] ?? latestNav;
                    }
                    gPeriodGain += units * (latestNav - refPrevNav);
                  }
                }
                final gPct = (gInv > 0) ? ((gCur - gInv) / gInv * 100) : 0;
                final gPeriodPct = (gCur - gPeriodGain > 0) ? (gPeriodGain / (gCur - gPeriodGain) * 100) : 0;

                return Column(
                  children: [
                    ListTile(
                      dense: true,
                      visualDensity: _setCompactLayout ? VisualDensity.compact : VisualDensity.standard,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      onTap: () {
                        setState(() {
                          if (isExpanded) _expandedGroups.remove(isin);
                          else _expandedGroups.add(isin);
                        });
                      },
                      title: txt(list.first['fund_name'] ?? 'Unknown Fund',
                          style: TextStyle(fontSize: _setCompactLayout ? 13 : 14, fontWeight: FontWeight.w600, color: Colors.indigo[900])),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text('${list.length} holdings \u2022 \u20b9${_formatCurrency(gInv)}',
                                    style: TextStyle(fontSize: _setCompactLayout ? 10 : 11, color: Colors.grey[600])),
                              ),
                              Icon(isExpanded ? Icons.expand_less : Icons.expand_more, size: _setCompactLayout ? 16 : 18, color: Colors.grey),
                              if (_setShowIconsInNav) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.account_balance_wallet, size: 12, color: Colors.indigo[400]),
                              ],
                            ],
                          ),
                        ],
                      ),
                      trailing: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() => _showNetReturns = !_showNetReturns);
                          _loadPortfolio();
                        },
                        child: Container(
                          width: 100,
                          alignment: Alignment.centerRight,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: !_showNetReturns
                                    ? Text(
                                  '${gPeriodGain >= 0 ? '+' : ''}${_formatCurrency(gPeriodGain)} (${gPeriodPct.toStringAsFixed(2)}%)',
                                  style: TextStyle(fontSize: _setCompactLayout ? 11 : 12, fontWeight: FontWeight.bold, color: gPeriodGain >= 0 ? Colors.green[700] : Colors.red[700]),
                                )
                                    : RichText(
                                  text: TextSpan(
                                    style: TextStyle(fontSize: _setCompactLayout ? 12 : 13, fontWeight: FontWeight.bold, color: Colors.black87),
                                    children: [
                                      TextSpan(text: _formatCurrency(gCur)),
                                      TextSpan(
                                        text: ' (${gPct >= 0 ? '+' : ''}${gPct.toStringAsFixed(2)}%)',
                                        style: TextStyle(color: gPct >= 0 ? Colors.green[700] : Colors.red[700], fontSize: _setCompactLayout ? 10 : 11),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (isExpanded)
                      ...list.map((r) {
                        final double inv = (r['invested_value'] as num? ?? 0).toDouble();
                        final double u = (r['total_units'] as num? ?? 0).toDouble();
                        final double nav = (r['latest_nav'] as num? ?? 0).toDouble();
                        double curVal = 0, pGain = 0;
                        if (nav > 0) {
                          curVal = u * nav;
                          double refPrevNav;
                          if (_portfolioPeriod == '1D') {
                            final prevNav = (r['prev_nav'] as num? ?? 0).toDouble();
                            refPrevNav = prevNav > 0 ? prevNav : nav;
                          } else {
                            refPrevNav = _periodNavs[r['isin']] ?? nav;
                          }
                          pGain = u * (nav - refPrevNav);
                        }
                        return Container(
                          margin: const EdgeInsets.only(left: 16),
                          decoration: BoxDecoration(border: Border(left: BorderSide(color: Colors.indigo[100]!, width: 1))),
                          child: ListTile(
                            dense: true,
                            visualDensity: _setCompactLayout ? VisualDensity.compact : VisualDensity.standard,
                            onTap: () => _showPortfolioDetails(r),
                            title: Text(r['investor_name'] ?? 'Family', style: TextStyle(fontSize: _setCompactLayout ? 12 : 13, color: Colors.indigo[700], fontWeight: FontWeight.w500)),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: FittedBox(
                                      alignment: Alignment.centerLeft,
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                          'U: ${u.toStringAsFixed(3)}${_setShowFolioInList ? ' \u2022 F: ${r['folio_number'] ?? '-'}' : ''} \u2022 ${r['latest_nav_date'] ?? 'No NAV'}',
                                          style: TextStyle(fontSize: _setCompactLayout ? 10 : 11, color: Colors.grey[600])
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            trailing: Container(
                              width: 100,
                              alignment: Alignment.centerRight,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      !_showNetReturns ? '${pGain >= 0 ? '+' : ''}${_formatCurrency(pGain)}' : _formatCurrency(curVal),
                                      style: TextStyle(fontSize: _setCompactLayout ? 11 : 12, fontWeight: FontWeight.w500, color: !_showNetReturns ? (pGain >= 0 ? Colors.green[700] : Colors.red[700]) : Colors.black87),
                                    ),
                                  ),
                                  Text('\u20b9${_formatCurrency(inv)}', style: TextStyle(fontSize: _setCompactLayout ? 9 : 10, color: Colors.grey)),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                  ],
                );
              },
            ),
          ),
        ),

        // Sticky Summary Footer
        if (_portfolioRows.isNotEmpty)
          Builder(builder: (context) {
            double totalInv = 0, totalCur = 0, totalPeriodGain = 0, totalCurForPeriod = 0;
            int validPeriodCount = 0;
            for (var r in _portfolioRows) {
              final double units = (r['total_units'] as num? ?? 0).toDouble();
              final double latestNav = (r['latest_nav'] as num? ?? 0).toDouble();
              totalInv += (r['invested_value'] as num? ?? 0).toDouble();
              final cur = units * latestNav;
              totalCur += cur;

              if (latestNav > 0) {
                double refPrevNav;
                if (_portfolioPeriod == '1D') {
                  final prevNav = (r['prev_nav'] as num? ?? 0).toDouble();
                  refPrevNav = prevNav > 0 ? prevNav : latestNav;
                } else {
                  refPrevNav = _periodNavs[r['isin']] ?? latestNav;
                }

                totalPeriodGain += units * (latestNav - refPrevNav);
                totalCurForPeriod += cur;
                if (refPrevNav > 0) validPeriodCount++;
              }
            }
            final totalNetGain = totalCur - totalInv;
            final totalNetPct = (totalInv > 0) ? (totalNetGain / totalInv * 100) : 0;
            final totalPeriodPct = (totalCurForPeriod - totalPeriodGain > 0) ? (totalPeriodGain / (totalCurForPeriod - totalPeriodGain) * 100) : 0;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                  color: Colors.indigo[50],
                  border: Border(top: BorderSide(color: Colors.indigo[100]!, width: 2)),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))]
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      txt('TOTAL', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 16)),
                      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Row(
                        children: [
                          txt('Effective ', style: const TextStyle(fontSize: 10, color: Colors.indigo)),
                          Text('$validPeriodCount/${_portfolioRows.length} ', style: const TextStyle(fontSize: 10, color: Colors.indigo, fontWeight: FontWeight.bold)),
                          txt('matched', style: const TextStyle(fontSize: 10, color: Colors.indigo)),
                          txt(' for $_portfolioPeriod', style: const TextStyle(fontSize: 10, color: Colors.indigo)),
                        ],
                      )),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                    Text(
                        !_showNetReturns ? '${totalPeriodGain >= 0 ? '+' : ''}\u20b9${_formatCurrency(totalPeriodGain)}' : '\u20b9${_formatCurrency(totalCur)}',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: !_showNetReturns ? (totalPeriodGain >= 0 ? Colors.green[800] : Colors.red[800]) : Colors.black87)
                    ),
                    Text(
                        !_showNetReturns ? 'Period: ${totalPeriodPct.toStringAsFixed(2)}%' : '\u20b9${_formatCurrency(totalInv)} (${totalNetGain >= 0 ? '+' : ''}${totalNetPct.toStringAsFixed(2)}%)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: !_showNetReturns ? (totalPeriodGain >= 0 ? Colors.green[800] : Colors.red[800]) : (totalNetGain >= 0 ? Colors.green[800] : Colors.red[800]))
                    ),
                  ]),
                ],
              ),
            );
          }),
      ],
    );
  }

  @override
  void dispose() {
    _tabCtl.dispose();
    _searchCtl.dispose();
    _scrollCtl.dispose();
    _portfolioScrollCtl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // --- HELPER METHODS ---

  List<String> _getMilestoneDates(String period) {
    final now = DateTime.now();
    final dates = <DateTime>[];
    DateTime latest = now;
    while (latest.weekday == DateTime.saturday || latest.weekday == DateTime.sunday) {
      latest = latest.subtract(const Duration(days: 1));
    }

    dates.add(latest);
    if (period == 'Custom' && _customPortfolioRange != null) {
      dates.add(_customPortfolioRange!.start);
      dates.add(_customPortfolioRange!.end);
    } else {
      dates.add(_getPeriodStartDate(period, from: latest));
    }

    final sorted = dates.toSet().toList()..sort();
    return sorted.map((d) {
      var bd = d;
      while (bd.weekday == DateTime.saturday || bd.weekday == DateTime.sunday) {
        bd = bd.subtract(const Duration(days: 1));
      }
      return DateFormat('yyyy-MM-dd').format(bd);
    }).toSet().toList()..sort();
  }

  DateTime _getPeriodStartDate(String period, {DateTime? from}) {
    final base = from ?? DateTime.now();
    switch (period) {
      case '1D': return base.subtract(const Duration(days: 1));
      case '1W': return base.subtract(const Duration(days: 7));
      case '1M': return DateTime(base.year, base.month - 1, base.day);
      case '3M': return DateTime(base.year, base.month - 3, base.day);
      case '6M': return DateTime(base.year, base.month - 6, base.day);
      case '1Y': return DateTime(base.year - 1, base.month, base.day);
      case '2Y': return DateTime(base.year - 2, base.month, base.day);
      case '3Y': return DateTime(base.year - 3, base.month, base.day);
      case '5Y': return DateTime(base.year - 5, base.month, base.day);
      default: return base;
    }
  }

  Widget _featureItem(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.indigo[50], borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: Colors.indigo, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                txt(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
                txt(desc, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String? value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: txt(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey, fontSize: 13))),
          Expanded(flex: 3, child: SelectableText(value ?? '-', style: TextStyle(fontWeight: FontWeight.w400, color: color, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _settingSwitch(String title, String subtitle, bool val, Function(bool) onChanged) {
    return SwitchListTile(
      title: txt(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: txt(subtitle, style: const TextStyle(fontSize: 11)),
      value: val,
      onChanged: onChanged,
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }
}

// --- SUB-PAGES & CUSTOM COMPONENTS ---

class _PortfolioChartsPage extends StatefulWidget {
  final List<MapEntry<String, double>> amcData;
  final List<MapEntry<String, double>> investorData;
  final List<MapEntry<String, double>> typeData;
  final List<MapEntry<String, double>> categoryData;
  final List<MapEntry<String, double>> schemeData;
  final List<MapEntry<String, double>> profitableData;
  final List<MapEntry<String, double>> historyData;
  final Map<String, List<Map<String, dynamic>>> segmentFunds;
  final double totalValue;
  final String Function(num) formatCurrency;
  final Widget Function(String, String?, {Color? color}) detailRow;
  final Widget Function(String, {TextStyle? style, bool overflow, TextAlign? align}) txt;

  const _PortfolioChartsPage({
    required this.amcData,
    required this.investorData,
    required this.typeData,
    required this.categoryData,
    required this.schemeData,
    required this.profitableData,
    required this.historyData,
    required this.segmentFunds,
    required this.totalValue,
    required this.formatCurrency,
    required this.detailRow,
    required this.txt,
  });

  @override
  _PortfolioChartsPageState createState() => _PortfolioChartsPageState();
}

class _PortfolioChartsPageState extends State<_PortfolioChartsPage> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: widget.txt('Portfolio Analytics')),
      body: Scrollbar(
        child: ListView(
          padding: const EdgeInsets.all(20.0),
          children: [
            // Line Chart Section
            if (widget.historyData.isNotEmpty) ...[
              widget.txt('Portfolio Value Growth', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
              const SizedBox(height: 8),
              Text('Trend of your total holdings value over time', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 24),
              _growthChartSection(widget.historyData),
              const Divider(height: 60),
            ],

            // Pie Charts for Allocations
            _chartSection('Scheme Allocation', widget.schemeData, 'FUND', context),
            const Divider(height: 60),
            _chartSection('Asset Allocation (AMC)', widget.amcData, 'AMC', context),
            const Divider(height: 60),
            _chartSection('Family Distribution', widget.investorData, 'INV', context),
            const Divider(height: 60),
            _chartSection('Category Mix', widget.categoryData, 'CAT', context),
            const Divider(height: 60),
            _chartSection('Scheme Type', widget.typeData, 'TYPE', context),

            const Divider(height: 60),

            // Gainers List
            widget.txt('Top Gainers', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
            Text('Funds with highest absolute profit in your portfolio', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 16),
            _profitabilitySection(widget.profitableData),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Widget _growthChartSection(List<MapEntry<String, double>> data) {
    return Container(
      height: 250,
      padding: const EdgeInsets.only(right: 16, top: 16),
      child: LineChart(
        LineChartData(
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              tooltipBgColor: Colors.indigo[900]!,
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  return LineTooltipItem(
                    '${data[spot.x.toInt()].key}\n\u20b9${widget.formatCurrency(spot.y)}',
                    const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  );
                }).toList();
              },
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey[200]!, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: true, border: Border(bottom: BorderSide(color: Colors.grey[300]!), left: BorderSide(color: Colors.grey[300]!))),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      int idx = value.toInt();
                      if (idx >= 0 && idx < data.length) {
                        final parts = data[idx].key.split('-');
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text('${parts[2]}/${parts[1]}', style: const TextStyle(fontSize: 10)),
                        );
                      }
                      return const Text('');
                    }
                )
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(data.length, (i) => FlSpot(i.toDouble(), data[i].value)),
              isCurved: true,
              color: Colors.indigo,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: true, color: Colors.indigo.withOpacity(0.1)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chartSection(String title, List<MapEntry<String, double>> data, String prefix, BuildContext context) {
    final topItems = data.take(5).toList();
    final othersValue = data.length > 5 ? data.skip(5).fold(0.0, (sum, e) => sum + e.value) : 0.0;

    final List<PieChartSectionData> sections = [];
    final List<Color> colors = [Colors.indigo, Colors.blue, Colors.teal, Colors.orange, Colors.red, Colors.grey];

    for (int i = 0; i < topItems.length; i++) {
      final isTouched = i == _touchedIndex;
      final pct = (topItems[i].value / widget.totalValue * 100);
      sections.add(PieChartSectionData(
        value: topItems[i].value,
        title: '${pct.toStringAsFixed(1)}%',
        radius: isTouched ? 75 : 65,
        color: colors[i],
        titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
      ));
    }
    if (othersValue > 0) {
      sections.add(PieChartSectionData(
        value: othersValue,
        title: '${(othersValue / widget.totalValue * 100).toStringAsFixed(1)}%',
        radius: 65,
        color: colors.last,
        titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        widget.txt(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
        const SizedBox(height: 24),
        SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (FlTouchEvent event, pieTouchResponse) {
                  if (event is FlTapUpEvent || event is FlLongPressEnd) {
                    final index = pieTouchResponse?.touchedSection?.touchedSectionIndex ?? -1;
                    if (index >= 0 && index < topItems.length) {
                      _showSegmentDetails(topItems[index].key, prefix, topItems[index].value, context);
                    } else if (index == topItems.length && othersValue > 0) {
                      _showSegmentDetails('Others', prefix, othersValue, context);
                    }
                  }

                  setState(() {
                    if (!event.isInterestedForInteractions ||
                        pieTouchResponse == null ||
                        pieTouchResponse.touchedSection == null) {
                      _touchedIndex = -1;
                      return;
                    }
                    _touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                  });
                },
              ),
              sections: sections,
              centerSpaceRadius: 45,
              sectionsSpace: 2,
            ),
          ),
        ),
        const SizedBox(height: 24),
        ...List.generate(topItems.length, (i) => _legendItem(colors[i], topItems[i].key, topItems[i].value, prefix, context)),
        if (othersValue > 0) _legendItem(colors.last, 'Others', othersValue, prefix, context),
      ],
    );
  }

  Widget _profitabilitySection(List<MapEntry<String, double>> data) {
    if (data.isEmpty) return const Text('No gainers found.');
    return Column(
      children: data.take(10).map((e) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          dense: true,
          title: widget.txt(e.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), overflow: true),
          trailing: Text('\u20b9${widget.formatCurrency(e.value)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
        ),
      )).toList(),
    );
  }

  void _showSegmentDetails(String name, String prefix, double totalSegVal, BuildContext context) {
    final funds = widget.segmentFunds['$prefix:$name'] ?? [];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: widget.txt(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total Segment Value: \u20b9${widget.formatCurrency(totalSegVal)}',
                style: TextStyle(fontSize: 13, color: Colors.indigo[900], fontWeight: FontWeight.bold)),
            const Divider(),
            SizedBox(
              height: 300,
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: funds.length,
                itemBuilder: (c, i) {
                  final f = funds[i];
                  final double fVal = (f['value'] as num? ?? 0).toDouble();
                  final pct = totalSegVal > 0 ? (fVal / totalSegVal * 100) : 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        widget.txt(f['name'] ?? 'Unknown', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('\u20b9${widget.formatCurrency(fVal)}', style: TextStyle(fontSize: 11, color: Colors.grey[700])),
                            Text('${pct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo)),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  Widget _legendItem(Color color, String name, double value, String prefix, BuildContext context) {
    final pct = (value / widget.totalValue * 100).toStringAsFixed(1);
    return InkWell(
      onTap: () => _showSegmentDetails(name, prefix, value, context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8),
        child: Row(
          children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 12),
            Expanded(child: widget.txt(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: true)),
            Text('\u20b9${widget.formatCurrency(value)} ($pct%)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[800])),
          ],
        ),
      ),
    );
  }
}

class _InfinLogo extends StatelessWidget {
  final double size;
  const _InfinLogo({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _InfinPainter(),
      ),
    );
  }
}

class _InfinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Background Circle
    final circlePaint = Paint()
      ..color = const Color(0xFF1A237E)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w / 2, h / 2), w / 2, circlePaint);

    // Stylized "I" and "n"
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.12
      ..strokeCap = StrokeCap.round;

    final path = Path();
    // Dot of "i"
    canvas.drawCircle(Offset(w * 0.25, h * 0.25), size.width * 0.08, Paint()..color = Colors.white);

    // Body of "i"
    path.moveTo(w * 0.25, h * 0.4);
    path.lineTo(w * 0.25, h * 0.75);

    // "n" shape
    path.moveTo(w * 0.45, h * 0.75);
    path.lineTo(w * 0.45, h * 0.45);
    path.quadraticBezierTo(w * 0.55, h * 0.35, w * 0.75, h * 0.45);
    path.lineTo(w * 0.75, h * 0.75);

    // Bottom curve
    path.moveTo(w * 0.15, h * 0.85);
    path.quadraticBezierTo(w * 0.5, h * 0.95, w * 0.85, h * 0.85);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CacheExplorerPage extends StatefulWidget {
  final NavRepository repo;
  final Widget Function(String, {TextStyle? style, bool overflow, TextAlign? align}) txt;
  const _CacheExplorerPage({super.key, required this.repo, required this.txt});

  @override
  State<_CacheExplorerPage> createState() => _CacheExplorerPageState();
}

class _CacheExplorerPageState extends State<_CacheExplorerPage> {
  List<Map<String, dynamic>> _objects = [];
  bool _loading = true;
  String _totalSize = "Unknown";

  @override
  void initState() {
    super.initState();
    _loadSchema();
  }

  Future<void> _loadSchema({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final db = await widget.repo.db;
    try {
      final dbPath = await getDatabasesPath();
      final file = File(p.join(dbPath, 'nav.db'));
      if (file.existsSync()) {
        _totalSize = _formatSize(file.lengthSync());
      }
    } catch (_) {}

    Map<String, int> tableSizes = {};
    try {
      final List<Map<String, dynamic>> sizes = await db.rawQuery("SELECT name, SUM(pgsize) as size FROM dbstat GROUP BY name");
      for (var row in sizes) {
        tableSizes[row['name'] as String] = row['size'] as int;
      }
    } catch (e) {
      debugPrint('dbstat query failed: $e. Using fallback size estimation.');
    }

    final List<Map<String, dynamic>> master = await db.rawQuery(
        "SELECT type, name, tbl_name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_stat%' ORDER BY type, name"
    );

    final tables = <String, Map<String, dynamic>>{};
    final List<Map<String, dynamic>> indices = [];

    for (var item in master) {
      if (item['type'] == 'table') {
        final name = item['name'] as String;
        if (name.startsWith('sqlite_')) continue;
        int count = 0;
        try {
          final c = await db.rawQuery("SELECT COUNT(*) as count FROM $name");
          count = c.first['count'] as int;
        } catch (_) {}

        tables[name] = {
          ...item,
          'row_count': count,
          'size': tableSizes[name],
          'indices': <Map<String, dynamic>>[],
        };
      } else if (item['type'] == 'index') {
        indices.add(item);
      }
    }

    for (var idx in indices) {
      final tblName = idx['tbl_name'] as String;
      if (tables.containsKey(tblName)) {
        final idxSize = tableSizes[idx['name']] ?? 0;
        (tables[tblName]!['indices'] as List).add({
          'name': idx['name'],
          'size': idxSize,
        });
        tables[tblName]!['total_size'] = (tables[tblName]!['total_size'] ?? tables[tblName]!['size'] ?? 0) + idxSize;
      }
    }

    for (var tbl in tables.values) {
      if (tbl['total_size'] == null) tbl['total_size'] = tbl['size'] ?? 0;
    }

    if (mounted) {
      setState(() {
        final sortedList = tables.values.toList();
        sortedList.sort((a, b) => (b['total_size'] as num? ?? 0).compareTo(a['total_size'] as num? ?? 0));
        _objects = sortedList;
        _loading = false;
      });
    }
  }

  String _formatSize(int? bytes) {
    if (bytes == null || bytes <= 0) return "Unknown";
    const suffixes = ["B", "KB", "MB", "GB"];
    var i = (log(bytes) / log(1024)).floor();
    return ((bytes / pow(1024, i)).toStringAsFixed(1)) + " " + suffixes[i];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            widget.txt('Cache Explorer', style: const TextStyle(fontSize: 16)),
            Text('Total DB Size: $_totalSize', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadSchema),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: _objects.length,
        itemBuilder: (context, index) {
          final item = _objects[index];
          final List idxList = item['indices'] ?? [];
          final int? tableDataSize = item['size'];
          final int? totalTableSize = item['total_size'];

          return Card(
            key: PageStorageKey('cache_table_${item['name']}'),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 2,
            child: ExpansionTile(
              leading: const Icon(Icons.table_chart, color: Colors.indigo),
              title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Text(
                '${item['row_count']} rows \u2022 ${idxList.length} indices \u2022 ${_formatSize(totalTableSize)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.open_in_new, color: Colors.indigo, size: 20),
                    tooltip: 'Browse Data',
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (ctx) => _TableBrowserPage(repo: widget.repo, tableName: item['name'])
                      ));
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_sweep, color: Colors.red[300], size: 20),
                    tooltip: 'Clear Table',
                    onPressed: () async {
                      bool? confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                        title: Text('Clear Table ${item['name']}?'),
                        content: const Text('All records in this table will be deleted.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear', style: const TextStyle(color: Colors.red))),
                        ],
                      ));
                      if (confirm == true) {
                        final db = await widget.repo.db;
                        await db.delete(item['name']);
                        _loadSchema();
                      }
                    },
                  ),
                ],
              ),
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  color: Colors.grey[50],
                  child: Column(
                    children: [
                      _breakupRow('Table Storage', _formatSize(tableDataSize), isHeader: true),
                      if (idxList.isNotEmpty) ...[
                        const Divider(height: 1),
                        ...idxList.map((idx) => _breakupRow(idx['name'], _formatSize(idx['size']))),
                      ] else ...[
                        const Divider(height: 1),
                        _breakupRow('No separate indices found', ''),
                      ],
                      const Divider(height: 1),
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.search, size: 18, color: Colors.indigo),
                        title: const Text('Browse Full Table Data', style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
                        onTap: () {
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (ctx) => _TableBrowserPage(repo: widget.repo, tableName: item['name'])
                          ));
                        },
                      ),
                    ],
                  ),
                ),
              ],
              onExpansionChanged: (v) { if (v) _loadSchema(silent: true); },
            ),
          );
        },
      ),
    );
  }

  Widget _breakupRow(String label, String size, {bool isHeader = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: isHeader ? FontWeight.bold : FontWeight.normal, color: isHeader ? Colors.black87 : Colors.black54))),
          Text(size, style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _TableBrowserPage extends StatefulWidget {
  final NavRepository repo;
  final String tableName;
  const _TableBrowserPage({super.key, required this.repo, required this.tableName});

  @override
  State<_TableBrowserPage> createState() => _TableBrowserPageState();
}

class _TableBrowserPageState extends State<_TableBrowserPage> {
  final TextEditingController _searchCtl = TextEditingController();
  final TextEditingController _pageCtl = TextEditingController();

  List<Map<String, dynamic>> _data = [];
  List<String> _columns = [];
  List<String> _recentTableSearches = [];
  bool _loading = true;
  int _totalRows = 0;
  int _currentPage = 1;
  static const int _pageSize = 100;

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
    _fetchData();
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _recentTableSearches = prefs.getStringList('recentSearch_${widget.tableName}') ?? [];
    });
  }

  Future<void> _saveSearch(String q) async {
    if (q.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    _recentTableSearches.remove(q);
    _recentTableSearches.insert(0, q);
    if (_recentTableSearches.length > 10) _recentTableSearches = _recentTableSearches.sublist(0, 10);
    await prefs.setStringList('recentSearch_${widget.tableName}', _recentTableSearches);
  }

  Future<void> _fetchData() async {
    setState(() => _loading = true);
    final database = await widget.repo.db;

    if (_searchCtl.text.isNotEmpty) _saveSearch(_searchCtl.text);
    String where = "";
    List<dynamic> args = [];
    if (_searchCtl.text.isNotEmpty) {
      if (_columns.isEmpty) {
        final List<Map<String, dynamic>> info = await database.rawQuery("PRAGMA table_info(${widget.tableName})");
        _columns = info.map((e) => e['name'] as String).toList();
      }

      where = " WHERE " + _columns.map((c) => "CAST($c AS TEXT) LIKE ?").join(" OR ");
      args = List.filled(_columns.length, "%${_searchCtl.text}%");
    }

    final countRes = await database.rawQuery("SELECT COUNT(*) as count FROM ${widget.tableName} $where", args);
    _totalRows = countRes.first['count'] as int;

    final offset = (_currentPage - 1) * _pageSize;
    final data = await database.rawQuery(
        "SELECT * FROM ${widget.tableName} $where LIMIT $_pageSize OFFSET $offset",
        args
    );

    if (mounted) {
      setState(() {
        _data = data;
        if (_data.isNotEmpty && _columns.isEmpty) {
          _columns = _data.first.keys.toList();
        }
        _loading = false;
      });
    }
  }

  void _goToPage() {
    final pNum = int.tryParse(_pageCtl.text);
    if (pNum != null && pNum > 0 && pNum <= (_totalRows / _pageSize).ceil()) {
      setState(() => _currentPage = pNum);
      _fetchData();
    }
  }

  void _showRecordDetail(Map<String, dynamic> r) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record Detail'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: r.entries.map((e) {
              final val = e.value?.toString().trim() ?? 'null';
              final isUrl = val.toLowerCase().startsWith('http');
              return ListTile(
                title: Text(e.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: InkWell(
                  onTap: isUrl ? () => _launchUrl(val) : null,
                  child: Text(
                      val,
                      style: TextStyle(
                        fontSize: 14,
                        color: isUrl ? Colors.blue[700] : Colors.black87,
                        decoration: isUrl ? TextDecoration.underline : null,
                        fontWeight: isUrl ? FontWeight.w500 : FontWeight.normal,
                      )
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;
    try {
      final uri = Uri.parse(cleanUrl);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxPages = (_totalRows / _pageSize).ceil();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tableName),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtl,
                    decoration: InputDecoration(
                      hintText: 'Search in table...',
                      fillColor: Colors.white,
                      filled: true,
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchCtl.text.isNotEmpty
                          ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _searchCtl.clear(); _fetchData(); })
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onSubmitted: (v) {
                      setState(() => _currentPage = 1);
                      _fetchData();
                    },
                  ),
                ),
                IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _fetchData),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.indigo[50],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Text('Total Rows: $_totalRows', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo)),
                const Spacer(),
                Text('Page $_currentPage of $maxPages', style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 60,
                  height: 35,
                  child: TextField(
                    controller: _pageCtl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.all(4)),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                TextButton(onPressed: _goToPage, child: const Text('Go', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _data.isEmpty
                ? const Center(child: Text('No records found'))
                : Scrollbar(
              interactive: true,
              thickness: 6,
              radius: const Radius.circular(3),
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    showCheckboxColumn: false,
                    headingRowHeight: 45,
                    dataRowHeight: 40,
                    headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 13),
                    columns: _columns.map((c) => DataColumn(label: Text(c))).toList(),
                    rows: _data.map((r) => DataRow(
                        onSelectChanged: (_) => _showRecordDetail(r),
                        cells: _columns.map((c) {
                          final val = r[c]?.toString() ?? 'null';
                          final isUrl = val.toLowerCase().startsWith('http');
                          return DataCell(
                              InkWell(
                                onTap: isUrl ? () => _launchUrl(val) : null,
                                child: Text(
                                    val,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isUrl ? Colors.blue[700] : null,
                                      decoration: isUrl ? TextDecoration.underline : null,
                                    )
                                ),
                              )
                          );
                        }).toList()
                    )).toList(),
                  ),
                ),
              ),
            ),
          ),

          // Recent searches for table
          if (_recentTableSearches.isNotEmpty && _searchCtl.text.isEmpty)
            Container(
              height: 45,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey[100]!))),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _recentTableSearches.length,
                itemBuilder: (c, i) => Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ActionChip(
                    label: Text(_recentTableSearches[i], style: const TextStyle(fontSize: 11)),
                    onPressed: () {
                      _searchCtl.text = _recentTableSearches[i];
                      setState(() => _currentPage = 1);
                      _fetchData();
                    },
                  ),
                ),
              ),
            ),

          // Pagination Footer
          Container(
            height: 60,
            decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey[200]!)),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))]
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.first_page),
                  onPressed: _currentPage > 1 ? () { setState(() => _currentPage = 1); _fetchData(); } : null,
                ),
                IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _currentPage > 1 ? () { setState(() => _currentPage--); _fetchData(); } : null
                ),
                Text('Page $_currentPage of $maxPages', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _currentPage < maxPages ? () { setState(() => _currentPage++); _fetchData(); } : null
                ),
                IconButton(
                  icon: const Icon(Icons.last_page),
                  onPressed: _currentPage < maxPages ? () { setState(() => _currentPage = maxPages); _fetchData(); } : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
