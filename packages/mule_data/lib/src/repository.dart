import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import 'capture.dart';
import 'dart:convert';

class CaptureSession {
  CaptureSession(this.id, this.stage, this.date);
  final String id, date;
  final Stage stage;
}

class CaptureRepository {
  CaptureRepository(this.db, {required this.deviceId});
  final Database db;
  final String deviceId;
  String operatorName = '';
  final _uuid = const Uuid();
  String get _now => DateTime.now().toUtc().toIso8601String();

  Future<CaptureSession?> resume() async {
    final rows = await db.rawQuery(
      '''SELECT v.id, r.stage, r.operational_date
      FROM revisions v JOIN reports r ON r.id=v.report_id
      WHERE v.status='draft' ORDER BY v.updated_at DESC, v.rowid DESC LIMIT 1''',
    );
    return rows.isEmpty ? null : _session(rows.single);
  }

  CaptureSession _session(Map<String, Object?> row) => CaptureSession(
    row['id'] as String,
    Stage.values.byName(row['stage'] as String),
    row['operational_date'] as String,
  );

  Future<CaptureSession> start(Stage stage, String date) async {
    final parsed = DateTime.tryParse(date);
    if (parsed == null || parsed.toIso8601String().substring(0, 10) != date) {
      throw ArgumentError('Invalid operational date');
    }
    return db.transaction((tx) async {
      final existing = await tx.rawQuery(
        '''SELECT v.id, r.stage, r.operational_date
        FROM revisions v JOIN reports r ON r.id=v.report_id
        WHERE v.status='draft' AND r.stage=? AND r.operational_date=? ''',
        [stage.name, date],
      );
      if (existing.isNotEmpty) return _session(existing.first);
      final closed = await tx.rawQuery(
        '''SELECT v.id, r.stage, r.operational_date FROM revisions v JOIN reports r ON r.id=v.report_id
        WHERE r.stage=? AND r.operational_date=? AND v.status='closed' ORDER BY v.number DESC, v.rowid DESC LIMIT 1''',
        [stage.name, date],
      );
      if (closed.isNotEmpty) return _session(closed.first);
      final report = _uuid.v4(), revision = _uuid.v4();
      await tx.insert('reports', {
        'id': report,
        'operational_date': date,
        'stage': stage.name,
        'device_id': deviceId,
        'created_at': _now,
      });
      await tx.insert('revisions', {
        'id': revision,
        'report_id': report,
        'number': 1,
        'updated_at': _now,
      });
      await _audit(tx, revision, null, 'report_started');
      return CaptureSession(revision, stage, date);
    });
  }

