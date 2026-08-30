import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Creates and retains an opaque installation identifier in secure storage.
/// This is not a hardware identifier and changes when secure app data is erased.
final class SecureDeviceIdentity {
  const SecureDeviceIdentity(
      {FlutterSecureStorage storage = const FlutterSecureStorage(),
      this.storageKey = 'flutter_licensing.device_id'})
      : _storage = storage;

  final FlutterSecureStorage _storage;
  final String storageKey;

  Future<String> getOrCreate() async {
    final stored = await _storage.read(key: storageKey);
    if (stored != null && stored.isNotEmpty) return stored;
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final created = base64UrlEncode(bytes).replaceAll('=', '');
    await _storage.write(key: storageKey, value: created);
    return created;
  }

  Future<String> hash() async {
    final digest = await Sha256().hash(utf8.encode(await getOrCreate()));
    return digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
