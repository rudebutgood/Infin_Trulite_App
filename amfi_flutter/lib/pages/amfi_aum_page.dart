import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/amfi_aum_data.dart';
import '../services/amfi_aum_service.dart';
import '../widgets/common_widgets.dart';

class AmfiAumPage extends StatefulWidget {
  final String selectedLanguage;
  final Future<String> Function(String) translate;
  final bool setCompactLayout;

  const AmfiAumPage({
    super.key,
    required this.selectedLanguage,
    required this.translate,
    required this.setCompactLayout,
  });

  @override
  State<AmfiAumPage> createState() => _AmfiAumPageState();
}

class _AmfiAumPageState extends State<AmfiAumPage> {
  final AmfiAumService _service = AmfiAumService();
  final TextEditingController _searchCtl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  AmfiAumComparison? _data;
  List<AmfiAumGroup> _filteredGroups = [];
  bool _loading = true;
  int _groupIndex = 0; // 0 for Category, 1 for AMC, 2 for AMC+Category

  final Map<String, List<int>> _compOptions = {
    'Previous Period': [1, 2],
    '1 Year ago': [2, 1],
    '2 Years ago': [3, 1],
    '3 Years ago': [4, 1],
    '5 Years ago': [6, 1],
    '10 Years ago': [11, 1],
  };
  String _selectedComp = 'Previous Period';
  
  String _sortBy = 'AUM';
  bool _isAscending = false;

