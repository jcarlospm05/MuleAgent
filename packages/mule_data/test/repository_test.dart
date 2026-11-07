import 'dart:io';

import 'package:mule_data/mule_data.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late CaptureRepository repo;
  late Directory directory;
  late String dbPath;
  Future<void> open() async {
    db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: configureDatabase,
        onCreate: createSchema,
      ),
    );
    repo = CaptureRepository(db, deviceId: 'test-device');
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mule_test_');
    dbPath = '${directory.path}/test.db';
    await open();
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
    'recovers exact persisted field and step after closing the database',
    () async {
      final session = await repo.start(Stage.entry, '2026-11-07');
      await repo.addTicket(session);
      var draft = (await repo.draft(session))!;
      await repo.saveValue(draft, 'Julio Esteves');
      await repo.move(draft, 1);
      draft = (await repo.draft(session))!;
      await repo.saveValue(draft, '000362');
      await db.close();
      await open();
      final resumed = (await repo.resume())!;
      draft = (await repo.draft(resumed))!;
      expect(draft.step, 1);
      expect(draft.value, '000362');
      expect(draft.values['driver'], 'Julio Esteves');
      expect(resumed.date, '2026-11-07');
    },
  );

  test('start and add are idempotent and entry/exit are independent', () async {
    final first = await repo.start(Stage.entry, '2026-11-07');
    expect((await repo.start(Stage.entry, '2026-11-07')).id, first.id);
    final exit = await repo.start(Stage.exit, '2026-11-07');
    expect(exit.id, isNot(first.id));
    await repo.addTicket(first);
    await repo.addTicket(first);
    expect(await repo.tickets(first), hasLength(1));
    expect(await repo.tickets(exit), isEmpty);
  });

  test('incomplete capture cannot complete or close; transaction leaves draft intact', () async {
    final session = await repo.start(Stage.entry, '2026-11-07');
    await repo.addTicket(session);
    final draft = (await repo.draft(session))!;
    await expectLater(repo.complete(session, draft), throwsStateError);
    await expectLater(
      db.update(
        'revisions',
        {'status': 'closed', 'closed_at': 'now', 'current_ticket_id': null},
        where: 'id=?',
        whereArgs: [session.id],
      ),
      throwsA(isA<DatabaseException>()),
    );
    expect((await repo.draft(session))!.ticketId, draft.ticketId);
  });

  test('complete, edit, revalidate and protect a closed revision', () async {
    final session = await repo.start(Stage.entry, '2026-11-07');
    await repo.addTicket(session);
    const values = [
      'Julio',
      '000362',
      'Proveedor A',
      '07:04',
      '111410.7',
      'Cámara averiada',
    ];
    for (var i = 0; i < values.length; i++) {
      final draft = (await repo.draft(session))!;
      await repo.saveValue(draft, values[i]);
      if (i < values.length - 1) await repo.move(draft, i + 1);
    }
    final draft = (await repo.draft(session))!;
    await repo.complete(session, draft);
    expect(await repo.draft(session), isNull);
    final ticket = (await repo.tickets(session)).single;
    expect(ticket['code'], '000362');
    expect(ticket['evidence_state'], 'omitted');
    await repo.edit(session, ticket['id'] as String);
    expect((await repo.draft(session))!.values['code'], '000362');
    await repo.complete(session, (await repo.draft(session))!);
    await db.update(
      'revisions',
      {'status': 'closed', 'closed_at': 'now'},
      where: 'id=?',
      whereArgs: [session.id],
    );
    await expectLater(repo.addTicket(session), throwsStateError);
    await expectLater(
      db.update(
        'tickets',
        {'code': 'changed'},
        where: 'id=?',
        whereArgs: [ticket['id']],
      ),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.update(
        'evidence',
        {'omission_reason': 'changed'},
        where: 'ticket_id=?',
        whereArgs: [ticket['id']],
      ),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.delete('revisions', where: 'id=?', whereArgs: [session.id]),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.update('audit_events', {'action': 'changed'}),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('stale capture cannot overwrite a subsequent step', () async {
    final session = await repo.start(Stage.exit, '2026-11-07');
    await repo.addTicket(session);
    final old = (await repo.draft(session))!;
    await repo.saveValue(old, '001');
    await repo.move(old, 1);
    await expectLater(repo.saveValue(old, 'stale'), throwsStateError);
    expect((await repo.draft(session))!.values['code'], '001');
  });

  test('validates time, decimal readings and operational date', () async {
    final fields = CaptureField.forStage(Stage.entry);
    final time = fields.singleWhere((f) => f.column == 'time');
    final meter = fields.singleWhere((f) => f.column == 'meter');
    expect(time.validate('23:59'), isNull);
    expect(time.validate('24:00'), isNotNull);
    expect(meter.validate('111410,7'), isNull);
    expect(meter.validate('-1'), isNotNull);
    expect(meter.validate('1.2345'), isNotNull);
    await expectLater(
      repo.start(Stage.entry, '2026-02-31'),
      throwsArgumentError,
    );
  });
}
