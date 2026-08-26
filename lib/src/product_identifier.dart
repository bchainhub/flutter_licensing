import 'package:package_info_plus/package_info_plus.dart';

abstract interface class ProductIdentifierProvider {
  Future<String> getProductIdentifier();
}

final class PackageInfoProductIdentifierProvider
    implements ProductIdentifierProvider {
  const PackageInfoProductIdentifierProvider();
  @override
  Future<String> getProductIdentifier() async =>
      (await PackageInfo.fromPlatform()).packageName;
}

final class FixedProductIdentifierProvider
    implements ProductIdentifierProvider {
  const FixedProductIdentifierProvider(this.productIdentifier);
  final String productIdentifier;
  @override
  Future<String> getProductIdentifier() async => productIdentifier;
}
