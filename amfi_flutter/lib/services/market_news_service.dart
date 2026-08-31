import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/io_client.dart';
import 'package:xml/xml.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import '../models/market_news.dart';
import 'nav_repository.dart';

class MarketNewsService {
  // List of high-quality financial RSS feeds
  final List<Map<String, String>> _feeds = [
    {
      'url': 'https://economictimes.indiatimes.com/markets/stocks/rssfeeds/2146842.cms',
      'source': 'Economic Times'
    },
    {
      'url': 'https://news.google.com/rss/search?q=site:moneycontrol.com+India+Market&hl=en-IN&gl=IN&ceid=IN:en',
      'source': 'MoneyControl'
    },
    {
      'url': 'https://news.google.com/rss/search?q=site:financialexpress.com+India+Stock+Market&hl=en-IN&gl=IN&ceid=IN:en',
      'source': 'Financial Express'
    },
    {
      'url': 'https://www.business-standard.com/rss/markets-106.rss',
      'source': 'Business Standard'
    },
    {
      'url': 'https://www.livemint.com/rss/markets',
      'source': 'LiveMint'
    },
    {
      'url': 'https://feeds.feedburner.com/ndtvprofit-latest',
      'source': 'NDTV Profit'
    },
    {
      'url': 'https://news.google.com/rss/search?q=India+Stock+Market&hl=en-IN&gl=IN&ceid=IN:en',
      'source': 'Google News'
    },
    {
      'url': 'https://news.google.com/rss/search?q=India+Economy+GDP+Inflation&hl=en-IN&gl=IN&ceid=IN:en',
      'source': 'Economy Watch'
    },
  ];

  IOClient? _client;

  IOClient _getClient() {
    if (_client != null) return _client!;
    HttpClient httpClient = HttpClient();
    httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    _client = IOClient(httpClient);
    return _client!;
  }

  // Static cache for faster app-internal navigation
  static List<MarketNews> _cachedNews = [];
  static DateTime? _lastFetchTime;

  List<MarketNews> get fullCache => _cachedNews;

  Future<List<MarketNews>> fetchNews({int hours = 2, int limit = 10, int offset = 0, bool force = false, String searchQuery = ""}) async {
    // 1. Curated primary feed (0 - 120)
    if (offset < 120) {
      if (!force && _cachedNews.isNotEmpty && _lastFetchTime != null && searchQuery.isEmpty) {
        if (DateTime.now().difference(_lastFetchTime!).inMinutes < 5) {
          final end = min(offset + limit, _cachedNews.length);
          if (offset >= _cachedNews.length) return [];
          return _cachedNews.sublist(offset, end);
        }
      }

      final client = _getClient();
      final now = DateTime.now();
      
      try {
        final List<List<_ScoredNews>> results = await Future.wait(
          _feeds.map((f) => _fetchSingleFeed(client, f['url']!, f['source']!, hours, now))
        );

        List<_ScoredNews> allScored = [];
        for (var list in results) {
          allScored.addAll(list);
        }

        allScored = _deduplicate(allScored);
        allScored.sort((a, b) => b.score.compareTo(a.score));

        final List<MarketNews> finalNews = [];
        final Set<String> addedUrls = {};

        for (var sn in allScored) {
          if (!addedUrls.contains(sn.news.link)) {
            finalNews.add(sn.news.copyWith(score: sn.score));
            addedUrls.add(sn.news.link);
          }
          if (finalNews.length >= 120) break;
        }

        _cachedNews = finalNews;
        _lastFetchTime = DateTime.now();

        // If a local search query is present, filter the results immediately
        List<MarketNews> toReturn = finalNews;
        if (searchQuery.isNotEmpty) {
          final q = searchQuery.toLowerCase();
          toReturn = finalNews.where((n) => 
            n.title.toLowerCase().contains(q) || 
            n.description.toLowerCase().contains(q)
          ).toList();
        }

        final end = min(offset + limit, toReturn.length);
        if (offset >= toReturn.length) return [];
        
        final paginated = toReturn.sublist(offset, end);
        return await _checkSavedStatus(paginated);
      } catch (e) {
        debugPrint('RSS fetch error: $e');
        return await _checkSavedStatus(_cachedNews); 
      }
    } 
    
    // 2. Secondary feed (120 - 240): Respect selected dropdown hours
    if (offset < 240) {
      final client = _getClient();
      final now = DateTime.now();
      try {
        // Expand timeframe slightly if 1hr/6hr is selected to ensure we have depth for scroll
        final lookbackHours = max(hours, 24); 
        final List<List<_ScoredNews>> results = await Future.wait(
          _feeds.map((f) => _fetchSingleFeed(client, f['url']!, f['source']!, lookbackHours, now))
        );

        List<_ScoredNews> allScored = [];
        for (var list in results) {
          allScored.addAll(list);
        }

        allScored = _deduplicate(allScored);
        
        // Filter out news already in the top 120 curated cache
        final cachedLinks = _cachedNews.map((n) => n.link).toSet();
        var secondaryNews = allScored
            .where((sn) => !cachedLinks.contains(sn.news.link))
            .map((sn) => sn.news.copyWith(score: sn.score))
            .toList();

        if (searchQuery.isNotEmpty) {
          final q = searchQuery.toLowerCase();
          secondaryNews = secondaryNews.where((n) => 
            n.title.toLowerCase().contains(q) || 
            n.description.toLowerCase().contains(q)
          ).toList();
        }

        final start = max(0, offset - 120);
        final end = min(start + limit, secondaryNews.length);
        if (start >= secondaryNews.length) return [];
        
        return await _checkSavedStatus(secondaryNews.sublist(start, end));
      } catch (e) {
        debugPrint('Extended RSS fetch error: $e');
        return [];
      }
    }

    // 3. Depth feed (> 240): Targeted Internet Search based on keyword
    final internetOffset = offset - 240;
    final finalQuery = searchQuery.isNotEmpty ? searchQuery : 'India Stock Market Finance';
    return await searchInternetNews(finalQuery, limit: limit, offset: internetOffset);
  }

