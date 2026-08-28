import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/portfolio_service.dart';
import '../services/nav_repository.dart';
import '../widgets/common_widgets.dart';
import '../pages/portfolio_charts_page.dart';

class PortfolioTab extends StatefulWidget {
  final String selectedLanguage;
  final Future<String> Function(String) translate;
  final String Function(String, {String? arg}) t;
  final DateTime? selectedFilterDate;
  final bool privacyMode;
  final bool hideZeroHoldings;
  final bool showFolioInList;
  final bool setCompactLayout;
  final bool setShowIconsInNav;
  final Set<int>? selectedImportIds;
  final int setApiTimeout;

  const PortfolioTab({
    super.key,
    required this.selectedLanguage,
    required this.translate,
    required this.t,
    this.selectedFilterDate,
    required this.privacyMode,
    required this.hideZeroHoldings,
    required this.showFolioInList,
    required this.setCompactLayout,
    required this.setShowIconsInNav,
    this.selectedImportIds,
    required this.setApiTimeout,
  });

  @override
  State<PortfolioTab> createState() => _PortfolioTabState();
}

class _PortfolioTabState extends State<PortfolioTab> {
  final PortfolioService _portfolio = PortfolioService();
  final NavRepository _repo = NavRepository();
  final ScrollController _portfolioScrollCtl = ScrollController();

  List<Map<String, dynamic>> _portfolioRows = [];
  Map<String, List<Map<String, dynamic>>> _groupedPortfolio = {};
  Set<String> _expandedGroups = {};
  String _selectedPortfolioCompany = 'All Companies';
  List<String> _portfolioAmcList = ['All Companies'];
  String _portfolioSortOption = 'Invested';
  bool _isPortfolioAscending = false;
  String _portfolioPeriod = '1D';
  bool _showNetReturns = false;
  bool _fetchingHistorical = false;
  DateTimeRange? _customPortfolioRange;
  Map<String, double> _periodNavs = {};

  @override
  void initState() {
    super.initState();
    _loadPortfolio();
  }

