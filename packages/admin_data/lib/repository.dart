import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import 'payload.dart';

Future<void> createAdminSchema(Database db) async {
  for (final sql in [
    '''CREATE TABLE admin_revisions(id TEXT PRIMARY KEY,report_id TEXT NOT NULL,number INTEGER NOT NULL,date TEXT NOT NULL,stage TEXT NOT NULL CHECK(stage IN ('entry','exit')),device TEXT NOT NULL,source TEXT NOT NULL CHECK(source IN ('received','own')),fingerprint TEXT NOT NULL,snapshot TEXT NOT NULL,pdf_path TEXT NOT NULL,package_path TEXT,received_at TEXT NOT NULL,UNIQUE(report_id,number))''',
    'CREATE INDEX admin_dates ON admin_revisions(date,stage,report_id,number)',
    '''CREATE TABLE admin_files(revision_id TEXT NOT NULL REFERENCES admin_revisions(id),original_path TEXT NOT NULL,local_path TEXT NOT NULL,sha256 TEXT NOT NULL,PRIMARY KEY(revision_id,original_path))''',
    '''CREATE TABLE received_events(id TEXT PRIMARY KEY,revision_id TEXT NOT NULL REFERENCES admin_revisions(id),payload TEXT NOT NULL)''',
    '''CREATE TABLE admin_events(id TEXT PRIMARY KEY,occurred_at TEXT NOT NULL,actor TEXT NOT NULL,device TEXT NOT NULL,action TEXT NOT NULL,date TEXT,details TEXT NOT NULL)''',
    '''CREATE TABLE admin_links(id TEXT PRIMARY KEY,date TEXT NOT NULL,entry_revision TEXT NOT NULL REFERENCES admin_revisions(id),entry_ticket TEXT NOT NULL,entry_report TEXT NOT NULL,entry_logical TEXT NOT NULL,exit_revision TEXT NOT NULL REFERENCES admin_revisions(id),exit_ticket TEXT NOT NULL,exit_report TEXT NOT NULL,exit_logical TEXT NOT NULL,active INTEGER NOT NULL CHECK(active IN (0,1)),created_at TEXT NOT NULL)''',
    'CREATE UNIQUE INDEX active_entry ON admin_links(entry_report,entry_logical) WHERE active=1',
    'CREATE UNIQUE INDEX active_exit ON admin_links(exit_report,exit_logical) WHERE active=1',
    for (final table in [
      'admin_revisions',
      'admin_files',
      'received_events',
      'admin_events',
    ]) ...[
      "CREATE TRIGGER ${table}_immutable_update BEFORE UPDATE ON $table BEGIN SELECT RAISE(ABORT,'Los originales son de solo lectura'); END",
      "CREATE TRIGGER ${table}_immutable_delete BEFORE DELETE ON $table BEGIN SELECT RAISE(ABORT,'Los originales son de solo lectura'); END",
    ],
  ]) {
    await db.execute(sql);
  }
}

class ImportResult {
  const ImportResult(this.duplicate, this.newEvents);
  final bool duplicate;
  final int newEvents;
}

class AdminRepository {
  AdminRepository(this.db, {required this.device, required this.actor});
  final Database db;
  final String device;
  String actor;
  final uuid = const Uuid();
  String get now => DateTime.now().toUtc().toIso8601String();
  Future<void> event(
    String action, {
    String? date,
    Map<String, Object?> details = const {},
  }) => db.transaction((tx) => _event(tx, action, date, details));
  Future<void> _event(
    Transaction tx,
    String action,
    String? date,
    Map<String, Object?> details,
  ) async {
    await tx.insert('admin_events', {
      'id': uuid.v4(),
      'occurred_at': now,
      'actor': actor,
      'device': device,
      'action': action,
      'date': date,
      'details': jsonEncode(details),
    });
  }

