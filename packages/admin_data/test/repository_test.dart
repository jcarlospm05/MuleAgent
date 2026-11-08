import 'dart:convert';
import 'package:admin_data/admin_data.dart';
import 'package:mule_data/mule_data.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'fixtures.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late AdminRepository repo;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        onConfigure: configureDatabase,
        onCreate: (db, _) async {
          await createSchema(db, schemaVersion);
          await createAdminSchema(db);
        },
        version: 1,
      ),
    );
    repo = AdminRepository(db, device: 'admin-device', actor: 'Carlos');
  });
  tearDown(() => db.close());
  Future<ImportResult> receive(Map<String, dynamic> p) async {
    final r = ReceivedReport.parse(p);
    return repo.importReport(r, paths(r), source: 'received');
  }

  test(
    'imports Operator contract, preserves zeros and recognizes re-sends with new audit events',
    () async {
      final p = jsonDecode(jsonEncode(packet())) as Map<String, dynamic>;
      expect((await receive(p)).duplicate, isFalse);
      expect((await receive(p)).duplicate, isTrue);
      final e = Map<String, dynamic>.from(p['tables']['audit_events'][0] as Map)
        ..['id'] = 'new-event';
      p['tables']['audit_events'].add(e);
      expect((await receive(p)).newEvents, 1);
      expect((await repo.tickets('2026-11-07')).single['code'], '000362');
      expect(await db.query('admin_revisions'), hasLength(1));
      expect(await db.query('received_events'), hasLength(2));
    },
  );
  test(
    'out-of-order revisions retain originals and only show the highest number',
    () async {
      await receive(packet(revision: 'revision-e2', number: 2, code: 'new'));
      await receive(packet());
      expect((await repo.tickets('2026-11-07')).single['code'], 'new');
      expect(
        (await repo.revisionTickets('revision-e1')).single['code'],
        '000362',
      );
      expect(await repo.reports(latest: false), hasLength(2));
    },
  );
  test(
    'same revision with changed data conflicts and rolls back audit changes',
    () async {
      await receive(packet());
      final changed = packet(code: 'different');
      await expectLater(receive(changed), throwsStateError);
      expect((await repo.tickets('2026-11-07')).single['code'], '000362');
      expect(await db.query('received_events'), hasLength(1));
    },
  );
  test(
    'manual links do not modify originals, reject reuse and become stale on new revision',
    () async {
      await receive(packet());
      await receive(
        packet(
          stage: 'exit',
          report: 'report-x',
          revision: 'revision-x1',
          code: 'DEMO-362',
        ),
      );
      var entries = await repo.tickets('2026-11-07');
      final a = entries.singleWhere((r) => r['stage'] == 'entry'),
          b = entries.singleWhere((r) => r['stage'] == 'exit');
      await repo.link(a, b);
      await expectLater(repo.link(a, b), throwsStateError);
      expect((await repo.links('2026-11-07')).single['stale'], false);
      await receive(packet(revision: 'revision-e2', number: 2));
      expect((await repo.links('2026-11-07')).single['stale'], true);
      await repo.unlink(
        (await repo.links('2026-11-07')).single['id'] as String,
      );
      entries = await repo.tickets('2026-11-07');
      await repo.link(entries.singleWhere((r) => r['stage'] == 'entry'), b);
      expect((await repo.links('2026-11-07')).single['stale'], false);
      expect(
        (await repo.revisionTickets('revision-e1')).single['code'],
        '000362',
      );
    },
  );
  test('cross-date links and forged row identities are rejected', () async {
    await receive(packet());
    await receive(
      packet(
        stage: 'exit',
        report: 'report-x',
        revision: 'revision-x1',
        date: '2026-11-08',
      ),
    );
    final a = (await repo.tickets('2026-11-07')).single,
        b = (await repo.tickets('2026-11-08')).single;
    await expectLater(repo.link(a, b), throwsStateError);
    await expectLater(
      repo.link({...a, 'date': '2026-11-08'}, b),
      throwsStateError,
    );
  });
  test(
    'originals are immutable and audit filters retain operator and administrator origins',
    () async {
      await receive(packet());
      await expectLater(
        db.update('admin_revisions', {'source': 'own'}),
        throwsA(isA<DatabaseException>()),
      );
      expect(await repo.audit(operator: 'Julio'), hasLength(1));
      expect(
        await repo.audit(operator: 'Carlos', action: 'imported'),
        hasLength(1),
      );
      expect(await repo.audit(equipment: 'not-existing'), isEmpty);
    },
  );
  test(
    'malformed references, incomplete reports, wrong hashes and traversal are rejected',
    () {
      for (final change in <void Function(Map<String, dynamic>)>[
        (p) => p['tables']['revisions'][0]['status'] = 'draft',
        (p) => p['tables']['tickets'][0]['revision_id'] = 'other',
        (p) => p['tables']['evidence'][0]['state'] = 'pending',
        (p) => p['files'].values.first['sha256'] = 'wrong',
        (p) {
          final f = p['files'].values.first;
          p['files'] = {'artifacts/../escape.pdf': f};
          p['pdf']['path'] = 'artifacts/../escape.pdf';
        },
      ]) {
        final p = jsonDecode(jsonEncode(packet())) as Map<String, dynamic>;
        change(p);
        expect(() => ReceivedReport.parse(p), throwsFormatException);
      }
    },
  );
  test(
    'full backup restores originals, links and audit in a fresh installation',
    () async {
      await receive(packet());
      await receive(
        packet(stage: 'exit', report: 'report-x', revision: 'revision-x1'),
      );
      final rows = await repo.tickets('2026-11-07');
      await repo.link(
        rows.singleWhere((r) => r['stage'] == 'entry'),
        rows.singleWhere((r) => r['stage'] == 'exit'),
      );
      final payload =
          jsonDecode(jsonEncode(await repo.backup())) as Map<String, dynamic>;
      final target = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          singleInstance: false,
          version: 1,
          onConfigure: configureDatabase,
          onCreate: (db, _) async {
            await createSchema(db, schemaVersion);
            await createAdminSchema(db);
          },
        ),
      );
      try {
        final restored = AdminRepository(
          target,
          device: 'new-device',
          actor: 'New admin',
        );
        await restored.restoreBackup(payload);
        expect(await restored.tickets('2026-11-07'), hasLength(2));
        expect((await restored.links('2026-11-07')).single['stale'], false);
        expect(await restored.audit(action: 'backup_restored'), hasLength(1));
        await expectLater(restored.restoreBackup(payload), throwsStateError);
        expect(await restored.tickets('2026-11-07'), hasLength(2));
      } finally {
        await target.close();
      }
    },
  );
}
