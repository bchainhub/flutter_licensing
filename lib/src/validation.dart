import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'clock.dart';
import 'key_registry.dart';
import 'license.dart';
import 'product_identifier.dart';

/// Describes the outcome of validating a license certificate.
enum LicenseValidationStatus {
  valid,
  malformed,
  unsupportedVersion,
  unknownKey,
  invalidSignature,
  invalidProduct,
  idMismatch,
  deviceIdMismatch,
  @Deprecated('Use idMismatch')
  coreIdMismatch,
  notYetValid,
  expired
}

/// Contains a validation status and the decoded license when available.
final class LicenseValidationResult {
  const LicenseValidationResult(this.status, {this.license});
  final LicenseValidationStatus status;
  final License? license;
  bool get isValid => status == LicenseValidationStatus.valid;
  bool get isExpired => status == LicenseValidationStatus.expired;
  DateTime? get expiresAt => license?.expiresAt;
  Duration? remaining(DateTime now) => license == null || !isValid
      ? null
      : license!.expiresAt.difference(now.toUtc());
}

/// Verifies signed license certificates against trusted keys and application data.
final class LicenseVerifier {
  LicenseVerifier(
      {required LicenseKeyRegistry keyRegistry,
      required ProductIdentifierProvider productIdentifierProvider,
      required TrustedClock clock})
      : _keys = keyRegistry,
        _product = productIdentifierProvider,
        _clock = clock;
  final LicenseKeyRegistry _keys;
  final ProductIdentifierProvider _product;
  final TrustedClock _clock;
  final Ed25519 _ed25519 = Ed25519();

  Future<LicenseValidationResult> verify(String certificate,
      {String? expectedId,
      String? expectedDeviceId,
      @Deprecated('Use expectedId') String? expectedCoreId}) async {
    try {
      final envelope = jsonDecode(certificate);
      if (envelope is! Map<String, dynamic> ||
          envelope.keys.any((k) => k != 'payload' && k != 'signature')) {
        return const LicenseValidationResult(LicenseValidationStatus.malformed);
      }
      final payloadText = envelope['payload'];
      final signatureText = envelope['signature'];
      if (payloadText is! String || signatureText is! String) {
        return const LicenseValidationResult(LicenseValidationStatus.malformed);
      }
      final payloadBytes = base64Url.decode(base64Url.normalize(payloadText));
      final signatureBytes =
          base64Url.decode(base64Url.normalize(signatureText));
      if (signatureBytes.length != 64 || payloadBytes.length > 16384) {
        return const LicenseValidationResult(LicenseValidationStatus.malformed);
      }
      final untrusted = jsonDecode(utf8.decode(payloadBytes));
      if (untrusted is! Map<String, dynamic> ||
          untrusted['key_id'] is! String) {
        return const LicenseValidationResult(LicenseValidationStatus.malformed);
      }
      final keyBytes = _keys.keyFor(untrusted['key_id'] as String);
      if (keyBytes == null) {
        return const LicenseValidationResult(
            LicenseValidationStatus.unknownKey);
      }
      final verified = await _ed25519.verify(payloadBytes,
          signature: Signature(signatureBytes,
              publicKey: SimplePublicKey(keyBytes, type: KeyPairType.ed25519)));
      if (!verified) {
        return const LicenseValidationResult(
            LicenseValidationStatus.invalidSignature);
      }
      final parsed = _parseTrusted(untrusted);
      if (parsed == null) {
        return const LicenseValidationResult(LicenseValidationStatus.malformed);
      }
      if (parsed.version != 1) {
        return LicenseValidationResult(
            LicenseValidationStatus.unsupportedVersion,
            license: parsed);
      }
      final currentProduct = await _product.getProductIdentifier();
      if (currentProduct.isEmpty || parsed.product != currentProduct) {
        return LicenseValidationResult(LicenseValidationStatus.invalidProduct,
            license: parsed);
      }
      final requiredId = expectedId ?? expectedCoreId;
      if (requiredId != null && parsed.id != requiredId) {
        return LicenseValidationResult(
            expectedId != null
                ? LicenseValidationStatus.idMismatch
                : LicenseValidationStatus.coreIdMismatch,
            license: parsed);
      }
      if (expectedDeviceId != null &&
          parsed.deviceIdHash != await _hashDeviceId(expectedDeviceId)) {
        return LicenseValidationResult(LicenseValidationStatus.deviceIdMismatch,
            license: parsed);
      }
      final now = await _clock.now();
      if (now.isBefore(parsed.notBefore)) {
        return LicenseValidationResult(LicenseValidationStatus.notYetValid,
            license: parsed);
      }
      if (!now.isBefore(parsed.expiresAt)) {
        return LicenseValidationResult(LicenseValidationStatus.expired,
            license: parsed);
      }
      return LicenseValidationResult(LicenseValidationStatus.valid,
          license: parsed);
    } on Object {
      return const LicenseValidationResult(LicenseValidationStatus.malformed);
    }
  }

  License? _parseTrusted(Map<String, dynamic> value) {
    const required = {
      'v',
      'license_id',
      'product',
      'planId',
      'issued_at',
      'not_before',
      'expires_at',
      'key_id'
    };
    const allowed = {...required, 'id', 'device_id_hash'};
    if (value.keys.toSet().difference(allowed).isNotEmpty ||
        required.difference(value.keys.toSet()).isNotEmpty) {
      return null;
    }
    final v = value['v'],
        core = value['id'],
        id = value['license_id'],
        product = value['product'],
        plan = value['planId'],
        issued = value['issued_at'],
        notBefore = value['not_before'],
        expires = value['expires_at'],
        key = value['key_id'];
    final deviceHash = value['device_id_hash'];
    if (v is! int ||
        plan is! int ||
        plan < 0 ||
        issued is! int ||
        notBefore is! int ||
        expires is! int ||
        (core != null && !_validString(core, 256)) ||
        !_validString(id, 256) ||
        !_validString(product, 255) ||
        !_validString(key, 128) ||
        (deviceHash != null &&
            (deviceHash is! String ||
                !RegExp(r'^[a-f0-9]{64}$').hasMatch(deviceHash))) ||
        (core == null && deviceHash == null) ||
        issued < 0 ||
        notBefore < 0 ||
        expires < 0 ||
        issued > expires ||
        notBefore > expires) {
      return null;
    }
    try {
      return License(
          version: v,
          coreId: core as String?,
          licenseId: id as String,
          product: product as String,
          planId: plan,
          issuedAt:
              DateTime.fromMillisecondsSinceEpoch(issued * 1000, isUtc: true),
          notBefore: DateTime.fromMillisecondsSinceEpoch(notBefore * 1000,
              isUtc: true),
          expiresAt:
              DateTime.fromMillisecondsSinceEpoch(expires * 1000, isUtc: true),
          keyId: key as String,
          deviceIdHash: deviceHash as String?);
    } on RangeError {
      return null;
    }
  }

  bool _validString(Object? value, int max) =>
      value is String && value.isNotEmpty && value.length <= max;

  Future<String> _hashDeviceId(String value) async {
    final digest = await Sha256().hash(utf8.encode(value));
    return digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