  @override
  void didUpdateWidget(PortfolioTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedFilterDate != widget.selectedFilterDate ||
        oldWidget.selectedImportIds != widget.selectedImportIds ||
        oldWidget.hideZeroHoldings != widget.hideZeroHoldings) {
      _loadPortfolio();
    }
  }

  Future<void> _loadPortfolio() async {
    _portfolioRows = await _portfolio.listPortfolio(
        amc: _selectedPortfolioCompany,
        orderBy: _getPortfolioOrder(),
        importIds: widget.selectedImportIds?.toList(),
        targetDate: widget.selectedFilterDate != null ? DateFormat('yyyy-MM-dd').format(widget.selectedFilterDate!) : null
    );

    if (widget.hideZeroHoldings) {
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
    if (mounted) setState(() {});
  }

  Future<void> _loadPeriodNavs() async {
    final milestoneDates = _getMilestoneDates(_portfolioPeriod);
    if (milestoneDates.isEmpty) return;
    
    // We want the NAV at the START of the period.
    final startDate = milestoneDates.first;

    final database = await _repo.db;
    final isins = _portfolioRows.map((r) => r['isin'] as String?).where((i) => i != null).cast<String>().toSet().toList();

    if (isins.isEmpty) return;

    final placeholders = List.filled(isins.length, '?').join(',');
    
    // Improved query to find the closest NAV ON or BEFORE the start date for each ISIN
    final sql = '''
      SELECT isin, nav_value FROM (
        SELECT isin_div_payout as isin, nav_value, nav_date FROM nav
        UNION ALL
        SELECT isin_reinvestment as isin, nav_value, nav_date FROM nav
      ) t
      WHERE nav_date <= ? AND isin IN ($placeholders)
      GROUP BY isin
      HAVING nav_date = MAX(nav_date)
    ''';

    final res = await database.rawQuery(sql, [startDate, ...isins]);
    if (mounted) {
      setState(() {
        _periodNavs = { for (var r in res) r['isin'] as String : (r['nav_value'] as num).toDouble() };
      });
    }
  }

  Future<void> _handlePeriodChange(String pVal) async {
    setState(() {
      _portfolioPeriod = pVal;
      _fetchingHistorical = true;
    });

    try {
      List<String> targetDates = [];
      if (pVal == 'Custom') {
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: DateTime.now(),
        );
        if (picked != null) {
          _customPortfolioRange = picked;
          targetDates = [
             DateFormat('yyyy-MM-dd').format(picked.start),
             DateFormat('yyyy-MM-dd').format(picked.end),
          ];
        } else {
          setState(() => _fetchingHistorical = false);
          return;
        }
      } else {
        targetDates = _getMilestoneDates(pVal);
      }

      if (targetDates.isNotEmpty) {
        final database = await _repo.db;
        
        // 1. Check which dates already have data in the local DB
        final String placeholders = List.filled(targetDates.length, '?').join(',');
        final List<Map<String, dynamic>> existing = await database.rawQuery(
          'SELECT DISTINCT nav_date FROM nav WHERE nav_date IN ($placeholders)',
          targetDates
        );
        
        final Set<String> cachedDates = existing.map((r) => r['nav_date'] as String).toSet();
        final List<String> missingDates = targetDates.where((d) => !cachedDates.contains(d)).toList();

        if (missingDates.isNotEmpty) {
          // 2. Only fetch missing dates from the API
          final count = await _repo.fetchAndImport(
            specificDates: missingDates,
            timeoutSeconds: widget.setApiTimeout,
            force: true
          );
          
          if (mounted && count > 0) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Fetched ${missingDates.length} business days from AMFI ($count records).'),
              duration: const Duration(seconds: 2),
            ));
          }
        } else {
          debugPrint('All required dates for $pVal are already available in cache.');
        }
      }
      await _loadPortfolio();
    } catch (e) {
      debugPrint('Error in period change: $e');
    } finally {
      if (mounted) setState(() => _fetchingHistorical = false);
    }
  }

  String? _getPortfolioOrder() {
    switch (_portfolioSortOption) {
      case 'Invested':
        return _isPortfolioAscending ? 'invested_asc' : 'invested_desc';
      case 'Value':
        return _isPortfolioAscending ? 'current_asc' : 'current_desc';
      case 'Return':
        return _isPortfolioAscending ? 'return_asc' : 'return_desc';
      case '1D Return':
        return _isPortfolioAscending ? '1d_asc' : '1d_desc';
      case 'Name':
        return _isPortfolioAscending ? 'name_asc' : 'name_desc';
      default:
        return null;
    }
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
            CommonWidgets.txt(r['fund_name'] ?? '-', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
            const Divider(),
            CommonWidgets.detailRow('Investor', r['investor_name']),
            CommonWidgets.detailRow('ISIN', r['isin']),
            CommonWidgets.detailRow('Folio', r['folio_number']),
            CommonWidgets.detailRow('Units', r['total_units']?.toString()),
            CommonWidgets.detailRow('Invested Value', '₹${CommonWidgets.formatCurrency(r['invested_value'] as num? ?? 0, privacyMode: widget.privacyMode)}'),
            CommonWidgets.detailRow('Current Value', '₹${CommonWidgets.formatCurrency(((r['total_units'] as num? ?? 0) * (r['latest_nav'] as num? ?? 0)), privacyMode: widget.privacyMode)}'),
            CommonWidgets.detailRow('Latest NAV', r['latest_nav']?.toString()),
            CommonWidgets.detailRow('NAV Date', r['latest_nav_date']),
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

  void _showPortfolioCharts() {
    Navigator.push(context, MaterialPageRoute(builder: (c) => PortfolioChartsPage(
      portfolioRows: _portfolioRows,
      selectedImportIds: widget.selectedImportIds,
      selectedLanguage: widget.selectedLanguage,
      translate: widget.translate,
    )));
  }

  List<String> _getMilestoneDates(String period) {
    final now = DateTime.now();
    final dates = <DateTime>[];
    
    // Find the latest business day (End of period)
    DateTime latest = now;
    while (latest.weekday == DateTime.saturday || latest.weekday == DateTime.sunday) {
      latest = latest.subtract(const Duration(days: 1));
    }
    dates.add(latest);

    if (period == 'Custom' && _customPortfolioRange != null) {
      dates.add(_customPortfolioRange!.start);
      dates.add(_customPortfolioRange!.end);
    } else {
      // Find the start of the period
      DateTime start = _getPeriodStartDate(period, from: latest);
      dates.add(start);
    }

    final formatted = dates.map((d) {
      var bd = d;
      // Adjust weekend to previous Friday for milestone identification
      while (bd.weekday == DateTime.saturday || bd.weekday == DateTime.sunday) {
        bd = bd.subtract(const Duration(days: 1));
      }
      return DateFormat('yyyy-MM-dd').format(bd);
    }).toSet().toList()..sort();
    
    return formatted;
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

  @override
  Widget build(BuildContext context) {
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
                      CommonWidgets.txt(_showNetReturns ? widget.t('net_returns') : widget.t('period_returns', arg: _portfolioPeriod),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _showNetReturns ? Colors.orange[900] : Colors.green[900]), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
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
        if (widget.selectedFilterDate != null)
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
                  Text('Showing values as of: ${DateFormat('dd-MMM-yyyy').format(widget.selectedFilterDate!)}',
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
                    items: _portfolioAmcList.map((s) => DropdownMenuItem(value: s, child: CommonWidgets.txt(s == 'All Companies' ? widget.t('all_amc') : s, overflow: true, selectedLanguage: widget.selectedLanguage, translate: widget.translate))).toList(),
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
              child: Row(
                children: [
                  Expanded(
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
                            'Invested', 'Value', 'Return', '1D Return', 'Name'
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
                  IconButton(
                    icon: Icon(_isPortfolioAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 20, color: Colors.indigo),
                    onPressed: () {
                      setState(() => _isPortfolioAscending = !_isPortfolioAscending);
                      _loadPortfolio();
                    },
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ],
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
            CommonWidgets.txt('My Holdings', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
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
            child: Column(children: [header, Expanded(child: Center(child: CommonWidgets.txt('No holdings imported yet', selectedLanguage: widget.selectedLanguage, translate: widget.translate)))]),
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
                      visualDensity: widget.setCompactLayout ? VisualDensity.compact : VisualDensity.standard,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      onTap: () {
                        setState(() {
                          if (isExpanded) _expandedGroups.remove(isin);
                          else _expandedGroups.add(isin);
                        });
                      },
                      title: CommonWidgets.txt(list.first['fund_name'] ?? 'Unknown Fund',
                          style: TextStyle(fontSize: widget.setCompactLayout ? 13 : 14, fontWeight: FontWeight.w600, color: Colors.indigo[900]), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text('${list.length} holdings \u2022 \u20b9${CommonWidgets.formatCurrency(gInv, privacyMode: widget.privacyMode)}',
                                    style: TextStyle(fontSize: widget.setCompactLayout ? 10 : 11, color: Colors.grey[600])),
                              ),
                              Icon(isExpanded ? Icons.expand_less : Icons.expand_more, size: widget.setCompactLayout ? 16 : 18, color: Colors.grey),
                              if (widget.setShowIconsInNav) ...[
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
                                  '${gPeriodGain >= 0 ? '+' : ''}${CommonWidgets.formatCurrency(gPeriodGain, privacyMode: widget.privacyMode)} (${gPeriodPct.toStringAsFixed(2)}%)',
                                  style: TextStyle(fontSize: widget.setCompactLayout ? 11 : 12, fontWeight: FontWeight.bold, color: gPeriodGain >= 0 ? Colors.green[700] : Colors.red[700]),
                                )
                                    : RichText(
                                  text: TextSpan(
                                    style: TextStyle(fontSize: widget.setCompactLayout ? 12 : 13, fontWeight: FontWeight.bold, color: Colors.black87),
                                    children: [
                                      TextSpan(text: CommonWidgets.formatCurrency(gCur, privacyMode: widget.privacyMode)),
                                      TextSpan(
                                        text: ' (${gPct >= 0 ? '+' : ''}${gPct.toStringAsFixed(2)}%)',
                                        style: TextStyle(color: gPct >= 0 ? Colors.green[700] : Colors.red[700], fontSize: widget.setCompactLayout ? 10 : 11),
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
                            visualDensity: widget.setCompactLayout ? VisualDensity.compact : VisualDensity.standard,
                            onTap: () => _showPortfolioDetails(r),
                            title: Text(r['investor_name'] ?? 'Family', style: TextStyle(fontSize: widget.setCompactLayout ? 12 : 13, color: Colors.indigo[700], fontWeight: FontWeight.w500)),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: FittedBox(
                                      alignment: Alignment.centerLeft,
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                          'U: ${u.toStringAsFixed(3)}${widget.showFolioInList ? ' \u2022 F: ${r['folio_number'] ?? '-'}' : ''} \u2022 ${r['latest_nav_date'] ?? 'No NAV'}',
                                          style: TextStyle(fontSize: widget.setCompactLayout ? 10 : 11, color: Colors.grey[600])
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
                                      !_showNetReturns ? '${pGain >= 0 ? '+' : ''}${CommonWidgets.formatCurrency(pGain, privacyMode: widget.privacyMode)}' : CommonWidgets.formatCurrency(curVal, privacyMode: widget.privacyMode),
                                      style: TextStyle(fontSize: widget.setCompactLayout ? 11 : 12, fontWeight: FontWeight.w500, color: !_showNetReturns ? (pGain >= 0 ? Colors.green[700] : Colors.red[700]) : Colors.black87),
                                    ),
                                  ),
                                  Text('\u20b9${CommonWidgets.formatCurrency(inv, privacyMode: widget.privacyMode)}', style: TextStyle(fontSize: widget.setCompactLayout ? 9 : 10, color: Colors.grey)),
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
                      CommonWidgets.txt('TOTAL', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 16), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Row(
                        children: [
                          CommonWidgets.txt('Effective ', style: const TextStyle(fontSize: 10, color: Colors.indigo), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                          Text('$validPeriodCount/${_portfolioRows.length} ', style: const TextStyle(fontSize: 10, color: Colors.indigo, fontWeight: FontWeight.bold)),
                          CommonWidgets.txt('matched', style: const TextStyle(fontSize: 10, color: Colors.indigo), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                          CommonWidgets.txt(' for ${_portfolioPeriod}', style: const TextStyle(fontSize: 10, color: Colors.indigo), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                        ],
                      )),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                    Text(
                        !_showNetReturns ? '${totalPeriodGain >= 0 ? '+' : ''}\u20b9${CommonWidgets.formatCurrency(totalPeriodGain, privacyMode: widget.privacyMode)}' : '\u20b9${CommonWidgets.formatCurrency(totalCur, privacyMode: widget.privacyMode)}',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: !_showNetReturns ? (totalPeriodGain >= 0 ? Colors.green[800] : Colors.red[800]) : Colors.black87)
                    ),
                    Text(
                        !_showNetReturns ? 'Period: ${totalPeriodPct.toStringAsFixed(2)}%' : '\u20b9${CommonWidgets.formatCurrency(totalInv, privacyMode: widget.privacyMode)} (${totalNetGain >= 0 ? '+' : ''}${totalNetPct.toStringAsFixed(2)}%)',
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
    _portfolioScrollCtl.dispose();
    super.dispose();
  }
}
