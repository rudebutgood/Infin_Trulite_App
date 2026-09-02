import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/factor_performance_data.dart';
import '../models/index_data.dart';
import '../services/index_service.dart';
import '../widgets/common_widgets.dart';

class FactorPerformancePage extends StatefulWidget {
  final String selectedLanguage;
  final Future<String> Function(String) translate;
  final bool setCompactLayout;
  final List<IndexData>? initialData;

  const FactorPerformancePage({
    super.key,
    required this.selectedLanguage,
    required this.translate,
    required this.setCompactLayout,
    this.initialData,
  });

  @override
  State<FactorPerformancePage> createState() => _FactorPerformancePageState();
}

class _FactorPerformancePageState extends State<FactorPerformancePage> {
  final IndexService _service = IndexService();
  final TextEditingController _searchCtl = TextEditingController();
  final ScrollController _scrollCtl = ScrollController();
  
  List<FactorPerformanceData> _allFactors = [];
  List<FactorPerformanceData> _filteredFactors = [];
  bool _loading = false;
  String _selectedPeriod = '1 Day';
  String _sortBy = 'Return';
  bool _isAscending = false;

  final List<String> _periods = ['1 Day', '1 Week', '1 Month', '1 Year'];
  final List<String> _sortOptions = ['Return', 'Name', 'P/E', 'Yield'];

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null && widget.initialData!.isNotEmpty) {
      _processData(widget.initialData!);
    } else {
      _fetchData();
    }
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  void _processData(List<IndexData> allIndices) {
    final List<FactorPerformanceData> mapped = [];

    for (var index in allIndices) {
      final key = FactorPerformanceData.normalize(index.name);
      if (FactorPerformanceData.factorMapping.containsKey(key)) {
        final map = FactorPerformanceData.factorMapping[key]!;
        mapped.add(FactorPerformanceData.fromIndexData(
          index,
          map['name']!,
          map['desc']!,
        ));
      }
    }
    
    _allFactors = mapped;
    _filter();
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final allIndices = await _service.fetchIndices();
      _processData(allIndices);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter() {
    final query = _searchCtl.text.toLowerCase().trim();
    List<FactorPerformanceData> list = _allFactors.where((f) {
      return f.factorName.toLowerCase().contains(query) || 
             f.indexName.toLowerCase().contains(query);
    }).toList();

    // Sorting
    list.sort((a, b) {
      int cmp = 0;
      if (_sortBy == 'Return') {
        cmp = _getReturnValue(a, _selectedPeriod).compareTo(_getReturnValue(b, _selectedPeriod));
      } else if (_sortBy == 'Name') {
        cmp = a.factorName.compareTo(b.factorName);
      } else if (_sortBy == 'P/E') {
        cmp = (a.pe ?? 999).compareTo(b.pe ?? 999);
      } else if (_sortBy == 'Yield') {
        cmp = (a.dy ?? 0).compareTo(b.dy ?? 0);
      }
      return _isAscending ? cmp : -cmp;
    });

    if (mounted) {
      setState(() {
        _filteredFactors = list;
      });
    }
  }

  double _getReturnValue(FactorPerformanceData data, String period) {
    switch (period) {
      case '1 Day': return data.dayReturn;
      case '1 Week': return data.weekReturn;
      case '1 Month': return data.oneMonthReturn;
      case '1 Year': return data.oneYearReturn;
      default: return data.oneYearReturn;
    }
  }

  void _showFullDetails(FactorPerformanceData d) {
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
                  Expanded(child: Text(d.factorName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Scrollbar(
                controller: s,
                thumbVisibility: true,
                child: ListView(
                  controller: s,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  children: [
                    CommonWidgets.txt('Description', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                    const SizedBox(height: 4),
                    Text(d.description, style: const TextStyle(fontSize: 13, height: 1.4)),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    CommonWidgets.txt('Returns Matrix', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _returnBoxDetail('1D', d.dayReturn),
                        _returnBoxDetail('1W', d.weekReturn),
                        _returnBoxDetail('1M', d.oneMonthReturn),
                        _returnBoxDetail('1Y', d.oneYearReturn),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    _detailRow('Index Name', d.indexName),
                    _detailRow('Last Value', '₹${d.last.toStringAsFixed(2)}'),
                    if (d.pe != null) _detailRow('P/E Ratio', d.pe!.toStringAsFixed(2)),
                    if (d.pb != null) _detailRow('P/B Ratio', d.pb!.toStringAsFixed(2)),
                    if (d.dy != null) _detailRow('Div. Yield', '${d.dy!.toStringAsFixed(2)}%'),
                    if (d.yearHigh != null) _detailRow('52W High', d.yearHigh!.toString()),
                    if (d.yearLow != null) _detailRow('52W Low', d.yearLow!.toString()),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 8),
                    CommonWidgets.txt('Raw Index Data', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                    ...d.rawData.entries.map((e) {
                      final val = e.value?.toString() ?? '-';
                      if (val.startsWith('http')) return const SizedBox.shrink();
                      return _detailRow(_formatKey(e.key), val);
                    }).toList(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey, fontSize: 13))),
          const SizedBox(width: 12),
          Expanded(flex: 3, child: SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _returnBoxDetail(String label, double value) {
    final color = value >= 0 ? Colors.green[700]! : Colors.red[700]!;
    return Container(
      width: 75,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}%',
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _formatKey(String key) {
    String result = key.replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(0)}');
    result = result.replaceAll('_', ' ');
    if (result.isEmpty) return key;
    result = result[0].toUpperCase() + result.substring(1);
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const Icon(Icons.analytics, size: 20),
            const SizedBox(width: 8),
            Expanded(child: CommonWidgets.txt('Factor Analysis', style: const TextStyle(fontWeight: FontWeight.bold), selectedLanguage: widget.selectedLanguage, translate: widget.translate)),
          ],
        ),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchData),
        ],
      ),
      body: Column(
        children: [
          _buildSearchAndFilters(),
          Expanded(
            child: _loading 
              ? const Center(child: CircularProgressIndicator())
              : _filteredFactors.isEmpty
                  ? Center(child: CommonWidgets.txt('No data available', selectedLanguage: widget.selectedLanguage, translate: widget.translate))
                  : Scrollbar(
                      controller: _scrollCtl,
                      interactive: true,
                      thickness: 6,
                      radius: const Radius.circular(3),
                      child: ListView.builder(
                        controller: _scrollCtl,
                        itemCount: _filteredFactors.length,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                        itemBuilder: (context, index) {
                          return _buildFactorCard(_filteredFactors[index]);
                        },
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: Colors.white,
      child: Column(
        children: [
          // Search Bar
          SizedBox(
            height: 45,
            child: TextField(
              controller: _searchCtl,
              onChanged: (v) => _filter(),
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              decoration: InputDecoration(
                hintText: 'Search Factors...',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20, color: Colors.blueGrey),
                suffixIcon: _searchCtl.text.isNotEmpty
                    ? IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.cancel, size: 20, color: Colors.grey),
                        onPressed: () {
                          _searchCtl.clear();
                          _filter();
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.indigo[900]!, width: 2)),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Period & Sorting Row
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    CommonWidgets.txt('Period:', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedPeriod,
                            isExpanded: true,
                            style: const TextStyle(color: Colors.black, fontSize: 14),
                            items: _periods.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedPeriod = val;
                                  _filter();
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    CommonWidgets.txt('Sort:', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _sortBy,
                            isExpanded: true,
                            style: const TextStyle(color: Colors.black, fontSize: 14),
                            items: _sortOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _sortBy = val;
                                  _filter();
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(_isAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 20, color: Colors.indigo[700]),
                      onPressed: () {
                        setState(() {
                          _isAscending = !_isAscending;
                          _filter();
                        });
                      },
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
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

  Widget _buildFactorCard(FactorPerformanceData d) {
    final returnValue = _getReturnValue(d, _selectedPeriod);
    final color = returnValue >= 0 ? Colors.green[700]! : Colors.red[700]!;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)),
      child: InkWell(
        onTap: () => _showFullDetails(d),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: widget.setCompactLayout ? 8 : 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CommonWidgets.txt(d.factorName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: widget.setCompactLayout ? 14 : 15, color: Colors.indigo[900]), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                    const SizedBox(height: 2),
                    Text(d.indexName, style: TextStyle(color: Colors.grey[600], fontSize: widget.setCompactLayout ? 11 : 12)),
                    if (d.pe != null || d.dy != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          '${d.pe != null ? "P/E: ${d.pe!.toStringAsFixed(1)}" : ""} ${d.dy != null ? "| Yield: ${d.dy!.toStringAsFixed(1)}%" : ""}',
                          style: TextStyle(color: Colors.blueGrey[600], fontSize: 10),
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${returnValue >= 0 ? '+' : ''}${returnValue.toStringAsFixed(2)}%',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: widget.setCompactLayout ? 13 : 14),
                  ),
                  Text(
                    _selectedPeriod,
                    style: TextStyle(color: color.withOpacity(0.8), fontSize: widget.setCompactLayout ? 10 : 11, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
