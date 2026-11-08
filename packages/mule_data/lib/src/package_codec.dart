import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Authenticated, versioned interchange. Shared password never enters SQLite.
class PackageCodec {
  static const maxBytes = 150 * 1024 * 1024;
  static const iterations = 210000;
  final _cipher = AesGcm.with256bits();
  Future<SecretKey> _key(String password, List<int> salt) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

  Future<Uint8List> encode(Map<String, dynamic> data, String password) async {
    if (password.length < 12) {
      throw ArgumentError('La clave debe tener al menos 12 caracteres.');
    }
    final plain = utf8.encode(jsonEncode(data));
    if (plain.length > maxBytes) {
      throw StateError(
        'El archivo supera el límite de 150 MB. Exporta menos jornadas.',
      );
    }
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final box = await _cipher.encrypt(
      gzip.encode(plain),
      secretKey: await _key(password, salt),
      aad: utf8.encode('MuleAgent:1'),
    );
    final envelope = {
      'format': 'MuleAgent',
      'version': 1,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  Future<Map<String, dynamic>> decode(List<int> bytes, String password) async {
    if (bytes.length > maxBytes * 2) {
      throw const FormatException('Archivo demasiado grande.');
    }
    final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (envelope['format'] != 'MuleAgent' ||
        envelope['version'] != 1 ||
        envelope['kdf'] != 'PBKDF2-HMAC-SHA256' ||
        envelope['iterations'] != iterations) {
      throw const FormatException('Versión de archivo incompatible.');
    }
    final salt = base64Decode(envelope['salt'] as String);
    final nonce = base64Decode(envelope['nonce'] as String);
    final mac = base64Decode(envelope['mac'] as String);
    if (salt.length != 16 || nonce.length != 12 || mac.length != 16) {
      throw const FormatException('Archivo inválido.');
    }
    final compressed = await _cipher.decrypt(
      SecretBox(
        base64Decode(envelope['ciphertext'] as String),
        nonce: nonce,
        mac: Mac(mac),
      ),
      secretKey: await _key(password, salt),
      aad: utf8.encode('MuleAgent:1'),
    );
    final output = BytesBuilder();
    await for (final part in gzip.decoder.bind(
      Stream<List<int>>.value(compressed),
    )) {
      if (output.length + part.length > maxBytes) {
        throw const FormatException('Contenido demasiado grande.');
      }
      output.add(part);
    }
    final data =
        jsonDecode(utf8.decode(output.takeBytes())) as Map<String, dynamic>;
    if (data['schema'] != schemaContract ||
        !['backup', 'report'].contains(data['kind'])) {
      throw const FormatException('Contenido incompatible.');
    }
    return data;
  }

  static const schemaContract = 1;
}
