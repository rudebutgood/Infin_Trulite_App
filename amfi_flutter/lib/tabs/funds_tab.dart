import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/nav_item.dart';
import '../services/nav_repository.dart';
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
  }

  Future<void> _initFilters() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedFundType = prefs.getString('selectedFundType') ?? 'Direct';
    _searchCtl.text = prefs.getString('lastSearch') ?? '';
    _recentSearches = prefs.getStringList('recentSearches') ?? [];
    
    _amcList = ['All Companies', ...await _repo.getFundCompanies()];
    
    final defaultSort = prefs.getString('setNAVDefaultSort') ?? 'Return \u2193';
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

    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      String? orderBy;
      switch (_sortOption) {
        case 'Return':
          orderBy = _isNavAscending ? 'return_asc' : 'return_desc';
          break;
        case 'Name':
          orderBy = _isNavAscending ? 'name_asc' : 'name_desc';
          break;
        case 'Nav Date':
          orderBy = _isNavAscending ? 'date_asc' : 'date_desc';
          break;
        case 'Nav report time':
          orderBy = _isNavAscending ? 'timestamp_asc' : 'timestamp_desc';
          break;
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
                Expanded(child: CommonWidgets.txt(it.schemeName ?? '-', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), selectedLanguage: widget.selectedLanguage, translate: widget.translate)),
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
            CommonWidgets.detailRow('Scheme Code', it.schemeCode),
            CommonWidgets.detailRow('ISIN (Payout)', it.isinDivPayout),
            CommonWidgets.detailRow('ISIN (Reinv)', it.isinReinvestment),
            CommonWidgets.detailRow('AMC', it.mfName),
            CommonWidgets.detailRow('Category', it.category),
            CommonWidgets.detailRow('NAV Value', it.navValue?.toString()),
            CommonWidgets.detailRow('NAV Date', it.navDate),
            CommonWidgets.detailRow('Sync Timestamp', it.apiTimestamp),
            CommonWidgets.detailRow('Is Held', it.isHeld ? 'Yes' : 'No'),
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

  Future<void> _launchExternalUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
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
            if (widget.lastSyncLog != null)
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      CommonWidgets.txt('Source: ', style: const TextStyle(fontSize: 10, color: Colors.black54), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                      Text('AMFI India (${CommonWidgets.formatImportedAt(widget.lastSyncLog!['end_time'])})',
                          style: const TextStyle(fontSize: 10, color: Colors.black54)),
                    ],
                  ),
                ),
              ),
            if (widget.selectedFilterDate != null)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.amber[100], borderRadius: BorderRadius.circular(4)),
                child: Text('Date: ${DateFormat('dd-MMM-yyyy').format(widget.selectedFilterDate!)}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber[900])),
              ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20, color: Colors.indigo),
              onPressed: widget.onRefreshTriggered,
              tooltip: 'Sync NAVs',
              visualDensity: VisualDensity.compact,
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
              hintText: widget.t('search'),
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
                  label: CommonWidgets.txt(tVal, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.bold : FontWeight.normal), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
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
                        child: Text(s == 'All Companies' ? widget.t('all_amc') : s, overflow: TextOverflow.ellipsis)
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
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _sortOption,
                          style: TextStyle(fontSize: 12, color: Colors.indigo[700], fontWeight: FontWeight.w600),
                          items: [
                            'Return', 'Name', 'Nav report time'
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
                  IconButton(
                    icon: Icon(_isNavAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 20, color: Colors.indigo[700]),
                    onPressed: () {
                      setState(() => _isNavAscending = !_isNavAscending);
                      _load();
                    },
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ],
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
          if (_items.isEmpty) return SizedBox(height: 300, child: Center(child: CommonWidgets.txt(widget.t('no_data'), selectedLanguage: widget.selectedLanguage, translate: widget.translate)));

          final it = _items[i - 1];
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            visualDensity: widget.setCompactLayout ? VisualDensity.compact : VisualDensity.standard,
            onTap: () => _showDetails(it),
            title: CommonWidgets.txt(it.schemeName ?? '-',
                style: TextStyle(fontSize: widget.setCompactLayout ? 13 : 14, fontWeight: it.isFavorite ? FontWeight.w700 : FontWeight.w500, color: Colors.indigo[900]), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(child: Text('${it.navDate ?? ''}  \u2022  ${it.apiTimestamp != null ? CommonWidgets.formatImportedAt(it.apiTimestamp!) : ''}',
                        style: TextStyle(fontSize: widget.setCompactLayout ? 10 : 11, color: Colors.grey[600]))),
                    if (widget.setShowIconsInNav) ...[
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
                Text(it.navValue?.toString() ?? '-', style: TextStyle(fontWeight: FontWeight.bold, fontSize: widget.setCompactLayout ? 13 : 14)),
                if (it.prevNavValue != null)
                  Builder(builder: (ctx) {
                    final diff = (it.navValue ?? 0) - (it.prevNavValue ?? 0);
                    final pct = (it.prevNavValue != null && it.prevNavValue! != 0) ? (diff / it.prevNavValue! * 100) : null;
                    final txtStr = (diff >= 0 ? '+' : '') + diff.toStringAsFixed(4) + (pct != null ? ' (${pct.toStringAsFixed(2)}%)' : '');
                    return Text(txtStr, style: TextStyle(color: diff >= 0 ? Colors.green[700] : Colors.red[700], fontSize: widget.setCompactLayout ? 10 : 11));
                  }),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _scrollCtl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }
}
