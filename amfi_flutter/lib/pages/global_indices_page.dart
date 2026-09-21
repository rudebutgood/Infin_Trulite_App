import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/global_index_service.dart';
import '../widgets/common_widgets.dart';

class GlobalIndicesPage extends StatefulWidget {
  final String selectedLanguage;
  final Future<String> Function(String) translate;
  final bool setCompactLayout;

  const GlobalIndicesPage({
    super.key,
    required this.selectedLanguage,
    required this.translate,
    required this.setCompactLayout,
  });

  @override
  State<GlobalIndicesPage> createState() => _GlobalIndicesPageState();
}

class _GlobalIndicesPageState extends State<GlobalIndicesPage> {
  final GlobalIndexService _service = GlobalIndexService();
  final TextEditingController _searchCtl = TextEditingController();
  final ScrollController _scrollCtl = ScrollController();

  List<GlobalIndexData> _all = [];
  List<GlobalIndexData> _visible = [];
  bool _loading = true;
  String _selectedCountry = 'All';
  String _sortBy = 'Change %';
  bool _isAscending = false;

  final List<String> _countries = [
    'All',
    'USA',
    'UK',
    'Japan',
    'China',
    'Taiwan',
    'Hongkong',
    'South Korea',
    'Germany',
    'France',
    'Australia',
    'Brazil',
    'South Africa',
    'Canada',
    'Russia',
    'Europe',
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
      final data = await _service.fetchGlobalIndices();
      if (mounted) {
        setState(() {
          _all = data;
          _sort();
        });
      }
    } catch (e) {
      debugPrint('Global indices page fetch error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _sort() {
    final query = _searchCtl.text.trim().toLowerCase();
    final filtered = _all.where((d) {
      final countryMatch = _selectedCountry == 'All' || d.country == _selectedCountry;
      final searchMatch = query.isEmpty || d.name.toLowerCase().contains(query) || d.country.toLowerCase().contains(query);
      return countryMatch && searchMatch;
    }).toList();

    filtered.sort((a, b) {
      int cmp;
      switch (_sortBy) {
        case 'Name':
          cmp = a.name.compareTo(b.name);
          break;
        case 'Last':
          cmp = a.last.compareTo(b.last);
          break;
        default:
          cmp = a.percentChange.compareTo(b.percentChange);
      }
      return _isAscending ? cmp : -cmp;
    });

    setState(() => _visible = filtered);
  }

  Widget _buildHeaderBox(String label, double value, {bool asPercent = false}) {
    final color = value >= 0 ? Colors.green : Colors.red;
    final formatted = asPercent
        ? '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}%'
        : value.toStringAsFixed(2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: asPercent ? color.withOpacity(0.08) : Colors.indigo.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(
            formatted,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: asPercent ? color : Colors.indigo),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Global Indices'),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetch),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            color: Colors.white,
            child: Column(
              children: [
                SizedBox(
                  height: 44,
                  child: TextField(
                    controller: _searchCtl,
                    onChanged: (_) => _sort(),
                    decoration: InputDecoration(
                      hintText: 'Search indices...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _searchCtl.text.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                _searchCtl.clear();
                                _sort();
                              },
                              icon: const Icon(Icons.close, size: 18),
                              padding: EdgeInsets.zero,
                            )
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _countries.length,
                    itemBuilder: (context, index) {
                      final item = _countries[index];
                      final selected = item == _selectedCountry;
                      return GestureDetector(
                        onTap: () {
                          _selectedCountry = item;
                          _sort();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: selected ? Colors.indigo[900] : Colors.grey[200],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            item,
                            style: TextStyle(
                              color: selected ? Colors.white : Colors.black87,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Sort:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _sortBy,
                            isExpanded: true,
                            style: const TextStyle(color: Colors.black, fontSize: 13),
                            items: const [
                              DropdownMenuItem(value: 'Change %', child: Text('Change %', style: TextStyle(fontSize: 11))),
                              DropdownMenuItem(value: 'Name', child: Text('Name', style: TextStyle(fontSize: 11))),
                              DropdownMenuItem(value: 'Last', child: Text('Last', style: TextStyle(fontSize: 11))),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                _sortBy = v;
                                _sort();
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {
                        _isAscending = !_isAscending;
                        _sort();
                      },
                      icon: Icon(_isAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 20, color: Colors.indigo[700]),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _visible.isEmpty
                    ? const Center(child: Text('No global indices available'))
                    : Scrollbar(
                        controller: _scrollCtl,
                        child: ListView.builder(
                          controller: _scrollCtl,
                          itemCount: _visible.length,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                          itemBuilder: (context, index) {
                            final item = _visible[index];
                            final deltaColor = item.percentChange >= 0 ? Colors.green : Colors.red;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)),
                              child: InkWell(
                                onTap: () {
                                  showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (ctx) {
                                      return DraggableScrollableSheet(
                                        initialChildSize: 0.8,
                                        minChildSize: 0.6,
                                        maxChildSize: 0.9,
                                        expand: false,
                                        builder: (sheetCtx, scrollCtrl) {
                                          return Container(
                                            decoration: BoxDecoration(
                                              color: Theme.of(sheetCtx).scaffoldBackgroundColor,
                                              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                                            ),
                                            child: SafeArea(
                                              top: false,
                                              child: Column(
                                                children: [
                                                  Container(
                                                    width: 48,
                                                    height: 5,
                                                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                                                    decoration: BoxDecoration(
                                                      color: Colors.grey[400],
                                                      borderRadius: BorderRadius.circular(10),
                                                    ),
                                                  ),
                                                  Padding(
                                                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                                                    child: Row(
                                                      children: [
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              Text(item.fullName.isNotEmpty ? item.fullName : item.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                                              const SizedBox(height: 4),
                                                              Text('${item.country} • ${item.exchangeName}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                                            ],
                                                          ),
                                                        ),
                                                        IconButton(
                                                          icon: const Icon(Icons.close),
                                                          onPressed: () => Navigator.pop(sheetCtx),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const Divider(height: 1),
                                                  Expanded(
                                                    child: Scrollbar(
                                                      controller: scrollCtrl,
                                                      thumbVisibility: true,
                                                      child: ListView(
                                                        controller: scrollCtrl,
                                                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
                                                        children: [
                                                          Row(
                                                            children: [
                                                              Expanded(
                                                                child: _buildHeaderBox('Change %', item.percentChange, asPercent: true),
                                                              ),
                                                              const SizedBox(width: 10),
                                                              Expanded(
                                                                child: _buildHeaderBox('Last', item.last),
                                                              ),
                                                            ],
                                                          ),
                                                          const SizedBox(height: 12),
                                                          GlobalIndexHistorySection(
                                                            index: item,
                                                            selectedLanguage: widget.selectedLanguage,
                                                            translate: widget.translate,
                                                          ),
                                                          const SizedBox(height: 16),
                                                          _detailRow('Name', item.fullName.isNotEmpty ? item.fullName : item.name),
                                                          _detailRow('Short Name', item.name),
                                                          _detailRow('Country', item.country),
                                                          _detailRow('Symbol', item.symbol),
                                                          _detailRow('Exchange', item.exchangeName),
                                                          _detailRow('Currency', item.currency),
                                                          _detailRow('Last Value', item.last.toStringAsFixed(2)),
                                                          _detailRow('Previous Close', item.previousClose.toStringAsFixed(2)),
                                                          _detailRow('Open', item.open.toStringAsFixed(2)),
                                                          _detailRow('Day High', item.dayHigh.toStringAsFixed(2)),
                                                          _detailRow('Day Low', item.dayLow.toStringAsFixed(2)),
                                                          _detailRow('52W High', item.fiftyTwoWeekHigh.toStringAsFixed(2)),
                                                          _detailRow('52W Low', item.fiftyTwoWeekLow.toStringAsFixed(2)),
                                                          _detailRow('Volume', item.volume.toString()),
                                                          _detailRow('Change %', '${item.percentChange >= 0 ? '+' : ''}${item.percentChange.toStringAsFixed(2)}%'),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(item.fullName.isNotEmpty ? item.fullName : item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.indigo)),
                                            const SizedBox(height: 2),
                                            Text(item.country, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            item.last.toStringAsFixed(2),
                                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${item.percentChange >= 0 ? '+' : ''}${item.percentChange.toStringAsFixed(2)}%',
                                            style: TextStyle(color: deltaColor, fontWeight: FontWeight.bold, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class GlobalIndexHistorySection extends StatefulWidget {
  final GlobalIndexData index;
  final String selectedLanguage;
  final Future<String> Function(String) translate;

  const GlobalIndexHistorySection({
   super.key,
   required this.index,
   required this.selectedLanguage,
   required this.translate,
  });

  @override
  State<GlobalIndexHistorySection> createState() => _GlobalIndexHistorySectionState();
}

class _GlobalIndexHistorySectionState extends State<GlobalIndexHistorySection> {
  final GlobalIndexService _service = GlobalIndexService();
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  String? _error;
  Map<String, double> _returns = {};
  String _selectedPeriod = '1Y';

  @override
  void initState() {
   super.initState();
   _load();
  }

  Future<void> _load() async {
   if (!mounted) return;
   setState(() {
     _loading = true;
     _error = null;
   });
   try {
     final data = await _service.fetchGlobalHistory(widget.index.symbol);
     if (mounted) {
       setState(() {
         _history = data;
         _returns = _calculateReturns(data);
         _loading = false;
         if (data.isEmpty) {
           _error = 'No historical data found';
         }
       });
     }
   } catch (e) {
     if (mounted) {
       setState(() {
         _error = 'Failed to load history';
         _loading = false;
       });
     }
   }
  }

  Map<String, double> _calculateReturns(List<Map<String, dynamic>> data) {
   if (data.length < 2) return {};
   final latest = (data.last['value'] as num).toDouble();
   final latestDate = DateTime.fromMillisecondsSinceEpoch(data.last['timestamp'] as int);

   double getRet(int days) {
     final target = latestDate.subtract(Duration(days: days));
     Map<String, dynamic>? point;
     for (var i = data.length - 1; i >= 0; i--) {
       final d = DateTime.fromMillisecondsSinceEpoch(data[i]['timestamp'] as int);
       if (d.isBefore(target) || d.isAtSameMomentAs(target)) {
         point = data[i];
         break;
       }
     }
     point ??= data.first;
     final oldVal = (point['value'] as num).toDouble();
     return oldVal > 0 ? ((latest / oldVal) - 1) * 100 : 0;
   }

   return {
     '1W': getRet(7),
     '1M': getRet(30),
     '3M': getRet(90),
     '6M': getRet(182),
     '1Y': getRet(365),
     '3Y': getRet(365 * 3),
     '5Y': getRet(365 * 5),
   };
  }

  List<Map<String, dynamic>> _getFilteredHistory(List<Map<String, dynamic>> data) {
   if (data.isEmpty) return [];
   int days = 365 * 5;
   if (_selectedPeriod == '1W') days = 7;
   else if (_selectedPeriod == '1M') days = 30;
   else if (_selectedPeriod == '3M') days = 90;
   else if (_selectedPeriod == '6M') days = 182;
   else if (_selectedPeriod == '1Y') days = 365;
   else if (_selectedPeriod == '3Y') days = 365 * 3;

   final latestTs = data.last['timestamp'] as int;
   final latestDate = DateTime.fromMillisecondsSinceEpoch(latestTs);
   final target = latestDate.subtract(Duration(days: days));
   return data.where((p) {
     final d = DateTime.fromMillisecondsSinceEpoch(p['timestamp'] as int);
     return d.isAfter(target) || d.isAtSameMomentAs(target);
   }).toList();
  }

  @override
  Widget build(BuildContext context) {
   if (_loading) {
     return const SizedBox(height: 150, child: Center(child: CircularProgressIndicator()));
   }
   if (_error != null) {
     return Container(
       height: 120,
       width: double.infinity,
       padding: const EdgeInsets.all(12),
       decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(12)),
       child: Center(
         child: Text(_error!, style: TextStyle(fontSize: 11, color: Colors.red[900])),
       ),
     );
   }
   if (_history.isEmpty) return const SizedBox();

   final filtered = _getFilteredHistory(_history);
   return Column(
     crossAxisAlignment: CrossAxisAlignment.start,
     children: [
       const Text('Historical Trend', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo)),
       const SizedBox(height: 12),
       SizedBox(
         height: 180,
         child: _buildChart(filtered),
       ),
       const SizedBox(height: 20),
       _buildReturnMatrix(),
     ],
   );
  }

  Widget _buildChart(List<Map<String, dynamic>> data) {
   if (data.length < 2) {
     return const Center(child: Text('Not enough data for this period', style: TextStyle(fontSize: 12, color: Colors.grey)));
   }

   final baseVal = (data.first['value'] as num).toDouble();
   double minValue = double.infinity;
   double maxValue = double.negativeInfinity;

   for (var p in data) {
     final v = (p['value'] as num).toDouble();
     final rebased = baseVal > 0 ? (v / baseVal * 100) : 100.0;
     if (rebased < minValue) minValue = rebased;
     if (rebased > maxValue) maxValue = rebased;
   }

   final padding = (maxValue - minValue) * 0.15;
   final minY = (minValue - padding).floorToDouble();
   final maxY = (maxValue + padding).ceilToDouble();

   return LineChart(
     LineChartData(
       gridData: const FlGridData(show: false),
       titlesData: const FlTitlesData(show: false),
       borderData: FlBorderData(show: false),
       minY: minY,
       maxY: maxY,
       lineTouchData: LineTouchData(
         touchTooltipData: LineTouchTooltipData(
           getTooltipItems: (spots) {
             return spots.map((spot) {
               final item = data[spot.x.toInt()];
               final date = DateTime.fromMillisecondsSinceEpoch(item['timestamp'] as int);
               final returnPct = spot.y - 100;
               return LineTooltipItem(
                 '${DateFormat('dd MMM yyyy').format(date)}\nValue: ${(item['value'] as num).toStringAsFixed(2)} (${returnPct >= 0 ? '+' : ''}${returnPct.toStringAsFixed(1)}%)',
                 const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
               );
             }).toList();
           },
         ),
       ),
       lineBarsData: [
         LineChartBarData(
           spots: List.generate(data.length, (i) {
             final v = (data[i]['value'] as num).toDouble();
             return FlSpot(i.toDouble(), baseVal > 0 ? (v / baseVal * 100) : 100);
           }),
           isCurved: true,
           color: Colors.indigo[700],
           barWidth: 1.5,
           dotData: const FlDotData(show: false),
           belowBarData: BarAreaData(
             show: true,
             gradient: LinearGradient(
               colors: [Colors.indigo.withOpacity(0.3), Colors.indigo.withOpacity(0.0)],
               begin: Alignment.topCenter,
               end: Alignment.bottomCenter,
             ),
           ),
         ),
       ],
     ),
   );
  }

  Widget _buildReturnMatrix() {
   final periods = ['1W', '1M', '3M', '6M', '1Y', '3Y', '5Y'];
   return Container(
     padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
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
         return Flexible(
           child: InkWell(
             onTap: () => setState(() => _selectedPeriod = pKey),
             borderRadius: BorderRadius.circular(8),
             child: Container(
               padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
               decoration: BoxDecoration(
                 color: isSelected ? Colors.indigo[50] : Colors.transparent,
                 borderRadius: BorderRadius.circular(8),
               ),
               child: Column(
                 mainAxisSize: MainAxisSize.min,
                 children: [
                   Text(pKey, style: TextStyle(fontSize: 9, color: isSelected ? Colors.indigo : Colors.grey, fontWeight: FontWeight.bold)),
                   const SizedBox(height: 6),
                   FittedBox(
                     fit: BoxFit.scaleDown,
                     child: Text(
                       retVal != null ? '${isPos ? '+' : ''}${retVal.toStringAsFixed(1)}%' : '-',
                       style: TextStyle(
                         fontSize: 12,
                         fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                         color: retVal != null ? (isPos ? Colors.green[700] : Colors.red[700]) : Colors.grey[400],
                       ),
                     ),
                   ),
                 ],
               ),
             ),
           ),
         );
       }).toList(),
     ),
   );
  }
}
