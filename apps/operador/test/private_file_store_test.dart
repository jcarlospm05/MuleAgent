import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:operador/storage/private_file_store.dart';

void main() {
  late Directory root;
  late PrivateFileStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('mule_private_store_');
    store = PrivateFileStore(root);
  });
  tearDown(() async => root.delete(recursive: true));

  test('rejects paths outside the private media and artifacts namespaces', () {
    for (final path in [
      '',
      '/tmp/report.mule',
      '../report.mule',
      'artifacts/../report.mule',
      r'media\photo.jpg',
      'settings/key',
      'media//photo.jpg',
      'artifacts/',
    ]) {
      expect(() => store.file(path), throwsFormatException, reason: path);
    }
  });

  test(
    'preserves original bytes and replaces only the requested file',
    () async {
      const original = [0, 255, 1, 2, 3, 127];
      await store.writeAtomic('media/original.jpg', original);
      await store.writeAtomic('artifacts/revision/entrada.mule', [8, 9]);
      await store.writeAtomic('artifacts/revision/entrada.mule', [10, 11]);
      expect(await store.file('media/original.jpg').readAsBytes(), original);
      expect(
        await store.file('artifacts/revision/entrada.mule').readAsBytes(),
        [10, 11],
      );
      final files = await root
          .list(recursive: true)
          .where((f) => f is File)
          .toList();
      expect(files, hasLength(2));
      expect(files.where((f) => f.path.endsWith('.tmp')), isEmpty);
    },
  );
}
