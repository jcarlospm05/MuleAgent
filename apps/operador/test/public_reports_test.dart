import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:mule_data/mule_data.dart';
import 'package:operador/public_reports.dart';
import 'package:operador/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class PublicServices extends OperatorServices {
  PublicServices(super.repo, super.root) : super(publicStorageEnabled: true);
  @override
  Future<String> password() async => 'public-copy-test-key-123';
}

Future<CaptureSession> closedExit(
  CaptureRepository repo,
  OperatorServices services,
  Directory dir,
) async {
  final session = await repo.start(Stage.exit, '2026-11-08');
  await repo.addTicket(session);
  for (final value in ['000362', 'Proveedor A', '19:16', '111421.9']) {
    final d = (await repo.draft(session))!;
    await repo.saveValue(d, value);
    await repo.move(d, d.step + 1);
  }
  final original = File('${dir.path}/camera.png');
  await original.writeAsBytes(
    image.encodePng(image.Image(width: 4, height: 4)),
  );
  await services.attachImage(
    (await repo.draft(session))!,
    XFile(original.path),
    'camera',
  );
  await repo.complete(session, (await repo.draft(session))!);
  await repo.closeRevision(session);
  return session;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late Directory dir, downloads;
  late CaptureRepository repo;
  late PublicServices services;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        version: schemaVersion,
        onConfigure: configureDatabase,
        onCreate: createSchema,
      ),
    );
    dir = await Directory.systemTemp.createTemp('public_originals_');
    downloads = await Directory.systemTemp.createTemp('public_downloads_');
    repo = CaptureRepository(db, deviceId: 'public-test-device');
    services = PublicServices(repo, dir);
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(PublicReports.channel, null);
    await db.close();
    await dir.delete(recursive: true);
    await downloads.delete(recursive: true);
  });
  test(
    'public close plan preserves PDF, encrypted packet and original photo; retries retain names and bytes',
    () async {
      final session = await closedExit(repo, services, dir);
      final plans = <Map<String, dynamic>>[];
      messenger.setMockMethodCallHandler(PublicReports.channel, (call) async {
        if (call.method == 'prepare') return null;
        final args = Map<String, dynamic>.from(call.arguments as Map);
        plans.add(args);
        final folder = Directory('${downloads.path}/${args['directory']}');
        await folder.create(recursive: true);
        for (final f in args['files'] as List) {
          final bytes = await File(f['source'] as String).readAsBytes();
          expect(sha256.convert(bytes).toString(), f['sha256']);
          await File('${folder.path}/${f['name']}').writeAsBytes(bytes);
        }
        return {
          'folder': 'Descargas/${args['directory']}',
          'count': (args['files'] as List).length,
        };
      });
      final location = await services.savePublicReport(session);
      expect(location, startsWith('Descargas/MuleAgent/2026-11-08/salida/'));
      expect(await services.publicFolder(session), location);
      expect((plans.single['files'] as List).length, 3);
      final names = (plans.single['files'] as List)
          .map((f) => f['name'] as String)
          .toList();
      expect(
        names.any(
          (n) => n.startsWith('salida_2026-11-08_') && n.endsWith('.pdf'),
        ),
        isTrue,
      );
      expect(names.any((n) => n.endsWith('.mule')), isTrue);
      final photo = names.singleWhere((n) => n.startsWith('foto_000362_'));
      expect(
        await File(
          '${downloads.path}/${plans.single['directory']}/$photo',
        ).readAsBytes(),
        await File('${dir.path}/camera.png').readAsBytes(),
      );
      expect(await services.recoverPublicReports(), 0);
      await services.savePublicReport(session);
      expect(plans[1], plans[0]);
      expect(await services.recoverPublicReports(verifyAll: true), 1);
      expect(plans[2], plans[0]);
    },
  );
  test(
    'failed public write preserves internal files, leaves no success marker and recovers on next launch',
    () async {
      final session = await closedExit(repo, services, dir);
      var fail = true;
      messenger.setMockMethodCallHandler(PublicReports.channel, (call) async {
        if (call.method == 'prepare') return null;
        if (fail) {
          throw PlatformException(
            code: 'disk_full',
            message: 'Sin espacio en Descargas',
          );
        }
        return {
          'folder': 'Descargas/${call.arguments['directory']}',
          'count': (call.arguments['files'] as List).length,
        };
      });
      await expectLater(
        services.savePublicReport(session),
        throwsA(isA<StateError>()),
      );
      expect(await services.publicFolder(session), isNull);
      final saved = await services.ensureArtifacts(session);
      expect(await services.file(saved['pdf_path'] as String).exists(), isTrue);
      expect(
        await services.file(saved['package_path'] as String).exists(),
        isTrue,
      );
      fail = false;
      expect(await services.recoverPublicReports(), 1);
      expect(await services.publicFolder(session), isNotNull);
    },
  );
  test(
    'denied legacy permission still prepares internal closure artifacts before reporting public failure',
    () async {
      final session = await closedExit(repo, services, dir);
      messenger.setMockMethodCallHandler(PublicReports.channel, (_) async {
        throw PlatformException(
          code: 'storage_permission',
          message: 'Permiso denegado',
        );
      });
      await expectLater(
        services.savePublicReport(session),
        throwsA(isA<StateError>()),
      );
      final artifacts = await db.query('artifacts');
      expect(artifacts, hasLength(1));
      expect(
        await services.file(artifacts.single['pdf_path'] as String).exists(),
        isTrue,
      );
      expect(await services.publicFolder(session), isNull);
    },
  );
}
