import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../widgets/common_widgets.dart';
import '../services/portfolio_service.dart';

class PortfolioChartsPage extends StatefulWidget {
  final List<Map<String, dynamic>> portfolioRows;
  final Set<int>? selectedImportIds;
  final String selectedLanguage;
  final Future<String> Function(String) translate;

  const PortfolioChartsPage({
    super.key,
    required this.portfolioRows,
    this.selectedImportIds,
    required this.selectedLanguage,
    required this.translate,
  });

  @override
  State<PortfolioChartsPage> createState() => _PortfolioChartsPageState();
}

class _PortfolioChartsPageState extends State<PortfolioChartsPage> {
  int _touchedIndex = -1;
  bool _loading = true;

  List<MapEntry<String, double>> _amcData = [];
  List<MapEntry<String, double>> _investorData = [];
  List<MapEntry<String, double>> _typeData = [];
  List<MapEntry<String, double>> _categoryData = [];
  List<MapEntry<String, double>> _schemeData = [];
  List<MapEntry<String, double>> _profitableData = [];
  List<MapEntry<String, double>> _historyData = [];
  Map<String, List<Map<String, dynamic>>> _segmentFunds = {};
  double _totalValue = 0;

  @override
  void initState() {
    super.initState();
    _processData();
  }

  Future<void> _processData() async {
    setState(() => _loading = true);
    try {
      final amcMap = <String, double>{};
      final invMap = <String, double>{};
      final typeMap = <String, double>{};
      final catMap = <String, double>{};
      final schemeMap = <String, double>{};
      final segmentFundsMap = <String, List<Map<String, dynamic>>>{};
      double totalVal = 0;

      for (var r in widget.portfolioRows) {
        final units = (r['total_units'] as num? ?? 0).toDouble();
        final latestNav = (r['latest_nav'] as num? ?? 0).toDouble();
        final val = units * latestNav;
        if (val <= 0) continue;
        totalVal += val;

        final amc = r['mf_name'] ?? 'Others';
        amcMap[amc] = (amcMap[amc] ?? 0) + val;
        segmentFundsMap.putIfAbsent('AMC:$amc', () => []).add({'name': r['fund_name'], 'value': val});

        final inv = r['investor_name'] ?? 'Others';
        invMap[inv] = (invMap[inv] ?? 0) + val;
        segmentFundsMap.putIfAbsent('INV:$inv', () => []).add({'name': r['fund_name'], 'value': val});

        final cat = r['category_name'] ?? 'Others';
        catMap[cat] = (catMap[cat] ?? 0) + val;
        segmentFundsMap.putIfAbsent('CAT:$cat', () => []).add({'name': r['fund_name'], 'value': val});

        final scheme = r['fund_name'] ?? 'Unknown';
        schemeMap[scheme] = (schemeMap[scheme] ?? 0) + val;
        segmentFundsMap.putIfAbsent('FUND:$scheme', () => []).add({'name': r['fund_name'], 'value': val});

        final type = (scheme.toUpperCase().contains('DIRECT')) ? 'Direct' : 'Regular';
        typeMap[type] = (typeMap[type] ?? 0) + val;
        segmentFundsMap.putIfAbsent('TYPE:$type', () => []).add({'name': r['fund_name'], 'value': val});
      }

      final amcData = amcMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final invData = invMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final catData = catMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final typeData = typeMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final schemeData = schemeMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

      final profitMap = <String, double>{};
      for (var r in widget.portfolioRows) {
        final units = (r['total_units'] as num? ?? 0).toDouble();
        final latestNav = (r['latest_nav'] as num? ?? 0).toDouble();
        final invested = (r['invested_value'] as num? ?? 0).toDouble();
        final profit = (units * latestNav) - invested;
        if (profit > 0) {
          profitMap[r['fund_name'] ?? 'Unknown'] = profit;
        }
      }
      final profitableData = profitMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

      final portfolioService = PortfolioService();
      final historyData = await portfolioService.getHistoricalValue(importIds: widget.selectedImportIds?.toList());

      if (mounted) {
        setState(() {
          _amcData = amcData;
          _investorData = invData;
          _typeData = typeData;
          _categoryData = catData;
          _schemeData = schemeData;
          _profitableData = profitableData;
          _historyData = historyData;
          _segmentFunds = segmentFundsMap;
          _totalValue = totalVal;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error processing analytics: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        title: CommonWidgets.txt('Portfolio Analytics', selectedLanguage: widget.selectedLanguage, translate: widget.translate),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
      ),
      body: Scrollbar(
        child: ListView(
          padding: const EdgeInsets.all(20.0),
          children: [
            if (_historyData.isNotEmpty) ...[
              CommonWidgets.txt('Portfolio Value Growth', 
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo), 
                  selectedLanguage: widget.selectedLanguage, translate: widget.translate),
              const SizedBox(height: 8),
              const Text('Trend of your total holdings value over time', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 24),
              _growthChartSection(_historyData),
              const Divider(height: 60),
            ],

            _chartSection('Scheme Allocation', _schemeData, 'FUND'),
            const Divider(height: 60),
            _chartSection('Asset Allocation (AMC)', _amcData, 'AMC'),
            const Divider(height: 60),
            _chartSection('Family Distribution', _investorData, 'INV'),
            const Divider(height: 60),
            _chartSection('Category Mix', _categoryData, 'CAT'),
            const Divider(height: 60),
            _chartSection('Scheme Type', _typeData, 'TYPE'),

            const Divider(height: 60),

            CommonWidgets.txt('Top Gainers', 
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo), 
                selectedLanguage: widget.selectedLanguage, translate: widget.translate),
            const Text('Funds with highest absolute profit in your portfolio', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            _profitabilitySection(_profitableData),
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
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  return LineTooltipItem(
                    '${data[spot.x.toInt()].key}\n\u20b9${CommonWidgets.formatCurrency(spot.y)}',
                    const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  );
                }).toList();
              },
            ),
          ),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
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
                        if (parts.length >= 3) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text('${parts[2]}/${parts[1]}', style: const TextStyle(fontSize: 10)),
                          );
                        }
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

  Widget _chartSection(String title, List<MapEntry<String, double>> data, String prefix) {
    final topItems = data.take(5).toList();
    final othersValue = data.length > 5 ? data.skip(5).fold(0.0, (sum, e) => sum + e.value) : 0.0;

    final List<PieChartSectionData> sections = [];
    final List<Color> colors = [Colors.indigo, Colors.blue, Colors.teal, Colors.orange, Colors.red, Colors.grey];

    for (int i = 0; i < topItems.length; i++) {
      final isTouched = i == _touchedIndex;
      final pct = (_totalValue > 0) ? (topItems[i].value / _totalValue * 100) : 0;
      sections.add(PieChartSectionData(
        value: topItems[i].value,
        title: '${pct.toStringAsFixed(1)}%',
        radius: isTouched ? 75 : 65,
        color: colors[i],
        titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
      ));
    }
    if (othersValue > 0) {
      final pct = (_totalValue > 0) ? (othersValue / _totalValue * 100) : 0;
      sections.add(PieChartSectionData(
        value: othersValue,
        title: '${pct.toStringAsFixed(1)}%',
        radius: 65,
        color: colors.last,
        titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommonWidgets.txt(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
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
                      _showSegmentDetails(topItems[index].key, prefix, topItems[index].value);
                    } else if (index == topItems.length && othersValue > 0) {
                      _showSegmentDetails('Others', prefix, othersValue);
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
        ...List.generate(topItems.length, (i) => _legendItem(colors[i], topItems[i].key, topItems[i].value, prefix)),
        if (othersValue > 0) _legendItem(colors.last, 'Others', othersValue, prefix),
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
          title: CommonWidgets.txt(e.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), overflow: true, selectedLanguage: widget.selectedLanguage, translate: widget.translate),
          trailing: Text('\u20b9${CommonWidgets.formatCurrency(e.value)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
        ),
      )).toList(),
    );
  }

  void _showSegmentDetails(String name, String prefix, double totalSegVal) {
    final funds = _segmentFunds['$prefix:$name'] ?? [];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: CommonWidgets.txt(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total Segment Value: \u20b9${CommonWidgets.formatCurrency(totalSegVal)}',
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
                        CommonWidgets.txt(f['name'] ?? 'Unknown', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('\u20b9${CommonWidgets.formatCurrency(fVal)}', style: TextStyle(fontSize: 11, color: Colors.grey[700])),
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

  Widget _legendItem(Color color, String name, double value, String prefix) {
    final pct = (_totalValue > 0) ? (value / _totalValue * 100).toStringAsFixed(1) : '0';
    return InkWell(
      onTap: () => _showSegmentDetails(name, prefix, value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8),
        child: Row(
          children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 12),
            Expanded(child: CommonWidgets.txt(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: true, selectedLanguage: widget.selectedLanguage, translate: widget.translate)),
            Text('\u20b9${CommonWidgets.formatCurrency(value)} ($pct%)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[800])),
          ],
        ),
      ),
    );
  }
}
