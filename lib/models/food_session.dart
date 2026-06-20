class FoodSessionStats {
  final int admitted;
  final int remainingToLimit;
  final int remainingToMax;
  final bool nearLimit;
  final bool full;

  FoodSessionStats({
    required this.admitted,
    required this.remainingToLimit,
    required this.remainingToMax,
    required this.nearLimit,
    required this.full,
  });

  factory FoodSessionStats.fromJson(Map<String, dynamic> json) {
    return FoodSessionStats(
      admitted: json['admitted'] ?? 0,
      remainingToLimit: json['remainingToLimit'] ?? 0,
      remainingToMax: json['remainingToMax'] ?? 0,
      nearLimit: json['nearLimit'] ?? false,
      full: json['full'] ?? false,
    );
  }
}

class FoodSession {
  final String id;
  final String name;
  final int limit;
  final int maxLimit;
  final bool isVisible;
  final int count;
  final FoodSessionStats? stats;

  FoodSession({
    required this.id,
    required this.name,
    required this.limit,
    required this.maxLimit,
    required this.isVisible,
    required this.count,
    this.stats,
  });

  factory FoodSession.fromJson(Map<String, dynamic> json) {
    return FoodSession(
      id: json['_id'] ?? json['id'],
      name: json['name'] ?? '',
      limit: json['limit'] ?? 0,
      maxLimit: json['maxLimit'] ?? 0,
      isVisible: json['isVisible'] ?? true,
      count: json['count'] ?? 0,
      stats: json['stats'] != null
          ? FoodSessionStats.fromJson(Map<String, dynamic>.from(json['stats']))
          : null,
    );
  }
}
