import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mule_data/mule_data.dart';
import 'package:mule_profiles/mule_profiles.dart';
import 'package:muleagent/main.dart';
import 'support.dart';

Future<void> settle(WidgetTester tester) async {
  // Drain navigation/profile microtasks between real SQL responses in fake time.
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

void main() {
  testWidgets(
    'initial Supervisor choice persists and has no reception or role switch',
    (tester) async {
      final installation = (await tester.runAsync(
        () => TestInstallation.create(),
      ))!;
      addTearDown(() => tester.runAsync(installation.close));
      await tester.pumpWidget(MuleAgentApp(bundle: installation.bundle));
      await settle(tester);
      expect(find.text('Elige el perfil de esta instalación'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Supervisor'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('no permitirá cambiar a Administrador'),
        findsOneWidget,
      );
      await tester.tap(find.text('Confirmar perfil'));
      await settle(tester);
      expect(find.text('Supervisor'), findsOneWidget);
      expect(find.text('Entrada de mulas'), findsOneWidget);
      expect(find.text('Recibir reportes'), findsNothing);
      expect(find.text('Cambiar a Supervisor'), findsNothing);
      expect(find.text('Volver a Administrador'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(MuleAgentApp(bundle: installation.bundle));
      await settle(tester);
      expect(find.text('Elige el perfil de esta instalación'), findsNothing);
      expect(find.text('Supervisor'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Administrator uses the same capture flow and can return from Supervisor without losing a draft',
    (tester) async {
      final installation = (await tester.runAsync(
        () => TestInstallation.create(role: AppRole.administrator),
      ))!;
      addTearDown(() => tester.runAsync(installation.close));
      final draft = (await tester.runAsync(() async {
        final session = await installation.bundle.capture.start(
          Stage.entry,
          '2026-11-09',
        );
        await installation.bundle.capture.addTicket(session);
        return session;
      }))!;
      await tester.pumpWidget(MuleAgentApp(bundle: installation.bundle));
      await settle(tester);
      expect(find.text('Administrador'), findsOneWidget);
      expect(find.text('Entrada de mulas'), findsOneWidget);
      await tester.ensureVisible(find.text('Cambiar a Supervisor'));
      await tester.tap(find.text('Cambiar a Supervisor'));
      await settle(tester);
      expect(find.text('Supervisor'), findsOneWidget);
      expect(find.text('Recibir reportes'), findsNothing);
      await tester.ensureVisible(find.text('Volver a Administrador'));
      await tester.tap(find.text('Volver a Administrador'));
      await settle(tester);
      expect(find.text('Administrador'), findsOneWidget);
      expect(find.text('Recibir reportes'), findsOneWidget);
      expect(
        (await tester.runAsync(installation.bundle.capture.resume))!.id,
        draft.id,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Administrator opens the receiving module without legacy Excel or cross-matching routes',
    (tester) async {
      final installation = (await tester.runAsync(
        () => TestInstallation.create(role: AppRole.administrator),
      ))!;
      addTearDown(() => tester.runAsync(installation.close));
      await tester.pumpWidget(MuleAgentApp(bundle: installation.bundle));
      await settle(tester);
      await tester.ensureVisible(find.text('Recibir reportes'));
      await tester.tap(find.text('Recibir reportes'));
      await settle(tester);
      expect(find.text('Elegir archivo e importar'), findsOneWidget);
      expect(find.text('Cruce manual'), findsNothing);
      expect(find.textContaining('Excel'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
