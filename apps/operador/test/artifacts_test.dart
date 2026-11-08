import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as image_codec;
import 'package:mule_data/mule_data.dart';
import 'package:operador/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TestServices extends OperatorServices {
  TestServices(super.repo, super.root);
  @override
  Future<String> password() async => 'clave-de-prueba-123';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
    'PDF and encrypted daily package preserve evidence; retry uses exact original files',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: schemaVersion,
          onConfigure: configureDatabase,
          onCreate: createSchema,
        ),
      );
      final root = await Directory.systemTemp.createTemp('mule_artifacts_');
      try {
        final repo = CaptureRepository(db, deviceId: 'test')
          ..operatorName = 'Julio';
        final services = TestServices(repo, root);
        final session = await repo.start(Stage.entry, '2026-11-07');
        await repo.addTicket(session);
        const values = [
          'Julio',
          '000362',
          'Proveedor A',
          '07:04',
          '111410.7',
          'No se dispone de foto',
        ];
        for (var i = 0; i < values.length; i++) {
          final draft = (await repo.draft(session))!;
          await repo.saveValue(draft, values[i]);
          if (i < values.length - 1) await repo.move(draft, i + 1);
        }
        await repo.complete(session, (await repo.draft(session))!);
        await repo.closeRevision(session);
        final first = await services.ensureArtifacts(session);
        final pdf = await services
            .file(first['pdf_path'] as String)
            .readAsBytes();
        expect(ascii.decode(pdf.take(4).toList()), '%PDF');
        final bytes = await services
            .file(first['package_path'] as String)
            .readAsBytes();
        final decoded = await PackageCodec().decode(
          bytes,
          await services.password(),
        );
        expect(decoded['kind'], 'report');
        expect(decoded['tables']['tickets'][0]['code'], '000362');
        expect(decoded['files'].containsKey(first['pdf_path']), isTrue);
        final second = await services.ensureArtifacts(session);
        expect(second, first);
        expect(
          await services.file(second['package_path'] as String).readAsBytes(),
          bytes,
        );
        final backup = await services.includeFiles(await repo.snapshot());
        expect(backup['files'].containsKey(first['package_path']), isTrue);
      } finally {
        await db.close();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'an original photo is attached, embedded in PDF and preserved byte for byte',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: schemaVersion,
          onConfigure: configureDatabase,
          onCreate: createSchema,
        ),
      );
      final root = await Directory.systemTemp.createTemp('mule_photo_');
      try {
        final repo = CaptureRepository(db, deviceId: 'test');
        final services = TestServices(repo, root);
        final session = await repo.start(Stage.exit, '2026-11-07');
        await repo.addTicket(session);
        const values = ['000362', 'Proveedor A', '19:16', '111421.9'];
        for (var i = 0; i < values.length; i++) {
          final draft = (await repo.draft(session))!;
          await repo.saveValue(draft, values[i]);
          await repo.move(draft, i + 1);
        }
        final bytes = image_codec.encodePng(
          image_codec.Image(width: 4, height: 4),
        );
        final original = File('${root.path}/input.png');
        await original.writeAsBytes(bytes);
        await services.attachImage(
          (await repo.draft(session))!,
          XFile(original.path),
          'gallery',
        );
        await repo.complete(session, (await repo.draft(session))!);
        await repo.closeRevision(session);
        final record = await services.ensureArtifacts(session);
        final payload = await PackageCodec().decode(
          await services.file(record['package_path'] as String).readAsBytes(),
          await services.password(),
        );
        final evidence = payload['tables']['evidence'][0];
        expect(
          base64Decode(
            payload['files'][evidence['private_path']]['bytes'] as String,
          ),
          bytes,
        );
        expect(evidence['state'], 'photo');
      } finally {
        await db.close();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
