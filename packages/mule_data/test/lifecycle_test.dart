import 'dart:convert';
import 'dart:io';
import 'package:mule_data/mule_data.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late CaptureRepository repo;
  Future<Database> open() => databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: schemaVersion,
      onConfigure: configureDatabase,
      onCreate: createSchema,
      singleInstance: false,
    ),
  );
  setUp(() async {
    db = await open();
    repo = CaptureRepository(db, deviceId: 'one')..operatorName = 'Julio';
  });
  tearDown(() => db.close());
  Future<CaptureSession> complete({bool photo = false}) async {
    final session = await repo.start(Stage.entry, '2026-11-07');
    await repo.addTicket(session);
    const values = [
      'Julio',
      '000362',
      'Proveedor A',
      '07:04',
      '111410.7',
      'Tablero dañado',
    ];
    for (var i = 0; i < values.length; i++) {
      final draft = (await repo.draft(session))!;
      if (photo && i == values.length - 1) {
        await repo.attachPhoto(draft, 'media/photo.jpg', 'hash', 'camera');
      } else {
        await repo.saveValue(draft, values[i]);
      }
      if (i < values.length - 1) await repo.move(draft, i + 1);
    }
    await repo.complete(session, (await repo.draft(session))!);
    return session;
  }

  test(
    'photo evidence completes without an omission and closed revisions stay intact after reopening',
    () async {
      final session = await complete(photo: true);
      await repo.closeRevision(session);
      final next = await repo.reopen(session);
      expect(
        (await repo.tickets(next)).single['logical_id'],
        (await repo.tickets(session)).single['logical_id'],
      );
      expect(next.id, isNot(session.id));
      expect((await repo.sessions(closed: true)), hasLength(1));
      await repo.edit(next, (await repo.tickets(next)).single['id'] as String);
      final draft = (await repo.draft(next))!;
      await repo.saveValue(draft, 'Otro mulero');
      expect((await repo.tickets(session)).single['driver'], 'Julio');
      expect((await repo.tickets(next)).single['driver'], 'Otro mulero');
      expect((await repo.reopen(session)).id, next.id);
    },
  );
  test(
    'backup restores closed revisions and a partial draft; repeated restore is idempotent',
    () async {
      final session = await complete();
      await repo.closeRevision(session);
      final next = await repo.reopen(session);
      await repo.addTicket(next);
      await repo.saveValue((await repo.draft(next))!, 'Borrador');
      final payload =
          jsonDecode(jsonEncode(await repo.snapshot())) as Map<String, dynamic>;
      final target = await open();
      try {
        final restored = CaptureRepository(target, deviceId: 'new-device');
        await restored.restore(payload);
        await restored.restore(payload);
        final active = (await restored.resume())!;
        expect((await restored.draft(active))!.value, 'Borrador');
        expect(await restored.sessions(closed: true), hasLength(1));
        expect(await target.query('tickets'), hasLength(3));
        final events = await target.query('audit_events');
        expect(events.every((e) => e['actor'] == 'Julio'), isTrue);
      } finally {
        await target.close();
      }
    },
  );
  test('conflicting restore rolls back all earlier inserts', () async {
    final session = await complete();
    final payload =
        jsonDecode(jsonEncode(await repo.snapshot())) as Map<String, dynamic>;
    payload['tables']['reports'].insert(0, {
      'id': 'new',
      'operational_date': '2026-11-06',
      'stage': 'entry',
      'device_id': 'other',
      'created_at': 'now',
    });
    payload['tables']['tickets'][0]['code'] = 'altered';
    await expectLater(repo.restore(payload), throwsStateError);
    expect(
      await db.query('reports', where: 'id=?', whereArgs: ['new']),
      isEmpty,
    );
    expect((await repo.tickets(session)).single['code'], '000362');
  });
  test(
    'closed reports are reused when selecting their date and stage',
    () async {
      final session = await complete();
      await repo.closeRevision(session);
      expect((await repo.start(Stage.entry, session.date)).id, session.id);
      final next = await repo.reopen(session);
      await repo.closeRevision(next);
      await expectLater(repo.reopen(session), throwsStateError);
    },
  );
  test(
    'authenticated packages reject wrong passwords, modified contents and unsupported versions',
    () async {
      final codec = PackageCodec();
      final payload = {
        'schema': 1,
        'kind': 'report',
        'tables': {},
        'files': {},
      };
      const password = 'clave-de-prueba-123';
      final first = await codec.encode(payload, password);
      final second = await codec.encode(payload, password);
      expect(first, isNot(equals(second)));
      expect(await codec.decode(first, password), payload);
      await expectLater(
        codec.decode(first, 'otra-clave-123'),
        throwsA(anything),
      );
      final changed = jsonDecode(utf8.decode(first)) as Map<String, dynamic>;
      final bytes = base64Decode(changed['ciphertext'] as String)..[0] ^= 1;
      changed['ciphertext'] = base64Encode(bytes);
      await expectLater(
        codec.decode(utf8.encode(jsonEncode(changed)), password),
        throwsA(anything),
      );
      changed['version'] = 2;
      await expectLater(
        codec.decode(utf8.encode(jsonEncode(changed)), password),
        throwsFormatException,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test('migrates an existing v1 database without removing reports', () async {
    final dir = await Directory.systemTemp.createTemp('mule_migration_');
    final path = '${dir.path}/old.db';
    var old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: configureDatabase,
        onCreate: (db, version) async {
          for (final sql in schemaV1) {
            await db.execute(sql);
          }
        },
      ),
    );
    await old.insert('reports', {
      'id': 'old-report',
      'operational_date': '2026-11-07',
      'stage': 'entry',
      'device_id': 'old',
      'created_at': 'now',
    });
    await old.close();
    old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: configureDatabase,
        onUpgrade: upgradeSchema,
      ),
    );
    try {
      expect((await old.query('reports')).single['id'], 'old-report');
      expect(await old.query('artifacts'), isEmpty);
      expect(
        (await old.rawQuery(
          'PRAGMA table_info(audit_events)',
        )).any((r) => r['name'] == 'actor'),
        isTrue,
      );
    } finally {
      await old.close();
      await dir.delete(recursive: true);
    }
  });
}
