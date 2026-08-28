import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the last observed trusted UTC time.
abstract interface class TrustedTimeStorage {
  Future<DateTime?> readLastTrustedTime();
  Future<void> writeLastTrustedTime(DateTime value);
}

/// Stores trusted time in platform-protected secure storage.
final class SecureTrustedTimeStorage implements TrustedTimeStorage {
  const SecureTrustedTimeStorage({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
    this.storageKey = 'flutter_licensing.last_trusted_time',
  }) : _storage = storage;

  final FlutterSecureStorage _storage;
  final String storageKey;

  @override
  Future<DateTime?> readLastTrustedTime() async {
    final value = await _storage.read(key: storageKey);
    final microseconds = value == null ? null : int.tryParse(value);
    return microseconds == null
        ? null
        : DateTime.fromMicrosecondsSinceEpoch(microseconds, isUtc: true);
  }

  @override
  Future<void> writeLastTrustedTime(DateTime value) => _storage.write(
        key: storageKey,
        value: value.toUtc().microsecondsSinceEpoch.toString(),
      );
}

/// Stores trusted time in memory for tests and ephemeral sessions.
final class InMemoryTrustedTimeStorage implements TrustedTimeStorage {
  DateTime? _value;
  @override
  Future<DateTime?> readLastTrustedTime() async => _value;
  @override
  Future<void> writeLastTrustedTime(DateTime value) async =>
      _value = value.toUtc();
}

/// Prevents local clock rollback by retaining the latest trusted time.
final class TrustedClock {
  TrustedClock(
      {required TrustedTimeStorage storage, DateTime Function()? systemNow})
      : _storage = storage,
        _systemNow = systemNow ?? DateTime.now;
  final TrustedTimeStorage _storage;
  final DateTime Function() _systemNow;
  Future<DateTime> now() async {
    final system = _systemNow().toUtc();
    final stored = await _storage.readLastTrustedTime();
    final effective =
        stored != null && stored.isAfter(system) ? stored.toUtc() : system;
    await _storage.writeLastTrustedTime(effective);
    return effective;
  }

  Future<void> updateFromTrustedSource(DateTime timestamp) async {
    final candidate = timestamp.toUtc();
    final current = await _storage.readLastTrustedTime();
    if (current == null || candidate.isAfter(current)) {
      await _storage.writeLastTrustedTime(candidate);
    }
  }
}
