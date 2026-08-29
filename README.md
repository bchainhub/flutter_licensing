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
);
await licensing.initialize();
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
- Optional `expectedCoreId` prevents sharing between identities.
- Import validates before storage. Same-plan certificates extend only when their expiration is later.
- `LicenseModel.separate` (the default) keeps a current license when a different plan is imported.
- `LicenseModel.replace` immediately replaces a different plan. A higher plan ID is an upgrade and a lower plan ID is a downgrade; both behave identically during import.
- Time is UTC and valid in `[not_before, expires_at)`. `TrustedClock` provides rollback resistance only as a best effort; a permanently offline, attacker-controlled client cannot establish trustworthy wall-clock time.

`SecureTrustedTimeStorage` persists the clock lower bound using platform secure storage. The included in-memory implementation is intended for tests.

## Security

Do not log certificates, signatures, public-key configuration, or Core IDs. Report vulnerabilities privately through [GitHub Security Advisories](https://github.com/bchainhub/flutter_licensing/security/advisories/new).

## License

[CORE License](LICENSE). Source-form distributions, modifications, and contributions must remain publicly available.
