import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/amfi_aum_data.dart';
import '../services/amfi_aum_service.dart';

class AmfiAumPage extends StatefulWidget {
  const AmfiAumPage({super.key});

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
  
  String _sortBy = 'AUM';
  bool _isAscending = false;

  final List<String> _sortOptions = ['Name', 'AUM', 'Growth', 'AUM Increase'];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final res = await _service.fetchAumComparison();
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
                        Text(group.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Tooltip(
                          message: 'Full Value: ₹${_formatAum(group.aum, full: true)} Cr',
                          child: Text('Current Total: ₹${_formatAum(group.aum)} Cr', style: const TextStyle(color: Colors.indigo, fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                        if (prevGroup != null)
                           Tooltip(
                             message: 'Full Value: ₹${_formatAum(prevGroup.aum, full: true)} Cr',
                             child: Text('Previous Total: ₹${_formatAum(prevGroup.aum)} Cr', style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
                              Expanded(child: Text(sch.schemeName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
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
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
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
        title: const Text('MF Industry AUM', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetch),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data == null
              ? const Center(child: Text('No data available'))
              : Scrollbar(
                  thumbVisibility: true,
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _buildSummaryCard()),
                      SliverToBoxAdapter(child: _buildSearchAndSort()),
                      SliverToBoxAdapter(child: _buildGroupingToggle()),
                      if (_filteredGroups.isEmpty)
                        const SliverFillRemaining(child: Center(child: Text('No entries found')))
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
              Text('Industry AAUM', style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                child: Text(cur.period, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
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
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                  child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(growth >= 0 ? Icons.trending_up : Icons.trending_down, color: color, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          '${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(2)}%',
                          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    Text(
                      '(${absDiff >= 0 ? '+' : ''}₹${_formatAum(absDiff.abs())} Cr)',
                      style: TextStyle(color: color.withOpacity(0.9), fontWeight: FontWeight.bold, fontSize: 10),
                    ),
                  ],
                ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('vs ${prev.period}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    Tooltip(
                      message: 'Full Value: ₹${_formatAum(prev.totalAum, full: true)} Cr',
                      child: Text('₹${_formatAum(prev.totalAum)} Cr', style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w500)),
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
              Text(label, style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.bold : FontWeight.normal, color: active ? Colors.indigo[700] : Colors.grey[600])),
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
              const Text('Sort By:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _sortBy,
                      isExpanded: true,
                      isDense: true,
                      style: const TextStyle(color: Colors.black87, fontSize: 13),
                      items: _sortOptions.map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
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
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(_isAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 20, color: Colors.indigo),
                onPressed: () {
                  setState(() {
                    _isAscending = !_isAscending;
                    _sortAndFilter();
                  });
                },
                tooltip: _isAscending ? 'Ascending' : 'Descending',
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
    final color = growth >= 0 ? Colors.green : Colors.red;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)),
      child: InkWell(
        onTap: () => _showGroupDetails(group),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Tooltip(
                          message: 'Full Value: ₹${_formatAum(group.aum, full: true)} Cr',
                          child: Text('₹${_formatAum(group.aum)} Cr', style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                        if (prevGroup != null)
                           Tooltip(
                             message: 'Full Value: ₹${_formatAum(prevGroup.aum, full: true)} Cr',
                             child: Text('  (₹${_formatAum(prevGroup.aum)})', style: const TextStyle(color: Colors.grey, fontSize: 11)),
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
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Tooltip(
                    message: 'Full Increase: ₹${_formatAum(absDiff, full: true)} Cr',
                    child: Text(
                      '(${absDiff >= 0 ? '+' : ''}₹${_formatAum(absDiff.abs())} Cr)',
                      style: TextStyle(color: color.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Text('Growth', style: TextStyle(color: Colors.grey, fontSize: 10)),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
