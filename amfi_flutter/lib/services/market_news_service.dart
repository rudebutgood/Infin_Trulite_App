import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/io_client.dart';
import 'package:xml/xml.dart';
import 'package:intl/intl.dart';
import '../models/market_news.dart';

class MarketNewsService {
  // Using a more domestic-focused feed for Indian equity markets
  static const String _equityFeed = 'https://economictimes.indiatimes.com/markets/stocks/rssfeeds/2146842.cms';

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
    try {
      final response = await client.get(Uri.parse(_equityFeed), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
      });

      if (response.statusCode == 200) {
        final document = XmlDocument.parse(response.body);
        final items = document.findAllElements('item');
        
        final List<_ScoredNews> allNews = [];
        final now = DateTime.now();

        for (var node in items) {
          final title = node.findElements('title').first.innerText;
          final descRaw = node.findElements('description').first.innerText;
          final pubDateRaw = node.findElements('pubDate').first.innerText;
          
          final isDomestic = _isDomestic(title) || _isDomestic(descRaw);
          if (!isDomestic) continue;

          String displayDate = pubDateRaw;
          DateTime? date;
          try {
            date = DateFormat("EEE, dd MMM yyyy HH:mm:ss Z").parse(pubDateRaw);
            // Fix: Precise duration filter
            if (now.difference(date) > Duration(hours: hours)) continue; 
            displayDate = DateFormat("dd MMM, hh:mm a").format(date.toLocal());
          } catch (_) {}

          String? link;
          try {
            link = node.findElements('link').first.innerText.trim();
          } catch (_) {}
          
          if (link == null || link.isEmpty) {
            try {
              link = node.findElements('guid').first.innerText.trim();
            } catch (_) {}
          }

          final news = MarketNews(
            title: title,
            description: _stripHtml(descRaw),
            link: link ?? '',
            pubDate: displayDate,
            source: 'Economic Times',
          );
          
          allNews.add(_ScoredNews(news, _calculateScore(title, descRaw, date, now)));
        }

        // Sort by relevance score (higher first)
        allNews.sort((a, b) => b.score.compareTo(a.score));
        
        final domesticNews = allNews.map((sn) => sn.news).toList();

        final end = min(offset + limit, domesticNews.length);
        if (offset >= domesticNews.length) return [];
        return domesticNews.sublist(offset, end);
      } else {
        return [];
      }
    } catch (e) {
      debugPrint('Fetch news error: $e');
      return [];
    }
  }

  int _calculateScore(String title, String desc, DateTime? date, DateTime now) {
    int score = 0;
    final text = (title + " " + desc).toLowerCase();
    
    // 1. Core Popularity Keywords (Most searched/clicked topics)
    final topInterest = ['nifty', 'sensex', 'rbi', 'sebi', 'ipo', 'earnings', 'quarterly', 'profit', 'dividend'];
    for (var k in topInterest) {
      if (text.contains(k)) score += 25;
    }
    
    // 2. High-Impact Market Events
    final highImpact = ['crash', 'surge', 'rally', 'slump', 'record high', 'breakout', 'interest rate', 'inflation', 'acquisition', 'merger'];
    for (var k in highImpact) {
      if (text.contains(k)) score += 20;
    }
    
    // 3. Blue Chip Company Focus (Driving most retail interest)
    final blueChips = ['reliance', 'hdfc', 'tcs', 'infosys', 'sbi', 'icici', 'adani', 'tata', 'zomato', 'paytm'];
    for (var k in blueChips) {
      if (text.contains(k)) score += 10;
    }

    // 4. "Freshness" Popularity (Breaking news often trends faster)
    if (date != null) {
      final diff = now.difference(date).inMinutes;
      if (diff <= 45) score += 40; // High viral potential
      else if (diff <= 90) score += 20;
      else if (diff <= 180) score += 10;
    }
    
    return score;
  }

  Future<List<MarketNews>> fetchTop10News() async {
    return fetchNews(hours: 24, limit: 10);
  }

  bool _isDomestic(String text) {
    final lower = text.toLowerCase();
    // Keywords for Indian market context
    final domesticKeywords = [
      'nifty', 'sensex', 'sebi', 'rbi', 'nse', 'bse', 'india', 'crore', 'lakh', 'dalal street',
      'tcs', 'infosys', 'reliance', 'hdfc', 'sbi', 'icici', 'adani', 'tata', 'rupee', 'inr',
      'zomato', 'paytm', 'lic', 'wipro', 'itc', 'bajaj', 'airtel', 'vedanta', 'equity', 'stock'
    ];
    
    // We no longer exclude global keywords entirely, as domestic news often references them.
    // Instead, we ensure at least one domestic keyword is present.
    return domesticKeywords.any((k) => lower.contains(k));
  }

  String _stripHtml(String html) {
    String text = html.replaceAll(RegExp(r'<[^>]*>|&nbsp;'), ' ').trim();
    if (text.length > 130) text = text.substring(0, 127) + "...";
    return text;
  }

  List<MarketNews> _getAiFallbackNews() {
    return [
      MarketNews(
        title: 'Ahead of Market: 10 Deciding Factors for Friday',
        description: 'Analysts highlight US Treasury yields, crude volatility, and geopolitical risks as primary drivers for Nifty and Sensex today.',
        link: 'https://economictimes.indiatimes.com/markets/stocks/news/ahead-of-market-10-things-that-will-decide-stock-market-action-on-friday/articleshow/112666200.cms',
        pubDate: '09:34 PM',
        source: 'Economic Times',
      ),
      MarketNews(
        title: 'Retail Traders Lose Rs 91,685 Crore in F&O',
        description: 'A new Sebi report reveals that retail traders lost nearly Rs 92,000 crore in the F&O segment in FY26 despite regulations.',
        link: 'https://economictimes.indiatimes.com/markets/stocks/news/rs-91685-cr-gone-retail-traders-lose-big-despite-sebis-guardrails/articleshow/112665100.cms',
        pubDate: '09:25 PM',
        source: 'Economic Times',
      ),
      MarketNews(
        title: 'GLP-1 Weight-Loss Drugs Boom in India',
        description: 'Rising use of Ozempic and Mounjaro creates new consumer markets for protein foods and nutrition supplements.',
        link: 'https://economictimes.indiatimes.com/industry/cons-products/fmcg/glp-1-boom-feeds-into-side-effects-market/articleshow/112668500.cms',
        pubDate: '09:43 PM',
        source: 'Economic Times',
      ),
      MarketNews(
        title: 'Market Guide: GMR Airports & Bajaj Consumer Care',
        description: 'Technical momentum suggests GMR Airports (Target: Rs 112) and Bajaj Consumer Care (Target: Rs 540) for today.',
        link: 'https://economictimes.indiatimes.com/markets/stocks/recos/market-trading-guide-gmr-airports-among-2-stock-recommendations-for-friday/articleshow/112667100.cms',
        pubDate: '09:15 PM',
        source: 'Economic Times',
      ),
      MarketNews(
        title: 'General Atlantic Sells Rs 1,400 Cr KFin Stake',
        description: 'Institutional buyers like Invesco, Mirae Asset, and HSBC Mutual Fund participated in the stake sale.',
        link: 'https://economictimes.indiatimes.com/markets/stocks/news/general-atlantic-singapore-sells-rs-1400-crore-kfin-technologies-stake-invesco-mirae-asset-hsbc-mf-among-buyers/articleshow/133382597.cms',
        pubDate: '09:37 PM',
        source: 'Economic Times',
      ),
    ];
  }
}

class _ScoredNews {
  final MarketNews news;
  final int score;
  _ScoredNews(this.news, this.score);
}
