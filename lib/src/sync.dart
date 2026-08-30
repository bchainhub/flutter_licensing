import 'dart:convert';
import 'package:http/http.dart' as http;

enum LicenseSyncStatus { valid, none, suspended }

final class LicenseSyncPayload {
  const LicenseSyncPayload({required this.status, required this.certificates});
  final LicenseSyncStatus status;
  final List<String> certificates;
}

/// Downloads active certificates from an AtomCyou project.
/// Certificates remain untrusted until [FlutterLicensing.sync] verifies them.
final class AtomCyouSyncClient {
  AtomCyouSyncClient(
      {required this.baseUri, required this.project, http.Client? client})
      : _client = client ?? http.Client();

  final Uri baseUri;
  final String project;
  final http.Client _client;

  Future<LicenseSyncPayload> download(String customerId) async {
    final uri = baseUri.resolve(
        '/api/v1/${Uri.encodeComponent(project)}/sync/${Uri.encodeComponent(customerId)}');
    final response =
        await _client.get(uri, headers: const {'accept': 'application/json'});
    if (response.statusCode != 200 && response.statusCode != 402) {
      throw LicenseSyncException(
          'AtomCyou returned HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> ||
        decoded['status'] is! String ||
        decoded['licenses'] is! List) {
      throw const LicenseSyncException('Invalid AtomCyou sync response');
    }
    final status = switch (decoded['status']) {
      'valid' => LicenseSyncStatus.valid,
      'none' => LicenseSyncStatus.none,
      'suspended' => LicenseSyncStatus.suspended,
      _ => throw const LicenseSyncException('Unknown AtomCyou sync status')
    };
    final certificates = <String>[];
    for (final item in decoded['licenses'] as List) {
      if (item is! Map<String, dynamic> || item['certificate'] is! String) {
        throw const LicenseSyncException('Invalid certificate entry');
      }
      certificates.add(item['certificate'] as String);
    }
    return LicenseSyncPayload(status: status, certificates: certificates);
  }
}

final class LicenseSyncException implements Exception {
  const LicenseSyncException(this.message);
  final String message;
  @override
  String toString() => 'LicenseSyncException: $message';
}
