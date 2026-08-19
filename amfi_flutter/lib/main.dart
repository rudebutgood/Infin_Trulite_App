import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'models/fii_dii_data.dart';
import 'models/gift_nifty_data.dart';
import 'models/gold_rate_data.dart';
import 'services/nav_repository.dart';
import 'services/portfolio_service.dart';
import 'services/fii_dii_service.dart';
import 'services/gift_nifty_service.dart';
import 'services/gold_rate_service.dart';
import 'models/index_data.dart';
import 'services/index_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';
import 'package:workmanager/workmanager.dart';
import 'package:sqflite/sqflite.dart';
import 'package:translator/translator.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'indices_page.dart';
import 'models/amfi_aum_data.dart';
import 'services/amfi_aum_service.dart';
import 'pages/amfi_aum_page.dart';
import 'pages/fii_dii_page.dart';
import 'pages/gift_nifty_page.dart';
import 'pages/bullion_page.dart';
import 'pages/market_news_page.dart';
import 'tabs/funds_tab.dart';
import 'tabs/portfolio_tab.dart';
import 'pages/portfolio_charts_page.dart';
import 'widgets/common_widgets.dart';
import 'services/market_news_service.dart';
import 'models/market_news.dart';

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
  final AmfiAumService _amfiAumService = AmfiAumService();
  final GiftNiftyService _giftNiftyService = GiftNiftyService();
  final GoldRateService _goldService = GoldRateService();
  final MarketNewsService _newsService = MarketNewsService();
  final GoogleTranslator _translator = GoogleTranslator();

  // Cache & State
  final Map<String, String> _translationCache = {};
  bool _loading = false;
  int _refreshCount = 0;

  // Metadata
  String? _lastImportedAt;
  DateTime? _lastImportedAtDt;
  Duration? _lastImportDuration;
  String? _lastApiTimestamp;
  Map<String, dynamic>? _lastSyncLog;
  List<FiiDiiData> _fiiDiiData = [];
  bool _fetchingFiiDii = false;
  List<IndexData> _indicesData = [];
  bool _fetchingIndices = false;
  List<GiftNiftyData> _giftNiftyData = [];
  bool _fetchingGiftNifty = false;
  List<GoldRateData> _goldRates = [];
  bool _fetchingGold = false;
  AmfiAumComparison? _amfiAumComparison;
  bool _fetchingAum = false;
  List<MarketNews> _marketNews = [];
  bool _fetchingNews = false;

  // Last Fetch Timestamps
  DateTime? _fiiDiiLastFetch;
  DateTime? _indicesLastFetch;
  DateTime? _aumLastFetch;
  DateTime? _giftNiftyLastFetch;
  DateTime? _goldLastFetch;
  DateTime? _newsLastFetch;

  // Tile Order state
  List<String> _tileIds = ['indices', 'giftNifty', 'fiiDii', 'gold', 'aum', 'marketNews'];

  // Shared Portfolio State (for Synopsis)
  List<Map<String, dynamic>> _portfolioRows = [];
  String _selectedLanguage = 'English';
  List<Map<String, dynamic>> _importedFiles = [];
  Set<int>? _selectedImportIds;
  DateTime? _selectedFilterDate;

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

    _initStateAsync();
  }

  Future<void> _initStateAsync() async {
    final prefs = await SharedPreferences.getInstance();

    // Load persisted filters
    _selectedLanguage = prefs.getString('selectedLanguage') ?? 'English';

    // Load metadata from Repository
    _lastImportedAt = await _repo.lastImportedAt();
    if (_lastImportedAt != null) {
      try { _lastImportedAtDt = DateTime.parse(_lastImportedAt!); } catch (_) { _lastImportedAtDt = null; }
    }
    _lastApiTimestamp = await _repo.lastApiTimestamp();
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
    
    final List<String> defaultOrder = ['indices', 'giftNifty', 'fiiDii', 'gold', 'aum', 'marketNews'];
    final savedOrder = prefs.getStringList('homeTileOrder');
    if (savedOrder == null) {
      _tileIds = defaultOrder;
    } else {
      // Add any new tiles that aren't in the saved order yet
      _tileIds = savedOrder;
      for (var id in defaultOrder) {
        if (!_tileIds.contains(id)) {
          _tileIds.add(id);
        }
      }
    }

    final themeStr = prefs.getString('setThemeMode') ?? 'system';
    _setThemeMode = ThemeMode.values.firstWhere(
            (e) => e.toString().split('.').last == themeStr,
        orElse: () => ThemeMode.system
    );
    widget.onThemeChanged(_setThemeMode);

    if (mounted) setState(() {});

    _importedFiles = await _portfolio.listImports();
    if (_selectedImportIds == null) {
      _selectedImportIds = _importedFiles.map((e) => e['id'] as int).toSet();
    }

    await _loadPortfolio();
    _fetchFiiDii();
    _fetchIndices();
    _fetchAmfiAum();
    _fetchGiftNifty();
    _fetchGoldRates();
    _fetchMarketNews();

    // Trigger refresh if no data is present
    if (_portfolioRows.isEmpty) {
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
        importIds: _selectedImportIds?.toList(),
        targetDate: _selectedFilterDate != null ? DateFormat('yyyy-MM-dd').format(_selectedFilterDate!) : null
    );

    if (_setHideZeroHoldings) {
      _portfolioRows = _portfolioRows.where((r) => (r['total_units'] as num? ?? 0) > 0.001).toList();
    }

    _importedFiles = await _portfolio.listImports();
    if (mounted) setState(() {});
  }

  Future<void> _fetchFiiDii({bool force = false}) async {
    if (_fetchingFiiDii && !force) return;
    setState(() => _fetchingFiiDii = true);
    try {
      _fiiDiiData = await _fiiDiiService.fetchFiiDiiData();
      _fiiDiiLastFetch = DateTime.now();
    } catch (e) {
      debugPrint('FII/DII Fetch Error: $e');
    } finally {
      if (mounted) setState(() => _fetchingFiiDii = false);
    }
  }

  Future<void> _fetchIndices({bool force = false}) async {
    if (_fetchingIndices && !force) return;
    setState(() => _fetchingIndices = true);
    try {
      final data = await _indexService.fetchIndices();
      data.sort((a, b) => b.percentChange.compareTo(a.percentChange));
      if (mounted) {
        setState(() {
          _indicesData = data;
          _indicesLastFetch = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint('Index Fetch Error: $e');
    } finally {
      if (mounted) setState(() => _fetchingIndices = false);
    }
  }

  Future<void> _fetchGiftNifty({bool force = false}) async {
    if (_fetchingGiftNifty && !force) return;
    setState(() => _fetchingGiftNifty = true);
    try {
      final data = await _giftNiftyService.fetchGiftNiftyData();
      if (mounted) {
        setState(() {
          _giftNiftyData = data;
          _giftNiftyLastFetch = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint('Gift Nifty Fetch Error: $e');
    } finally {
      if (mounted) setState(() => _fetchingGiftNifty = false);
    }
  }

  Future<void> _fetchGoldRates({bool force = false}) async {
    if (_fetchingGold && !force) return;
    setState(() => _fetchingGold = true);
    try {
      final data = await _goldService.fetchGoldRates();
      if (mounted) {
        setState(() {
          _goldRates = data;
          _goldLastFetch = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint('Gold Fetch Error: $e');
    } finally {
      if (mounted) setState(() => _fetchingGold = false);
    }
  }

  Future<void> _fetchAmfiAum({bool force = false}) async {
    if (_fetchingAum && !force) return;
    setState(() => _fetchingAum = true);
    try {
      final data = await _amfiAumService.fetchAumComparison();
      if (mounted) {
        setState(() {
          _amfiAumComparison = data;
          _aumLastFetch = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint('AUM Fetch Error: $e');
    } finally {
      if (mounted) setState(() => _fetchingAum = false);
    }
  }

  Future<void> _fetchMarketNews({bool force = false}) async {
    if (_fetchingNews && !force) return;
    setState(() => _fetchingNews = true);
    try {
      final data = await _newsService.fetchTop10News();
      if (mounted) {
        setState(() {
          _marketNews = data;
          _newsLastFetch = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint('News Fetch Error: $e');
    } finally {
      if (mounted) setState(() => _fetchingNews = false);
    }
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
      _lastSyncLog = await _repo.getLastSyncLog();

      if (_lastImportedAt != null) {
        try { _lastImportedAtDt = DateTime.parse(_lastImportedAt!); } catch (_) { _lastImportedAtDt = null; }
      }
      await _loadPortfolio();
      _fetchFiiDii(force: true);
      _fetchIndices(force: true);
      _fetchAmfiAum(force: true);
      _fetchGiftNifty(force: true);
      _fetchGoldRates(force: true);
      _fetchMarketNews(force: true);

      if (mounted) {
        setState(() {
          _refreshCount++;
        });
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
      setState(() {
        _selectedFilterDate = picked;
        _refreshCount++;
      });
      _loadPortfolio();
    }
  }

  // --- UI WIDGETS & MODALS ---

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
                          Tab(child: CommonWidgets.txt('Sync', selectedLanguage: _selectedLanguage, translate: _translate), icon: const Icon(Icons.sync_outlined)),
                          Tab(child: CommonWidgets.txt('UI', selectedLanguage: _selectedLanguage, translate: _translate), icon: const Icon(Icons.palette_outlined)),
                          Tab(child: CommonWidgets.txt('Tools', selectedLanguage: _selectedLanguage, translate: _translate), icon: const Icon(Icons.build_outlined)),
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
              title: CommonWidgets.txt('Choose Language', selectedLanguage: _selectedLanguage, translate: _translate),
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
          title: CommonWidgets.txt('Sync Time', style: const TextStyle(fontSize: 14), selectedLanguage: _selectedLanguage, translate: _translate),
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
          title: CommonWidgets.txt('API Timeout', style: const TextStyle(fontSize: 14), selectedLanguage: _selectedLanguage, translate: _translate),
          subtitle: Text('$_setApiTimeout seconds', style: const TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.timer_outlined),
          onTap: () {
            final ctl = TextEditingController(text: _setApiTimeout.toString());
            showDialog(context: context, builder: (ctx) => AlertDialog(
              title: CommonWidgets.txt('API Timeout (s)', selectedLanguage: _selectedLanguage, translate: _translate),
              content: TextField(controller: ctl, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Enter seconds')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: CommonWidgets.txt('Cancel', selectedLanguage: _selectedLanguage, translate: _translate)),
                TextButton(onPressed: () async {
                  final v = int.tryParse(ctl.text);
                  if (v != null && v > 0) {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt('setApiTimeout', v);
                    setState(() => _setApiTimeout = v);
                    Navigator.pop(ctx);
                    setLocalState(() {});
                  }
                }, child: CommonWidgets.txt('Save', selectedLanguage: _selectedLanguage, translate: _translate))
              ],
            ));
          },
        ),
        ListTile(
          title: CommonWidgets.txt('Lookback Window', style: const TextStyle(fontSize: 14), selectedLanguage: _selectedLanguage, translate: _translate),
          subtitle: Text('Fetch last $_setRefreshDays business days on refresh', style: const TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.history),
          onTap: () {
            showDialog(context: context, builder: (ctx) => AlertDialog(
              title: CommonWidgets.txt('Lookback Days', selectedLanguage: _selectedLanguage, translate: _translate),
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
          setLocalState(() {});
        }),
        ListTile(
          title: CommonWidgets.txt('Appearance', style: const TextStyle(fontSize: 14), selectedLanguage: _selectedLanguage, translate: _translate),
          subtitle: Text(_setThemeMode.toString().split('.').last.toUpperCase(), style: const TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.palette),
          onTap: () {
            showDialog(context: context, builder: (ctx) => AlertDialog(
              title: CommonWidgets.txt('Choose Theme', selectedLanguage: _selectedLanguage, translate: _translate),
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
        _actionTile('Clear Data > 3 Days Old', Icons.auto_delete_outlined, _clearOlderThan3Days),
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
        setState(() {
          _refreshCount++;
        });
        await _loadPortfolio();
        _fetchFiiDii();
        _fetchIndices();
        _fetchAmfiAum();
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
        setState(() {
          _refreshCount++;
        });
      }
    }
  }

  void _clearOlderThan3Days() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 3));
    final cutoffStr = DateFormat('yyyy-MM-dd').format(cutoff);

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Purge Old Data?'),
        content: Text('This will delete all NAV history older than $cutoffStr (3 days ago).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Purge', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      final count = await _repo.clearDataOlderThan(cutoffStr);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Purged $count old records')));
      setState(() {
        _refreshCount++;
      });
    }
  }

  void _showCacheExplorer() {
    Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => _CacheExplorerPage(
        repo: _repo,
        txt: (t, {style, overflow = false, align}) => CommonWidgets.txt(t, style: style, overflow: overflow, align: align, selectedLanguage: _selectedLanguage, translate: _translate)
    )));
  }

  void _showFeaturesDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            _InfinLogo(size: 28),
            const SizedBox(width: 12),
            CommonWidgets.txt('App Features', style: TextStyle(color: Colors.indigo[900]), selectedLanguage: _selectedLanguage, translate: _translate),
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
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: CommonWidgets.txt('Got it!', selectedLanguage: _selectedLanguage, translate: _translate))],
      ),
    );
  }

  void _showDisclosuresDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: CommonWidgets.txt('Legal Disclosures', style: TextStyle(color: Colors.indigo[900]), selectedLanguage: _selectedLanguage, translate: _translate),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CommonWidgets.txt('Disclaimer', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), selectedLanguage: _selectedLanguage, translate: _translate),
              const SizedBox(height: 4),
              CommonWidgets.txt(
                'Infin Trulite is a data tracking tool only. It does not provide financial, investment, or legal advice. All mutual fund investments are subject to market risks.',
                style: const TextStyle(fontSize: 11, color: Colors.black87),
                selectedLanguage: _selectedLanguage, translate: _translate
              ),
              const SizedBox(height: 12),
              CommonWidgets.txt('Data Source', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), selectedLanguage: _selectedLanguage, translate: _translate),
              const SizedBox(height: 4),
              CommonWidgets.txt(
                'All Mutual Fund NAV data is sourced from AMFI (Association of Mutual Funds in India). While we strive for accuracy, the developer is not responsible for any discrepancies in the data.',
                style: const TextStyle(fontSize: 11, color: Colors.black87),
                selectedLanguage: _selectedLanguage, translate: _translate
              ),
              const SizedBox(height: 12),
              CommonWidgets.txt('Privacy', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), selectedLanguage: _selectedLanguage, translate: _translate),
              const SizedBox(height: 4),
              CommonWidgets.txt(
                'Your portfolio data and statement imports are stored exclusively on your device. We do not upload or store your financial information on any remote server.',
                style: const TextStyle(fontSize: 11, color: Colors.black87),
                selectedLanguage: _selectedLanguage, translate: _translate
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: CommonWidgets.txt('Accept', selectedLanguage: _selectedLanguage, translate: _translate))],
      ),
    );
  }

  Widget _actionTile(String title, IconData icon, Function onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.indigo, size: 20),
      title: CommonWidgets.txt(title, style: const TextStyle(fontSize: 14), selectedLanguage: _selectedLanguage, translate: _translate),
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
      setState(() {
        _refreshCount++;
      });
      await _loadPortfolio();
      _fetchFiiDii(force: true);
      _fetchIndices(force: true);
      _fetchAmfiAum(force: true);
      _fetchGiftNifty(force: true);
      _fetchGoldRates(force: true);
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
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: CommonWidgets.txt('Manage Imports', selectedLanguage: _selectedLanguage, translate: _translate),
          content: SizedBox(
            width: double.maxFinite,
            child: imports.isEmpty
                ? const Center(child: Text('No imports found'))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: imports.length,
                    itemBuilder: (c, i) {
                      final imp = imports[i];
                      final id = imp['id'] as int;
                      final isSelected = _selectedImportIds?.contains(id) ?? true;

                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: isSelected,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedImportIds?.add(id);
                            } else {
                              _selectedImportIds?.remove(id);
                            }
                            _refreshCount++;
                          });
                          setLocalState(() {});
                          _loadPortfolio();
                        },
                        title: Text(
                          imp['investor_name'] != null && imp['investor_name'].toString().isNotEmpty
                              ? imp['investor_name']
                              : (imp['file_name'] ?? 'Unknown File'),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('Imported: ${imp['imported_at']}', style: const TextStyle(fontSize: 11)),
                        secondary: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                          onPressed: () async {
                            bool? del = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Delete Import?'),
                                content: const Text('This will remove all holdings associated with this statement.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                  TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                                ],
                              ),
                            );
                            if (del == true) {
                              await _portfolio.deleteImport(id);
                              setState(() {
                                _selectedImportIds?.remove(id);
                                _refreshCount++;
                              });
                              Navigator.pop(ctx);
                              _showManageImportsDialog();
                              _loadPortfolio();
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      ),
    );
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
                      title: CommonWidgets.txt('Show Balances?', selectedLanguage: _selectedLanguage, translate: _translate),
                      content: CommonWidgets.txt('Portfolio values will be visible on the screen.', selectedLanguage: _selectedLanguage, translate: _translate),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: CommonWidgets.txt('Cancel', selectedLanguage: _selectedLanguage, translate: _translate)),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: CommonWidgets.txt('Show', style: const TextStyle(color: Colors.red), selectedLanguage: _selectedLanguage, translate: _translate)),
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
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'import') _pickAndImportFile();
                else if (v == 'manage') _showManageImportsDialog();
                else if (v == 'settings') _showSettingsMenu();
                else if (v == 'clear_date') {
                  setState(() {
                    _selectedFilterDate = null;
                    _refreshCount++;
                  });
                  _loadPortfolio();
                }
              },
              itemBuilder: (ctx) => [
                if (_selectedFilterDate != null)
                  PopupMenuItem(
                      value: 'clear_date',
                      child: Row(children: [const Icon(Icons.clear, size: 20, color: Colors.red), const SizedBox(width: 8), CommonWidgets.txt('Clear Date Filter', selectedLanguage: _selectedLanguage, translate: _translate)])
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
                              CommonWidgets.txt('Import Portfolio', selectedLanguage: _selectedLanguage, translate: _translate),
                              const Text('Excel/CSV Support', style: TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          )
                        ]
                    )
                ),
                PopupMenuItem(value: 'manage', child: Row(children: [const Icon(Icons.layers, size: 20, color: Colors.indigo), const SizedBox(width: 8), CommonWidgets.txt('Manage Imports', selectedLanguage: _selectedLanguage, translate: _translate)])),
                PopupMenuItem(value: 'settings', child: Row(children: [const Icon(Icons.tune, size: 20, color: Colors.indigo), const SizedBox(width: 8), const Text('Settings')])),
              ],
            ),
          ],
        ),
        body: TabBarView(
          controller: _tabCtl,
          children: [
            _buildHomeTab(),
            FundsTab(
              key: ValueKey('funds_$_refreshCount'),
              selectedLanguage: _selectedLanguage,
              translate: _translate,
              t: t,
              selectedFilterDate: _selectedFilterDate,
              lastSyncLog: _lastSyncLog,
              setCompactLayout: _setCompactLayout,
              setShowIconsInNav: _setShowIconsInNav,
              setPrioritizeHeldAndFav: _setPrioritizeHeldAndFav,
              onRefreshTriggered: _refresh,
            ),
            PortfolioTab(
              key: ValueKey('portfolio_$_refreshCount'),
              selectedLanguage: _selectedLanguage,
              translate: _translate,
              t: t,
              selectedFilterDate: _selectedFilterDate,
              privacyMode: _setPrivacyMode,
              hideZeroHoldings: _setHideZeroHoldings,
              showFolioInList: _setShowFolioInList,
              setCompactLayout: _setCompactLayout,
              setShowIconsInNav: _setShowIconsInNav,
              selectedImportIds: _selectedImportIds,
              setApiTimeout: _setApiTimeout,
            ),
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
            BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Funds'),
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
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _tabCtl.animateTo(2),
              splashColor: Colors.white.withOpacity(0.15),
              highlightColor: Colors.white.withOpacity(0.05),
              child: Ink(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.indigo[900]!, Colors.indigo[700]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CommonWidgets.txt(t('synopsis'), style: const TextStyle(color: Colors.white70, fontSize: 14), selectedLanguage: _selectedLanguage, translate: _translate),
                    const SizedBox(height: 8),
                    Text('₹${CommonWidgets.formatCurrency(totalCur, privacyMode: _setPrivacyMode)}', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
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
          ),
        ),

        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            CommonWidgets.txt(t('quick_access'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo[900]), selectedLanguage: _selectedLanguage, translate: _translate),
          ],
        ),
        const SizedBox(height: 12),

        // Grid of Quick Access Tiles
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: _setCompactLayout ? 10 : 16,
          crossAxisSpacing: _setCompactLayout ? 10 : 16,
          childAspectRatio: _setCompactLayout ? 1.8 : 1.5,
          children: _tileIds.map((id) => _buildDraggableTile(id)).toList(),
        ),

        const SizedBox(height: 32),
        // Sync Status & Info
        if (_lastSyncLog != null) ...[
          CommonWidgets.txt('Recent Activity', style: const TextStyle(fontWeight: FontWeight.bold), selectedLanguage: _selectedLanguage, translate: _translate),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[300]!)),
            child: Column(
              children: [
                _infoRow('Last Sync', CommonWidgets.formatImportedAt(_lastSyncLog!['end_time'])),
                _infoRow('Rows Fetched', _lastSyncLog!['rows_fetched'].toString()),
                _infoRow('Duration', '${(_lastSyncLog!['duration_ms'] / 1000).toStringAsFixed(1)}s'),
                _infoRow('Status', _lastSyncLog!['status'], color: _lastSyncLog!['status'] == 'Success' ? Colors.green : Colors.red),
              ],
            ),
          ),
        ],

        const SizedBox(height: 32),
        // App Guide / Feature Items
        CommonWidgets.txt('App Guide', style: const TextStyle(fontWeight: FontWeight.bold), selectedLanguage: _selectedLanguage, translate: _translate),
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
        CommonWidgets.txt(label, style: const TextStyle(color: Colors.white60, fontSize: 12), selectedLanguage: _selectedLanguage, translate: _translate),
        const SizedBox(height: 4),
        Text(
          '${value >= 0 ? '+' : ''}₹${CommonWidgets.formatCurrency(value, privacyMode: _setPrivacyMode)}',
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
                CommonWidgets.txt('FII / DII Trade Data', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), selectedLanguage: _selectedLanguage, translate: _translate),
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
                                CommonWidgets.txt(d.category, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), selectedLanguage: _selectedLanguage, translate: _translate),
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

  Widget _buildDraggableTile(String id) {
    return DragTarget<String>(
      onWillAccept: (data) => data != id,
      onAccept: (data) async {
        setState(() {
          final oldIdx = _tileIds.indexOf(data);
          final newIdx = _tileIds.indexOf(id);
          final temp = _tileIds[oldIdx];
          _tileIds[oldIdx] = _tileIds[newIdx];
          _tileIds[newIdx] = temp;
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('homeTileOrder', _tileIds);
      },
      builder: (context, candidateData, rejectedData) {
        return LongPressDraggable<String>(
          data: id,
          feedback: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: (MediaQuery.of(context).size.width - 48) / 2,
              height: ((MediaQuery.of(context).size.width - 48) / 2) / (_setCompactLayout ? 1.8 : 1.5),
              child: _buildTileById(id),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: _buildTileById(id)),
          child: _buildTileById(id),
        );
      },
    );
  }

  Widget _buildTileById(String id) {
    switch (id) {
      case 'fiiDii': return _fiiDiiTile();
      case 'indices': return _indicesTile();
      case 'aum': return _aumTile();
      case 'giftNifty': return _giftNiftyTile();
      case 'gold': return _goldTile();
      case 'marketNews': return _marketNewsTile();
      default: return const SizedBox.shrink();
    }
  }

  Widget _marketNewsTile() {
    MarketNews? top;
    if (_marketNews.isNotEmpty) top = _marketNews.first;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => MarketNewsPage(selectedLanguage: _selectedLanguage, translate: _translate, setCompactLayout: _setCompactLayout))),
            splashColor: Colors.indigo.withOpacity(0.1),
            child: Padding(
              padding: EdgeInsets.all(_setCompactLayout ? 8 : 10),
              child: _fetchingNews
                  ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.auto_awesome, color: Colors.amber[700], size: _setCompactLayout ? 14 : 16),
                            const SizedBox(width: 4),
                            CommonWidgets.txt('AI NEWS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: _setCompactLayout ? 12 : 13, color: Colors.indigo[900]), selectedLanguage: _selectedLanguage, translate: _translate),
                          ],
                        ),
                        SizedBox(height: _setCompactLayout ? 4 : 6),
                        if (top != null)
                          Expanded(
                            child: CommonWidgets.txt(top.title, 
                              style: TextStyle(fontSize: _setCompactLayout ? 10 : 11, fontWeight: FontWeight.w500, color: Colors.black87),
                              overflow: true, selectedLanguage: _selectedLanguage, translate: _translate),
                          )
                        else
                          Text('No Data', style: TextStyle(fontSize: _setCompactLayout ? 10 : 11, color: Colors.grey)),
                        const Spacer(),
                        if (_newsLastFetch != null)
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Text(
                              'AI \u2022 ${DateFormat('dd MMM HH:mm').format(_newsLastFetch!)}',
                              style: const TextStyle(fontSize: 8, color: Colors.grey),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: IconButton(
              icon: const Icon(Icons.refresh, size: 14, color: Colors.grey),
              onPressed: () => _fetchMarketNews(force: true),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
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

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => FiiDiiPage(selectedLanguage: _selectedLanguage, translate: _translate, setCompactLayout: _setCompactLayout))),
            splashColor: Colors.indigo.withOpacity(0.1),
            child: Padding(
              padding: EdgeInsets.all(_setCompactLayout ? 8 : 10),
              child: _fetchingFiiDii
                  ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.swap_horizontal_circle, color: Colors.indigo[700], size: _setCompactLayout ? 14 : 16),
                            const SizedBox(width: 4),
                            CommonWidgets.txt('FII/DII', style: TextStyle(fontWeight: FontWeight.bold, fontSize: _setCompactLayout ? 12 : 13), selectedLanguage: _selectedLanguage, translate: _translate),
                          ],
                        ),
                        SizedBox(height: _setCompactLayout ? 4 : 6),
                        if (fii != null) _fiiDiiRow(fii.date, 'FII', fii.netValue),
                        if (dii != null) _fiiDiiRow(dii.date, 'DII', dii.netValue),
                        if (fii == null && dii == null)
                          Text('No Data', style: TextStyle(fontSize: _setCompactLayout ? 10 : 11, color: Colors.grey)),
                        const Spacer(),
                        if (_fiiDiiLastFetch != null)
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Text(
                              'NSE \u2022 ${DateFormat('dd MMM HH:mm').format(_fiiDiiLastFetch!)}',
                              style: const TextStyle(fontSize: 8, color: Colors.grey),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: IconButton(
              icon: const Icon(Icons.refresh, size: 14, color: Colors.grey),
              onPressed: () => _fetchFiiDii(force: true),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fiiDiiRow(String date, String label, double value) {
    String displayDate = date;
    if (date.contains('-')) {
      final parts = date.split('-');
      if (parts.length >= 2) displayDate = "${parts[0]} ${parts[1]}";
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(displayDate, style: TextStyle(fontSize: _setCompactLayout ? 8 : 9, color: Colors.grey, fontWeight: FontWeight.w500)),
          Row(
            children: [
              Text(label, style: TextStyle(fontSize: _setCompactLayout ? 9 : 10, color: Colors.black54)),
              const SizedBox(width: 4),
              Text('${value > 0 ? '+' : ''}${value.toInt()}',
                  style: TextStyle(fontSize: _setCompactLayout ? 10 : 11, fontWeight: FontWeight.bold, color: value >= 0 ? Colors.green : Colors.red)),
            ],
          ),
        ],
      ),
    );
  }

  void _showIndicesDetails() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => IndicesPage(selectedLanguage: _selectedLanguage, translate: _translate, setCompactLayout: _setCompactLayout)));
  }

  void _showGiftNiftyDetails() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => GiftNiftyPage(selectedLanguage: _selectedLanguage, translate: _translate, setCompactLayout: _setCompactLayout)));
  }

  void _showGoldDetails() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => BullionPage(selectedLanguage: _selectedLanguage, translate: _translate, setCompactLayout: _setCompactLayout)));
  }

  Widget _compactTradeItem(String label, double val, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
        Text(
          val > 1000 ? val.toInt().toString() : val.toStringAsFixed(2),
          style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 11),
        ),
      ],
    );
  }

  Widget _giftNiftyTile() {
    GiftNiftyData? near, far;
    if (_giftNiftyData.isNotEmpty) {
      near = _giftNiftyData.first;
      if (_giftNiftyData.length > 1) far = _giftNiftyData[1];
    }

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          InkWell(
            onTap: _showGiftNiftyDetails,
            splashColor: Colors.indigo.withOpacity(0.1),
            child: Padding(
              padding: EdgeInsets.all(_setCompactLayout ? 8 : 10),
              child: _fetchingGiftNifty
                  ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.public, color: Colors.indigo[700], size: _setCompactLayout ? 14 : 16),
                            const SizedBox(width: 4),
                            CommonWidgets.txt('GIFT NIFTY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: _setCompactLayout ? 11 : 12), selectedLanguage: _selectedLanguage, translate: _translate),
                          ],
                        ),
                        SizedBox(height: _setCompactLayout ? 4 : 6),
                        if (near != null) _giftNiftyRow(near.expiryDate, near.lastPrice, near.percentChange),
                        if (far != null) _giftNiftyRow(far.expiryDate, far.lastPrice, far.percentChange),
                        if (_giftNiftyData.isEmpty)
                          Text('No Data', style: TextStyle(fontSize: _setCompactLayout ? 10 : 11, color: Colors.grey)),
                        const Spacer(),
                        if (_giftNiftyLastFetch != null)
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Text(
                              'NSE IX \u2022 ${DateFormat('dd MMM HH:mm').format(_giftNiftyLastFetch!)}',
                              style: const TextStyle(fontSize: 8, color: Colors.grey),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: IconButton(
              icon: const Icon(Icons.refresh, size: 14, color: Colors.grey),
              onPressed: () => _fetchGiftNifty(force: true),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _giftNiftyRow(String date, double ltp, double pct) {
    // Shorten date: "25-Aug-2026" -> "25 Aug"
    String displayDate = date;
    if (date.contains('-')) {
      final parts = date.split('-');
      if (parts.length >= 2) displayDate = "${parts[0]} ${parts[1]}";
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(displayDate, style: TextStyle(fontSize: _setCompactLayout ? 8 : 9, color: Colors.grey, fontWeight: FontWeight.w500)),
          Row(
            children: [
              Text(ltp.toStringAsFixed(1), style: TextStyle(fontSize: _setCompactLayout ? 10 : 11, fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              Text(
                '(${pct > 0 ? '+' : ''}${pct.toStringAsFixed(2)}%)',
                style: TextStyle(fontSize: _setCompactLayout ? 8 : 9, fontWeight: FontWeight.w600, color: pct >= 0 ? Colors.green : Colors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _goldTile() {
    GoldRateData? gold, silver, usdinr;
    if (_goldRates.isNotEmpty) {
      try {
        // Prefer Indian rows (BIS for Gold, India for Silver)
        gold = _goldRates.firstWhere((d) => d.symbol.toUpperCase().contains('GOLD') && d.symbol.toUpperCase().contains('BIS'));
      } catch (_) {
        try { gold = _goldRates.firstWhere((d) => d.symbol.toUpperCase().contains('GOLD SPOT')); } catch (_) {}
      }
      try {
        silver = _goldRates.firstWhere((d) => d.symbol.toUpperCase().contains('SILVER') && d.symbol.toUpperCase().contains('INDIA'));
      } catch (_) {
        try { silver = _goldRates.firstWhere((d) => d.symbol.toUpperCase().contains('SILVER SPOT')); } catch (_) {}
      }
      try {
        usdinr = _goldRates.firstWhere((d) => d.symbol.toUpperCase().contains('USDINR'));
      } catch (_) {}
    }

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          InkWell(
            onTap: _showGoldDetails,
            splashColor: Colors.indigo.withOpacity(0.1),
            child: Padding(
              padding: EdgeInsets.all(_setCompactLayout ? 8 : 10),
              child: _fetchingGold
                  ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.currency_rupee, color: Colors.amber, size: _setCompactLayout ? 14 : 16),
                            const SizedBox(width: 4),
                            CommonWidgets.txt('BULLION', style: TextStyle(fontWeight: FontWeight.bold, fontSize: _setCompactLayout ? 11 : 12), selectedLanguage: _selectedLanguage, translate: _translate),
                          ],
                        ),
                        SizedBox(height: _setCompactLayout ? 4 : 6),
                        if (gold != null) _rateRow('Gold', gold.ask),
                        if (silver != null) _rateRow('Silver', silver.ask),
                        if (usdinr != null) _rateRow('USDINR', usdinr.ask),
                        if (_goldRates.isEmpty)
                          Text('No Data', style: TextStyle(fontSize: _setCompactLayout ? 10 : 11, color: Colors.grey)),
                        const Spacer(),
                        if (_goldLastFetch != null)
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Text(
                              'DP Gold \u2022 ${DateFormat('dd MMM HH:mm').format(_goldLastFetch!)}',
                              style: const TextStyle(fontSize: 8, color: Colors.grey),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: IconButton(
              icon: const Icon(Icons.refresh, size: 14, color: Colors.grey),
              onPressed: () => _fetchGoldRates(force: true),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rateRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: _setCompactLayout ? 9 : 10, color: Colors.grey, fontWeight: FontWeight.w500)),
          Text(
            label == 'USDINR' ? value.toStringAsFixed(2) : value.toInt().toString(),
            style: TextStyle(fontSize: _setCompactLayout ? 10 : 11, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _indicesTile() {
    IndexData? nifty, nifty500;
    if (_indicesData.isNotEmpty) {
      try {
        nifty = _indicesData.firstWhere((d) => d.name.toUpperCase() == 'NIFTY 50');
      } catch (_) {}
      try {
        nifty500 = _indicesData.firstWhere((d) => d.name.toUpperCase() == 'NIFTY 500');
      } catch (_) {}
    }

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          InkWell(
            onTap: _showIndicesDetails,
            splashColor: Colors.indigo.withOpacity(0.1),
            child: Padding(
              padding: EdgeInsets.all(_setCompactLayout ? 8 : 10),
              child: _fetchingIndices
                  ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.analytics, color: Colors.indigo[700], size: _setCompactLayout ? 14 : 16),
                            const SizedBox(width: 4),
                            CommonWidgets.txt('Indices', style: TextStyle(fontWeight: FontWeight.bold, fontSize: _setCompactLayout ? 12 : 13), selectedLanguage: _selectedLanguage, translate: _translate),
                          ],
                        ),
                        SizedBox(height: _setCompactLayout ? 4 : 6),
                        if (nifty != null) _indexRow('Nifty 50', nifty.last, nifty.percentChange),
                        if (nifty500 != null) _indexRow('Nifty 500', nifty500.last, nifty500.percentChange),
                        if (_indicesData.isEmpty)
                          Text('No Data', style: TextStyle(fontSize: _setCompactLayout ? 10 : 11, color: Colors.grey)),
                        const Spacer(),
                        if (_indicesLastFetch != null)
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Text(
                              'NSE \u2022 ${DateFormat('dd MMM HH:mm').format(_indicesLastFetch!)}',
                              style: const TextStyle(fontSize: 8, color: Colors.grey),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: IconButton(
              icon: const Icon(Icons.refresh, size: 14, color: Colors.grey),
              onPressed: () => _fetchIndices(force: true),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aumTile() {
    final data = _amfiAumComparison;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AmfiAumPage(selectedLanguage: _selectedLanguage, translate: _translate, setCompactLayout: _setCompactLayout))),
            splashColor: Colors.indigo.withOpacity(0.1),
            child: Padding(
              padding: EdgeInsets.all(_setCompactLayout ? 8 : 10),
              child: _fetchingAum
                  ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.pie_chart, color: Colors.indigo[700], size: _setCompactLayout ? 14 : 16),
                            const SizedBox(width: 4),
                            CommonWidgets.txt('MF AUM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: _setCompactLayout ? 12 : 13), selectedLanguage: _selectedLanguage, translate: _translate),
                          ],
                        ),
                        SizedBox(height: _setCompactLayout ? 4 : 6),
                        if (data != null) ...[
                          Text(data.current.period, style: TextStyle(fontSize: _setCompactLayout ? 9 : 10, color: Colors.indigo[400], fontWeight: FontWeight.w500)),
                          SizedBox(height: _setCompactLayout ? 1 : 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '₹${(data.current.totalAum / 100000).toStringAsFixed(1)}L Cr',
                                style: TextStyle(fontSize: _setCompactLayout ? 12 : 13, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 8),
                              Row(
                                children: [
                                  Icon(
                                    data.percentageIncrease >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                                    size: _setCompactLayout ? 8 : 10,
                                    color: data.percentageIncrease >= 0 ? Colors.green : Colors.red,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    '${data.percentageIncrease.abs().toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      fontSize: _setCompactLayout ? 9 : 10,
                                      fontWeight: FontWeight.bold,
                                      color: data.percentageIncrease >= 0 ? Colors.green : Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ] else
                          Text('No Data', style: TextStyle(fontSize: _setCompactLayout ? 10 : 11, color: Colors.grey)),
                        const Spacer(),
                        if (_aumLastFetch != null)
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Text(
                              'AMFI \u2022 ${DateFormat('dd MMM HH:mm').format(_aumLastFetch!)}',
                              style: const TextStyle(fontSize: 8, color: Colors.grey),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: IconButton(
              icon: const Icon(Icons.refresh, size: 14, color: Colors.grey),
              onPressed: () => _fetchAmfiAum(force: true),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _indexRow(String label, double last, double pct) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: _setCompactLayout ? 8 : 9, color: Colors.grey, fontWeight: FontWeight.w500)),
          Row(
            children: [
              Text(last.toStringAsFixed(1), style: TextStyle(fontSize: _setCompactLayout ? 10 : 11, fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              Text(
                '(${pct > 0 ? '+' : ''}${pct.toStringAsFixed(2)}%)',
                style: TextStyle(fontSize: _setCompactLayout ? 8 : 9, fontWeight: FontWeight.w600, color: pct >= 0 ? Colors.green : Colors.red),
              ),
            ],
          ),
        ],
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
            CommonWidgets.txt(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), selectedLanguage: _selectedLanguage, translate: _translate),
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

  @override
  void dispose() {
    _tabCtl.dispose();
    super.dispose();
  }

  // --- HELPER METHODS ---

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
                CommonWidgets.txt(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87), selectedLanguage: _selectedLanguage, translate: _translate),
                CommonWidgets.txt(desc, style: const TextStyle(fontSize: 11, color: Colors.grey), selectedLanguage: _selectedLanguage, translate: _translate),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingSwitch(String title, String subtitle, bool val, Function(bool) onChanged) {
    return SwitchListTile(
      title: CommonWidgets.txt(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500), selectedLanguage: _selectedLanguage, translate: _translate),
      subtitle: CommonWidgets.txt(subtitle, style: const TextStyle(fontSize: 11), selectedLanguage: _selectedLanguage, translate: _translate),
      value: val,
      onChanged: onChanged,
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }
}

// --- SUB-PAGES & CUSTOM COMPONENTS ---

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
  
  int? _sortColumnIndex;
  bool _isAscending = true;

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
    
    String orderBy = "";
    if (_sortColumnIndex != null && _columns.isNotEmpty) {
      final colName = _columns[_sortColumnIndex!];
      orderBy = " ORDER BY $colName ${_isAscending ? "ASC" : "DESC"}";
    }

    final data = await database.rawQuery(
        "SELECT * FROM ${widget.tableName} $where $orderBy LIMIT $_pageSize OFFSET $offset",
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
                    sortColumnIndex: _sortColumnIndex,
                    sortAscending: _isAscending,
                    headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 13),
                    columns: _columns.map((c) => DataColumn(
                      label: Text(c),
                      onSort: (index, ascending) {
                        setState(() {
                          _sortColumnIndex = index;
                          _isAscending = ascending;
                        });
                        _fetchData();
                      },
                    )).toList(),
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
