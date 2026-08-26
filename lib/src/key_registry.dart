import 'dart:convert';
import 'package:flutter/services.dart';

final class LicenseKeyRegistry {
  final Map<String, Uint8List> _keys = {};
  void add({required String keyId, required String publicKey}) =>
      addBytes(keyId: keyId, publicKey: _decode(publicKey));
  void addBytes({required String keyId, required List<int> publicKey}) {
    _validateKeyId(keyId);
    if (publicKey.length != 32) {
      throw ArgumentError.value(
          publicKey.length, 'publicKey', 'Ed25519 keys must be 32 bytes');
    }
    _keys[keyId] = Uint8List.fromList(publicKey);
  }

  /// Loads `<assetDirectory>/<keyId>.pub`, e.g. `license-2026-01.pub`.
  Future<void> addAsset(String keyId,
      {String assetDirectory = 'assets/license_keys',
      AssetBundle? bundle}) async {
    _validateKeyId(keyId);
    final value =
        await (bundle ?? rootBundle).loadString('$assetDirectory/$keyId.pub');
    add(keyId: keyId, publicKey: value);
  }

  void remove(String keyId) => _keys.remove(keyId);
  bool has(String keyId) => _keys.containsKey(keyId);
  List<String> get keyIds => List.unmodifiable(_keys.keys);
  Uint8List? keyFor(String keyId) =>
      _keys[keyId] == null ? null : Uint8List.fromList(_keys[keyId]!);
  static Uint8List _decode(String encoded) {
    var value = encoded.trim();
    if (value.startsWith('-----BEGIN PUBLIC KEY-----')) {
      value = value
          .replaceAll('-----BEGIN PUBLIC KEY-----', '')
          .replaceAll('-----END PUBLIC KEY-----', '')
          .replaceAll(RegExp(r'\s'), '');
      final der = base64.decode(value);
      const prefix = <int>[
        0x30,
        0x2a,
        0x30,
        0x05,
        0x06,
        0x03,
        0x2b,
        0x65,
        0x70,
        0x03,
        0x21,
        0x00
      ];
      if (der.length != prefix.length + 32 ||
          !List.generate(prefix.length, (i) => der[i] == prefix[i])
              .every((v) => v)) {
        throw const FormatException('Invalid Ed25519 public-key PEM');
      }
      return Uint8List.fromList(der.sublist(prefix.length));
    }
    return Uint8List.fromList(base64Url
        .decode(base64Url.normalize(value.replaceAll(RegExp(r'\s'), ''))));
  }

  static void _validateKeyId(String keyId) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$').hasMatch(keyId)) {
      throw ArgumentError.value(keyId, 'keyId', 'Invalid key identifier');
    }
  }
}