  Future<ImportResult> importReport(
    ReceivedReport report,
    Map<String, String> paths, {
    required String source,
    String? packagePath,
  }) => db.transaction((tx) async {
    if (!['received', 'own'].contains(source)) {
      throw ArgumentError('Origen inválido');
    }
    final existing = await tx.query(
      'admin_revisions',
      where: 'id=? OR (report_id=? AND number=?)',
      whereArgs: [report.id, report.reportId, report.number],
    );
    final duplicate = existing.isNotEmpty;
    if (duplicate) {
      if (existing.length != 1 ||
          existing.single['id'] != report.id ||
          existing.single['fingerprint'] != report.fingerprint) {
        throw StateError(
          'Conflicto: esta revisión ya existe con contenido distinto. Se conservaron los originales.',
        );
      }
    } else {
      if (!paths.containsKey(report.pdfPath) ||
          !report.files.keys.every(paths.containsKey)) {
        throw StateError('Faltan archivos verificados.');
      }
      final other = await tx.query(
        'admin_revisions',
        where: 'report_id=?',
        whereArgs: [report.reportId],
        limit: 1,
      );
      if (other.isNotEmpty &&
          (other.single['date'] != report.date ||
              other.single['stage'] != report.stage ||
              other.single['device'] != report.report['device_id'])) {
        throw StateError('Cambió la identidad de un reporte existente.');
      }
      await tx.insert('admin_revisions', {
        'id': report.id,
        'report_id': report.reportId,
        'number': report.number,
        'date': report.date,
        'stage': report.stage,
        'device': report.report['device_id'],
        'source': source,
        'fingerprint': report.fingerprint,
        'snapshot': canonical(report.toJson()),
        'pdf_path': paths[report.pdfPath],
        'package_path': packagePath,
        'received_at': now,
      });
      for (final entry in paths.entries) {
        await tx.insert('admin_files', {
          'revision_id': report.id,
          'original_path': entry.key,
          'local_path': entry.value,
          'sha256': digest(report.files[entry.key]!),
        });
      }
    }
    var newEvents = 0;
    if (source == 'received') {
      for (final e in report.events) {
        final old = await tx.query(
          'received_events',
          where: 'id=?',
          whereArgs: [e['id']],
        );
        if (old.isEmpty) {
          await tx.insert('received_events', {
            'id': e['id'],
            'revision_id': report.id,
            'payload': canonical(e),
          });
          newEvents++;
        } else if (old.single['payload'] != canonical(e)) {
          throw StateError('Conflicto en un evento de auditoría.');
        }
      }
    }
    await _event(
      tx,
      duplicate ? 'report_resent' : 'report_imported',
      report.date,
      {'revision': report.id, 'source': source, 'new_events': newEvents},
    );
    return ImportResult(duplicate, newEvents);
  });
  Future<List<Map<String, Object?>>> reports({
    String? date,
    bool latest = true,
  }) => db.rawQuery(
    '''SELECT a.* FROM admin_revisions a WHERE (? IS NULL OR a.date=?)
    ${latest ? 'AND a.number=(SELECT max(b.number) FROM admin_revisions b WHERE b.report_id=a.report_id)' : ''} ORDER BY a.date DESC,a.stage,a.received_at DESC''',
    [date, date],
  );
  Future<Map<String, Object?>> revision(String id) async => (await db.query(
    'admin_revisions',
    where: 'id=?',
    whereArgs: [id],
  )).single;
  Future<List<Map<String, Object?>>> tickets(
    String date, {
    String? stage,
  }) async {
    final result = <Map<String, Object?>>[];
    for (final revision in await reports(date: date)) {
      if (stage != null && revision['stage'] != stage) continue;
      final data =
          jsonDecode(revision['snapshot'] as String) as Map<String, dynamic>;
      final files = await db.query(
        'admin_files',
        where: 'revision_id=?',
        whereArgs: [revision['id']],
      );
      for (final t in data['tickets'] as List) {
        final e = (data['evidence'] as List).singleWhere(
          (e) => e['ticket_id'] == t['id'],
        );
        result.add({
          ...Map<String, Object?>.from(t as Map),
          'stage': revision['stage'],
          'date': date,
          'report_id': revision['report_id'],
          'source': revision['source'],
          'revision_number': revision['number'],
          'device': revision['device'],
          'evidence_state': e['state'],
          'omission_reason': e['omission_reason'],
          'sha256': e['sha256'],
          'photo_path': e['state'] == 'photo'
              ? files.singleWhere(
                  (f) => f['original_path'] == e['private_path'],
                )['local_path']
              : null,
        });
      }
    }
    return result;
  }

  Future<List<Map<String, Object?>>> revisionTickets(String id) async {
    final r = await revision(id);
    final data = jsonDecode(r['snapshot'] as String) as Map<String, dynamic>;
    final files = await db.query(
      'admin_files',
      where: 'revision_id=?',
      whereArgs: [id],
    );
    return (data['tickets'] as List).map((t) {
      final e = (data['evidence'] as List).singleWhere(
        (e) => e['ticket_id'] == t['id'],
      );
      return <String, Object?>{
        ...Map<String, Object?>.from(t as Map),
        'stage': r['stage'],
        'date': r['date'],
        'report_id': r['report_id'],
        'source': r['source'],
        'revision_number': r['number'],
        'device': r['device'],
        'evidence_state': e['state'],
        'omission_reason': e['omission_reason'],
        'sha256': e['sha256'],
        'photo_path': e['state'] == 'photo'
            ? files.singleWhere(
                (f) => f['original_path'] == e['private_path'],
              )['local_path']
            : null,
      };
    }).toList();
  }

