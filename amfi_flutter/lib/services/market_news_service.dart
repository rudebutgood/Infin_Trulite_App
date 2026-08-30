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

  Future<List<MarketNews>> fetchNews({int hours = 2, int limit = 10, int offset = 0, bool force = false}) async {
    // Return cache if it's fresh (last 5 minutes)
    if (!force && _cachedNews.isNotEmpty && _lastFetchTime != null) {
      if (DateTime.now().difference(_lastFetchTime!).inMinutes < 5) {
        final end = min(offset + limit, _cachedNews.length);
        if (offset >= _cachedNews.length) return [];
        return _cachedNews.sublist(offset, end);
      }
    }

    final client = _getClient();
    final now = DateTime.now();
    
    try {
      // 1. Fetch from all sources in parallel with individual timeouts
      // Future.wait will catch all results that finish within their internal timeouts
      final List<List<_ScoredNews>> results = await Future.wait(
        _feeds.map((f) => _fetchSingleFeed(client, f['url']!, f['source']!, hours, now))
      );

      // 2. Aggregate all news from successful responses
      List<_ScoredNews> allScored = [];
      for (var list in results) {
        allScored.addAll(list);
      }

      // 3. Simple Deduplication
      allScored = _deduplicate(allScored);

      // 4. Best Ranking First: Sort all news by their AI impact score
      allScored.sort((a, b) => b.score.compareTo(a.score));

      final List<MarketNews> finalNews = [];
      final Set<String> addedUrls = {};

      for (var sn in allScored) {
        if (!addedUrls.contains(sn.news.link)) {
          finalNews.add(sn.news.copyWith(score: sn.score));
          addedUrls.add(sn.news.link);
        }
        // Limit to top 150 relevant stories to allow for deeper scrolling
        if (finalNews.length >= 150) break;
      }

      // 5. Update Cache
      _cachedNews = finalNews;
      _lastFetchTime = DateTime.now();

      // 6. Pagination
      final end = min(offset + limit, finalNews.length);
      if (offset >= finalNews.length) return [];
      
      final paginated = finalNews.sublist(offset, end);
      return await _checkSavedStatus(paginated);
    } catch (e) {
      debugPrint('Multi-source fetch news error: $e');
      return await _checkSavedStatus(_cachedNews); 
    }
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
        
        final news = MarketNews(
          title: _decodeHtmlEntities(title.trim()),
          description: _stripHtml(descRaw),
          link: link.trim(),
          pubDate: displayDate,
          source: sourceName,
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
    final topInterest = ['nifty', 'sensex', 'rbi', 'sebi', 'ipo', 'earnings', 'quarterly', 'profit', 'dividend'];
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
}

class _ScoredNews {
  final MarketNews news;
  final int score;
  _ScoredNews(this.news, this.score);
}
