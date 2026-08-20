import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/market_news.dart';
import '../services/market_news_service.dart';
import '../widgets/common_widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  final ScrollController _scrollCtl = ScrollController();
  List<MarketNews> _news = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _currentPage = 0;
  bool _hasMore = true;
  int _selectedHours = 24;

  final List<Map<String, dynamic>> _filters = [
    {'label': 'Last 1 hr', 'value': 1},
    {'label': 'Last 6 hrs', 'value': 6},
    {'label': 'Last 24 hrs', 'value': 24},
    {'label': 'Last 2 days', 'value': 48},
    {'label': 'Last 7 days', 'value': 168},
  ];

  @override
  void initState() {
    super.initState();
    _fetch();
    _scrollCtl.addListener(() {
      if (_scrollCtl.position.pixels >= _scrollCtl.position.maxScrollExtent - 200) {
        if (!_loading && !_loadingMore && _hasMore) {
          _fetchMore();
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollCtl.dispose();
    super.dispose();
  }

  Future<void> _fetch({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _loading = true);
    _currentPage = 0;
    _hasMore = true;
    try {
      final res = await _service.fetchNews(hours: _selectedHours, limit: 10, offset: 0);
      if (mounted) {
        setState(() {
          _news = res;
          if (res.length < 10) _hasMore = false;
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

  Future<void> _fetchMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    _currentPage++;
    try {
      final res = await _service.fetchNews(hours: _selectedHours, limit: 10, offset: _currentPage * 10);
      if (mounted) {
        setState(() {
          if (res.isEmpty) {
            _hasMore = false;
          } else {
            _news.addAll(res);
            if (res.length < 10) _hasMore = false;
          }
        });
      }
    } catch (e) {
      debugPrint('Load more error: $e');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _showNewsPopup(String url, String title) {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent("Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36")
      ..loadRequest(Uri.parse(url));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setPopupState) {
          bool loading = true;
          controller.setNavigationDelegate(NavigationDelegate(
            onPageStarted: (_) => setPopupState(() => loading = true),
            onPageFinished: (_) => setPopupState(() => loading = false),
          ));

          return Container(
            height: MediaQuery.of(ctx).size.height * 0.9,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.indigo[900],
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.open_in_new, color: Colors.white, size: 20),
                            onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                            tooltip: 'Open in Browser',
                          ),
                          IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (loading) const LinearProgressIndicator(minHeight: 2),
                Expanded(child: WebViewWidget(controller: controller)),
              ],
            ),
          );
        }
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    // Legacy fallback if needed, but we use _showNewsPopup now
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.inAppWebView);
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
                        controller: _scrollCtl,
                        itemCount: _news.length + (_hasMore ? 1 : 0),
                        padding: const EdgeInsets.all(12),
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          if (index == _news.length) {
                            return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)));
                          }
                          return _buildNewsCard(_news[index]);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CommonWidgets.txt('Top Market Stories', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo[900]), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                const SizedBox(height: 2),
                Text('India market news summarized by AI.', style: TextStyle(fontSize: 10, color: Colors.grey[600], fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          Container(
            height: 35,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.indigo[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.indigo[100]!),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedHours,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo[900]),
                items: _filters.map((f) => DropdownMenuItem<int>(
                  value: f['value'],
                  child: Text(f['label']),
                )).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _selectedHours = v);
                    _fetch();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewsCard(MarketNews d) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)),
      child: InkWell(
        onTap: () => _showNewsPopup(d.link, d.title),
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
                  const SizedBox(width: 4),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => launchUrl(Uri.parse(d.link), mode: LaunchMode.externalApplication),
                      borderRadius: BorderRadius.circular(20),
                      child: const Padding(
                        padding: EdgeInsets.all(4.0),
                        child: Icon(Icons.open_in_new, size: 16, color: Colors.grey),
                      ),
                    ),
                  ),
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
