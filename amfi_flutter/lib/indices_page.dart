import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models/factor_performance_data.dart';
import 'models/index_data.dart';
import 'services/index_service.dart';
import 'widgets/common_widgets.dart';

class IndicesPage extends StatefulWidget {
  final String selectedLanguage;
  final Future<String> Function(String) translate;
  final bool setCompactLayout;

  const IndicesPage({
    super.key,
    required this.selectedLanguage,
    required this.translate,
    required this.setCompactLayout,
  });

  @override
  State<IndicesPage> createState() => _IndicesPageState();
}

class _IndicesPageState extends State<IndicesPage> {
  final IndexService _service = IndexService();
  final TextEditingController _searchCtl = TextEditingController();
  final ScrollController _scrollCtl = ScrollController();
  List<IndexData> _data = [];
  List<IndexData> _filteredData = [];
  List<String> _keys = ['All'];
  bool _loading = true;
  String _selectedKey = 'All';
  String _sortBy = 'Change %';
  bool _isAscending = false;

  final List<String> _sortOptions = [
    'Name',
    'Change %',
    '1M Change %',
    '1Y Change %',
    'vs Year High %',
    'PE Ratio',
    'PB Ratio'
  ];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final res = await _service.fetchIndices();
      if (mounted) {
        setState(() {
          _data = res;
          _keys = ['All', ...res.map((e) => e.rawData['key']?.toString() ?? 'Others').toSet().where((k) => k != 'null' && k.isNotEmpty).toList()..sort()];
          _sort();
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

  void _sort() {
    setState(() {
      _data.sort((a, b) {
        if (_sortBy == 'Name') {
          int cmp = a.name.compareTo(b.name);
          return _isAscending ? cmp : -cmp;
        }

        double? valA = _getSortValue(a);
        double? valB = _getSortValue(b);

        // Always keep N/A at the bottom
        if (valA == null && valB == null) return 0;
        if (valA == null) return 1; 
        if (valB == null) return -1;

        int cmp = valA.compareTo(valB);
        return _isAscending ? cmp : -cmp;
      });
      _filter();
    });
  }

  double? _getSortValue(IndexData d) {
    switch (_sortBy) {
      case 'Change %': return d.percentChange;
      case '1M Change %': return d.perChange30d;
      case '1Y Change %': return d.perChange365d;
      case 'vs Year High %': return d.diffFromYearHigh;
      case 'PE Ratio': return d.pe;
      case 'PB Ratio': return d.pb;
      default: return null;
    }
  }

  void _filter() {
    final query = _searchCtl.text.toLowerCase().trim();
    setState(() {
      _filteredData = _data.where((d) {
        final matchesQuery = query.isEmpty || d.name.toLowerCase().contains(query);
        final matchesKey = _selectedKey == 'All' || (d.rawData['key']?.toString() ?? 'Others') == _selectedKey;
        return matchesQuery && matchesKey;
      }).toList();
    });
  }

  void _showFullDetails(IndexData d) {
    final key = FactorPerformanceData.normalize(d.name);
    final factorInfo = FactorPerformanceData.factorMapping[key];
    final String description = factorInfo?['desc'] ?? '';
    
    // Calculate 1W return if possible
    double? weekReturn;
    final oneWeekAgoVal = _toDouble(d.rawData['oneWeekAgoVal']);
    if (oneWeekAgoVal > 0) {
      weekReturn = ((d.last - oneWeekAgoVal) / oneWeekAgoVal * 100);
    }

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
                        Text(d.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        if (d.rawData['key'] != null)
                          Text(d.rawData['key'].toString(), style: TextStyle(fontSize: 11, color: Colors.indigo[300], fontWeight: FontWeight.bold)),
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
                child: ListView(
                  controller: s,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  children: [
                    if (description.isNotEmpty) ...[
                      CommonWidgets.txt('Description', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                      const SizedBox(height: 4),
                      Text(description, style: const TextStyle(fontSize: 13, height: 1.4)),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                    ],
                    
                    CommonWidgets.txt('Returns Matrix', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _returnBoxDetail('1D', d.percentChange),
                        if (weekReturn != null) _returnBoxDetail('1W', weekReturn),
                        if (d.perChange30d != null) _returnBoxDetail('1M', d.perChange30d!),
                        if (d.perChange365d != null) _returnBoxDetail('1Y', d.perChange365d!),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 8),
                    
                    CommonWidgets.txt('Key Statistics', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                    const SizedBox(height: 8),
                    _detailRow('Last Value', '₹${d.last.toStringAsFixed(2)}'),
                    _detailRow('Variation', '${d.variation >= 0 ? '+' : ''}${d.variation.toStringAsFixed(2)} pts'),
                    if (d.pe != null) _detailRow('P/E Ratio', d.pe!.toStringAsFixed(2)),
                    if (d.pb != null) _detailRow('P/B Ratio', d.pb!.toStringAsFixed(2)),
                    if (d.yearHigh != null) _detailRow('52W High', d.yearHigh!.toString()),
                    if (d.yearLow != null) _detailRow('52W Low', d.yearLow!.toString()),
                    if (d.diffFromYearHigh != null) _detailRow('vs 52W High', '${d.diffFromYearHigh!.toStringAsFixed(2)}%'),
                    
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 8),
                    CommonWidgets.txt('Raw Index Data', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                    const SizedBox(height: 8),
                    ...d.rawData.entries.map((e) {
                      final valueStr = e.value?.toString() ?? '-';
                      final isUrl = valueStr.startsWith('http');
                      // Skip internal fields already shown
                      if (['index', 'last', 'variation', 'percentChange', 'key'].contains(e.key)) return const SizedBox.shrink();
                      
                      return _detailRow(
                        _formatKey(e.key),
                        valueStr,
                        isUrl: isUrl,
                        onUrlTap: isUrl ? () => _launchUrl(valueStr) : null,
                      );
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

  double _toDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val.replaceAll(',', '')) ?? 0.0;
    return 0.0;
  }

  Widget _returnBoxDetail(String label, double value) {
    final color = value >= 0 ? Colors.green[700]! : Colors.red[700]!;
    return Container(
      width: 70,
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

  Widget _detailRow(String label, String value, {bool isUrl = false, VoidCallback? onUrlTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey, fontSize: 13))),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: isUrl
                ? InkWell(
                    onTap: onUrlTap,
                    child: Text(value, style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline, fontSize: 13)),
                  )
                : SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
            Expanded(child: CommonWidgets.txt('Market Indices', style: const TextStyle(fontWeight: FontWeight.bold), selectedLanguage: widget.selectedLanguage, translate: widget.translate)),
          ],
        ),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetch),
        ],
      ),
      body: Column(
        children: [
          _buildSearchAndFilters(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredData.isEmpty
                    ? Center(child: CommonWidgets.txt('No data available', selectedLanguage: widget.selectedLanguage, translate: widget.translate))
                    : Scrollbar(
                        controller: _scrollCtl,
                        interactive: true,
                        thickness: 6,
                        radius: const Radius.circular(3),
                        child: ListView.builder(
                          controller: _scrollCtl,
                          itemCount: _filteredData.length,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                          itemBuilder: (context, index) {
                            final d = _filteredData[index];
                            return _buildIndexCard(d);
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
                hintText: 'Search Indices...',
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
                flex: 4,
                child: Row(
                  children: [
                    CommonWidgets.txt('Filter:', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedKey,
                            isExpanded: true,
                            style: const TextStyle(color: Colors.black, fontSize: 13),
                            items: _keys.map((p) => DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)))).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedKey = val;
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
              const SizedBox(width: 8),
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
                            style: const TextStyle(color: Colors.black, fontSize: 13),
                            items: _sortOptions.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)))).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _sortBy = val;
                                  _sort();
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
                          _sort();
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

  Widget _buildIndexCard(IndexData d) {
    double? displayChange;
    String label = '';
    Color? color;

    switch (_sortBy) {
      case '1M Change %':
        displayChange = d.perChange30d;
        label = '1M: ';
        break;
      case '1Y Change %':
        displayChange = d.perChange365d;
        label = '1Y: ';
        break;
      case 'vs Year High %':
        displayChange = d.diffFromYearHigh;
        label = 'vs High: ';
        break;
      case 'PE Ratio':
        displayChange = d.pe;
        label = 'PE: ';
        color = Colors.indigo;
        break;
      case 'PB Ratio':
        displayChange = d.pb;
        label = 'PB: ';
        color = Colors.indigo;
        break;
      default:
        displayChange = d.percentChange;
        label = '';
    }

    if (color == null) {
      color = (displayChange ?? 0) >= 0 ? Colors.green[700] : Colors.red[700];
    }

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
                    CommonWidgets.txt(d.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: widget.setCompactLayout ? 14 : 15, color: Colors.indigo[900]), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                    const SizedBox(height: 2),
                    Text('Last: ₹${d.last.toStringAsFixed(2)}', style: TextStyle(color: Colors.black87, fontSize: widget.setCompactLayout ? 12 : 13)),
                    if (d.yearHigh != null && d.yearLow != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Text('52W H: ${d.yearHigh} | L: ${d.yearLow}', style: TextStyle(color: Colors.grey[600], fontSize: widget.setCompactLayout ? 9 : 10)),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${label.isNotEmpty ? label : ''}${(displayChange ?? 0) >= 0 && !_sortBy.contains('Ratio') ? '+' : ''}${displayChange?.toStringAsFixed(2) ?? 'N/A'}${(_sortBy.contains('%') || _sortBy == 'vs Year High %') ? '%' : ''}',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: widget.setCompactLayout ? 13 : 14),
                  ),
                  Text(
                    '${d.variation >= 0 ? '+' : ''}${d.variation.toStringAsFixed(2)} pts',
                    style: TextStyle(color: color!.withOpacity(0.8), fontSize: widget.setCompactLayout ? 10 : 11, fontWeight: FontWeight.w500),
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
