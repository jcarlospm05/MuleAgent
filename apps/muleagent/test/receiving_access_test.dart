import 'dart:typed_data';
import 'package:administrador/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mule_profiles/mule_profiles.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Supervisor cannot call receiving service directly or bypass its file picker',
    () async {
      final installation = await TestInstallation.create(
        role: AppRole.supervisor,
      );
      try {
        final b = installation.bundle;
        final receiver = AdminServices(
          b.admin,
          b.capture,
          b.services,
          access: b.profiles,
        );
        await expectLater(
          receiver.importBytes(Uint8List(0), 'any'),
          throwsStateError,
        );
        await expectLater(
          receiver.importPath('/not/readable/file.mule', 'any'),
          throwsStateError,
        );
        await expectLater(receiver.receive(), throwsStateError);
        expect(await installation.db.query('admin_revisions'), isEmpty);
        expect(await installation.root.list().toList(), isEmpty);
      } finally {
        await installation.close();
      }
    },
  );
  test(
    'an existing receiver rechecks the active role after Administrator switches',
    () async {
      final installation = await TestInstallation.create(
        role: AppRole.administrator,
      );
      try {
        final b = installation.bundle;
        final receiver = AdminServices(
          b.admin,
          b.capture,
          b.services,
          access: b.profiles,
        );
        await b.profiles.switchTo(AppRole.supervisor);
        await expectLater(
          receiver.importBytes(Uint8List(0), 'any'),
          throwsStateError,
        );
        await b.profiles.switchTo(AppRole.administrator);
        await expectLater(
          receiver.importBytes(Uint8List(0), 'any'),
          throwsA(isA<FormatException>()),
        );
      } finally {
        await installation.close();
      }
    },
  );
}
