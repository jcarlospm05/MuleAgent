import 'package:administrador/services.dart';
import 'package:admin_data/admin_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mule_data/mule_data.dart';
import 'package:mule_profiles/mule_profiles.dart';
import '../../../packages/admin_data/test/fixtures.dart' as fixtures;
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'legacy administrator backup merges received archives without replacing a local draft or profile',
    () async {
      final source = await TestInstallation.create(role: AppRole.administrator);
      final target = await TestInstallation.create(role: AppRole.administrator);
      try {
        final a = source.bundle, b = target.bundle;
        final incoming = AdminServices(
          a.admin,
          a.capture,
          a.services,
          access: a.profiles,
        );
        final report = ReceivedReport.parse(fixtures.packet());
        await incoming.saveReport(report, source: 'received');
        final backup = await incoming.backupPayload();
        final draft = await b.capture.start(Stage.exit, '2026-11-09');
        await b.capture.addTicket(draft);
        await b.services.restorePayload(backup);
        await b.services.restorePayload(backup);
        expect((await b.capture.resume())!.id, draft.id);
        expect(await b.admin.tickets('2026-11-07'), hasLength(1));
        expect(await b.admin.reports(), hasLength(1));
        expect((await b.profiles.load())!.installedAs, AppRole.administrator);
        final row = (await b.admin.reports()).single;
        expect(
          await b.services.file(row['pdf_path'] as String).readAsBytes(),
          report.files[report.pdfPath],
        );
      } finally {
        await source.close();
        await target.close();
      }
    },
  );
  test(
    'Supervisor refuses a legacy administrator backup before writing any imported files',
    () async {
      final source = await TestInstallation.create(role: AppRole.administrator);
      final target = await TestInstallation.create(role: AppRole.supervisor);
      try {
        final a = source.bundle;
        final incoming = AdminServices(
          a.admin,
          a.capture,
          a.services,
          access: a.profiles,
        );
        await incoming.saveReport(
          ReceivedReport.parse(fixtures.packet()),
          source: 'received',
        );
        final backup = await incoming.backupPayload();
        await expectLater(
          target.bundle.services.restorePayload(backup),
          throwsStateError,
        );
        expect(await target.bundle.admin.reports(), isEmpty);
        expect(await target.root.list().toList(), isEmpty);
        expect((await target.bundle.profiles.load())!.canSwitchRoles, isFalse);
      } finally {
        await source.close();
        await target.close();
      }
    },
  );
  test(
    'an Operator backup cannot elevate installation privileges via SQLite settings',
    () async {
      final target = await TestInstallation.create(role: AppRole.supervisor);
      try {
        final tables =
            (await target.bundle.capture.snapshot())['tables']
                as Map<String, dynamic>;
        tables['settings'] = [
          {
            'key': 'mule_installation_profile_v1',
            'value':
                '{"version":1,"installed_as":"administrator","active_role":"administrator"}',
          },
        ];
        await target.bundle.services.restorePayload({
          'schema': 1,
          'kind': 'backup',
          'tables': tables,
          'files': <String, dynamic>{},
        });
        expect(
          (await target.bundle.profiles.load())!.installedAs,
          AppRole.supervisor,
        );
        await expectLater(
          target.bundle.profiles.requireAdministrator(),
          throwsStateError,
        );
      } finally {
        await target.close();
      }
    },
  );
}
