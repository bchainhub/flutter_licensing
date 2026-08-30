import 'device_identity.dart';
import 'entitlements.dart';
import 'license.dart';
import 'storage.dart';
import 'sync.dart';
import 'validation.dart';

/// Controls how an imported license for a different plan is handled.
enum LicenseModel {
  /// Keeps plans separate. A certificate for a different plan is not imported.
  separate,

  /// Immediately replaces the current plan with the imported plan.
  replace,
}

/// Coordinates license storage, validation, and feature entitlement checks.
final class FlutterLicensing {
  FlutterLicensing(
      {required LicenseVerifier verifier,
      required LicenseStorage storage,
      FeatureEntitlements? entitlements,
      this.expectedId,
      this.expectedDeviceId,
      @Deprecated('Use expectedId') this.expectedCoreId})
      : _verifier = verifier,
        _storage = storage,
        entitlements = entitlements ?? FeatureEntitlements() {
    if (expectedId != null &&
        expectedCoreId != null &&
        expectedId != expectedCoreId) {
      throw ArgumentError('expectedId and expectedCoreId must match.');
    }
    if (expectedId == null &&
        expectedCoreId == null &&
        expectedDeviceId == null) {
      throw ArgumentError(
          'At least one customer/Core ID or device ID is required.');
    }
  }
  final LicenseVerifier _verifier;
  final LicenseStorage _storage;
  final FeatureEntitlements entitlements;
  final String? expectedId;
  final String? expectedDeviceId;
  @Deprecated('Use expectedId')
  final String? expectedCoreId;
  String? _certificate;
  LicenseValidationResult? _lastResult;
  License? get currentLicense =>
      _lastResult?.isValid == true ? _lastResult!.license : null;
  Future<void> initialize() => loadLicense();
  Future<LicenseValidationResult> loadLicense() async {
    _certificate = await _storage.readLicense();
    return validateLicense();
  }

  Future<LicenseValidationResult> validateLicense() async {
    if (_certificate == null) {
      return _lastResult =
          const LicenseValidationResult(LicenseValidationStatus.malformed);
    }
    return _lastResult = await _verifier.verify(_certificate!,
        expectedId: expectedId ?? expectedCoreId,
        expectedDeviceId: expectedDeviceId);
  }

  Future<LicenseValidationResult> importLicense(String certificate,
      {LicenseModel model = LicenseModel.separate}) async {
    final candidate = await _verifier.verify(certificate,
        expectedId: expectedId ?? expectedCoreId,
        expectedDeviceId: expectedDeviceId);
    if (!candidate.isValid) return candidate;
    if (_certificate != null) {
      final existing = await _verifier.verify(_certificate!,
          expectedId: expectedId ?? expectedCoreId,
          expectedDeviceId: expectedDeviceId);
      if (existing.isValid) {
        final oldLicense = existing.license!;
        final newLicense = candidate.license!;
        final sameLicense = oldLicense.coreId == newLicense.coreId &&
            oldLicense.product == newLicense.product &&
            oldLicense.planId == newLicense.planId;
        final replacesPlan = model == LicenseModel.replace &&
            oldLicense.coreId == newLicense.coreId &&
            oldLicense.product == newLicense.product &&
            oldLicense.planId != newLicense.planId;
        if ((!sameLicense && !replacesPlan) ||
            (sameLicense &&
                !newLicense.expiresAt.isAfter(oldLicense.expiresAt))) {
          return existing;
        }
      }
    }
    await _storage.saveLicense(certificate);
    _certificate = certificate;
    _lastResult = candidate;
    return candidate;
  }

  String? exportLicense() => _certificate;

  /// Downloads active licenses, verifies every certificate, and stores the
  /// newest verified certificate. A successful `none` or `suspended` response
  /// removes the local certificate; network failures leave offline state intact.
  Future<LicenseSynchronizationResult> sync(
      AtomCyouSyncClient client, String customerId) async {
    final payload = await client.download(customerId);
    if (payload.status != LicenseSyncStatus.valid) {
      await deleteLicense();
      return LicenseSynchronizationResult(payload.status, const []);
    }
    final validations = <LicenseValidationResult>[];
    for (final certificate in payload.certificates) {
      final validation = await _verifier.verify(certificate,
          expectedId: expectedId ?? expectedCoreId,
          expectedDeviceId: expectedDeviceId);
      validations.add(validation);
    }
    if (validations.any((validation) => !validation.isValid)) {
      return LicenseSynchronizationResult(payload.status, validations);
    }
    if (payload.certificates.isNotEmpty) {
      await _storage.saveLicense(payload.certificates.first);
      _certificate = payload.certificates.first;
      _lastResult = validations.first;
    }
    return LicenseSynchronizationResult(payload.status, validations);
  }

  /// Synchronizes a device-only license by hash, keeping the raw installation
  /// secret out of the public request URL.
  Future<LicenseSynchronizationResult> syncByDevice(
      AtomCyouSyncClient client, SecureDeviceIdentity identity) async {
    if (expectedDeviceId == null) {
      throw StateError('expectedDeviceId is required for device sync.');
    }
    return sync(client, await identity.hash());
  }

  Future<bool> hasValidLicense() async => (await validateLicense()).isValid;
  Future<LicenseAccessResult> checkFeature(LicenseFeature feature) async {
    if (entitlements.isFree(feature)) {
      return const LicenseAccessResult(LicenseAccessStatus.allowed);
    }
    if (_certificate == null) {
      return const LicenseAccessResult(LicenseAccessStatus.noLicense);
    }
    final result = await validateLicense();
    if (result.isValid) {
      return LicenseAccessResult(
          entitlements.permits(feature, result.license!.planId)
              ? LicenseAccessStatus.allowed
              : LicenseAccessStatus.planDoesNotIncludeFeature,
          validation: result);
    }
    final status = switch (result.status) {
      LicenseValidationStatus.expired => LicenseAccessStatus.expired,
      LicenseValidationStatus.notYetValid => LicenseAccessStatus.notYetValid,
      LicenseValidationStatus.invalidProduct =>
        LicenseAccessStatus.invalidProduct,
      LicenseValidationStatus.idMismatch => LicenseAccessStatus.coreIdMismatch,
      LicenseValidationStatus.deviceIdMismatch =>
        LicenseAccessStatus.coreIdMismatch,
      LicenseValidationStatus.coreIdMismatch =>
        LicenseAccessStatus.coreIdMismatch,
      _ => LicenseAccessStatus.invalidLicense
    };
    return LicenseAccessResult(status, validation: result);
  }

  Future<bool> isFeatureAllowed(LicenseFeature feature) async =>
      (await checkFeature(feature)).isAllowed;
  Future<void> deleteLicense() async {
    await _storage.deleteLicense();
    _certificate = null;
    _lastResult = null;
  }
}

final class LicenseSynchronizationResult {
  const LicenseSynchronizationResult(this.status, this.validations);
  final LicenseSyncStatus status;
  final List<LicenseValidationResult> validations;
  bool get isVerified =>
      status == LicenseSyncStatus.valid &&
      validations.isNotEmpty &&
      validations.every((validation) => validation.isValid);
}
