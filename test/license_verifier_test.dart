import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_licensing/flutter_licensing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
      String? deviceId,
      bool includeCustomerId = true,
      DateTime? expires}) async {
    final payload = utf8.encode(jsonEncode({
      'v': 1,
      if (includeCustomerId) 'id': 'cb_test',
      if (deviceId != null)
        'device_id_hash': (await Sha256().hash(utf8.encode(deviceId)))
            .bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(),
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
    expect(result.license!.id, 'cb_test');
  });

  test('cryptographically binds customer and optional device IDs', () async {
    final encoded = await certificate(deviceId: 'device-123');
    expect((await verifier.verify(encoded, expectedId: 'cb_test')).status,
        LicenseValidationStatus.valid);
    expect((await verifier.verify(encoded, expectedId: 'another-user')).status,
        LicenseValidationStatus.idMismatch);
    expect(
        (await verifier.verify(encoded, expectedDeviceId: 'device-123')).status,
        LicenseValidationStatus.valid);
    expect(
        (await verifier.verify(encoded, expectedDeviceId: 'device-456')).status,
        LicenseValidationStatus.deviceIdMismatch);
  });

  test('distinguishes product mismatch and expiration', () async {
    expect(
        (await verifier.verify(await certificate(product: 'com.other'))).status,
        LicenseValidationStatus.invalidProduct);
    expect((await verifier.verify(await certificate(expires: now))).status,
        LicenseValidationStatus.expired);
  });

  test('accepts an explicit expected product override', () async {
    final encoded = await certificate(product: 'onl.tone.app');
    expect(
      (await verifier.verify(
        encoded,
        expectedId: 'cb_test',
        expectedProduct: 'onl.tone.app',
      ))
          .status,
      LicenseValidationStatus.valid,
    );
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
        entitlements: entitlements,
        expectedId: 'cb_test');
    expect((await licensing.checkFeature(basic)).status,
        LicenseAccessStatus.allowed);
  });

  test('accepts a device-only signed identity', () async {
    final encoded = await certificate(
        deviceId: 'device-only-secret', includeCustomerId: false);
    final result =
        await verifier.verify(encoded, expectedDeviceId: 'device-only-secret');

    expect(result.status, LicenseValidationStatus.valid);
    expect(result.license!.id, isNull);
    expect(result.license!.deviceIdHash, hasLength(64));
  });

  test('requires at least one expected identity', () {
    expect(
        () => FlutterLicensing(
            verifier: verifier, storage: InMemoryLicenseStorage()),
        throwsArgumentError);
  });

  test('sync downloads and validates active licenses before storage', () async {
    final encoded = await certificate(deviceId: 'device-123');
    final client = AtomCyouSyncClient(
        baseUri: Uri.parse('https://atom.cyou'),
        project: 'my-project',
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/my-project/sync/cb_test');
          return http.Response(
              jsonEncode({
                'status': 'valid',
                'licenses': [
                  {'certificate': encoded}
                ]
              }),
              200);
        }));
    final licensing = FlutterLicensing(
        verifier: verifier,
        storage: InMemoryLicenseStorage(),
        expectedId: 'cb_test',
        expectedDeviceId: 'device-123');

    final result = await licensing.sync(client, 'cb_test');

    expect(result.isVerified, isTrue);
    expect(licensing.currentLicense!.deviceIdHash, hasLength(64));
  });

  test('separate licensing keeps a different current plan', () async {
    final storage = InMemoryLicenseStorage();
    final licensing = FlutterLicensing(
        verifier: verifier, storage: storage, expectedId: 'cb_test');
    await licensing.importLicense(await certificate(planId: 1));

    final result = await licensing.importLicense(await certificate(planId: 2));

    expect(result.license!.planId, 1);
    expect(licensing.currentLicense!.planId, 1);
  });

  test('replace licensing immediately upgrades or downgrades', () async {
    final storage = InMemoryLicenseStorage();
    final licensing = FlutterLicensing(
        verifier: verifier, storage: storage, expectedId: 'cb_test');
    await licensing.importLicense(await certificate(planId: 1));

    var result = await licensing.importLicense(await certificate(planId: 2),
        model: LicenseModel.replace);
    expect(result.license!.planId, 2);

    result = await licensing.importLicense(await certificate(planId: 1),
        model: LicenseModel.replace);
    expect(result.license!.planId, 1);
  });

  test('same plan only extends to a later expiration', () async {
    final storage = InMemoryLicenseStorage();
    final licensing = FlutterLicensing(
        verifier: verifier, storage: storage, expectedId: 'cb_test');
    final later = now.add(const Duration(days: 60));
    await licensing.importLicense(await certificate(expires: later));

    final result = await licensing.importLicense(
        await certificate(expires: now.add(const Duration(days: 10))),
        model: LicenseModel.replace);

    expect(result.license!.expiresAt, later);
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
