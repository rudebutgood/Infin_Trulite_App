import 'package:flutter/material.dart';
import '../models/gold_rate_data.dart';
import '../services/gold_rate_service.dart';
import '../widgets/common_widgets.dart';

class BullionPage extends StatefulWidget {
  final String selectedLanguage;
  final Future<String> Function(String) translate;
  final bool setCompactLayout;

  const BullionPage({
    super.key,
    required this.selectedLanguage,
    required this.translate,
    required this.setCompactLayout,
  });

  @override
  State<BullionPage> createState() => _BullionPageState();
}

class _BullionPageState extends State<BullionPage> {
  final GoldRateService _service = GoldRateService();
  List<GoldRateData> _data = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final res = await _service.fetchGoldRates();
      if (mounted) {
        setState(() {
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
        title: CommonWidgets.txt('Bullion Rates', style: const TextStyle(fontWeight: FontWeight.bold), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
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
                    : ListView.separated(
                        itemCount: _data.length,
                        padding: const EdgeInsets.all(12),
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => _buildRow(_data[index]),
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
          CommonWidgets.txt('Real-time Precious Metal Rates', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo[900]), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
          const SizedBox(height: 4),
          Text('Data sourced from DP Gold. BIS rows represent Indian market rates.', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildRow(GoldRateData d) {
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
                  Text(d.symbol, style: TextStyle(fontWeight: FontWeight.bold, fontSize: widget.setCompactLayout ? 14 : 15, color: Colors.indigo[900])),
                  const SizedBox(height: 2),
                  if (d.info.isNotEmpty)
                    Text(d.info, style: TextStyle(color: Colors.grey[600], fontSize: widget.setCompactLayout ? 10 : 11, fontStyle: FontStyle.italic)),
                  SizedBox(height: widget.setCompactLayout ? 4 : 8),
                  Row(
                    children: [
                      _miniInfo('Low', d.low, Colors.red[700]!),
                      const SizedBox(width: 16),
                      _miniInfo('High', d.high, Colors.green[700]!),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatPrice(d.bid),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: widget.setCompactLayout ? 16 : 18, color: Colors.black87),
                ),
                CommonWidgets.txt('Bid Price', style: TextStyle(color: Colors.grey[600], fontSize: widget.setCompactLayout ? 9 : 10), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                const SizedBox(height: 4),
                Text(
                  _formatPrice(d.ask),
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: widget.setCompactLayout ? 12 : 13, color: Colors.indigo[400]),
                ),
                CommonWidgets.txt('Ask Price', style: TextStyle(color: Colors.grey[600], fontSize: widget.setCompactLayout ? 8 : 9), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniInfo(String label, double val, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommonWidgets.txt(label, style: TextStyle(fontSize: widget.setCompactLayout ? 9 : 10, color: Colors.grey), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
        Text(_formatPrice(val), style: TextStyle(fontSize: widget.setCompactLayout ? 11 : 12, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }

  String _formatPrice(double val) {
    if (val == 0) return '-';
    return val > 1000 ? val.toInt().toString() : val.toStringAsFixed(2);
  }
}
