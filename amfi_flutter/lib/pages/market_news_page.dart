import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
    {'label': 'Saved', 'value': -1},
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
      if (_selectedHours == -1) {
        final res = await _service.fetchSavedNews();
        if (mounted) {
          setState(() {
            _news = res;
            _hasMore = false;
          });
        }
        return;
      }
      final res = await _service.fetchNews(hours: _selectedHours, limit: 20, offset: 0, force: !silent);
      if (mounted) {
        setState(() {
          _news = res;
          if (res.length < 20) _hasMore = false;
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
      final res = await _service.fetchNews(hours: _selectedHours, limit: 20, offset: _currentPage * 20);
      if (mounted) {
        setState(() {
          if (res.isEmpty) {
            _hasMore = false;
          } else {
            _news.addAll(res);
            if (res.length < 20) _hasMore = false;
          }
        });
      }
    } catch (e) {
      debugPrint('Load more error: $e');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _showNewsPopup(MarketNews news) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _NewsWebViewPopup(
        news: news,
        selectedLanguage: widget.selectedLanguage,
        translate: widget.translate,
      ),
    );
  }

  Future<void> _launchInBrowser(String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;
    try {
      final Uri uri = Uri.parse(cleanUrl);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Invalid news link.')),
        );
      }
    }
  }

  Future<void> _launchUrl(String url) async {
    // Legacy fallback
    _launchInBrowser(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, size: 20),
            const SizedBox(width: 8),
            Expanded(child: CommonWidgets.txt('AI Market Insights', style: const TextStyle(fontWeight: FontWeight.bold), selectedLanguage: widget.selectedLanguage, translate: widget.translate)),
          ],
        ),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_selectedHours == -1 ? Icons.bookmark : Icons.bookmark_border),
            onPressed: () {
              setState(() => _selectedHours = _selectedHours == -1 ? 24 : -1);
              _fetch();
            },
            tooltip: 'View Saved Articles',
          ),
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
                          return _ExpandableNewsCard(
                            news: _news[index],
                            selectedLanguage: widget.selectedLanguage,
                            translate: widget.translate,
                            setCompactLayout: widget.setCompactLayout,
                            onTap: () => _showNewsPopup(_news[index]),
                            onBookmarkToggle: () async {
                              await _service.toggleSave(_news[index]);
                              setState(() {
                                _news[index] = _news[index].copyWith(isSaved: !_news[index].isSaved);
                                if (_selectedHours == -1 && !_news[index].isSaved) {
                                  _news.removeAt(index);
                                }
                              });
                            },
                          );
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
}

class _ExpandableNewsCard extends StatefulWidget {
  final MarketNews news;
  final String selectedLanguage;
  final Future<String> Function(String) translate;
  final bool setCompactLayout;
  final VoidCallback onTap;
  final VoidCallback onBookmarkToggle;

  const _ExpandableNewsCard({
    required this.news,
    required this.selectedLanguage,
    required this.translate,
    required this.setCompactLayout,
    required this.onTap,
    required this.onBookmarkToggle,
  });

  @override
  State<_ExpandableNewsCard> createState() => _ExpandableNewsCardState();
}

class _ExpandableNewsCardState extends State<_ExpandableNewsCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.news;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)),
      child: InkWell(
        onTap: widget.onTap,
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
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onBookmarkToggle,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Icon(
                          d.isSaved ? Icons.bookmark : Icons.bookmark_border,
                          size: 20,
                          color: d.isSaved ? Colors.amber[700] : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => setState(() => _isExpanded = !_isExpanded),
                child: CommonWidgets.txt(d.description,
                  style: TextStyle(fontSize: widget.setCompactLayout ? 11 : 12, color: Colors.black87),
                  maxLines: _isExpanded ? null : 3,
                  overflow: _isExpanded ? false : true,
                  selectedLanguage: widget.selectedLanguage, translate: widget.translate),
              ),

              const SizedBox(height: 8),
              Row(
                children: [
                  Text(d.source, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo[300])),
                  const SizedBox(width: 8),
                  Text(d.pubDate, style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                  const Spacer(),
                  if (d.description.length > 50)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => setState(() => _isExpanded = !_isExpanded),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more, 
                            size: 16, color: Colors.grey),
                        ),
                      ),
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

class _NewsWebViewPopup extends StatefulWidget {
  final MarketNews news;
  final String selectedLanguage;
  final Future<String> Function(String) translate;

  const _NewsWebViewPopup({
    required this.news,
    required this.selectedLanguage,
    required this.translate,
  });

  @override
  State<_NewsWebViewPopup> createState() => _NewsWebViewPopupState();
}

class _NewsWebViewPopupState extends State<_NewsWebViewPopup> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _showTranslated = true;

  String _getTranslatedUrl(String originalUrl) {
    if (widget.selectedLanguage == 'English') return originalUrl;
    final code = CommonWidgets.getLangCode(widget.selectedLanguage);
    return 'https://translate.google.com/translate?sl=auto&tl=$code&u=${Uri.encodeComponent(originalUrl)}';
  }

  @override
  void initState() {
    super.initState();
    _showTranslated = widget.selectedLanguage != 'English';
    final initialUrl = _showTranslated ? _getTranslatedUrl(widget.news.link) : widget.news.link;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent("Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36")
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _isLoading = true),
        onPageFinished: (_) => setState(() => _isLoading = false),
        onWebResourceError: (error) => setState(() => _isLoading = false),
      ))
      ..loadRequest(Uri.parse(initialUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.indigo[900],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: CommonWidgets.txt(
                    widget.news.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: true,
                    selectedLanguage: widget.selectedLanguage,
                    translate: widget.translate,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.open_in_new, color: Colors.white, size: 20),
                      onPressed: () async {
                        final uri = Uri.parse(widget.news.link);
                        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                          await launchUrl(uri, mode: LaunchMode.platformDefault);
                        }
                      },
                      tooltip: 'Open in Browser',
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: WebViewWidget(
              controller: _controller,
              gestureRecognizers: {
                Factory<VerticalDragGestureRecognizer>(() => VerticalDragGestureRecognizer()),
                Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
              },
            ),
          ),
        ],
      ),
    );
  }
}