  final List<String> _sortOptions = ['Name', 'AUM', 'Growth', 'AUM Increase'];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch({bool force = false}) async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final comp = _compOptions[_selectedComp]!;
      final res = await _service.fetchAumComparison(
        ignoreCache: force,
        compFyId: comp[0],
        compPeriodId: comp[1],
      );
      if (mounted) {
        setState(() {
          _data = res;
          _sortAndFilter();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _sortAndFilter() {
    if (_data == null) return;
    
    // 1. Get Source List
    List<AmfiAumGroup> sourceList;
    if (_groupIndex == 0) sourceList = List.from(_data!.current.categories);
    else if (_groupIndex == 1) sourceList = List.from(_data!.current.amcs);
    else sourceList = List.from(_data!.current.amcCategories);

    // 2. Sort
    sourceList.sort((a, b) {
      int cmp = 0;
      if (_sortBy == 'Name') {
        cmp = a.name.compareTo(b.name);
      } else if (_sortBy == 'AUM') {
        cmp = a.aum.compareTo(b.aum);
      } else if (_sortBy == 'Growth') {
        cmp = _getGroupGrowth(a).compareTo(_getGroupGrowth(b));
      } else if (_sortBy == 'AUM Increase') {
        cmp = _getGroupAumIncrease(a).compareTo(_getGroupAumIncrease(b));
      }
      return _isAscending ? cmp : -cmp;
    });

    // 3. Filter
    final query = _searchCtl.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredGroups = sourceList;
      } else {
        _filteredGroups = sourceList
            .where((g) => g.name.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  AmfiAumGroup? _getPreviousGroup(AmfiAumGroup current) {
    if (_data == null) return null;
    try {
      List<AmfiAumGroup> prevList;
      if (_groupIndex == 0) prevList = _data!.previous.categories;
      else if (_groupIndex == 1) prevList = _data!.previous.amcs;
      else prevList = _data!.previous.amcCategories;

      return prevList.firstWhere((g) => g.name == current.name);
    } catch (_) {
      return null;
    }
  }

  double _getGroupGrowth(AmfiAumGroup current) {
    final prev = _getPreviousGroup(current);
    if (prev == null || prev.aum == 0) return 0;
    return (current.aum - prev.aum) / prev.aum * 100;
  }

  double _getGroupAumIncrease(AmfiAumGroup current) {
    final prev = _getPreviousGroup(current);
    if (prev == null) return 0;
    return (current.aum - prev.aum);
  }

  void _showGroupDetails(AmfiAumGroup group) {
    final prevGroup = _getPreviousGroup(group);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (c, s) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CommonWidgets.txt(group.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                        Tooltip(
                          message: 'Full Value: ₹${_formatAum(group.aum, full: true)} Cr',
                          child: Row(
                            children: [
                              CommonWidgets.txt('Current Total: ', style: const TextStyle(color: Colors.indigo, fontSize: 13, fontWeight: FontWeight.bold), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                              Text('₹${_formatAum(group.aum)} Cr', style: const TextStyle(color: Colors.indigo, fontSize: 13, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        if (prevGroup != null)
                           Tooltip(
                             message: 'Full Value: ₹${_formatAum(prevGroup.aum, full: true)} Cr',
                             child: Row(
                               children: [
                                 CommonWidgets.txt('Previous Total: ', style: const TextStyle(color: Colors.grey, fontSize: 12), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                                 Text('₹${_formatAum(prevGroup.aum)} Cr', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                               ],
                             ),
                           ),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Scrollbar(
                controller: s,
                thumbVisibility: true,
                child: ListView.separated(
                  controller: s,
                  padding: const EdgeInsets.all(16),
                  itemCount: group.schemes.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final sch = group.schemes[i];
                    double? pSchAum;
                    if (prevGroup != null) {
                      try {
                        pSchAum = prevGroup.schemes.firstWhere((ps) => ps.amfiCode == sch.amfiCode || ps.schemeName == sch.schemeName).totalAum;
                      } catch (_) {}
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: CommonWidgets.txt(sch.schemeName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500), selectedLanguage: widget.selectedLanguage, translate: widget.translate)),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Tooltip(
                                    message: 'Full Value: ₹${_formatAum(sch.totalAum, full: true)} Cr',
                                    child: Text('₹${_formatAum(sch.totalAum)} Cr', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo)),
                                  ),
                                  if (pSchAum != null) ...[
                                    Tooltip(
                                      message: 'Full Value: ₹${_formatAum(pSchAum, full: true)} Cr',
                                      child: Text('(₹${_formatAum(pSchAum)} Cr)', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                    ),
                                    Text(
                                      '${(sch.totalAum - pSchAum) >= 0 ? '+' : ''}₹${_formatAum((sch.totalAum - pSchAum).abs())} Cr',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: (sch.totalAum - pSchAum) >= 0 ? Colors.green : Colors.red),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Code: ${sch.amfiCode}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              Row(
                                children: [
                                  _miniAumInfo('Excl FoF', sch.aumExclFoF),
                                  const SizedBox(width: 12),
                                  _miniAumInfo('FoF', sch.aumFoF),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniAumInfo(String label, double val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        CommonWidgets.txt(label, style: const TextStyle(fontSize: 9, color: Colors.grey), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
        Tooltip(
          message: 'Full Value: ${val.toStringAsFixed(2)}',
          child: Text(_formatAum(val), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  String _formatAum(double val, {bool full = false}) {
    if (full) {
      return NumberFormat.currency(locale: 'en_IN', symbol: '', decimalDigits: 2).format(val).trim();
    }
    
    // For main display, we want to keep it readable but not lose as much info as toStringAsPrecision(4) did
    // NumberFormat en_IN automatically handles lakhs/crores formatting with commas
    if (val.abs() >= 1000) {
      return NumberFormat.currency(locale: 'en_IN', symbol: '', decimalDigits: 0).format(val).trim();
    } else {
      return NumberFormat.currency(locale: 'en_IN', symbol: '', decimalDigits: 1).format(val).trim();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const Icon(Icons.pie_chart, size: 20),
            const SizedBox(width: 8),
            Expanded(child: CommonWidgets.txt('MF Industry AUM', style: const TextStyle(fontWeight: FontWeight.bold), selectedLanguage: widget.selectedLanguage, translate: widget.translate)),
          ],
        ),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _fetch(force: true)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data == null
              ? Center(child: CommonWidgets.txt('No data available', selectedLanguage: widget.selectedLanguage, translate: widget.translate))
              : Scrollbar(
                  controller: _scrollController,
                  interactive: true,
                  thickness: 6,
                  radius: const Radius.circular(3),
                  thumbVisibility: true,
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverToBoxAdapter(child: _buildSummaryCard()),
                      SliverToBoxAdapter(child: _buildSearchAndSort()),
                      SliverToBoxAdapter(child: _buildGroupingToggle()),
                      if (_filteredGroups.isEmpty)
                        SliverFillRemaining(child: Center(child: CommonWidgets.txt('No entries found', selectedLanguage: widget.selectedLanguage, translate: widget.translate)))
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (ctx, i) => _buildGroupCard(_filteredGroups[i]),
                              childCount: _filteredGroups.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSummaryCard() {
    final cur = _data!.current;
    final prev = _data!.previous;
    final growth = _data!.percentageIncrease;
    final absDiff = cur.totalAum - prev.totalAum;
    final color = growth >= 0 ? Colors.greenAccent[400]! : Colors.redAccent[100]!;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo[900]!, Colors.indigo[700]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.indigo.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CommonWidgets.txt('Industry AAUM', style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                child: CommonWidgets.txt(cur.period, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Tooltip(
            message: 'Full Value: ₹${_formatAum(cur.totalAum, full: true)} Cr',
            child: Text('₹${_formatAum(cur.totalAum)} Cr', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Tooltip(
                message: 'Absolute Growth: ₹${_formatAum(absDiff, full: true)} Cr',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(growth >= 0 ? Icons.trending_up : Icons.trending_down, color: color, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          '${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(2)}%',
                          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    Text(
                      '(${absDiff >= 0 ? '+' : ''}₹${_formatAum(absDiff.abs())} Cr)',
                      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CommonWidgets.txt('vs ', style: const TextStyle(color: Colors.white70, fontSize: 11), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                        CommonWidgets.txt(prev.period, style: const TextStyle(color: Colors.white70, fontSize: 11), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Tooltip(
                      message: 'Full Value: ₹${_formatAum(prev.totalAum, full: true)} Cr',
                      child: Text('₹${_formatAum(prev.totalAum)} Cr', style: const TextStyle(color: Colors.white60, fontSize: 14, fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupingToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
      child: Row(
        children: [
          _toggleItem(0, 'Category', Icons.category_outlined),
          _toggleItem(1, 'AMC', Icons.business_outlined),
          _toggleItem(2, 'AMC+Cat', Icons.account_tree_outlined),
        ],
      ),
    );
  }

  Widget _toggleItem(int index, String label, IconData icon) {
    final active = _groupIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _groupIndex = index;
            _sortAndFilter();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? Colors.indigo[50] : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: active ? Colors.indigo[700] : Colors.grey),
              const SizedBox(width: 6),
              CommonWidgets.txt(label, style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.bold : FontWeight.normal, color: active ? Colors.indigo[700] : Colors.grey[600]), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchAndSort() {
    String hint = 'Search...';
    if (_groupIndex == 0) hint = 'Search Category...';
    else if (_groupIndex == 1) hint = 'Search AMC...';
    else hint = 'Search AMC or Category...';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          TextField(
            controller: _searchCtl,
            onChanged: (v) => _sortAndFilter(),
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedComp,
                      isExpanded: true,
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                      items: _compOptions.keys.map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: CommonWidgets.txt(value, selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedComp = val);
                          _fetch();
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _sortBy,
                      isExpanded: true,
                      style: const TextStyle(color: Colors.black87, fontSize: 12),
                      items: _sortOptions.map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: CommonWidgets.txt(value, selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _sortBy = val;
                            _sortAndFilter();
                          });
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(_isAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 20, color: Colors.indigo),
                onPressed: () {
                  setState(() {
                    _isAscending = !_isAscending;
                    _sortAndFilter();
                  });
                },
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(AmfiAumGroup group) {
    final prevGroup = _getPreviousGroup(group);
    final growth = _getGroupGrowth(group);
    final absDiff = _getGroupAumIncrease(group);
    final color = growth >= 0 ? Colors.green[700]! : Colors.red[700]!;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)),
      child: InkWell(
        onTap: () => _showGroupDetails(group),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(widget.setCompactLayout ? 12 : 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CommonWidgets.txt(group.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: widget.setCompactLayout ? 13 : 14, color: Colors.indigo[900]), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Tooltip(
                          message: 'Full Value: ₹${_formatAum(group.aum, full: true)} Cr',
                          child: Text('₹${_formatAum(group.aum)} Cr', style: TextStyle(color: Colors.black87, fontSize: widget.setCompactLayout ? 12 : 13, fontWeight: FontWeight.w600)),
                        ),
                        if (prevGroup != null)
                           Tooltip(
                             message: 'Full Value: ₹${_formatAum(prevGroup.aum, full: true)} Cr',
                             child: Text('  (₹${_formatAum(prevGroup.aum)})', style: TextStyle(color: Colors.grey[600], fontSize: widget.setCompactLayout ? 10 : 11)),
                           ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(2)}%',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: widget.setCompactLayout ? 13 : 14),
                  ),
                  Tooltip(
                    message: 'Full Increase: ₹${_formatAum(absDiff, full: true)} Cr',
                    child: Text(
                      '(${absDiff >= 0 ? '+' : ''}₹${_formatAum(absDiff.abs())} Cr)',
                      style: TextStyle(color: color.withOpacity(0.8), fontSize: widget.setCompactLayout ? 9 : 10, fontWeight: FontWeight.w600),
                    ),
                  ),
                  CommonWidgets.txt('Growth', style: TextStyle(color: Colors.grey[600], fontSize: widget.setCompactLayout ? 9 : 10), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                ],
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: Colors.grey, size: widget.setCompactLayout ? 18 : 20),
            ],
          ),
        ),
      ),
    );
  }
}
