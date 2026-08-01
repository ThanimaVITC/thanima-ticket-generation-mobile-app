/// One stay in the User Pool. A user who leaves and comes back has two of these.
class PoolEntry {
  final String id;
  final String name;
  final String regNo;
  final String email;
  final String phone;
  final String nfcId;
  final DateTime enteredAt;
  final DateTime? exitedAt;

  PoolEntry({
    required this.id,
    required this.name,
    required this.regNo,
    required this.email,
    required this.phone,
    required this.nfcId,
    required this.enteredAt,
    this.exitedAt,
  });

  bool get isInPool => exitedAt == null;

  /// How long the stay lasted, or has lasted so far. Computed from enteredAt
  /// rather than the server's durationMs snapshot so the UI ticks locally
  /// without re-fetching.
  Duration get timeInPool => (exitedAt ?? DateTime.now()).difference(enteredAt);

  /// "2h 14m" / "43m 12s" / "58s" — matches formatDuration() on the server.
  static String format(Duration d) {
    if (d.isNegative) return '—';
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }

  String get formattedTimeInPool => format(timeInPool);

  factory PoolEntry.fromJson(Map<String, dynamic> json) {
    final exited = json['exitedAt'];
    return PoolEntry(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: json['name']?.toString() ?? '',
      regNo: json['regNo']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      nfcId: json['nfcId']?.toString() ?? '',
      enteredAt:
          DateTime.tryParse(json['enteredAt']?.toString() ?? '')?.toLocal() ??
              DateTime.now(),
      exitedAt: exited == null
          ? null
          : DateTime.tryParse(exited.toString())?.toLocal(),
    );
  }
}
