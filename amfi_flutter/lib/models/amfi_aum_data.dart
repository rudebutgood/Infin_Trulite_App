class AmfiAumData {
  final String period;
  final double totalAum;
  final List<AmfiAumGroup> categories;
  final List<AmfiAumGroup> amcs;
  final List<AmfiAumGroup> amcCategories;

  AmfiAumData({
    required this.period,
    required this.totalAum,
    required this.categories,
    required this.amcs,
    required this.amcCategories,
  });
}

class AmfiAumGroup {
  final String name;
  final double aum;
  final List<AmfiSchemeDetail> schemes;

  AmfiAumGroup({
    required this.name,
    required this.aum,
    this.schemes = const [],
  });
}

class AmfiSchemeDetail {
  final String schemeName;
  final int amfiCode;
  final double aumExclFoF;
  final double aumFoF;
  final double totalAum;

  AmfiSchemeDetail({
    required this.schemeName,
    required this.amfiCode,
    required this.aumExclFoF,
    required this.aumFoF,
    required this.totalAum,
  });
}

class AmfiAumComparison {
  final AmfiAumData current;
  final AmfiAumData previous;

  AmfiAumComparison({required this.current, required this.previous});

  double get increase => current.totalAum - previous.totalAum;
  double get percentageIncrease => previous.totalAum > 0 ? (increase / previous.totalAum * 100) : 0;
}
