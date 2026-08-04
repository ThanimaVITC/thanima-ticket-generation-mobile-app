import 'package:flutter_test/flutter_test.dart';
import 'package:thanima_app/models/pool_entry.dart';

void main() {
  test('parses an active stay and leaves exitedAt null', () {
    final entry = PoolEntry.fromJson({
      '_id': 'abc123',
      'name': 'Asha K',
      'regNo': 'REG001',
      'email': 'asha@example.com',
      'phone': '9876543210',
      'nfcId': '04A23F9C',
      'enteredAt': DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 30))
          .toIso8601String(),
      'exitedAt': null,
    });

    expect(entry.isInPool, isTrue);
    expect(entry.exitedAt, isNull);
    // Counted from enteredAt, so it grows on its own without a re-fetch.
    expect(entry.timeInPool.inMinutes, inInclusiveRange(29, 31));
  });

  test('parses a finished stay and fixes its duration', () {
    final entered = DateTime.utc(2026, 8, 1, 10, 0);
    final exited = DateTime.utc(2026, 8, 1, 12, 14);

    final entry = PoolEntry.fromJson({
      '_id': 'abc124',
      'name': 'Ravi M',
      'enteredAt': entered.toIso8601String(),
      'exitedAt': exited.toIso8601String(),
    });

    expect(entry.isInPool, isFalse);
    expect(entry.timeInPool, const Duration(hours: 2, minutes: 14));
    expect(entry.formattedTimeInPool, '2h 14m');
    // Missing optional fields must not blow up the parse.
    expect(entry.regNo, '');
    expect(entry.phone, '');
  });

  test('formats durations the same way the server does', () {
    expect(PoolEntry.format(Duration.zero), '0s');
    expect(PoolEntry.format(const Duration(seconds: 58)), '58s');
    expect(PoolEntry.format(const Duration(minutes: 43)), '43m 0s');
    expect(PoolEntry.format(const Duration(minutes: 43, seconds: 12)), '43m 12s');
    expect(PoolEntry.format(const Duration(hours: 2, minutes: 14)), '2h 14m');
    expect(PoolEntry.format(const Duration(seconds: -1)), '—');
  });
}