  Future<Draft?> draft(CaptureSession session) async {
    final rows = await db.rawQuery(
      '''SELECT t.*, v.current_step, e.omission_reason, e.state AS evidence_state, e.private_path
      FROM revisions v JOIN tickets t ON t.id=v.current_ticket_id
      JOIN evidence e ON e.ticket_id=t.id WHERE v.id=?''',
      [session.id],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return Draft(
      revisionId: session.id,
      ticketId: row['id'] as String,
      stage: session.stage,
      date: session.date,
      step: row['current_step'] as int,
      values: {
        for (final field in CaptureField.forStage(session.stage))
          field.column: row[field.column] as String? ?? '',
        'evidence_state': row['evidence_state'] as String,
        'private_path': row['private_path'] as String? ?? '',
      },
    );
  }

  Future<void> addTicket(CaptureSession session) => db.transaction((tx) async {
    await _requireDraft(tx, session.id);
    final revisions = await tx.query(
      'revisions',
      where: 'id=?',
      whereArgs: [session.id],
    );
    if (revisions.single['current_ticket_id'] != null) return;
    final ticket = _uuid.v4();
    await tx.insert('tickets', {
      'id': ticket,
      'revision_id': session.id,
      'logical_id': ticket,
      'updated_at': _now,
    });
    await tx.insert('evidence', {
      'id': _uuid.v4(),
      'ticket_id': ticket,
      'state': 'pending',
    });
    await tx.update(
      'revisions',
      {'current_ticket_id': ticket, 'current_step': 0, 'updated_at': _now},
      where: 'id=?',
      whereArgs: [session.id],
    );
    await _audit(tx, session.id, ticket, 'ticket_started');
  });

  /// Stores even an incomplete value. Advance and completion validate separately.
  Future<void> saveValue(Draft draft, String value) =>
      db.transaction((tx) async {
        await _requireCurrent(tx, draft);
        final field = draft.fields[draft.step];
        if (field.column == 'omission_reason') {
          final old = (await tx.query(
            'evidence',
            where: 'ticket_id=?',
            whereArgs: [draft.ticketId],
          )).single;
          if (old['state'] == 'photo') return;
          await tx.update(
            'evidence',
            {
              'state': value.trim().isEmpty ? 'pending' : 'omitted',
              'omission_reason': value.trim().isEmpty ? null : value,
              'private_path': null,
              'sha256': null,
              'source': null,
            },
            where: 'ticket_id=?',
            whereArgs: [draft.ticketId],
          );
        } else {
          await tx.update(
            'tickets',
            {field.column: value, 'updated_at': _now},
            where: 'id=?',
            whereArgs: [draft.ticketId],
          );
        }
        await _audit(
          tx,
          draft.revisionId,
          draft.ticketId,
          'field_saved:${field.column}',
        );
        await tx.update(
          'revisions',
          {'updated_at': _now},
          where: 'id=?',
          whereArgs: [draft.revisionId],
        );
      });

  Future<void> move(Draft draft, int step) => db.transaction((tx) async {
    await _requireCurrent(tx, draft);
    if (step < 0 || step >= draft.fields.length) {
      throw RangeError('Invalid step');
    }
    await tx.update(
      'revisions',
      {'current_step': step, 'updated_at': _now},
      where: 'id=?',
      whereArgs: [draft.revisionId],
    );
  });

  Future<void> complete(CaptureSession session, Draft draft) => db.transaction((
    tx,
  ) async {
    await _requireCurrent(tx, draft);
    if (session.id != draft.revisionId) throw StateError('Wrong session');
    final ticket = (await tx.query(
      'tickets',
      where: 'id=?',
      whereArgs: [draft.ticketId],
    )).single;
    final evidence = (await tx.query(
      'evidence',
      where: 'ticket_id=?',
      whereArgs: [draft.ticketId],
    )).single;
    for (final field in draft.fields) {
      if (field.column == 'omission_reason' && evidence['state'] == 'photo') {
        continue;
      }
      final value =
          (field.column == 'omission_reason'
                  ? evidence[field.column]
                  : ticket[field.column])
              as String? ??
          '';
      final error = field.validate(value);
      if (error != null) throw StateError('${field.title}: $error');
    }
    await tx.update(
      'tickets',
      {'completed': 1, 'updated_at': _now},
      where: 'id=?',
      whereArgs: [draft.ticketId],
    );
    await tx.update(
      'revisions',
      {'current_ticket_id': null, 'current_step': 0, 'updated_at': _now},
      where: 'id=?',
      whereArgs: [session.id],
    );
    await _audit(tx, session.id, draft.ticketId, 'ticket_completed');
  });

  Future<List<Map<String, Object?>>> tickets(CaptureSession session) =>
      db.rawQuery(
        '''
    SELECT t.*, e.state AS evidence_state, e.omission_reason, e.private_path, e.sha256, e.source FROM tickets t
    JOIN evidence e ON e.ticket_id=t.id WHERE t.revision_id=? ORDER BY t.rowid''',
        [session.id],
      );

  Future<void> edit(CaptureSession session, String ticketId) => db.transaction((
    tx,
  ) async {
    await _requireDraft(tx, session.id);
    final revision = (await tx.query(
      'revisions',
      where: 'id=?',
      whereArgs: [session.id],
    )).single;
    if (revision['current_ticket_id'] != null) {
      throw StateError('Finish the current ticket first');
    }
    final updated = await tx.update(
      'tickets',
      {'completed': 0},
      where: 'id=? AND revision_id=?',
      whereArgs: [ticketId, session.id],
    );
    if (updated != 1) throw StateError('Unknown ticket');
    await tx.update(
      'revisions',
      {'current_ticket_id': ticketId, 'current_step': 0, 'updated_at': _now},
      where: 'id=?',
      whereArgs: [session.id],
    );
    await _audit(tx, session.id, ticketId, 'ticket_edit_started');
  });

  Future<void> setSetting(String key, String value) async {
    await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> setting(String key) async {
    final rows = await db.query('settings', where: 'key=?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Future<List<Map<String, Object?>>> sessions({
    bool closed = false,
  }) => db.rawQuery(
    "SELECT v.*, r.operational_date, r.stage, r.device_id FROM revisions v JOIN reports r ON r.id=v.report_id WHERE v.status=? ORDER BY r.operational_date DESC, v.number DESC",
    [closed ? 'closed' : 'draft'],
  );
  Future<CaptureSession> sessionById(String id) async {
    final row = (await db.rawQuery(
      'SELECT v.id, r.stage, r.operational_date FROM revisions v JOIN reports r ON r.id=v.report_id WHERE v.id=?',
      [id],
    )).single;
    return _session(row);
  }

  Future<void> attachPhoto(
    Draft draft,
    String relativePath,
    String digest,
    String source,
  ) => db.transaction((tx) async {
    await _requireCurrent(tx, draft);
    await tx.update(
      'evidence',
      {
        'state': 'photo',
        'private_path': relativePath,
        'sha256': digest,
        'source': source,
        'omission_reason': null,
      },
      where: 'ticket_id=?',
      whereArgs: [draft.ticketId],
    );
    await _audit(tx, draft.revisionId, draft.ticketId, 'photo_attached');
  });
  Future<void> clearPhoto(Draft draft) => db.transaction((tx) async {
    await _requireCurrent(tx, draft);
    await tx.update(
      'evidence',
      {
        'state': 'pending',
        'private_path': null,
        'sha256': null,
        'source': null,
        'omission_reason': null,
      },
      where: 'ticket_id=?',
      whereArgs: [draft.ticketId],
    );
    await _audit(tx, draft.revisionId, draft.ticketId, 'photo_removed');
  });
  Future<void> closeRevision(CaptureSession session) =>
      db.transaction((tx) async {
        await _requireDraft(tx, session.id);
        await tx.update(
          'revisions',
          {'status': 'closed', 'closed_at': _now, 'updated_at': _now},
          where: 'id=?',
          whereArgs: [session.id],
        );
        await _audit(tx, session.id, null, 'revision_closed');
      });
  Future<CaptureSession> reopen(CaptureSession session) =>
      db.transaction((tx) async {
        final old = (await tx.query(
          'revisions',
          where: 'id=?',
          whereArgs: [session.id],
        )).single;
        if (old['status'] != 'closed') {
          throw StateError('La etapa no está cerrada.');
        }
        final drafts = await tx.query(
          'revisions',
          where: 'report_id=? AND status=?',
          whereArgs: [old['report_id'], 'draft'],
        );
        if (drafts.isNotEmpty) {
          return CaptureSession(
            drafts.single['id'] as String,
            session.stage,
            session.date,
          );
        }
        final max =
            (await tx.rawQuery(
                  'SELECT max(number) AS n FROM revisions WHERE report_id=?',
                  [old['report_id']],
                )).single['n']
                as int;
        if (old['number'] != max) {
          throw StateError(
            'Abre la revisión más reciente para continuar esta jornada.',
          );
        }
        final id = _uuid.v4();
        await tx.insert('revisions', {
          'id': id,
          'report_id': old['report_id'],
          'number': max + 1,
          'updated_at': _now,
        });
        final tickets = await tx.query(
          'tickets',
          where: 'revision_id=?',
          whereArgs: [session.id],
        );
        for (final ticket in tickets) {
          final ticketId = _uuid.v4();
          await tx.insert('tickets', {
            ...ticket,
            'id': ticketId,
            'revision_id': id,
          });
          final evidence = (await tx.query(
            'evidence',
            where: 'ticket_id=?',
            whereArgs: [ticket['id']],
          )).single;
          await tx.insert('evidence', {
            ...evidence,
            'id': _uuid.v4(),
            'ticket_id': ticketId,
          });
        }
        await _audit(tx, id, null, 'revision_reopened');
        return CaptureSession(id, session.stage, session.date);
      });
  Future<void> recordShare(CaptureSession session) =>
      db.transaction((tx) => _audit(tx, session.id, null, 'share_started'));
  Future<Map<String, dynamic>> snapshot({
    String? revisionId,
  }) => db.transaction((tx) async {
    final tables = <String, dynamic>{};
    if (revisionId == null) {
      for (final table in [
        'reports',
        'revisions',
        'tickets',
        'evidence',
        'audit_events',
        'settings',
        'artifacts',
      ]) {
        tables[table] = await tx.query(table);
      }
    } else {
      final revision = (await tx.query(
        'revisions',
        where: 'id=?',
        whereArgs: [revisionId],
      )).single;
      if (revision['status'] != 'closed') {
        throw StateError('La revisión todavía está abierta.');
      }
      tables['reports'] = await tx.query(
        'reports',
        where: 'id=?',
        whereArgs: [revision['report_id']],
      );
      tables['revisions'] = [revision];
      tables['tickets'] = await tx.query(
        'tickets',
        where: 'revision_id=?',
        whereArgs: [revisionId],
      );
      tables['evidence'] = await tx.rawQuery(
        'SELECT e.* FROM evidence e JOIN tickets t ON t.id=e.ticket_id WHERE t.revision_id=?',
        [revisionId],
      );
      tables['audit_events'] = await tx.query(
        'audit_events',
        where: 'revision_id=?',
        whereArgs: [revisionId],
      );
    }
    return {
      'schema': 1,
      'kind': revisionId == null ? 'backup' : 'report',
      'created_at': _now,
      'tables': tables,
    };
  });

  /// Merge a validated backup without overwriting different local rows.
  Future<void> restore(Map<String, dynamic> payload) => db.transaction((
    tx,
  ) async {
    if (payload['schema'] != 1 || payload['kind'] != 'backup') {
      throw const FormatException('Selecciona un respaldo completo.');
    }
    final tables = payload['tables'] as Map<String, dynamic>;
    final allowed = [
      'reports',
      'revisions',
      'tickets',
      'evidence',
      'audit_events',
      'settings',
      'artifacts',
    ];
    if (tables.keys.length != allowed.length ||
        !allowed.every(tables.containsKey)) {
      throw const FormatException('Estructura de respaldo inválida.');
    }
    Future<bool> insertChecked(String table, Map<String, Object?> row) async {
      final key = table == 'settings'
          ? 'key'
          : table == 'artifacts'
          ? 'revision_id'
          : 'id';
      final existing = await tx.query(
        table,
        where: '$key=?',
        whereArgs: [row[key]],
      );
      if (existing.isNotEmpty) {
        if (table == 'settings') return false;
        if (!_same(existing.single, row)) {
          throw StateError(
            'El respaldo contiene cambios distintos para un registro existente. Restaura en una instalación nueva.',
          );
        }
        return false;
      }
      await tx.insert(table, row);
      return true;
    }

    for (final raw in tables['reports'] as List) {
      await insertChecked('reports', Map<String, Object?>.from(raw as Map));
    }
    final seenTickets = <String>{}, seenEvidence = <String>{};
    for (final raw in tables['revisions'] as List) {
      final revision = Map<String, Object?>.from(raw as Map);
      final existing = await tx.query(
        'revisions',
        where: 'id=?',
        whereArgs: [revision['id']],
      );
      if (existing.isNotEmpty && !_same(existing.single, revision)) {
        throw StateError(
          'Una jornada local difiere del respaldo. Restaura en una instalación nueva.',
        );
      }
      if (existing.isEmpty) {
        await tx.insert('revisions', {
          ...revision,
          'status': 'draft',
          'closed_at': null,
          'current_ticket_id': null,
        });
      }
      for (final ticketRaw in (tables['tickets'] as List).where(
        (t) => t['revision_id'] == revision['id'],
      )) {
        final ticket = Map<String, Object?>.from(ticketRaw as Map);
        if (!seenTickets.add(ticket['id'] as String)) {
          throw const FormatException('Ficha duplicada.');
        }
        await insertChecked('tickets', ticket);
        for (final evidenceRaw in (tables['evidence'] as List).where(
          (e) => e['ticket_id'] == ticket['id'],
        )) {
          final evidence = Map<String, Object?>.from(evidenceRaw as Map);
          if (!seenEvidence.add(evidence['id'] as String)) {
            throw const FormatException('Evidencia duplicada.');
          }
          await insertChecked('evidence', evidence);
        }
      }
      if (existing.isEmpty) {
        final update = {...revision}..remove('id');
        await tx.update(
          'revisions',
          update,
          where: 'id=?',
          whereArgs: [revision['id']],
        );
      }
    }
    if (seenTickets.length != (tables['tickets'] as List).length ||
        seenEvidence.length != (tables['evidence'] as List).length) {
      throw const FormatException('Relaciones inválidas en el respaldo.');
    }
    for (final table in ['audit_events', 'settings', 'artifacts']) {
      for (final raw in tables[table] as List) {
        await insertChecked(table, Map<String, Object?>.from(raw as Map));
      }
    }
    if ((await tx.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
      throw const FormatException('Relaciones incompletas en el respaldo.');
    }
  });
  bool _same(Map<String, Object?> a, Map<String, Object?> b) =>
      a.length == b.length &&
      a.keys.every((k) => jsonEncode(a[k]) == jsonEncode(b[k]));

  Future<void> _requireDraft(Transaction tx, String id) async {
    final rows = await tx.query(
      'revisions',
      where: 'id=? AND status=?',
      whereArgs: [id, 'draft'],
    );
    if (rows.length != 1) throw StateError('Revision is not editable');
  }

  Future<void> _requireCurrent(Transaction tx, Draft draft) async {
    await _requireDraft(tx, draft.revisionId);
    final rows = await tx.query(
      'revisions',
      where: 'id=? AND current_ticket_id=? AND current_step=?',
      whereArgs: [draft.revisionId, draft.ticketId, draft.step],
    );
    if (rows.length != 1) throw StateError('Stale capture step');
  }

  Future<void> _audit(
    Transaction tx,
    String revision,
    String? ticket,
    String action,
  ) => tx.insert('audit_events', {
    'id': _uuid.v4(),
    'revision_id': revision,
    'ticket_id': ticket,
    'device_id': deviceId,
    'actor': operatorName,
    'occurred_at': _now,
    'action': action,
  });
}
