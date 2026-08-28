import 'validation.dart';

/// Identifies a feature controlled by a license entitlement.
extension type const LicenseFeature(String id) {
  bool get isValid => id.isNotEmpty && id.length <= 128;
}

/// Maps features to free access or permitted plan identifiers.
final class FeatureEntitlements {
  final Set<String> _free = {};
  final Map<String, Set<int>> _plans = {};
  void allowWithoutLicense(LicenseFeature feature) {
    _validate(feature);
    _free.add(feature.id);
  }

  void allowForPlans(LicenseFeature feature, Iterable<int> planIds) {
    _validate(feature);
    if (planIds.any((id) => id < 0)) {
      throw ArgumentError('Plan IDs must be non-negative');
    }
    _plans[feature.id] = Set.unmodifiable(planIds);
  }

  bool isFree(LicenseFeature feature) => _free.contains(feature.id);
  bool permits(LicenseFeature feature, int planId) =>
      _plans[feature.id]?.contains(planId) ?? false;
  void _validate(LicenseFeature feature) {
    if (!feature.isValid) throw ArgumentError.value(feature.id, 'feature');
  }
}

/// Describes why access to a licensed feature was granted or denied.
enum LicenseAccessStatus {
  allowed,
  noLicense,
  expired,
  notYetValid,
  invalidLicense,
  invalidProduct,
  planDoesNotIncludeFeature,
  coreIdMismatch
}

/// Contains a feature-access decision and its optional validation result.
final class LicenseAccessResult {
  const LicenseAccessResult(this.status, {this.validation});
  final LicenseAccessStatus status;
  final LicenseValidationResult? validation;
  bool get isAllowed => status == LicenseAccessStatus.allowed;
}
