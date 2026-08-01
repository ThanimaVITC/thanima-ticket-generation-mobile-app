/// One person on an event's unpaid list. Free-form on purpose — unpaid
/// attendees are filtered out at CSV import, so there is no registration row
/// and no email to link to.
class UnpaidEntry {
  final String id;
  final String name;
  final String regNo;
  final String source; // 'manual' | 'ocr'
  final DateTime createdAt;

  UnpaidEntry({
    required this.id,
    required this.name,
    required this.regNo,
    required this.source,
    required this.createdAt,
  });

  factory UnpaidEntry.fromJson(Map<String, dynamic> json) {
    return UnpaidEntry(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: json['name']?.toString() ?? '',
      regNo: json['regNo']?.toString() ?? '',
      source: json['source']?.toString() ?? 'manual',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal() ??
              DateTime.now(),
    );
  }
}
