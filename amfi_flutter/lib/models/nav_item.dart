class NavItem {
  final int? id;
  final String? schemeCode;
  final String? isinDivPayout;
  final String? isinReinvestment;
  final String? schemeName;
  final double? navValue;
  final String? navDate;
  final String? importedAt;
  final String? apiTimestamp;
  final String? mfName;
  final String? category;
  final bool isFavorite;
  final bool isHeld;

  // comparison fields
  final double? prevNavValue;
  final String? prevNavDate;

  NavItem({
    this.id,
    this.schemeCode,
    this.isinDivPayout,
    this.isinReinvestment,
    this.schemeName,
    this.navValue,
    this.navDate,
    this.importedAt,
    this.apiTimestamp,
    this.mfName,
    this.category,
    this.isFavorite = false,
    this.isHeld = false,
    this.prevNavValue,
    this.prevNavDate,
  });

  factory NavItem.fromMap(Map<String, dynamic> m) => NavItem(
        id: m['id'] as int?,
        schemeCode: m['scheme_code'] as String?,
        isinDivPayout: m['isin_div_payout'] as String?,
        isinReinvestment: m['isin_reinvestment'] as String?,
        schemeName: m['scheme_name'] as String?,
        navValue: m['nav_value'] == null ? null : (m['nav_value'] as num).toDouble(),
        navDate: m['nav_date'] as String?,
        importedAt: m['imported_at'] as String?,
        apiTimestamp: m['api_timestamp'] as String?,
        mfName: m['mf_name'] as String?,
        category: m['category_name'] as String?,
        isFavorite: (m['is_favorite'] as int? ?? 0) == 1,
        isHeld: (m['is_held'] as int? ?? 0) == 1,
        prevNavValue: m.containsKey('prev_nav_value') && m['prev_nav_value'] != null ? (m['prev_nav_value'] as num).toDouble() : null,
        prevNavDate: m['prev_nav_date'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'scheme_code': schemeCode,
        'isin_div_payout': isinDivPayout,
        'isin_reinvestment': isinReinvestment,
        'scheme_name': schemeName,
        'nav_value': navValue,
        'nav_date': navDate,
        'imported_at': importedAt,
      };
}
