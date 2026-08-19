import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/market_news.dart';
import '../services/market_news_service.dart';
import '../widgets/common_widgets.dart';

class MarketNewsPage extends StatefulWidget {
  final String selectedLanguage;
  final Future<String> Function(String) translate;
  final bool setCompactLayout;

  const MarketNewsPage({
    super.key,
    required this.selectedLanguage,
    required this.translate,
    required this.setCompactLayout,
  });

  @override
  State<MarketNewsPage> createState() => _MarketNewsPageState();
}

class _MarketNewsPageState extends State<MarketNewsPage> {
  final MarketNewsService _service = MarketNewsService();
  List<MarketNews> _news = [];
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
      final res = await _service.fetchTop10News();
      if (mounted) {
        setState(() {
          _news = res;
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

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: CommonWidgets.txt('AI Market Insights', style: const TextStyle(fontWeight: FontWeight.bold), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
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
                : _news.isEmpty
                    ? Center(child: CommonWidgets.txt('No news available', selectedLanguage: widget.selectedLanguage, translate: widget.translate))
                    : ListView.separated(
                        itemCount: _news.length,
                        padding: const EdgeInsets.all(12),
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => _buildNewsCard(_news[index]),
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
          CommonWidgets.txt('Top 10 Market Stories', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo[900]), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
          const SizedBox(height: 4),
          Text('India market news from the last hour. Summarized by AI.', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildNewsCard(MarketNews d) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)),
      child: InkWell(
        onTap: () => _launchUrl(d.link),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(widget.setCompactLayout ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: CommonWidgets.txt(d.title, 
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: widget.setCompactLayout ? 13 : 14, color: Colors.indigo[900]),
                      selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.open_in_new, size: 14, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 8),
              CommonWidgets.txt(d.description, 
                style: TextStyle(fontSize: widget.setCompactLayout ? 11 : 12, color: Colors.black87),
                selectedLanguage: widget.selectedLanguage, translate: widget.translate),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(d.source, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo[300])),
                  Text(d.pubDate, style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
