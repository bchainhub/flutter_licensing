/// Immutable claims extracted from a verified license certificate.
final class License {
  const License(
      {required this.version,
      required this.coreId,
      required this.licenseId,
      required this.product,
      required this.planId,
      required this.issuedAt,
      required this.notBefore,
      required this.expiresAt,
      required this.keyId,
      this.deviceIdHash});
  final int version;
  String get id => coreId;
  @Deprecated('Use id')
  final String coreId;
  final String licenseId;
  final String product;
  final int planId;
  final DateTime issuedAt;
  final DateTime notBefore;
  final DateTime expiresAt;
  final String keyId;
  final String? deviceIdHash;
}
