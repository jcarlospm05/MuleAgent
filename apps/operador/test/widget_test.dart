import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mule_data/mule_data.dart';
import 'package:operador/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  setUpAll(() async {
    const dir = String.fromEnvironment('FONT_DIR');
    if (dir.isNotEmpty) {
      final loader = FontLoader('Roboto');
      for (final weight in ['Regular', 'Bold']) {
        loader.addFont(
          Future.value(
            ByteData.sublistView(
              File('$dir/Roboto-$weight.ttf').readAsBytesSync(),
            ),
          ),
        );
      }
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('$dir/MaterialIcons-Regular.otf').readAsBytesSync(),
            ),
          ),
        );
      await icons.load();
    }
  });
  testWidgets(
    'one field per screen, validates, saves and resumes without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = (await tester.runAsync(
        () => databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: schemaVersion,
            onConfigure: configureDatabase,
            onCreate: createSchema,
          ),
        ),
      ))!;
      addTearDown(() => tester.runAsync(db.close));
      final repo = CaptureRepository(db, deviceId: 'widget-test');
      await tester.pumpWidget(OperatorApp(repository: repo));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('MuleAgent'), findsOneWidget);
      expect(find.text('Despacho mulas'), findsOneWidget);
      expect(find.text('Iniciar día'), findsNothing);
      await tester.tap(find.text('Entrada de mulas'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.ensureVisible(find.text('Siguiente'));
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('Completa este dato para continuar.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Julio Esteves');
      await tester.tap(find.text('Siguiente'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.text('Entrada · 2 de 6'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final session = (await repo.resume())!;
        expect((await repo.draft(session))!.values['driver'], 'Julio Esteves');
      });
    },
  );
  testWidgets(
    'two large home buttons open the correct stage and preserve another pending entry',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = (await tester.runAsync(() async {
        final db = await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: schemaVersion,
            onConfigure: configureDatabase,
            onCreate: createSchema,
          ),
        );
        final repo = CaptureRepository(db, deviceId: 'menu-test');
        final pending = await repo.start(
          Stage.entry,
          DateTime.now().toIso8601String().substring(0, 10),
        );
        await repo.addTicket(pending);
        await repo.saveValue((await repo.draft(pending))!, 'Julio');
        return repo;
      }))!;
      addTearDown(() => tester.runAsync(repo.db.close));
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: OperatorApp(repository: repo),
        ),
      );
      await settleStorage(tester);
      expect(find.text('MuleAgent'), findsOneWidget);
      expect(find.text('Iniciar día'), findsNothing);
      for (final label in ['Entrada de mulas', 'Despacho mulas']) {
        final button = find.ancestor(
          of: find.text(label),
          matching: find.byType(FilledButton),
        );
        expect(tester.getSize(button).height, greaterThanOrEqualTo(96));
      }
      await preview(tester, boundary, 'home');
      await tester.tap(find.text('Despacho mulas'));
      await settleStorage(tester);
      expect(find.text('Despacho · 1 de 5'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('MuleAgent'), findsOneWidget);
      await tester.tap(find.text('Atrás'));
      await settleStorage(tester);
      await tester.ensureVisible(find.text('Jornadas pendientes'));
      await tester.tap(find.text('Jornadas pendientes'));
      await settleStorage(tester);
      final entry = find.textContaining('Entrada ·');
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await settleStorage(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Julio',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'closed reports retain a branded header and large outlined icon actions',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = (await tester.runAsync(() async {
        final db = await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: schemaVersion,
            onConfigure: configureDatabase,
            onCreate: createSchema,
          ),
        );
        final repo = CaptureRepository(db, deviceId: 'closed-menu');
        final session = await repo.start(Stage.entry, '2026-11-07');
        await repo.addTicket(session);
        const values = [
          'Julio',
          '000362',
          'Proveedor A',
          '07:04',
          '111410.7',
          'No se pudo tomar foto',
        ];
        for (var i = 0; i < values.length; i++) {
          final draft = (await repo.draft(session))!;
          await repo.saveValue(draft, values[i]);
          if (i < values.length - 1) {
            await repo.move(draft, i + 1);
          }
        }
        await repo.complete(session, (await repo.draft(session))!);
        await repo.closeRevision(session);
        return repo;
      }))!;
      addTearDown(() => tester.runAsync(repo.db.close));
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: OperatorApp(repository: repo),
        ),
      );
      await settleStorage(tester);
      await tester.ensureVisible(find.text('Historial y archivos'));
      await tester.tap(find.text('Historial y archivos'));
      await settleStorage(tester);
      await tester.tap(find.text('Entrada · 2026-11-07'));
      await settleStorage(tester);
      expect(find.text('MuleAgent'), findsOneWidget);
      expect(find.text('Entrada cerrada'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('MuleAgent')).dy,
        greaterThanOrEqualTo(0),
      );
      for (final label in [
        'Ver e imprimir PDF',
        'Guardar PDF y archivo cifrado',
        'Ver fichas y fotos',
        'Continuar esta jornada',
        'Volver al inicio',
      ]) {
        final button = find.ancestor(
          of: find.text(label),
          matching: find.byType(OutlinedButton),
        );
        expect(button, findsOneWidget);
        expect(tester.getSize(button).height, greaterThanOrEqualTo(64));
        expect(
          find.descendant(of: button, matching: find.byType(Icon)),
          findsOneWidget,
        );
      }
      await preview(tester, boundary, 'closed');
      await tester.ensureVisible(find.text('Ver fichas y fotos'));
      await tester.tap(find.text('Ver fichas y fotos'));
      await settleStorage(tester);
      expect(find.text('MuleAgent'), findsOneWidget);
      expect(find.text('Fichas y evidencias'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> settleStorage(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pumpAndSettle();
}

Future<void> preview(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  if (!const bool.fromEnvironment('CAPTURE_PREVIEWS')) return;
  await tester.pump();
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 2);
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    Directory('build/previews').createSync(recursive: true);
    File(
      'build/previews/$name.png',
    ).writeAsBytesSync(data.buffer.asUint8List());
    image.dispose();
  });
}
