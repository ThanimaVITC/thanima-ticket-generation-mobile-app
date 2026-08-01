import 'dart:async';
import 'dart:io' show Platform;

import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';

/// Thrown when the card can't be read. [message] is safe to show to staff.
class NfcFailure implements Exception {
  final String message;
  const NfcFailure(this.message);

  @override
  String toString() => message;
}

/// Reads the hardware UID off an ID card.
///
/// We deliberately read only the tag's serial number, not its contents: on the
/// MIFARE cards most college IDs use, the data sectors are key-protected, but
/// the UID is always readable and is already unique per card.
///
/// Android only by design — iOS Core NFC needs a paid-account entitlement and
/// can't read the UID of arbitrary MIFARE cards anyway. On iOS this reports
/// "not supported" rather than half-working.
class NfcService {
  /// Whether an NFC session can be started right now, and if not, why.
  /// Returns null when the platform has no NFC support at all.
  Future<NfcAvailability?> availability() async {
    if (!Platform.isAndroid) return null;
    try {
      return await NfcManager.instance.checkAvailability();
    } catch (_) {
      return null;
    }
  }

  /// A staff-facing explanation of why NFC can't be used, or null if it can.
  Future<String?> unavailableReason() async {
    if (!Platform.isAndroid) {
      return 'NFC card reading is only supported on Android devices.';
    }
    final state = await availability();
    switch (state) {
      case NfcAvailability.enabled:
        return null;
      case NfcAvailability.disabled:
        return 'NFC is turned off. Enable it in system settings, then try again.';
      case NfcAvailability.unsupported:
      case null:
        return 'This device does not have an NFC reader.';
    }
  }

  /// Waits for a card to be tapped and returns its UID as uppercase hex with no
  /// separators — the exact spelling the server stores.
  ///
  /// Throws [NfcFailure] if NFC is unusable, the tag has no readable UID, or
  /// nothing is tapped before [timeout].
  Future<String> readCardId({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final reason = await unavailableReason();
    if (reason != null) throw NfcFailure(reason);

    final completer = Completer<String>();

    try {
      await NfcManager.instance.startSession(
        // All three so we catch ISO 14443 (MIFARE/NTAG), 15693 and FeliCa cards.
        pollingOptions: {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
          NfcPollingOption.iso18092,
        },
        onDiscovered: (NfcTag tag) async {
          if (completer.isCompleted) return;

          final id = NfcTagAndroid.from(tag)?.id;
          if (id == null || id.isEmpty) {
            completer.completeError(
              const NfcFailure('This card has no readable ID. Try another card.'),
            );
            return;
          }

          completer.complete(_toHex(id));
        },
      );
    } catch (e) {
      await _stop();
      throw NfcFailure('Could not start the NFC reader: $e');
    }

    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () => throw const NfcFailure('No card was tapped. Try again.'),
      );
    } finally {
      await _stop();
    }
  }

  /// Cancels an in-flight read (used when staff back out of a scan).
  Future<void> cancel() => _stop();

  Future<void> _stop() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {
      // Stopping an already-stopped session is not an error worth surfacing.
    }
  }

  static String _toHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
}
