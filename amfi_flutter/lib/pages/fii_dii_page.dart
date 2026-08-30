import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/fii_dii_data.dart';
import '../services/fii_dii_service.dart';
import '../widgets/common_widgets.dart';

class FiiDiiPage extends StatefulWidget {
  final String selectedLanguage;
  final Future<String> Function(String) translate;
  final bool setCompactLayout;

  const FiiDiiPage({
    super.key,
    required this.selectedLanguage,
    required this.translate,
    required this.setCompactLayout,
  });

  @override
  State<FiiDiiPage> createState() => _FiiDiiPageState();
}

class _FiiDiiPageState extends State<FiiDiiPage> {
  final FiiDiiService _service = FiiDiiService();
  final ScrollController _scrollCtl = ScrollController();
  List<FiiDiiData> _data = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _scrollCtl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final res = await _service.fetchFiiDiiData();
      if (mounted) {
        setState(() {
          // Sort to show FII first, then DII
          res.sort((a, b) {
            if (a.category.contains('FII') && b.category.contains('DII')) return -1;
            if (a.category.contains('DII') && b.category.contains('FII')) return 1;
            return 0;
          });
          _data = res;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
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
            const Icon(Icons.swap_horizontal_circle, size: 20),
            const SizedBox(width: 8),
            Expanded(child: CommonWidgets.txt('FII / DII Activity', style: const TextStyle(fontWeight: FontWeight.bold), selectedLanguage: widget.selectedLanguage, translate: widget.translate)),
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
          _buildHeader(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _data.isEmpty
                    ? const Center(child: Text('No data available'))
                    : Scrollbar(
                        controller: _scrollCtl,
                        interactive: true,
                        thickness: 6,
                        radius: const Radius.circular(3),
                        child: ListView.separated(
                          controller: _scrollCtl,
                          itemCount: _data.length,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) => _buildRow(_data[index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommonWidgets.txt('Institutional Trading Activity', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo[900]), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
          const SizedBox(height: 4),
          Text('Values in Crores (₹). Data sourced from NSE India.', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildRow(FiiDiiData d) {
    final isNetPositive = d.netValue >= 0;
    final color = isNetPositive ? Colors.green[700] : Colors.red[700];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)),
      child: Padding(
        padding: EdgeInsets.all(widget.setCompactLayout ? 12 : 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CommonWidgets.txt(d.category, style: TextStyle(fontWeight: FontWeight.bold, fontSize: widget.setCompactLayout ? 14 : 15, color: Colors.indigo[900]), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                  const SizedBox(height: 2),
                  Text(d.date, style: TextStyle(color: Colors.grey[600], fontSize: widget.setCompactLayout ? 11 : 12)),
                  SizedBox(height: widget.setCompactLayout ? 4 : 8),
                  Row(
                    children: [
                      _miniInfo('Buy', d.buyValue),
                      const SizedBox(width: 16),
                      _miniInfo('Sell', d.sellValue),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isNetPositive ? '+' : ''}${d.netValue.toInt()}',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: widget.setCompactLayout ? 16 : 18),
                ),
                CommonWidgets.txt('Net Value', style: TextStyle(color: Colors.grey[600], fontSize: widget.setCompactLayout ? 9 : 10), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniInfo(String label, double val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommonWidgets.txt(label, style: TextStyle(fontSize: widget.setCompactLayout ? 9 : 10, color: Colors.grey), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
        Text('₹${val.toInt()}', style: TextStyle(fontSize: widget.setCompactLayout ? 11 : 12, fontWeight: FontWeight.w600, color: Colors.black87)),
      ],
    );
  }
}
