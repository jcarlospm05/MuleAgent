import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'private_file_store.dart';

/// Builds the existing attachment manifest without knowing capture state or UI.
class PayloadFiles {
  PayloadFiles(this.store);
  final PrivateFileStore store;

  Future<Map<String, dynamic>> includeFiles(
    Map<String, dynamic> snapshot, {
    List<String> extra = const [],
  }) async {
    final payload = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
    final tables = payload['tables'] as Map<String, dynamic>;
    final paths = <String>{...extra};
    for (final e in tables['evidence'] as List<dynamic>) {
      if (e['state'] == 'photo') paths.add(e['private_path'] as String);
    }
    for (final a in tables['artifacts'] as List<dynamic>? ?? []) {
      paths.add(a['pdf_path'] as String);
      paths.add(a['package_path'] as String);
    }
    var total = 0;
    final files = <String, dynamic>{};
    for (final path in paths) {
      final source = store.file(path);
      if (!await source.exists()) {
        throw StateError(
          'Falta una foto o archivo original. No se generó un respaldo incompleto.',
        );
      }
      total += await source.length();
      if (total > 100 * 1024 * 1024) {
        throw StateError(
          'El conjunto supera 100 MB de archivos. Conserva los reportes individuales y divide el respaldo antes de continuar.',
        );
      }
      final bytes = await source.readAsBytes();
      files[path] = {
        'bytes': base64Encode(bytes),
        'sha256': sha256.convert(bytes).toString(),
      };
    }
    payload['files'] = files;
    return payload;
  }
}
