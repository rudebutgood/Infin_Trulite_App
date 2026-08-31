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
  final TextEditingController _searchCtl = TextEditingController();
  List<MarketNews> _news = [];
  String _searchQuery = "";
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
    _searchCtl.addListener(() {
      setState(() => _searchQuery = _searchCtl.text);
    });
  }

  @override
  void dispose() {
    _scrollCtl.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  List<MarketNews> get _filteredNews {
    if (_searchQuery.isEmpty) return _news;
    final query = _searchQuery.toLowerCase();
    return _news.where((n) =>
      n.title.toLowerCase().contains(query) ||
      n.description.toLowerCase().contains(query) ||
      n.source.toLowerCase().contains(query)
    ).toList();
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

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredNews;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? theme.scaffoldBackgroundColor : Colors.grey[50],
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, size: 20),
            const SizedBox(width: 8),
            Expanded(child: CommonWidgets.txt('Market Insights', style: const TextStyle(fontWeight: FontWeight.bold), selectedLanguage: widget.selectedLanguage, translate: widget.translate)),
          ],
        ),
        backgroundColor: isDark ? Colors.grey[900] : Colors.indigo[900],
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
          _buildSearchBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? _buildNoResults()
                    : Scrollbar(
                        controller: _scrollCtl,
                        interactive: true,
                        thickness: 6,
                        radius: const Radius.circular(3),
                        child: ListView.separated(
                          controller: _scrollCtl,
                          itemCount: filtered.length + (_hasMore ? 1 : 0),
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            if (index == filtered.length) {
                              return _buildLoadMoreIndicator();
                            }
                            final item = filtered[index];
                            return _ExpandableNewsCard(
                              news: item,
                              selectedLanguage: widget.selectedLanguage,
                              translate: widget.translate,
                              setCompactLayout: widget.setCompactLayout,
                              onTap: () => _showNewsPopup(item),
                              onBookmarkToggle: () async {
                                await _service.toggleSave(item);
                                setState(() {
                                  final mainIdx = _news.indexWhere((n) => n.link == item.link);
                                  if (mainIdx != -1) {
                                    _news[mainIdx] = _news[mainIdx].copyWith(isSaved: !_news[mainIdx].isSaved);
                                    if (_selectedHours == -1 && !_news[mainIdx].isSaved) {
                                      _news.removeAt(mainIdx);
                                    }
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 64, color: isDark ? Colors.grey[700] : Colors.grey[300]),
            const SizedBox(height: 16),
            CommonWidgets.txt(_searchQuery.isEmpty ? 'No news available' : 'No matches found for "$_searchQuery"', 
                style: TextStyle(fontSize: 16, color: isDark ? Colors.white70 : Colors.black54),
                selectedLanguage: widget.selectedLanguage, translate: widget.translate),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadMoreIndicator() {
    return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)));
  }

  Widget _buildSearchBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      color: isDark ? Colors.transparent : Colors.white,
      child: TextField(
        controller: _searchCtl,
        decoration: InputDecoration(
          hintText: 'Search within news...',
          hintStyle: TextStyle(fontSize: 13, color: isDark ? Colors.grey[500] : Colors.grey),
          prefixIcon: Icon(Icons.search, size: 20, color: isDark ? Colors.indigoAccent : Colors.indigo),
          suffixIcon: _searchQuery.isNotEmpty 
            ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => _searchCtl.clear())
            : null,
          filled: true,
          fillColor: isDark ? Colors.grey[900] : Colors.grey[100],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
        style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black87),
      ),
    );
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: isDark ? Colors.transparent : Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CommonWidgets.txt('Top Market Stories', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.indigo[900]), selectedLanguage: widget.selectedLanguage, translate: widget.translate),
                const SizedBox(height: 2),
                Text('India market news curated from top sources.', style: TextStyle(fontSize: 10, color: isDark ? Colors.grey[400] : Colors.grey[600], fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          Container(
            height: 35,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.indigo[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isDark ? Colors.grey[800]! : Colors.indigo[100]!),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedHours,
                dropdownColor: isDark ? Colors.grey[900] : Colors.white,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.indigo[900]),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 0,
      color: isDark ? Colors.grey[900] : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[200]!)),
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
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: widget.setCompactLayout ? 13 : 14, color: isDark ? Colors.white : Colors.indigo[900]),
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
                  style: TextStyle(fontSize: widget.setCompactLayout ? 11 : 12, color: isDark ? Colors.white70 : Colors.black87),
                  maxLines: _isExpanded ? null : 3,
                  overflow: _isExpanded ? false : true,
                  selectedLanguage: widget.selectedLanguage, translate: widget.translate),
              ),

              const SizedBox(height: 8),
              Row(
                children: [
                  Text(d.source, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isDark ? Colors.indigoAccent[100] : Colors.indigo[300])),
                  const SizedBox(width: 8),
                  Text(d.pubDate, style: TextStyle(fontSize: 10, color: isDark ? Colors.grey[500] : Colors.grey[400])),
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