  Future<List<MarketNews>> _checkSavedStatus(List<MarketNews> newsList) async {
    if (newsList.isEmpty) return [];
    try {
      final db = await NavRepository().db;
      final links = newsList.map((n) => n.link).toList();
      final placeholders = List.filled(links.length, '?').join(',');
      
      final res = await db.rawQuery(
        'SELECT link FROM saved_news WHERE link IN ($placeholders)',
        links
      );
      
      final savedLinks = res.map((r) => r['link'] as String).toSet();
      return newsList.map((n) => n.copyWith(isSaved: savedLinks.contains(n.link))).toList();
    } catch (e) {
      debugPrint('Error checking saved status: $e');
      return newsList;
    }
  }

  Future<void> toggleSave(MarketNews news) async {
    final db = await NavRepository().db;
    if (news.isSaved) {
      await db.delete('saved_news', where: 'link = ?', whereArgs: [news.link]);
    } else {
      await db.insert('saved_news', {
        'title': news.title,
        'description': news.description,
        'link': news.link,
        'pub_date': news.pubDate,
        'source': news.source,
        'saved_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<List<MarketNews>> fetchSavedNews() async {
    try {
      final db = await NavRepository().db;
      final res = await db.query('saved_news', orderBy: 'saved_at DESC');
      
      return res.map((r) => MarketNews(
        title: r['title'] as String,
        description: r['description'] as String,
        link: r['link'] as String,
        pubDate: r['pub_date'] as String,
        source: r['source'] as String,
        isSaved: true,
        score: 0,
      )).toList();
    } catch (e) {
      debugPrint('Error fetching saved news: $e');
      return [];
    }
  }

  Future<List<_ScoredNews>> _fetchSingleFeed(
    IOClient client, 
    String url, 
    String sourceName, 
    int hours, 
    DateTime now
  ) async {
    try {
      final response = await client.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36',
        'Accept': 'application/xml,text/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,image/png,*/*;q=0.5',
        'Accept-Language': 'en-US,en;q=0.9',
        'Cache-Control': 'no-cache',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('Feed $sourceName ($url) returned status ${response.statusCode}');
        return [];
      }

      // Pre-process body to fix common XML issues
      String cleanedBody = response.body
          .replaceAll(RegExp(r'&(?!(amp|lt|gt|quot|apos|#))'), '&amp;')
          .replaceAll(RegExp(r'<[^>]+(?=[^>]*<)'), ''); // Strip broken tags that miss closing >

      XmlDocument document;
      try {
        document = XmlDocument.parse(cleanedBody);
      } catch (e) {
        // Ultimate fallback: if XML parsing still fails, try to scrape manually with Regex
        return _manualScrape(cleanedBody, sourceName, hours, now);
      }

      final items = document.findAllElements('item');
      final List<_ScoredNews> feedNews = [];

      debugPrint('Source $sourceName: Found ${items.length} items');

      // Whitelisted sources are already 100% Indian Market focused
      final isWhitelisted = [
        'Economic Times', 'MoneyControl', 'Business Standard', 
        'LiveMint', 'Financial Express', 'NDTV Profit', 'Google News'
      ].contains(sourceName);

      for (var node in items) {
        String title = _getNodeText(node, 'title');
        String descRaw = _getNodeText(node, 'description');
        if (descRaw.isEmpty) descRaw = _getNodeText(node, 'content:encoded');
        
        String pubDateRaw = _getNodeText(node, 'pubDate');
        String sourceInFeed = _getNodeText(node, 'source');
        
        // For Aggregators (Google/Bloomberg), verify it's a domestic story
        // For Whitelisted portals, accept everything to avoid missing company specific news
        if (!isWhitelisted) {
          final isDomestic = _isDomestic(title) || _isDomestic(descRaw);
          if (!isDomestic) continue;
        }

        DateTime? date = _parseDate(pubDateRaw);
        if (date != null) {
          if (now.difference(date) > Duration(hours: hours)) continue;
        }

        String displayDate = date != null ? DateFormat("dd MMM, hh:mm a").format(date.toLocal()) : pubDateRaw;

        String? link = _getNodeText(node, 'link');
        if (link.isEmpty) link = _getNodeText(node, 'guid');
        
        // Format Google News sources with the website in brackets
        String displaySource = sourceName;
        if (sourceName == 'Google News' || sourceName == 'Internet Search' || sourceName == 'Economy Watch') {
          String website = sourceInFeed.isNotEmpty ? sourceInFeed : _extractDomain(link);
          displaySource = "Google News ($website)";
        }

        final news = MarketNews(
          title: _decodeHtmlEntities(title.trim()),
          description: _stripHtml(descRaw),
          link: link.trim(),
          pubDate: displayDate,
          source: displaySource,
        );
        
        feedNews.add(_ScoredNews(news, _calculateScore(title, descRaw, date, now, sourceName)));
      }
      return feedNews;
    } catch (e) {
      debugPrint('Error fetching $sourceName: $e');
      return [];
    }
  }

  String _getNodeText(XmlElement node, String name) {
    try {
      return node.findElements(name).first.innerText.trim();
    } catch (_) {
      return '';
    }
  }

  DateTime? _parseDate(String raw) {
    try {
      // Try standard RSS format first
      return DateFormat("EEE, dd MMM yyyy HH:mm:ss Z").parse(raw);
    } catch (_) {
      try {
        // Try fallback for some feeds that might use different zones
        return DateTime.parse(raw);
      } catch (_) {
        return null;
      }
    }
  }

  List<_ScoredNews> _deduplicate(List<_ScoredNews> news) {
    final Map<String, _ScoredNews> unique = {};
    for (var sn in news) {
      // Use the URL as the unique key for 100% reliable deduplication
      final key = sn.news.link.trim().toLowerCase();
      if (key.isEmpty) continue;
      
      if (!unique.containsKey(key)) {
        unique[key] = sn;
      } else {
        // If duplicate URL found, keep the one with the higher score
        if (sn.score > unique[key]!.score) {
          unique[key] = sn;
        }
      }
    }
    
    // Optional: Second pass for very similar titles (95% match)
    final List<_ScoredNews> result = [];
    final Set<String> seenTitles = {};
    
    for (var sn in unique.values) {
      final titleKey = sn.news.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (seenTitles.contains(titleKey)) continue;
      
      seenTitles.add(titleKey);
      result.add(sn);
    }

    return result;
  }

  int _calculateScore(String title, String desc, DateTime? date, DateTime now, String source) {
    int score = 0;
    final text = (title + " " + desc).toLowerCase();
    
    // 1. Core Popularity Keywords
    final topInterest = [
      'nifty', 'sensex', 'rbi', 'sebi', 'ipo', 'earnings', 'quarterly', 
      'profit', 'dividend', 'gdp', 'fmcg', 'inflation', 'budget', 'policy', 'interest rate'
    ];
    for (var k in topInterest) {
      if (text.contains(k)) score += 25;
    }
    
    // 2. High-Impact Market Events
    final highImpact = ['crash', 'surge', 'rally', 'slump', 'record high', 'breakout', 'interest rate', 'inflation', 'merger'];
    for (var k in highImpact) {
      if (text.contains(k)) score += 20;
    }
    
    // 3. Blue Chip Company Focus
    final blueChips = ['reliance', 'hdfc', 'tcs', 'infosys', 'sbi', 'icici', 'adani', 'tata', 'zomato', 'paytm'];
    for (var k in blueChips) {
      if (text.contains(k)) score += 10;
    }

    // 4. Freshness
    if (date != null) {
      final diff = now.difference(date).inMinutes;
      if (diff <= 30) score += 50; 
      else if (diff <= 60) score += 30;
      else if (diff <= 180) score += 15;
    }

    // No source bias - let the content and freshness decide the rank
    
    return score;
  }

  List<_ScoredNews> _manualScrape(String body, String source, int hours, DateTime now) {
    debugPrint('Manual scraping $source due to XML failure');
    final List<_ScoredNews> newsList = [];
    final itemMatches = RegExp(r'<item>(.*?)<\/item>', dotAll: true).allMatches(body);

    for (var match in itemMatches) {
      String itemContent = match.group(1)!;
      String title = _regexExtract(itemContent, r'<title>(.*?)<\/title>');
      String link = _regexExtract(itemContent, r'<link>(.*?)<\/link>');
      String desc = _regexExtract(itemContent, r'<description>(.*?)<\/description>');
      String pubDate = _regexExtract(itemContent, r'<pubDate>(.*?)<\/pubDate>');

      if (title.isEmpty) continue;

      DateTime? date = _parseDate(pubDate);
      if (date != null && now.difference(date).inHours > hours) continue;

      final news = MarketNews(
        title: _decodeHtmlEntities(title.replaceAll('<![CDATA[', '').replaceAll(']]>', '').trim()),
        description: _stripHtml(desc.replaceAll('<![CDATA[', '').replaceAll(']]>', '')),
        link: link.replaceAll('<![CDATA[', '').replaceAll(']]>', '').trim(),
        pubDate: date != null ? DateFormat("dd MMM, hh:mm a").format(date.toLocal()) : pubDate,
        source: source,
      );
      newsList.add(_ScoredNews(news, _calculateScore(title, desc, date, now, source)));
    }
    return newsList;
  }

  String _regexExtract(String content, String pattern) {
    final match = RegExp(pattern, dotAll: true).firstMatch(content);
    return match?.group(1) ?? '';
  }

  Future<List<MarketNews>> fetchTop10News({bool force = false}) async {
    return fetchNews(hours: 24, limit: 20, force: force);
  }

  Future<List<MarketNews>> searchInternetNews(String query, {int limit = 20, int offset = 0}) async {
    if (query.trim().isEmpty) return [];
    
    final client = _getClient();
    final now = DateTime.now();
    final encodedQuery = Uri.encodeComponent('${query.trim()} India Market');
    final url = 'https://news.google.com/rss/search?q=$encodedQuery&hl=en-IN&gl=IN&ceid=IN:en';
    
    try {
      // Use 'Internet Search' as a flag to trigger domain extraction in _fetchSingleFeed
      final results = await _fetchSingleFeed(client, url, 'Internet Search', 720, now); 
      
      // Sort by score (freshness + keyword matches)
      results.sort((a, b) => b.score.compareTo(a.score));
      
      final List<MarketNews> newsList = results.map((sn) => sn.news.copyWith(score: sn.score)).toList();
      
      // Pagination
      final end = min(offset + limit, newsList.length);
      if (offset >= newsList.length) return [];
      
      final paginated = newsList.sublist(offset, end);
      return await _checkSavedStatus(paginated);
    } catch (e) {
      debugPrint('Internet search news error: $e');
      return [];
    }
  }

  bool _isDomestic(String text) {
    final lower = text.toLowerCase();
    final domesticKeywords = [
      'nifty', 'sensex', 'sebi', 'rbi', 'nse', 'bse', 'india', 'crore', 'lakh', 'dalal street',
      'tcs', 'infosys', 'reliance', 'hdfc', 'sbi', 'icici', 'adani', 'tata', 'rupee', 'inr',
      'zomato', 'paytm', 'lic', 'wipro', 'itc', 'bajaj', 'airtel', 'vedanta', 'equity', 'stock',
      'market', 'share', 'mutual fund', 'nav', 'ipo', 'dividend', 'gst', 'finmin', 'finance', 
      'investor', 'trade', 'q1', 'q2', 'q3', 'q4', 'bonus', 'buyback', 'portfolio', 'investment'
    ];
    return domesticKeywords.any((k) => lower.contains(k));
  }

  String _decodeHtmlEntities(String text) {
    if (!text.contains('&')) return text;
    
    return text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&#8377;', '₹')
      .replaceAll('&rupee;', '₹')
      .replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
        try {
          final charCode = int.parse(match.group(1)!);
          return String.fromCharCode(charCode);
        } catch (_) { return match.group(0)!; }
      })
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
        try {
          final charCode = int.parse(match.group(1)!, radix: 16);
          return String.fromCharCode(charCode);
        } catch (_) { return match.group(0)!; }
      });
  }

  String _stripHtml(String html) {
    // 1. Remove HTML tags
    String text = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
    
    // 2. Decode HTML entities
    text = _decodeHtmlEntities(text);
    
    // 3. Clean up whitespace
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    // 4. Truncate if too long for preview
    if (text.length > 500) text = text.substring(0, 497) + "...";
    return text;
  }

  String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      String host = uri.host.toLowerCase();
      if (host.startsWith('www.')) host = host.substring(4);
      return host;
    } catch (_) {
      return 'News Source';
    }
  }
}

class _ScoredNews {
  final MarketNews news;
  final int score;
  _ScoredNews(this.news, this.score);
}
