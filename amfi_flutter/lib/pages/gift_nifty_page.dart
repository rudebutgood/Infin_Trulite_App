import 'package:flutter/material.dart';
import '../models/gift_nifty_data.dart';
import '../services/gift_nifty_service.dart';
import '../widgets/common_widgets.dart';

class GiftNiftyPage extends StatefulWidget {
  final String selectedLanguage;
  final Future<String> Function(String) translate;
  final bool setCompactLayout;

  const GiftNiftyPage({
    super.key,
    required this.selectedLanguage,
    required this.translate,
    required this.setCompactLayout,
  });

  @override
  State<GiftNiftyPage> createState() => _GiftNiftyPageState();
}

class _GiftNiftyPageState extends State<GiftNiftyPage> {
  final GiftNiftyService _service = GiftNiftyService();
  List<GiftNiftyData> _data = [];
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
      final res = await _service.fetchGiftNiftyData();
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
        titleSpacing: 0,
        title: Row(
          children: [
            const Icon(Icons.public, size: 20),
            const SizedBox(width: 8),
            Expanded(child: CommonWidgets.txt('GIFT Nifty Futures', style: const TextStyle(fontWeight: FontWeight.bold), selectedLanguage: widget.selectedLanguage, translate: widget.translate)),
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
          CommonWidgets.txt('Offshore Index Futures', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo[900]), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
          const SizedBox(height: 4),
          Text('Values in USD. Data sourced from NSE International Exchange.', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildRow(GiftNiftyData d) {
    final color = d.dayChange >= 0 ? Colors.green[700] : Colors.red[700];

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
                  CommonWidgets.txt('${d.symbol} Future', style: TextStyle(fontWeight: FontWeight.bold, fontSize: widget.setCompactLayout ? 14 : 15, color: Colors.indigo[900]), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                  const SizedBox(height: 2),
                  Text('Expiry: ${d.expiryDate}', style: TextStyle(color: Colors.grey[600], fontSize: widget.setCompactLayout ? 11 : 12)),
                  const SizedBox(height: 2),
                  Text('Updated: ${d.timestamp}', style: TextStyle(color: Colors.grey[400], fontSize: widget.setCompactLayout ? 9 : 10)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  d.lastPrice.toStringAsFixed(1),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: widget.setCompactLayout ? 16 : 18, color: Colors.black87),
                ),
                Row(
                  children: [
                    Text(
                      '${d.dayChange >= 0 ? '+' : ''}${d.dayChange.toStringAsFixed(1)}',
                      style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: widget.setCompactLayout ? 11 : 12),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '(${d.percentChange >= 0 ? '+' : ''}${d.percentChange.toStringAsFixed(2)}%)',
                      style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: widget.setCompactLayout ? 11 : 12),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
