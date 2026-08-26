import 'entitlements.dart';
import 'license.dart';
import 'storage.dart';
import 'validation.dart';

enum LicenseReplacementPolicy { newerExpiration, always }

final class FlutterLicensing {
  FlutterLicensing(
      {required LicenseVerifier verifier,
      required LicenseStorage storage,
      FeatureEntitlements? entitlements,
      this.expectedCoreId})
      : _verifier = verifier,
        _storage = storage,
        entitlements = entitlements ?? FeatureEntitlements();
  final LicenseVerifier _verifier;
  final LicenseStorage _storage;
  final FeatureEntitlements entitlements;
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
    return _lastResult =
        await _verifier.verify(_certificate!, expectedCoreId: expectedCoreId);
  }

  Future<LicenseValidationResult> importLicense(String certificate,
      {LicenseReplacementPolicy replacementPolicy =
          LicenseReplacementPolicy.newerExpiration}) async {
    final candidate =
        await _verifier.verify(certificate, expectedCoreId: expectedCoreId);
    if (!candidate.isValid) return candidate;
    if (replacementPolicy == LicenseReplacementPolicy.newerExpiration &&
        _certificate != null) {
      final existing =
          await _verifier.verify(_certificate!, expectedCoreId: expectedCoreId);
      if (existing.isValid) {
        final oldLicense = existing.license!;
        final newLicense = candidate.license!;
        final sameSubscription = oldLicense.coreId == newLicense.coreId &&
            oldLicense.product == newLicense.product &&
            oldLicense.planId == newLicense.planId;
        if (!sameSubscription ||
            !newLicense.expiresAt.isAfter(oldLicense.expiresAt)) {
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
