class Registration {
  final String id;
  final String name;
  final String regNo;
  final String email;
  final String eventId;
  final bool attended;
  final DateTime? markedAt;

  Registration({
    required this.id,
    required this.name,
    required this.regNo,
    required this.email,
    required this.eventId,
    required this.attended,
    this.markedAt,
  });

  factory Registration.fromJson(Map<String, dynamic> json) {
    return Registration(
      id: json['_id'],
      name: json['name'],
      regNo: json['regNo'],
      email: json['email'],
      eventId: json['eventId'],
      attended: json['attended'] ?? false,
      markedAt: json['attendance'] != null
          ? DateTime.parse(json['attendance']['markedAt'])
          : null,
    );
  }
}
