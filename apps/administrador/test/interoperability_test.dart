import 'dart:convert';
import 'dart:io';
import 'package:admin_data/admin_data.dart';
import 'package:administrador/main.dart';
import 'package:administrador/services.dart';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:mule_data/mule_data.dart';
import 'package:operador/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LocalServices extends OperatorServices {
  LocalServices(super.repo, super.root);
  @override
  Future<String> password() async => 'muleagent-test-key-123';
  @override
  Future<bool> configured() async => true;
}

Future<Database> database({bool admin = false}) =>
    databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        version: 1,
        onConfigure: configureDatabase,
        onCreate: (db, _) async {
          await createSchema(db, schemaVersion);
          if (admin) await createAdminSchema(db);
        },
      ),
    );
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
    'imports a real encrypted Operator packet, keeps originals and exports PDF and Excel with images',
    () async {
      final source = await database(), target = await database(admin: true);
      final sourceDir = await Directory.systemTemp.createTemp(
            'operator_source_',
          ),
          targetDir = await Directory.systemTemp.createTemp('admin_target_');
      try {
        final origin = CaptureRepository(source, deviceId: 'operator-test')
          ..operatorName = 'Julio';
        final sourceStorage = LocalServices(origin, sourceDir);
        final own = CaptureRepository(target, deviceId: 'admin-test')
          ..operatorName = 'Carlos';
        final repo = AdminRepository(
          target,
          device: 'admin-test',
          actor: 'Carlos',
        );
        final storage = LocalServices(own, targetDir),
            service = AdminServices(repo, own, LocalServices(own, targetDir));
        final session = await origin.start(Stage.entry, '2026-11-07');
        await origin.addTicket(session);
        const values = ['Julio', '000362', '=1+1', '07:04', '111410.7'];
        for (var i = 0; i < values.length; i++) {
          final draft = (await origin.draft(session))!;
          await origin.saveValue(draft, values[i]);
          await origin.move(draft, i + 1);
        }
        final picture = image.encodePng(image.Image(width: 16, height: 16));
        final original = File('${sourceDir.path}/photo.png');
        await original.writeAsBytes(picture);
        await sourceStorage.attachImage(
          (await origin.draft(session))!,
          XFile(original.path),
          'gallery',
        );
        await origin.complete(session, (await origin.draft(session))!);
        await origin.closeRevision(session);
        final artifacts = await sourceStorage.ensureArtifacts(session);
        final packet = await sourceStorage
            .file(artifacts['package_path'] as String)
            .readAsBytes();
        final first = await service.importBytes(
          packet,
          await sourceStorage.password(),
        );
        expect(first.result.duplicate, false);
        expect(
          (await service.importBytes(
            packet,
            await sourceStorage.password(),
          )).result.duplicate,
          true,
        );
        final rows = await repo.tickets('2026-11-07');
        expect(rows, hasLength(1));
        expect(rows.single['code'], '000362');
        expect(
          await storage.file(rows.single['photo_path'] as String).readAsBytes(),
          picture,
        );
        final r = await repo.revision(session.id);
        expect(
          await storage.file(r['pdf_path'] as String).readAsBytes(),
          await sourceStorage
              .file(artifacts['pdf_path'] as String)
              .readAsBytes(),
        );
        final generated = await service.pdf('2026-11-07', 'all');
        expect(ascii.decode(generated.take(4).toList()), '%PDF');
        final excelBytes = await service.excel('2026-11-07', 'all');
        Directory('build/test_exports').createSync(recursive: true);
        File(
          'build/test_exports/administrador.xlsx',
        ).writeAsBytesSync(excelBytes);
        final workbook = ZipDecoder().decodeBytes(excelBytes);
        expect(workbook.files.any((f) => f.name.startsWith('xl/media/')), true);
        final sheet = utf8.decode(
          workbook.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
        );
        expect(sheet.contains('=1+1'), true);
        expect(sheet.contains('<f>'), false);
        expect(sheet.contains('inlineStr'), true);
        await expectLater(
          service.importBytes(packet, 'wrong-password-123'),
          throwsA(anything),
        );
        expect(await repo.reports(), hasLength(1));
        final backup = await service.backupPayload();
        final restoredDb = await database(admin: true);
        final restoredDir = await Directory.systemTemp.createTemp(
          'admin_restore_',
        );
        try {
          final restoredCapture = CaptureRepository(
            restoredDb,
            deviceId: 'restored',
          );
          final restoredRepo = AdminRepository(
            restoredDb,
            device: 'restored',
            actor: 'Restored admin',
          );
          final restoredService = AdminServices(
            restoredRepo,
            restoredCapture,
            LocalServices(restoredCapture, restoredDir),
          );
          await restoredService.restorePayload(backup);
          final restoredRows = await restoredRepo.tickets('2026-11-07');
          expect(restoredRows, hasLength(1));
          expect(
            await restoredService.storage
                .file(restoredRows.single['photo_path'] as String)
                .readAsBytes(),
            picture,
          );
        } finally {
          await restoredDb.close();
          await restoredDir.delete(recursive: true);
        }
      } finally {
        await source.close();
        await target.close();
        await sourceDir.delete(recursive: true);
        await targetDir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  testWidgets(
    'administrator menu uses large icon buttons and opens receive flow',
    (tester) async {
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('admin_ui_'),
      ))!;
      final db = (await tester.runAsync(() => database(admin: true)))!;
      addTearDown(
        () => tester.runAsync(() async {
          await db.close();
          await dir.delete(recursive: true);
        }),
      );
      final capture = CaptureRepository(db, deviceId: 'admin-ui')
        ..operatorName = 'Carlos';
      final repo = AdminRepository(db, device: 'admin-ui', actor: 'Carlos');
      final services = AdminServices(
        repo,
        capture,
        LocalServices(capture, dir),
      );
      await tester.pumpWidget(
        AdministratorApp(bundle: AdminBundle(capture, repo, services)),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(find.text('Administrador'), findsWidgets);
      expect(find.text('MuleAgent'), findsOneWidget);
      final receive = find.text('Recibir reporte del Operador');
      expect(
        tester
            .getSize(
              find.ancestor(of: receive, matching: find.byType(FilledButton)),
            )
            .height,
        greaterThanOrEqualTo(88),
      );
      await tester.tap(receive);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(find.text('Elegir archivo e importar'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      await tester.tap(find.text('Atrás'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      await tester.ensureVisible(find.text('Captura propia'));
      await tester.tap(find.text('Captura propia'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(find.text('Captura propia · Administrador'), findsOneWidget);
      expect(find.text('Entrada de mulas'), findsOneWidget);
      await tester.ensureVisible(find.text('Volver al Administrador'));
      await tester.tap(find.text('Volver al Administrador'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
