import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists an encoded license certificate.
abstract interface class LicenseStorage {
  Future<void> saveLicense(String certificate);
  Future<String?> readLicense();
  Future<void> deleteLicense();
  Future<bool> hasLicense();
}

/// Persists a license certificate in platform-protected secure storage.
final class SecureLicenseStorage implements LicenseStorage {
  const SecureLicenseStorage(
      {FlutterSecureStorage storage = const FlutterSecureStorage(),
      this.storageKey = 'flutter_licensing.certificate'})
      : _storage = storage;
  final FlutterSecureStorage _storage;
  final String storageKey;
  @override
  Future<void> saveLicense(String certificate) =>
      _storage.write(key: storageKey, value: certificate);
  @override
  Future<String?> readLicense() => _storage.read(key: storageKey);
  @override
  Future<void> deleteLicense() => _storage.delete(key: storageKey);
  @override
  Future<bool> hasLicense() async => (await readLicense()) != null;
}

/// Keeps a license certificate in memory for tests or ephemeral sessions.
final class InMemoryLicenseStorage implements LicenseStorage {
  String? _certificate;
  @override
  Future<void> saveLicense(String certificate) async =>
      _certificate = certificate;
  @override
  Future<String?> readLicense() async => _certificate;
  @override
  Future<void> deleteLicense() async => _certificate = null;
  @override
  Future<bool> hasLicense() async => _certificate != null;
}
