class Event {
  final String id;
  final String title;
  final String? description;
  final DateTime date;
  final String? location;
  final bool foodSessionsEnabled;

  Event({
    required this.id,
    required this.title,
    this.description,
    required this.date,
    this.location,
    this.foodSessionsEnabled = false,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['_id'],
      title: json['title'],
      description: json['description'],
      date: DateTime.parse(json['date']),
      location: json['location'],
      foodSessionsEnabled: json['foodSessionsEnabled'] ?? false,
    );
  }
}
