class MarketNews {
  final String title;
  final String description;
  final String link;
  final String pubDate;
  final String source;
  final int? score;
  final bool isSaved;

  MarketNews({
    required this.title,
    required this.description,
    required this.link,
    required this.pubDate,
    required this.source,
    this.score,
    this.isSaved = false,
  });

  factory MarketNews.fromRssItem(Map<String, dynamic> item, String source) {
    return MarketNews(
      title: item['title'] ?? 'No Title',
      description: item['description'] ?? '',
      link: item['link'] ?? '',
      pubDate: item['pubDate'] ?? '',
      source: source,
      score: 0,
      isSaved: false,
    );
  }

  MarketNews copyWith({int? score, bool? isSaved}) {
    return MarketNews(
      title: title,
      description: description,
      link: link,
      pubDate: pubDate,
      source: source,
      score: score ?? this.score,
      isSaved: isSaved ?? this.isSaved,
    );
  }
}
