import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/nav_item.dart';
import '../services/nav_repository.dart';
import '../services/index_service.dart';
import '../widgets/common_widgets.dart';

class FundsTab extends StatefulWidget {
  final String selectedLanguage;
  final Future<String> Function(String) translate;
  final String Function(String, {String? arg}) t;
  final DateTime? selectedFilterDate;
  final Map<String, dynamic>? lastSyncLog;
  final bool setCompactLayout;
  final bool setShowIconsInNav;
  final bool setPrioritizeHeldAndFav;
  final VoidCallback? onRefreshTriggered;

  const FundsTab({
    super.key,
    required this.selectedLanguage,
    required this.translate,
    required this.t,
    this.selectedFilterDate,
    this.lastSyncLog,
    required this.setCompactLayout,
    required this.setShowIconsInNav,
    required this.setPrioritizeHeldAndFav,
    this.onRefreshTriggered,
  });

  @override
  State<FundsTab> createState() => _FundsTabState();
}

class _FundsTabState extends State<FundsTab> {
  final NavRepository _repo = NavRepository();
  final TextEditingController _searchCtl = TextEditingController();
  final ScrollController _scrollCtl = ScrollController();
  final FocusNode _searchFocus = FocusNode();

  List<NavItem> _items = [];
  List<String> _recentSearches = [];
  bool _loading = true;
  bool _showSuggestions = false;