  Future<List<Map<String, Object?>>> links(String date) async {
    final rows = await db.query(
      'admin_links',
      where: 'date=? AND active=1',
      whereArgs: [date],
    );
    final latest = await reports(date: date);
    final result = <Map<String, Object?>>[];
    for (final l in rows) {
      final entry = await revisionTickets(l['entry_revision'] as String);
      final exit = await revisionTickets(l['exit_revision'] as String);
      result.add({
        ...l,
        'entry_code': entry.singleWhere(
          (t) => t['id'] == l['entry_ticket'],
        )['code'],
        'exit_code': exit.singleWhere(
          (t) => t['id'] == l['exit_ticket'],
        )['code'],
        'stale':
            !latest.any((r) => r['id'] == l['entry_revision']) ||
            !latest.any((r) => r['id'] == l['exit_revision']),
      });
    }
    return result;
  }

  Future<void> link(
    Map<String, Object?> entry,
    Map<String, Object?> exit,
  ) => db.transaction((tx) async {
    if (entry['stage'] != 'entry' ||
        exit['stage'] != 'exit' ||
        entry['date'] != exit['date']) {
      throw StateError('Elige una entrada y un despacho de la misma fecha.');
    }
    for (final ticket in [entry, exit]) {
      final rows = await tx.query(
        'admin_revisions',
        where: 'id=?',
        whereArgs: [ticket['revision_id']],
      );
      if (rows.length != 1) throw StateError('Reporte no encontrado.');
      final revision = rows.single;
      final max = (await tx.rawQuery(
        'SELECT max(number) AS n FROM admin_revisions WHERE report_id=?',
        [revision['report_id']],
      )).single['n'];
      final original =
          (jsonDecode(revision['snapshot'] as String)['tickets'] as List).where(
            (t) => t['id'] == ticket['id'],
          );
      if (max != revision['number'] ||
          original.length != 1 ||
          original.single['logical_id'] != ticket['logical_id'] ||
          revision['stage'] != ticket['stage'] ||
          revision['date'] != ticket['date'] ||
          revision['report_id'] != ticket['report_id']) {
        throw StateError('La ficha cambió de revisión. Actualiza la jornada.');
      }
    }
    final existing = await tx.rawQuery(
      'SELECT id FROM admin_links WHERE active=1 AND ((entry_report=? AND entry_logical=?) OR (exit_report=? AND exit_logical=?))',
      [
        entry['report_id'],
        entry['logical_id'],
        exit['report_id'],
        exit['logical_id'],
      ],
    );
    if (existing.isNotEmpty) {
      throw StateError(
        'Una ficha ya está vinculada. Quita su vínculo antes de cambiarlo.',
      );
    }
    final id = uuid.v4();
    await tx.insert('admin_links', {
      'id': id,
      'date': entry['date'],
      'entry_revision': entry['revision_id'],
      'entry_ticket': entry['id'],
      'entry_report': entry['report_id'],
      'entry_logical': entry['logical_id'],
      'exit_revision': exit['revision_id'],
      'exit_ticket': exit['id'],
      'exit_report': exit['report_id'],
      'exit_logical': exit['logical_id'],
      'active': 1,
      'created_at': now,
    });
    await _event(tx, 'link_created', entry['date'] as String, {
      'link': id,
      'entry': entry['id'],
      'exit': exit['id'],
    });
  });
  Future<void> unlink(String id) => db.transaction((tx) async {
    final row = (await tx.query(
      'admin_links',
      where: 'id=? AND active=1',
      whereArgs: [id],
    )).single;
    await tx.update(
      'admin_links',
      {'active': 0},
      where: 'id=?',
      whereArgs: [id],
    );
    await _event(tx, 'link_removed', row['date'] as String, {'link': id});
  });
  static const backupTables = [
    'reports',
    'revisions',
    'tickets',
    'evidence',
    'audit_events',
    'settings',
    'artifacts',
    'admin_revisions',
    'admin_files',
    'received_events',
    'admin_events',
    'admin_links',
  ];
  Future<Map<String, dynamic>> backup() => db.transaction((tx) async {
    return {for (final table in backupTables) table: await tx.query(table)};
  });
  Future<void> restoreBackup(Map<String, dynamic> tables) => db.transaction((
    tx,
  ) async {
    if (tables.length != backupTables.length ||
        !backupTables.every(tables.containsKey)) {
      throw const FormatException('Respaldo administrativo incompatible.');
    }
    for (final table in ['reports', 'admin_revisions', 'admin_links']) {
      if ((await tx.query(table, limit: 1)).isNotEmpty) {
        throw StateError(
          'Restaura el respaldo en una instalación sin jornadas. Los datos actuales se conservaron.',
        );
      }
    }
    Future<void> insertRows(String table, Iterable<dynamic> rows) async {
      for (final raw in rows) {
        await tx.insert(table, Map<String, Object?>.from(raw as Map));
      }
    }

    await insertRows('reports', tables['reports'] as List);
    final seenTickets = <String>{}, seenEvidence = <String>{};
    for (final raw in tables['revisions'] as List) {
      final revision = Map<String, Object?>.from(raw as Map);
      await tx.insert('revisions', {
        ...revision,
        'status': 'draft',
        'closed_at': null,
        'current_ticket_id': null,
      });
      for (final t in (tables['tickets'] as List).where(
        (t) => t['revision_id'] == revision['id'],
      )) {
        if (!seenTickets.add(t['id'] as String)) {
          throw const FormatException('Ficha duplicada en el respaldo.');
        }
        await tx.insert('tickets', Map<String, Object?>.from(t as Map));
        for (final e in (tables['evidence'] as List).where(
          (e) => e['ticket_id'] == t['id'],
        )) {
          if (!seenEvidence.add(e['id'] as String)) {
            throw const FormatException('Evidencia duplicada.');
          }
          await tx.insert('evidence', Map<String, Object?>.from(e as Map));
        }
      }
      final restored = {...revision}..remove('id');
      await tx.update(
        'revisions',
        restored,
        where: 'id=?',
        whereArgs: [revision['id']],
      );
    }
    if (seenTickets.length != (tables['tickets'] as List).length ||
        seenEvidence.length != (tables['evidence'] as List).length) {
      throw const FormatException('Relaciones incompletas en el respaldo.');
    }
    for (final table in [
      'audit_events',
      'artifacts',
      'admin_revisions',
      'admin_files',
      'received_events',
      'admin_events',
      'admin_links',
    ]) {
      await insertRows(table, tables[table] as List);
    }
    for (final raw in tables['settings'] as List) {
      final row = Map<String, Object?>.from(raw as Map);
      if ((await tx.query(
            'settings',
            where: 'key=?',
            whereArgs: [row['key']],
          )).isEmpty &&
          row['key'] != 'pending_photo') {
        await tx.insert('settings', row);
      }
    }
    if ((await tx.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
      throw const FormatException('El respaldo tiene relaciones inválidas.');
    }
    await _event(tx, 'backup_restored', null, {});
  });
  Future<List<Map<String, Object?>>> audit({
    String? date,
    String operator = '',
    String equipment = '',
    String action = '',
  }) async {
    final result = <Map<String, Object?>>[];
    for (final row in await db.rawQuery(
      'SELECT e.payload,r.date FROM received_events e JOIN admin_revisions r ON r.id=e.revision_id',
    )) {
      final e = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      result.add({
        'origin': 'Recibido',
        'date': row['date'],
        'actor': e['actor'] ?? '',
        'device': e['device_id'],
        'occurred_at': e['occurred_at'],
        'action': e['action'],
        'details': e['details'] ?? '',
        'id': e['id'],
      });
    }
    for (final row in await db.query('admin_events')) {
      result.add({...row, 'origin': 'Administrador'});
    }
    for (final row in await db.rawQuery(
      'SELECT e.*,r.operational_date FROM audit_events e JOIN revisions v ON v.id=e.revision_id JOIN reports r ON r.id=v.report_id',
    )) {
      result.add({
        ...row,
        'origin': 'Captura propia',
        'date': row['operational_date'],
        'device': row['device_id'],
      });
    }
    final unique = <String, Map<String, Object?>>{
      for (final event in result) event['id'] as String: event,
    };
    result
      ..clear()
      ..addAll(unique.values);
    result.retainWhere(
      (r) =>
          (date == null || r['date'] == date) &&
          r['actor'].toString().toLowerCase().contains(
            operator.toLowerCase(),
          ) &&
          r['device'].toString().toLowerCase().contains(
            equipment.toLowerCase(),
          ) &&
          r['action'].toString().toLowerCase().contains(action.toLowerCase()),
    );
    result.sort(
      (a, b) =>
          b['occurred_at'].toString().compareTo(a['occurred_at'].toString()),
    );
    return result;
  }
}
