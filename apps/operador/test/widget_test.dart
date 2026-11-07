import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mule_data/mule_data.dart';
import 'package:operador/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
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
      await tester.tap(find.text('Iniciar día'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar entrada'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.ensureVisible(find.text('Siguiente →'));
      await tester.tap(find.text('Siguiente →'));
      await tester.pumpAndSettle();
      expect(find.text('Completa este dato para continuar.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Julio Esteves');
      await tester.tap(find.text('Siguiente →'));
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
}
