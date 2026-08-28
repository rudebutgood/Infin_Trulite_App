import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/io_client.dart';
import 'package:xml/xml.dart';
import 'package:intl/intl.dart';
import '../models/market_news.dart';

class MarketNewsService {
  // List of high-quality financial RSS feeds
  final List<Map<String, String>> _feeds = [
    {
      'url': 'https://economictimes.indiatimes.com/markets/stocks/rssfeeds/2146842.cms',
      'source': 'Economic Times'
    },
    {
      'url': 'https://www.moneycontrol.com/rss/buzzingstocks.xml',
      'source': 'MoneyControl'
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
      'url': 'https://www.financialexpress.com/market/stock-market/feed/',
      'source': 'Financial Express'
    },
    {
      'url': 'https://feeds.feedburner.com/ndtvprofit-latest',
      'source': 'NDTV Profit'
    },
    {
      'url': 'https://news.google.com/rss/topics/CAAqJggKIiBDQkFTRWdvSUwyMHZNRGRqTVhZU0FtVnVHZ0pKVGlnQVAB?hl=en-IN&gl=IN&ceid=IN:en',
      'source': 'Google News'
    },
    {
      'url': 'https://www.bloomberg.com/asia/rss',
      'source': 'Bloomberg Asia'
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

  Future<List<MarketNews>> fetchNews({int hours = 2, int limit = 10, int offset = 0}) async {
    final client = _getClient();
    final now = DateTime.now();
    
    try {
      // 1. Fetch from all sources in parallel
      final results = await Future.wait(
        _feeds.map((f) => _fetchSingleFeed(client, f['url']!, f['source']!, hours, now))
      );

      // 2. Aggregate all news
      List<_ScoredNews> allScored = [];
      for (var list in results) {
        allScored.addAll(list);
      }

      // 3. Simple Deduplication (by title similarity)
      allScored = _deduplicate(allScored);

      // 4. Global Sorting by relevance score
      allScored.sort((a, b) => b.score.compareTo(a.score));
      
      final finalNews = allScored.map((sn) => sn.news).toList();

      // 5. Pagination
      final end = min(offset + limit, finalNews.length);
      if (offset >= finalNews.length) return [];
      return finalNews.sublist(offset, end);
    } catch (e) {
      debugPrint('Multi-source fetch news error: $e');
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
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
      });

      if (response.statusCode != 200) return [];

      final document = XmlDocument.parse(response.body);
      final items = document.findAllElements('item');
      final List<_ScoredNews> feedNews = [];

      for (var node in items) {
        String title = _getNodeText(node, 'title');
        String descRaw = _getNodeText(node, 'description');
        if (descRaw.isEmpty) descRaw = _getNodeText(node, 'content:encoded');
        
        String pubDateRaw = _getNodeText(node, 'pubDate');
        
        final isDomestic = _isDomestic(title) || _isDomestic(descRaw);
        if (!isDomestic) continue;

        DateTime? date = _parseDate(pubDateRaw);
        if (date != null) {
          if (now.difference(date) > Duration(hours: hours)) continue;
        }

        String displayDate = date != null ? DateFormat("dd MMM, hh:mm a").format(date.toLocal()) : pubDateRaw;

        String? link = _getNodeText(node, 'link');
        if (link.isEmpty) link = _getNodeText(node, 'guid');
        
        final news = MarketNews(
          title: title.trim(),
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
      // Normalize title for keying: lowercase and remove non-alphanumeric
      final key = sn.news.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (key.isEmpty) continue;
      
      if (!unique.containsKey(key)) {
        unique[key] = sn;
      } else {
        // If duplicate found, keep the one with the higher score
        if (sn.score > unique[key]!.score) {
          unique[key] = sn;
        }
      }
    }
    return unique.values.toList();
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

    // 5. Source Weighting (Small bias for established domestic terminals)
    if (source == 'MoneyControl') score += 5; // Good for intra-day buzzing stocks
    
    return score;
  }

  Future<List<MarketNews>> fetchTop10News() async {
    return fetchNews(hours: 24, limit: 10);
  }

  bool _isDomestic(String text) {
    final lower = text.toLowerCase();
    final domesticKeywords = [
      'nifty', 'sensex', 'sebi', 'rbi', 'nse', 'bse', 'india', 'crore', 'lakh', 'dalal street',
      'tcs', 'infosys', 'reliance', 'hdfc', 'sbi', 'icici', 'adani', 'tata', 'rupee', 'inr',
      'zomato', 'paytm', 'lic', 'wipro', 'itc', 'bajaj', 'airtel', 'vedanta', 'equity', 'stock'
    ];
    return domesticKeywords.any((k) => lower.contains(k));
  }

  String _stripHtml(String html) {
    String text = html.replaceAll(RegExp(r'<[^>]*>|&nbsp;'), ' ').trim();
    // Keep more content for the popup summary, but still clean
    if (text.length > 500) text = text.substring(0, 497) + "...";
    return text;
  }
}

class _ScoredNews {
  final MarketNews news;
  final int score;
  _ScoredNews(this.news, this.score);
}
