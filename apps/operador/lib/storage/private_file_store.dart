import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Owns only private paths and byte writes; it does not know SQLite or the UI.
class PrivateFileStore {
  PrivateFileStore(this.root);
  final Directory root;

  File file(String relative) {
    if (relative.isEmpty ||
        p.isAbsolute(relative) ||
        relative.contains('\\') ||
        relative.split('/').any((part) => part == '..' || part.isEmpty) ||
        !['media', 'artifacts'].contains(relative.split('/').first)) {
      throw const FormatException('Ruta de archivo inválida.');
    }
    return File(p.join(root.path, relative));
  }

  Future<void> writeAtomic(String relative, List<int> bytes) async {
    final target = file(relative);
    await target.parent.create(recursive: true);
    final temp = File('${target.path}.${const Uuid().v4()}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(target.path);
  }
}
