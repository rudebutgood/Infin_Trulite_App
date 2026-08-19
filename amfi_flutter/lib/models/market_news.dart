class MarketNews {
  final String title;
  final String description;
  final String link;
  final String pubDate;
  final String source;

  MarketNews({
    required this.title,
    required this.description,
    required this.link,
    required this.pubDate,
    required this.source,
  });

  factory MarketNews.fromRssItem(Map<String, dynamic> item, String source) {
    return MarketNews(
      title: item['title'] ?? 'No Title',
      description: item['description'] ?? '',
      link: item['link'] ?? '',
      pubDate: item['pubDate'] ?? '',
      source: source,
    );
  }
}
