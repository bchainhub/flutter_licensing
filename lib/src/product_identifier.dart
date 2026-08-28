import 'package:package_info_plus_platform_interface/package_info_platform_interface.dart';

/// Supplies the product identifier expected in a license certificate.
abstract interface class ProductIdentifierProvider {
  Future<String> getProductIdentifier();
}

/// Reads the current application identifier from platform package metadata.
final class PackageInfoProductIdentifierProvider
    implements ProductIdentifierProvider {
  const PackageInfoProductIdentifierProvider();
  @override
  Future<String> getProductIdentifier() async =>
      (await PackageInfoPlatform.instance.getAll()).packageName;
}

/// Returns a fixed product identifier, typically for tests or custom setups.
final class FixedProductIdentifierProvider
    implements ProductIdentifierProvider {
  const FixedProductIdentifierProvider(this.productIdentifier);
  final String productIdentifier;
  @override
  Future<String> getProductIdentifier() async => productIdentifier;
}
