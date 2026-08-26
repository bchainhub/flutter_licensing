import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_licensing/flutter_licensing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Ed25519 algorithm;
  late SimpleKeyPair keyPair;
  late LicenseVerifier verifier;
  final now = DateTime.utc(2026, 8, 26);

  setUp(() async {
    algorithm = Ed25519();
    keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final keys = LicenseKeyRegistry()
      ..addBytes(keyId: 'license-2026-01', publicKey: publicKey.bytes);
    verifier = LicenseVerifier(
      keyRegistry: keys,
      productIdentifierProvider:
          const FixedProductIdentifierProvider('com.application.app'),
      clock: TrustedClock(
          storage: InMemoryTrustedTimeStorage(), systemNow: () => now),
    );
  });

  Future<String> certificate(
      {String product = 'com.application.app',
      int planId = 67,
      DateTime? expires}) async {
    final payload = utf8.encode(jsonEncode({
      'v': 1,
      'id': 'cb_test',
      'license_id': 'lic_test',
      'product': product,
      'planId': planId,
      'issued_at':
          now.subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000,
      'not_before':
          now.subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000,
      'expires_at': (expires ?? now.add(const Duration(days: 30)))
              .millisecondsSinceEpoch ~/
          1000,
      'key_id': 'license-2026-01',
    }));
    final signature = await algorithm.sign(payload, keyPair: keyPair);
    return jsonEncode({
      'payload': base64UrlEncode(payload).replaceAll('=', ''),
      'signature': base64UrlEncode(signature.bytes).replaceAll('=', '')
    });
  }

  test('verifies the original signed payload and arbitrary plan ID', () async {
    final result = await verifier.verify(await certificate(planId: 9001));
    expect(result.status, LicenseValidationStatus.valid);
    expect(result.license!.planId, 9001);
  });

  test('distinguishes product mismatch and expiration', () async {
    expect(
        (await verifier.verify(await certificate(product: 'com.other'))).status,
        LicenseValidationStatus.invalidProduct);
    expect((await verifier.verify(await certificate(expires: now))).status,
        LicenseValidationStatus.expired);
  });

  test('rejects tampering and unknown keys', () async {
    final valid = jsonDecode(await certificate()) as Map<String, dynamic>;
    valid['signature'] = '${valid['signature']}'.replaceFirst(RegExp('.'), 'A');
    expect((await verifier.verify(jsonEncode(valid))).isValid, isFalse);
  });

  test('free feature works without a license', () async {
    const basic = LicenseFeature('basic');
    final entitlements = FeatureEntitlements()..allowWithoutLicense(basic);
    final licensing = FlutterLicensing(
        verifier: verifier,
        storage: InMemoryLicenseStorage(),
        entitlements: entitlements);
    expect((await licensing.checkFeature(basic)).status,
        LicenseAccessStatus.allowed);
  });

  test('trusted clock never moves backwards', () async {
    final storage = InMemoryTrustedTimeStorage();
    var system = now;
    final clock = TrustedClock(storage: storage, systemNow: () => system);
    expect(await clock.now(), now);
    system = now.subtract(const Duration(days: 10));
    expect(await clock.now(), now);
  });
}
