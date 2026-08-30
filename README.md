# Flutter Licensing

Offline, fail-closed Ed25519 license verification and feature entitlements for Flutter. The backend remains the only issuer; this package contains public keys only and performs no networking or payment processing.

## Certificate

The certificate is JSON containing base64url-encoded `payload` and `signature`. Verification is performed over the original decoded payload bytes. A payload's signed `key_id` selects a preconfigured trust key and can never introduce its own key.

```json
{"payload":"<base64url>","signature":"<base64url>"}
```

## Setup

Add public-key assets to the host application's `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/license_keys/license-2026-01.pub
```

The filename follows the signed key ID: `"key_id": "license-2026-01"` resolves to `assets/license_keys/license-2026-01.pub`.

```dart
final keys = LicenseKeyRegistry();
await keys.addAsset('license-2026-01');

final verifier = LicenseVerifier(
  keyRegistry: keys,
  productIdentifierProvider: const PackageInfoProductIdentifierProvider(),
  clock: TrustedClock(storage: const SecureTrustedTimeStorage()),
);

final rules = FeatureEntitlements()
  ..allowWithoutLicense(const LicenseFeature('basic'))
  ..allowForPlans(const LicenseFeature('export'), [3, 67]);

final licensing = FlutterLicensing(
  verifier: verifier,
  storage: const SecureLicenseStorage(),
  entitlements: rules,
	expectedId: customerId,
	expectedDeviceId: deviceId,
);
await licensing.initialize();
final syncResult = await licensing.sync(
  AtomCyouSyncClient(
    baseUri: Uri.parse('https://atom.cyou'),
    project: 'my-project',
  ),
  customerId,
);
final result = await licensing.importLicense(
  certificateText,
  model: LicenseModel.replace,
);
final allowed = await licensing.isFeatureAllowed(const LicenseFeature('export'));
```

Keys may instead be supplied as 32 raw bytes, base64/base64url, or an RFC 8410 PEM public key. Never download a key from the same untrusted certificate. Changing a configurable public key changes the application's trust root.

## Behavior

- `product` must exactly match the running package/bundle identifier.
- Arbitrary non-negative `planId` values are valid; optional names never affect validity.
- Free features work without a license.
- The signed payload includes the Core/customer identity as `id` and may include `device_id_hash`, a SHA-256 digest of a separate high-entropy installation ID.
- Device-only certificates may omit `id`. Every certificate and every `FlutterLicensing` instance must have at least one customer/Core or device identity.
- `SecureDeviceIdentity` generates a random 256-bit installation ID and retains it in platform secure storage. Send that value as CorePort `deviceid`; AtomCyou stores and returns only its signed hash.
- `expectedId` verifies the owner. `expectedDeviceId` is hashed locally before comparison with `device_id_hash`; it does not replace the owner. Avoid predictable hardware identifiers because an unsalted hash of low-entropy data can be guessed.
- `sync` downloads only active AtomCyou certificates and verifies every certificate before updating secure local storage. Network errors preserve offline state; authoritative `none` and `suspended` responses remove it.
- Device-only apps use `syncByDevice(client, secureDeviceIdentity)`, which places only the device hash—not the raw secret—in the AtomCyou URL.
- Import validates before storage. Same-plan certificates extend only when their expiration is later.
- `LicenseModel.separate` (the default) keeps a current license when a different plan is imported.
- `LicenseModel.replace` immediately replaces a different plan. A higher plan ID is an upgrade and a lower plan ID is a downgrade; both behave identically during import.
- Time is UTC and valid in `[not_before, expires_at)`. `TrustedClock` provides rollback resistance only as a best effort; a permanently offline, attacker-controlled client cannot establish trustworthy wall-clock time.

`SecureTrustedTimeStorage` persists the clock lower bound using platform secure storage. The included in-memory implementation is intended for tests.

## Security

Do not log certificates, signatures, public-key configuration, or Core IDs. Report vulnerabilities privately through [GitHub Security Advisories](https://github.com/bchainhub/flutter_licensing/security/advisories/new).

## License

[CORE License](LICENSE). Source-form distributions, modifications, and contributions must remain publicly available.
