import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import 'capture.dart';

class CaptureSession {
  CaptureSession(this.id, this.stage, this.date);
  final String id, date;
  final Stage stage;
}

class CaptureRepository {
  CaptureRepository(this.db, {required this.deviceId});
  final Database db;
  final String deviceId;
  final _uuid = const Uuid();
  String get _now => DateTime.now().toUtc().toIso8601String();

  Future<CaptureSession?> resume() async {
    final rows = await db.rawQuery(
      '''SELECT v.id, r.stage, r.operational_date
      FROM revisions v JOIN reports r ON r.id=v.report_id
      WHERE v.status='draft' AND r.device_id=? ORDER BY v.updated_at DESC, v.rowid DESC LIMIT 1''',
      [deviceId],
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
        WHERE v.status='draft' AND r.stage=? AND r.operational_date=? AND r.device_id=?''',
        [stage.name, date, deviceId],
      );
      if (existing.isNotEmpty) return _session(existing.first);
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
      '''SELECT t.*, v.current_step, e.omission_reason
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
          await tx.update(
            'evidence',
            {
              'state': value.trim().isEmpty ? 'pending' : 'omitted',
              'omission_reason': value.trim().isEmpty ? null : value,
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

  Future<void> complete(CaptureSession session, Draft draft) =>
      db.transaction((tx) async {
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
    SELECT t.*, e.state AS evidence_state, e.omission_reason FROM tickets t
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
    'occurred_at': _now,
    'action': action,
  });
}