  final List<String> _fundTypes = ['All', 'Direct', 'Regular', 'IDCW', 'Others'];
  String _selectedFundType = 'Direct';
  String _selectedCompany = 'All Companies';
  List<String> _amcList = ['All Companies'];
  String _sortOption = 'Return';
  bool _isNavAscending = false;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() {
      if (mounted) {
        setState(() {
          _showSuggestions = _searchFocus.hasFocus && _recentSearches.isNotEmpty;
        });
      }
    });
    _initFilters();
  }

  @override
  void didUpdateWidget(FundsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedFilterDate != widget.selectedFilterDate ||
        oldWidget.setPrioritizeHeldAndFav != widget.setPrioritizeHeldAndFav) {
      _load();
    }
    if (widget.lastSyncLog != oldWidget.lastSyncLog) {
      _load();
    }
  }

  Future<void> _initFilters() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Always default to Direct when opening the page
      _selectedFundType = 'Direct';
      
      // Aggressive ghost text cleanup
      String last = (prefs.getString('lastSearch') ?? '').trim();
      if (last.toLowerCase() == 'auto' || last.isEmpty) {
        _searchCtl.text = '';
        if (last.isNotEmpty) await prefs.setString('lastSearch', '');
      } else {
        _searchCtl.text = last;
      }

      _recentSearches = prefs.getStringList('recentSearches') ?? [];
      
      final amcs = await _repo.getFundCompanies();

      if (mounted) {
        setState(() {
          _amcList = ['All Companies', ...amcs].toSet().toList();
        });
      }
      
      final defaultSort = prefs.getString('setNAVDefaultSort') ?? 'Return \u2193';
      if (mounted) {
        setState(() {
          if (defaultSort.contains('\u2193')) {
            _sortOption = defaultSort.replaceAll(' \u2193', '');
            _isNavAscending = false;
          } else if (defaultSort.contains('\u2191')) {
            _sortOption = defaultSort.replaceAll(' \u2191', '');
            _isNavAscending = true;
          } else {
            _sortOption = defaultSort;
            _isNavAscending = false;
          }
        });
      }
    } catch (e) {
      debugPrint('Error initializing filters: $e');
    } finally {
      _load();
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      String? orderBy;
      switch (_sortOption) {
        case 'Return': orderBy = _isNavAscending ? 'return_asc' : 'return_desc'; break;
        case 'Name': orderBy = _isNavAscending ? 'name_asc' : 'name_desc'; break;
        case 'Nav Date': orderBy = _isNavAscending ? 'date_asc' : 'date_desc'; break;
        case 'Nav report time': orderBy = _isNavAscending ? 'timestamp_asc' : 'timestamp_desc'; break;
      }
      final list = await _repo.queryLatestWithChange(
        q: _searchCtl.text,
        fundType: _selectedFundType,
        amc: _selectedCompany,
        orderBy: orderBy,
        date: widget.selectedFilterDate != null ? DateFormat('yyyy-MM-dd').format(widget.selectedFilterDate!) : null,
        prioritizeHeldAndFav: widget.setPrioritizeHeldAndFav,
      );
      if (mounted) {
        setState(() {
          _items = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      if (mounted) setState(() => _loading = false);
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
    });
    _savePrefs();
  }

  Future<void> _toggleFavorite(NavItem it) async {
    await _repo.toggleFavorite(it.schemeCode!, !it.isFavorite);
    _load(silent: true);
  }

  void _showDetails(NavItem it) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (c, s) => Scrollbar(
          controller: s,
          interactive: true,
          thickness: 6,
          radius: const Radius.circular(3),
          child: ListView(
            controller: s,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            children: [
              Row(
                children: [
                  Expanded(child: CommonWidgets.txt(it.schemeName ?? '-', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), selectedLanguage: widget.selectedLanguage, translate: widget.translate)),
                  IconButton(icon: Icon(it.isFavorite ? Icons.star : Icons.star_border, color: Colors.amber), onPressed: () { Navigator.pop(ctx); _toggleFavorite(it); }),
                ],
              ),
              const SizedBox(height: 16),
              FundHistorySection(
                schemeCode: it.schemeCode!,
                schemeName: it.schemeName ?? '',
                category: it.category,
                selectedLanguage: widget.selectedLanguage,
                setCompactLayout: widget.setCompactLayout,
                translate: widget.translate,
              ),
              const Divider(height: 40),
              CommonWidgets.detailRow('Scheme Code', it.schemeCode),
              CommonWidgets.detailRow('AMC', it.mfName),
              CommonWidgets.detailRow('Category', it.category),
              CommonWidgets.detailRow('Plan', it.plan),
              CommonWidgets.detailRow('Option', it.option),
              CommonWidgets.detailRow('ISIN (Payout)', it.isinDivPayout),
              CommonWidgets.detailRow('ISIN (Reinvest)', it.isinReinvestment),
              const Divider(),
              CommonWidgets.detailRow('NAV Value', it.navValue?.toString(), color: Colors.indigo, trailing: const Text('INR', style: TextStyle(fontSize: 10, color: Colors.grey))),
              CommonWidgets.detailRow('NAV Date', it.navDate),
              if (it.prevNavValue != null) ...[
                CommonWidgets.detailRow('Prev NAV', it.prevNavValue?.toString()),
                CommonWidgets.detailRow('Prev Date', it.prevNavDate),
                Builder(builder: (ctx) {
                  final d = (it.navValue ?? 0) - (it.prevNavValue ?? 0);
                  final p = (it.prevNavValue != 0) ? (d / it.prevNavValue! * 100) : null;
                  return CommonWidgets.detailRow('Change', '${d >= 0 ? '+' : ''}${d.toStringAsFixed(4)} ${p != null ? '(${p.toStringAsFixed(2)}%)' : ''}', color: d >= 0 ? Colors.green : Colors.red);
                }),
              ],
              const Divider(),
              CommonWidgets.detailRow('Imported At', it.importedAt != null ? CommonWidgets.formatImportedAt(it.importedAt!) : null),
              CommonWidgets.detailRow('API Timestamp', it.apiTimestamp != null ? CommonWidgets.formatImportedAt(it.apiTimestamp!) : null),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => launchUrl(Uri.parse('https://www.google.com/search?q=${it.schemeName}'), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.search), label: const Text('Search on Web'),
              ),
              const SizedBox(height: 20),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (widget.lastSyncLog != null)
              Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Row(children: [
                  CommonWidgets.txt('Source: ', style: const TextStyle(fontSize: 10, color: Colors.black54), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                  Text('AMFI India (${CommonWidgets.formatImportedAt(widget.lastSyncLog!['end_time'])})', style: const TextStyle(fontSize: 10, color: Colors.black54)),
              ]))),
            if (widget.selectedFilterDate != null)
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.amber[100], borderRadius: BorderRadius.circular(4)),
                child: Text('Date: ${DateFormat('dd-MMM-yyyy').format(widget.selectedFilterDate!)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber[900]))),
            const Spacer(),
            IconButton(icon: const Icon(Icons.refresh, size: 20, color: Colors.indigo), onPressed: () { if (widget.onRefreshTriggered != null) { setState(() => _loading = true); widget.onRefreshTriggered!(); } }, tooltip: 'Sync NAVs', visualDensity: VisualDensity.compact),
          ],
        ),
        const SizedBox(height: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 45, child: TextField(controller: _searchCtl, focusNode: _searchFocus, onSubmitted: (v) => _updateSearchHistory(v), onChanged: (v) { setState(() {}); _load(silent: true); },
                style: const TextStyle(fontSize: 14, color: Colors.black87),
                decoration: InputDecoration(hintText: widget.t('search'), isDense: true, prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchCtl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.cancel, size: 20), onPressed: () { _searchCtl.clear(); _savePrefs(); _load(); }) : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.white))),
            if (_showSuggestions && _recentSearches.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)]),
                child: Column(
                  children: _recentSearches.take(10).map((s) => ListTile(
                    dense: true, visualDensity: VisualDensity.compact,
                    leading: const Icon(Icons.history, size: 16, color: Colors.grey),
                    title: Text(s, style: const TextStyle(fontSize: 13)),
                    onTap: () { _searchCtl.text = s; _searchFocus.unfocus(); _load(); },
                  )).toList(),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: _fundTypes.map((tVal) {
          final s = tVal == _selectedFundType;
          return Padding(padding: const EdgeInsets.only(right: 8.0), child: ChoiceChip(label: CommonWidgets.txt(tVal, style: TextStyle(fontSize: 12, fontWeight: s ? FontWeight.bold : FontWeight.normal), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
            selected: s, selectedColor: Colors.indigo[100], checkmarkColor: Colors.indigo, onSelected: (v) async { if (v) { setState(() => _selectedFundType = tVal); await _savePrefs(); _load(); } }));
        }).toList())),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(flex: 5, child: Container(height: 40, padding: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
            child: DropdownButtonHideUnderline(child: DropdownButton<String>(isExpanded: true, value: _selectedCompany, style: const TextStyle(fontSize: 13, color: Colors.black87),
              items: _amcList.map((s) => DropdownMenuItem(value: s, child: Text(s == 'All Companies' ? widget.t('all_amc') : s, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) { if (v != null) { setState(() => _selectedCompany = v); _load(); } } )))),
          const SizedBox(width: 8),
          Flexible(flex: 4, child: Row(children: [
            Expanded(child: Container(height: 40, padding: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
              child: DropdownButtonHideUnderline(child: DropdownButton<String>(isExpanded: true, value: _sortOption, style: TextStyle(fontSize: 12, color: Colors.indigo[700], fontWeight: FontWeight.w600),
                items: ['Return', 'Name', 'Nav report time'].map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) { if (v != null) { setState(() => _sortOption = v); _load(); } } )))),
            IconButton(icon: Icon(_isNavAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 20, color: Colors.indigo[700]), onPressed: () { setState(() => _isNavAscending = !_isNavAscending); _load(); }, visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
          ])),
        ]),
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              if (widget.onRefreshTriggered != null) {
                widget.onRefreshTriggered!();
                // Wait a bit for the main refresh to trigger rebuild or finish
                await Future.delayed(const Duration(seconds: 1));
              } else {
                await _load();
              }
            },
            child: Scrollbar(
              controller: _scrollCtl,
              interactive: true,
              thickness: 6,
              radius: const Radius.circular(3),
              child: ListView.separated(
                controller: _scrollCtl,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                itemCount: _items.length + 1,
                separatorBuilder: (context, index) => index == 0 ? const SizedBox() : Divider(height: 1, thickness: 0.5, color: Colors.grey[200]),
                itemBuilder: (c, i) {
                  if (i == 0) return _buildHeader();
                  if (_items.isEmpty && i == 1) return SizedBox(height: 300, child: Center(child: CommonWidgets.txt(widget.t('no_data'), selectedLanguage: widget.selectedLanguage, translate: widget.translate)));

                  final it = _items[i - 1];
                  return ListTile(
                    dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: widget.setCompactLayout ? VisualDensity.compact : VisualDensity.standard,
                    onTap: () => _showDetails(it),
                    title: CommonWidgets.txt(it.schemeName ?? '-', style: TextStyle(fontSize: widget.setCompactLayout ? 13 : 14, fontWeight: it.isFavorite ? FontWeight.w700 : FontWeight.w500, color: Colors.indigo[900]), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                    subtitle: Row(children: [
                        Expanded(child: Text('${it.navDate ?? ''} \u2022 ${it.apiTimestamp != null ? CommonWidgets.formatImportedAt(it.apiTimestamp!) : ''}', style: TextStyle(fontSize: widget.setCompactLayout ? 10 : 11, color: Colors.grey[600]))),
                        if (widget.setShowIconsInNav) ...[
                          if (it.isFavorite) Padding(padding: const EdgeInsets.only(right: 6.0), child: Icon(Icons.star, size: 12, color: Colors.amber[700])),
                          if (it.isHeld) Icon(Icons.account_balance_wallet, size: 12, color: Colors.indigo[400]),
                        ],
                    ]),
                    trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(it.navValue?.toString() ?? '-', style: TextStyle(fontWeight: FontWeight.bold, fontSize: widget.setCompactLayout ? 13 : 14)),
                      if (it.prevNavValue != null) Builder(builder: (ctx) {
                        final d = (it.navValue ?? 0) - (it.prevNavValue ?? 0);
                        final p = (it.prevNavValue != 0) ? (d / it.prevNavValue! * 100) : null;
                        return Text('${d >= 0 ? '+' : ''}${d.toStringAsFixed(4)} ${p != null ? '(${p.toStringAsFixed(2)}%)' : ''}', style: TextStyle(color: d >= 0 ? Colors.green[700] : Colors.red[700], fontSize: widget.setCompactLayout ? 10 : 11));
                      }),
                    ]),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _searchCtl.dispose(); _scrollCtl.dispose(); _searchFocus.dispose();
    super.dispose();
  }
}

class FundHistorySection extends StatefulWidget {
  final String schemeCode;
  final String schemeName;
  final String? category;
  final String selectedLanguage;
  final bool setCompactLayout;
  final Future<String> Function(String) translate;

  const FundHistorySection({
    super.key,
    required this.schemeCode,
    required this.schemeName,
    this.category,
    required this.selectedLanguage,
    required this.setCompactLayout,
    required this.translate,
  });

  @override
  State<FundHistorySection> createState() => _FundHistorySectionState();
}

class _FundHistorySectionState extends State<FundHistorySection> {
  final NavRepository _repo = NavRepository();
  final IndexService _indexService = IndexService();
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _benchmarkHistory = [];
  bool _loading = true;
  Map<String, double> _returns = {};
  String _selectedPeriod = '1Y';
  String _benchmarkName = 'Nifty 500';

  // Toggle visibility
  bool _showFundLine = true;
  bool _showBenchmarkLine = true;

  // Range selection state
  int? _startIdx;
  int? _endIdx;
  bool _isSelecting = false;
  final Map<int, Offset> _pointers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final benchmark = _determineBenchmark(widget.schemeName, widget.category);
      debugPrint('Benchmark for ${widget.schemeName}: $benchmark');
      
      final results = await Future.wait([
        _repo.getHistoryForScheme(widget.schemeCode),
        _indexService.fetchIndexHistory(benchmark),
      ]);
      if (mounted) {
        setState(() {
          _benchmarkName = benchmark;
          _history = results[0];
          _benchmarkHistory = results[1];
          _returns = _calculateReturns(_history);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }


  String _determineBenchmark(String name, String? category) {
    final n = name.toUpperCase();
    final c = (category ?? '').toUpperCase();
    
    // --- 1. DIRECT INDEX TRACKERS (ETFs / Index Funds) ---
    // Rule: If the fund is explicitly named after an index, use that index.
    if (n.contains('NIFTY 50') && !n.contains('NEXT 50')) return 'NIFTY 50';
    if (n.contains('NIFTY NEXT 50')) return 'NIFTY NEXT 50';
    if (n.contains('NIFTY 100')) return 'NIFTY 100';
    if (n.contains('NIFTY 200')) return 'NIFTY 200';
    if (n.contains('NIFTY 500')) return 'NIFTY 500';
    if (n.contains('MIDCAP 150')) return 'NIFTY MIDCAP 150';
    if (n.contains('MIDCAP 100')) return 'NIFTY MIDCAP 100';
    if (n.contains('SMALLCAP 250')) return 'NIFTY SMALLCAP 250';
    if (n.contains('SMALLCAP 50')) return 'NIFTY SMALLCAP 50';
    if (n.contains('BANK NIFTY') || n.contains('NIFTY BANK')) return 'NIFTY BANK';
    if (n.contains('NIFTY IT')) return 'NIFTY IT';
    
    // --- 2. SEBI TIER-1 CATEGORY MAPPING (Highest Priority for Active Funds) ---
    // Rule: SEBI category determines the benchmark. This avoids AMC names (like "Bank of India") 
    // triggering false sectoral matches.
    if (c.contains('SMALL CAP')) return 'NIFTY SMALLCAP 250';
    if (c.contains('MID CAP')) return 'NIFTY MIDCAP 150';
    if (c.contains('LARGE CAP')) return 'NIFTY 100';
    if (c.contains('LARGE & MID')) return 'NIFTY LARGEMIDCAP 250';
    if (c.contains('FLEXI CAP') || c.contains('MULTI CAP') || c.contains('ELSS') || c.contains('FOCUSED')) return 'NIFTY 500';
    if (c.contains('VALUE') || c.contains('CONTRA') || c.contains('DIVIDEND YIELD')) return 'NIFTY 500';
    
    // Debt Categories
    if (c.contains('LIQUID') || c.contains('OVERNIGHT')) return 'NIFTY LIQUID INDEX';
    if (c.contains('MONEY MARKET') || c.contains('ULTRA SHORT')) return 'NIFTY MONEY MARKET INDEX';
    if (c.contains('SHORT DURATION') || c.contains('LOW DURATION')) return 'NIFTY SHORT DURATION DEBT INDEX';
    if (c.contains('CORPORATE BOND')) return 'NIFTY CORPORATE BOND INDEX';
    if (c.contains('BANKING AND PSU DEBT')) return 'NIFTY BANKING & PSU DEBT INDEX';
    if (c.contains('DYNAMIC BOND')) return 'NIFTY DYNAMIC BOND INDEX';
    if (c.contains('GILT')) return 'NIFTY 10 YR BENCHMARK G-SEC';
    
    // Arbitrage / Hybrid
    if (c.contains('ARBITRAGE')) return 'NIFTY 50 ARBITRAGE INDEX';
    if (c.contains('AGGRESSIVE HYBRID')) return 'NIFTY 50 HYBRID COMPOSITE DEBT 65:35';
    if (c.contains('BALANCED HYBRID') || c.contains('DYNAMIC ASSET')) return 'NIFTY 50 HYBRID COMPOSITE DEBT 50:50';
    if (c.contains('CONSERVATIVE HYBRID')) return 'NIFTY 50 HYBRID COMPOSITE DEBT 15:85';

    // --- 3. SECTORAL / THEMATIC MAPPING (Fallback for Sectoral/Thematic category) ---
    // Rule: If it's not a standard cap-based fund, look for sectoral keywords.
    if (n.contains('BANK') || n.contains('FINANCIAL') || n.contains('BFSI')) {
      // Special check: ensure 'BANK' isn't just part of AMC name for a diversified fund
      if (c.contains('SECTORAL') || c.contains('THEMATIC') || n.contains('BANKING')) {
         return 'NIFTY FINANCIAL SERVICES';
      }
    }
    if (n.contains(' IT ') || n.contains('TECHNOLOGY') || n.contains('TECH')) return 'NIFTY IT';
    if (n.contains('PHARMA') || n.contains('HEALTHCARE')) {
       return n.contains('HEALTHCARE') ? 'NIFTY HEALTHCARE' : 'NIFTY PHARMA';
    }
    if (n.contains('FMCG') || n.contains('CONSUMPTION') || n.contains('CONSUMER')) return 'NIFTY FMCG';
    if (n.contains('DEFENCE')) return 'NIFTY INDIA DEFENCE';
    if (n.contains('TOURISM') || n.contains('HOSPITALITY')) return 'NIFTY INDIA TOURISM';
    if (n.contains('INFRA')) return 'NIFTY INFRA';
    if (n.contains('ENERGY') || n.contains('POWER')) return 'NIFTY ENERGY';
    if (n.contains('AUTO')) return 'NIFTY AUTO';
    if (n.contains('METAL') || n.contains('COMMODITIES')) return 'NIFTY METAL';
    if (n.contains('MEDIA')) return 'NIFTY MEDIA';
    if (n.contains('REALTY')) return 'NIFTY REALTY';
    if (n.contains('HOUSING')) return 'NIFTY HOUSING';
    if (n.contains('POWER')) return 'NIFTY POWER';
    if (n.contains('CAPITAL GOODS')) return 'NIFTY CAPITAL GOODS';
    if (n.contains('TELECOM') || n.contains('COMMUNICATION')) return 'NIFTY TELECOMMUNICATIONS';
    if (n.contains('RETAIL') || n.contains('SHOPPING')) return 'NIFTY RETAIL';
    if (n.contains('HOSPITAL')) return 'NIFTY HOSPITALS';
    if (n.contains('NBFC') || n.contains('FINANCE')) {
       if (n.contains('HOUSING')) return 'NIFTY HOUSING FINANCE';
       return 'NIFTY NBFC';
    }
    if (n.contains('INSURANCE')) return 'NIFTY INSURANCE';
    if (n.contains('RAILWAY')) return 'NIFTY INDIA RAILWAYS PSU';
    if (n.contains('EV ') || n.contains('ELECTRIC VEHICLE')) return 'NIFTY EV & NEW AGE AUTOMOTIVE';
    if (n.contains('MNC')) return 'NIFTY MNC';
    if (n.contains('PSE') || n.contains('PSU') || n.contains('CPSE')) return 'NIFTY PSE';
    if (n.contains('SERVICES')) return 'NIFTY SERVICES SECTOR';
    if (n.contains('MANUFACTURING')) return 'NIFTY INDIA MANUFACTURING';
    if (n.contains('DIGITAL')) return 'NIFTY INDIA DIGITAL';
    if (n.contains('LOGISTICS') || n.contains('TRANSPORT') || n.contains('MOBILITY')) return 'NIFTY TRANSPORTATION & LOGISTICS';
    if (n.contains('CONSUMER DURABLES')) return 'NIFTY CONSUMER DURABLES';
    if (n.contains('OIL') || n.contains('GAS')) return 'NIFTY OIL & GAS';
    if (n.contains('MICRO CAP') || n.contains('MICROCAP')) return 'NIFTY MICROCAP 250';
    
    // Strategy / Smart Beta
    if (n.contains('MOMENTUM')) return 'NIFTY200 MOMENTUM 30';
    if (n.contains('ALPHA')) return 'NIFTY ALPHA 50';
    if (n.contains('QUALITY')) return 'NIFTY100 QUALITY 30';
    if (n.contains('LOW VOL')) return 'NIFTY LOW VOLATILITY 50';
    if (n.contains('EQUAL WEIGHT')) return 'NIFTY50 EQUAL WEIGHT';
    if (n.contains('GROWTH')) return 'NIFTY500 GROWTH 50';
    
    // --- 4. FALLBACKS ---
    if (n.contains('SMALL')) return 'NIFTY SMALLCAP 250';
    if (n.contains('MID')) return 'NIFTY MIDCAP 150';
    if (n.contains('BLUECHIP') || n.contains('LARGE')) return 'NIFTY 100';
    if (n.contains('TAX') || n.contains('SAVER') || n.contains('BASKET')) return 'NIFTY 500';
    if (c.contains('MULTI ASSET') || c.contains('EQUITY SAVINGS')) return 'NIFTY 50';
    
    return 'NIFTY 500'; 
  }

  Map<String, double> _calculateReturns(List<Map<String, dynamic>> data) {
    if (data.length < 2) return {};
    final latest = (data.last['nav_value'] as num).toDouble();
    final latestDateStr = data.last['nav_date'] ?? '';
    final latestDate = DateTime.tryParse(latestDateStr) ?? DateTime.now();

    double getRet(int days) {
      final target = latestDate.subtract(Duration(days: days));
      Map<String, dynamic>? point;
      for (var i = data.length - 1; i >= 0; i--) {
        final d = DateTime.tryParse(data[i]['nav_date'] ?? '');
        if (d != null && (d.isBefore(target) || d.isAtSameMomentAs(target))) {
          point = data[i];
          break;
        }
      }
      point ??= data.first;
      final oldVal = (point['nav_value'] as num).toDouble();
      return (oldVal > 0) ? (latest / oldVal - 1) * 100 : 0;
    }

    return {
      '1W': getRet(7),
      '1M': getRet(30),
      '3M': getRet(90),
      '6M': getRet(182),
      '1Y': getRet(365),
    };
  }

  List<Map<String, dynamic>> _getFilteredHistory(List<Map<String, dynamic>> fullData, bool isNav) {
    if (fullData.isEmpty) return [];

    int days = 365;
    if (_selectedPeriod == '1W') days = 7;
    else if (_selectedPeriod == '1M') days = 30;
    else if (_selectedPeriod == '3M') days = 90;
    else if (_selectedPeriod == '6M') days = 182;

    final lastItem = fullData.last;
    DateTime? latestDate;
    if (isNav) {
      latestDate = DateTime.tryParse(lastItem['nav_date'] ?? '');
    } else {
      latestDate = DateTime.fromMillisecondsSinceEpoch(lastItem['timestamp'] as int);
    }
    
    latestDate ??= DateTime.now();
    final target = latestDate.subtract(Duration(days: days));

    return fullData.where((p) {
      DateTime? d;
      if (isNav) {
        d = DateTime.tryParse(p['nav_date'] ?? '');
      } else {
        d = DateTime.fromMillisecondsSinceEpoch(p['timestamp'] as int);
      }
      return d != null && (d.isAfter(target) || d.isAtSameMomentAs(target));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 150, child: Center(child: CircularProgressIndicator()));
    if (_history.isEmpty) return const SizedBox();

    final filteredNav = _getFilteredHistory(_history, true);
    final filteredBench = _getFilteredHistory(_benchmarkHistory, false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final chartWidth = constraints.maxWidth - 12; 
            return Stack(
              children: [
                _buildChart(filteredNav, filteredBench, chartWidth),
                if (_isSelecting && _startIdx != null && _endIdx != null) 
                  _buildRangeOverlay(filteredNav, chartWidth),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            InkWell(
              onTap: () => setState(() => _showFundLine = !_showFundLine),
              child: Opacity(
                opacity: _showFundLine ? 1.0 : 0.4,
                child: _legendMarker(Colors.indigo[700]!, 'Fund'),
              ),
            ),
            const SizedBox(width: 16),
            InkWell(
              onTap: () => setState(() => _showBenchmarkLine = !_showBenchmarkLine),
              child: Opacity(
                opacity: _showBenchmarkLine ? 1.0 : 0.4,
                child: _legendMarker(Colors.orange[700]!, _benchmarkName),
              ),
            ),
            const SizedBox(width: 2),
            PopupMenuButton<String>(
              icon: const Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onSelected: (String val) async {
                setState(() {
                  _benchmarkName = val;
                  _loading = true;
                });
                try {
                  final benchData = await _indexService.fetchIndexHistory(val);
                  if (mounted) {
                    setState(() {
                      _benchmarkHistory = benchData;
                      _loading = false;
                    });
                  }
                } catch (e) {
                  if (mounted) setState(() => _loading = false);
                }
              },
              itemBuilder: (BuildContext context) {
                final List<String> commonIndices = [
                  'NIFTY 50', 'NIFTY NEXT 50', 'NIFTY 100', 'NIFTY 200', 'NIFTY 500',
                  'NIFTY MIDCAP 50', 'NIFTY MIDCAP 100', 'NIFTY MIDCAP 150',
                  'NIFTY SMALLCAP 50', 'NIFTY SMALLCAP 100', 'NIFTY SMALLCAP 250',
                  'NIFTY BANK', 'NIFTY IT', 'NIFTY PHARMA', 'NIFTY FMCG', 'NIFTY AUTO', 
                  'NIFTY ENERGY', 'NIFTY INFRA', 'NIFTY REALTY', 'NIFTY CPSE', 'NIFTY INDIA DEFENCE'
                ];
                return commonIndices.map((String choice) {
                  return PopupMenuItem<String>(
                    value: choice,
                    height: 32,
                    child: Text(
                      choice,
                      style: TextStyle(
                        fontSize: widget.setCompactLayout ? 13 : 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.indigo[900],
                      ),
                    ),
                  );
                }).toList();
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildReturnMatrix(),
      ],
    );
  }

  Widget _legendMarker(Color color, String label) {
    return Row(
      children: [
        Container(width: 10, height: 2, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildChart(List<Map<String, dynamic>> navData, List<Map<String, dynamic>> benchData, double chartWidth) {
    if (navData.length < 2) return const SizedBox(height: 180, child: Center(child: Text('Not enough data', style: TextStyle(fontSize: 12, color: Colors.grey))));
    
    // --- Date-based Data Alignment ---
    // 1. Create a map of benchmark values keyed by date string (YYYY-MM-DD)
    final Map<String, double> benchMap = {};
    for (var p in benchData) {
       final d = DateTime.fromMillisecondsSinceEpoch(p['timestamp'] as int);
       final dateKey = DateFormat('yyyy-MM-dd').format(d);
       benchMap[dateKey] = (p['value'] as num).toDouble();
    }

    // 2. Identify the common base date (the first date in navData)
    final firstNavDateStr = navData.first['nav_date'] ?? '';
    final firstNavDate = DateTime.tryParse(firstNavDateStr) ?? DateTime.now();
    
    // 3. Find the benchmark value for the first NAV date to use as a base for rebasing
    double benchBase = 1.0;
    if (benchMap.isNotEmpty) {
      // Look for exact match or closest previous value
      String lookupKey = DateFormat('yyyy-MM-dd').format(firstNavDate);
      if (benchMap.containsKey(lookupKey)) {
        benchBase = benchMap[lookupKey]!;
      } else {
        // Fallback: Use the earliest available benchmark point if exact match isn't found
        benchBase = (benchData.first['value'] as num).toDouble();
      }
    }

    final navBase = (navData.first['nav_value'] as num).toDouble();

    List<FlSpot> navSpots = [];
    List<FlSpot> benchSpots = [];

    for (int i = 0; i < navData.length; i++) {
      final navDateStr = navData[i]['nav_date'] ?? '';
      final navDate = DateTime.tryParse(navDateStr);
      final navVal = (navData[i]['nav_value'] as num).toDouble();
      
      // X-coordinate is simply the index in navData to keep timeline linear
      final double x = i.toDouble();
      
      // Plot Fund spot
      navSpots.add(FlSpot(x, navBase > 0 ? (navVal / navBase * 100) : 100));

      // Plot Benchmark spot aligned to the same X (same date)
      if (navDate != null && benchMap.isNotEmpty) {
        String lookupKey = DateFormat('yyyy-MM-dd').format(navDate);
        double? bVal;
        
        if (benchMap.containsKey(lookupKey)) {
          bVal = benchMap[lookupKey];
        } else {
          // If no exact date match (e.g., weekend/holiday mismatch), look for previous value
          for (int dayBack = 1; dayBack <= 5; dayBack++) {
            final prevKey = DateFormat('yyyy-MM-dd').format(navDate.subtract(Duration(days: dayBack)));
            if (benchMap.containsKey(prevKey)) {
              bVal = benchMap[prevKey];
              break;
            }
          }
        }
        
        if (bVal != null) {
          benchSpots.add(FlSpot(x, benchBase > 0 ? (bVal / benchBase * 100) : 100));
        }
      }
    }

    double minY = 100;
    double maxY = 100;
    for (var s in navSpots) {
      if (s.y < minY) minY = s.y;
      if (s.y > maxY) maxY = s.y;
    }
    for (var s in benchSpots) {
      if (s.y < minY) minY = s.y;
      if (s.y > maxY) maxY = s.y;
    }
    
    final padding = (maxY - minY) * 0.15;
    minY = (minY - padding).floorToDouble();
    maxY = (maxY + padding).ceilToDouble();

    return Listener(
      onPointerDown: (e) {
        setState(() {
          _pointers[e.pointer] = e.localPosition;
          _updateSelection(navData, chartWidth);
        });
      },
      onPointerMove: (e) {
        setState(() {
          _pointers[e.pointer] = e.localPosition;
          _updateSelection(navData, chartWidth);
        });
      },
      onPointerUp: (e) {
        setState(() {
          _pointers.remove(e.pointer);
          if (_pointers.length < 2) _isSelecting = false;
        });
      },
      onPointerCancel: (e) {
        setState(() {
          _pointers.remove(e.pointer);
          _isSelecting = false;
        });
      },
      child: Container(
        height: 180,
        width: double.infinity,
        padding: const EdgeInsets.only(right: 12, left: 0),
        child: LineChart(
          LineChartData(
            lineTouchData: LineTouchData(
              enabled: !_isSelecting,
              touchTooltipData: LineTouchTooltipData(
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItems: (touchedSpots) {
                  // Sort touched spots to have a consistent display order (Fund first, then Benchmark)
                  final sortedSpots = touchedSpots.toList()..sort((a, b) => a.barIndex.compareTo(b.barIndex));
                  
                  return sortedSpots.map((spot) {
                    if (spot.barIndex == 0) { // Fund
                      if (!_showFundLine) return null;
                      final item = navData[spot.x.toInt()];
                      final rebasedVal = spot.y;
                      final returnPct = rebasedVal - 100;
                      return LineTooltipItem(
                        '${item['nav_date']}\nFund: \u20b9${(item['nav_value'] as num).toStringAsFixed(2)} (${returnPct >= 0 ? '+' : ''}${returnPct.toStringAsFixed(1)}%)',
                        const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      );
                    } else if (spot.barIndex == 1) { // Benchmark
                      if (!_showBenchmarkLine) return null;
                      final rebasedVal = spot.y;
                      final returnPct = rebasedVal - 100;
                      return LineTooltipItem(
                        'Benchmark: ${returnPct >= 0 ? '+' : ''}${returnPct.toStringAsFixed(1)}%',
                        TextStyle(color: Colors.orange[200], fontSize: 10, fontWeight: FontWeight.bold),
                      );
                    }
                    return null;
                  }).where((item) => item != null).toList();
                },
              ),
            ),
            gridData: const FlGridData(show: false),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            minY: minY,
            maxY: maxY,
            lineBarsData: [
              if (benchSpots.isNotEmpty && _showBenchmarkLine)
                LineChartBarData(
                  spots: benchSpots,
                  isCurved: true,
                  color: Colors.orange[700],
                  barWidth: 1.5,
                  dotData: const FlDotData(show: false),
                ),
              if (_showFundLine)
                LineChartBarData(
                  spots: navSpots,
                  isCurved: true,
                  color: Colors.indigo[700],
                  barWidth: 1.5,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: true, color: Colors.indigo.withOpacity(0.05)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateSelection(List<Map<String, dynamic>> data, double chartWidth) {
    if (_pointers.length >= 2) {
      _isSelecting = true;
      final sortedPointers = _pointers.values.toList()..sort((a, b) => a.dx.compareTo(b.dx));
      final p1 = sortedPointers.first;
      final p2 = sortedPointers.last;
      
      if (chartWidth <= 0) return;

      double x1Pct = (p1.dx / chartWidth).clamp(0.0, 1.0);
      double x2Pct = (p2.dx / chartWidth).clamp(0.0, 1.0);
      
      _startIdx = (x1Pct * (data.length - 1)).round().clamp(0, data.length - 1);
      _endIdx = (x2Pct * (data.length - 1)).round().clamp(0, data.length - 1);
    }
  }

  Widget _buildRangeOverlay(List<Map<String, dynamic>> data, double chartWidth) {
    if (_startIdx == null || _endIdx == null || _startIdx == _endIdx) return const SizedBox();
    
    if (_startIdx! >= data.length || _endIdx! >= data.length) return const SizedBox();

    final s = data[_startIdx!];
    final e = data[_endIdx!];
    final v1 = (s['nav_value'] as num).toDouble();
    final v2 = (e['nav_value'] as num).toDouble();
    final ret = (v1 > 0) ? (v2 / v1 - 1) * 100 : 0.0;
    
    // Calculate benchmark return for the same period if available
    double? benchRet;
    if (_benchmarkHistory.isNotEmpty) {
      final sDate = DateTime.tryParse(s['nav_date'] ?? '');
      final eDate = DateTime.tryParse(e['nav_date'] ?? '');
      
      if (sDate != null && eDate != null) {
        Map<String, dynamic>? bs, be;
        for (var p in _benchmarkHistory) {
          final d = DateTime.fromMillisecondsSinceEpoch(p['timestamp'] as int);
          if (bs == null && (d.isAfter(sDate) || d.isAtSameMomentAs(sDate))) bs = p;
          if (be == null && (d.isAfter(eDate) || d.isAtSameMomentAs(eDate))) be = p;
        }
        if (bs != null && be != null) {
          final bv1 = (bs['value'] as num).toDouble();
          final bv2 = (be['value'] as num).toDouble();
          if (bv1 > 0) benchRet = (bv2 / bv1 - 1) * 100;
        }
      }
    }

    final x1 = (_startIdx! / (data.length - 1)) * chartWidth;
    final x2 = (_endIdx! / (data.length - 1)) * chartWidth;

    return IgnorePointer(
      child: Container(
        height: 180,
        width: double.infinity,
        child: Stack(
          children: [
            Positioned(
              left: x1,
              width: (x2 - x1).clamp(0, double.infinity),
              top: 0,
              bottom: 0,
              child: Container(color: Colors.indigo.withOpacity(0.1)),
            ),
            Positioned(
              left: x1, top: 0, bottom: 0,
              child: Container(width: 2, color: Colors.indigo),
            ),
            Positioned(
              left: x2, top: 0, bottom: 0,
              child: Container(width: 2, color: Colors.indigo),
            ),
            Positioned(
              left: (x1 + (x2 - x1) / 2 - 60).clamp(0, chartWidth - 120),
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.indigo[900]?.withOpacity(0.9), 
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4)],
                ),
                child: Column(
                  children: [
                    Text('${s['nav_date']} \u2192 ${e['nav_date']}', style: const TextStyle(color: Colors.white, fontSize: 8)),
                    Text('Fund: ${ret >= 0 ? '+' : ''}${ret.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                    if (benchRet != null)
                      Text('Bench: ${benchRet >= 0 ? '+' : ''}${benchRet.toStringAsFixed(1)}%', style: TextStyle(color: Colors.orange[200], fontWeight: FontWeight.bold, fontSize: 10)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReturnMatrix() {
    final periods = ['1W', '1M', '3M', '6M', '1Y'];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: periods.map((pKey) {
          final isSelected = _selectedPeriod == pKey;
          final retVal = _returns[pKey];
          final isPos = (retVal ?? 0) >= 0;

          return InkWell(
            onTap: () => setState(() => _selectedPeriod = pKey),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? Colors.indigo[50] : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(pKey, style: TextStyle(fontSize: 10, color: isSelected ? Colors.indigo : Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(
                    retVal != null ? '${isPos ? '+' : ''}${retVal.toStringAsFixed(1)}%' : '-',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                      color: retVal != null ? (isPos ? Colors.green[700] : Colors.red[700]) : Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
