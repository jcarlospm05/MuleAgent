import 'package:sqflite_common/sqlite_api.dart';

/// v1: almacenamiento local. El cifrado lo aplica el adaptador de cada app.
const schemaVersion = 2;

Future<void> configureDatabase(Database db) =>
    db.execute('PRAGMA foreign_keys = ON');

Future<void> createSchema(Database db, int version) async {
  for (final sql in schemaV1) {
    await db.execute(sql);
  }
  await upgradeSchema(db, 1, version);
}

Future<void> upgradeSchema(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2 && newVersion >= 2) {
    for (final sql in schemaV2) {
      await db.execute(sql);
    }
  }
}

const schemaV2 = <String>[
  "ALTER TABLE audit_events ADD COLUMN actor TEXT NOT NULL DEFAULT ''",
  "ALTER TABLE audit_events ADD COLUMN details TEXT",
  "CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
  "CREATE TABLE artifacts (revision_id TEXT PRIMARY KEY REFERENCES revisions(id), pdf_path TEXT NOT NULL, package_path TEXT NOT NULL, pdf_sha256 TEXT NOT NULL, created_at TEXT NOT NULL)",
];

const schemaV1 = <String>[
  '''CREATE TABLE reports (
    id TEXT PRIMARY KEY,
    operational_date TEXT NOT NULL CHECK(length(operational_date) = 10),
    stage TEXT NOT NULL CHECK(stage IN ('entry','exit')),
    device_id TEXT NOT NULL,
    created_at TEXT NOT NULL
  )''',
  '''CREATE TABLE revisions (
    id TEXT PRIMARY KEY,
    report_id TEXT NOT NULL REFERENCES reports(id),
    number INTEGER NOT NULL CHECK(number > 0),
    status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','closed')),
    current_ticket_id TEXT REFERENCES tickets(id),
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    current_step INTEGER NOT NULL DEFAULT 0 CHECK(current_step BETWEEN 0 AND 5),
    closed_at TEXT,
    UNIQUE(report_id, number),
    CHECK((status = 'draft' AND closed_at IS NULL) OR
          (status = 'closed' AND closed_at IS NOT NULL AND current_ticket_id IS NULL))
  )''',
  '''CREATE UNIQUE INDEX one_draft_per_report ON revisions(report_id)
     WHERE status = 'draft' ''',
  '''CREATE TABLE tickets (
    id TEXT PRIMARY KEY,
    revision_id TEXT NOT NULL REFERENCES revisions(id),
    logical_id TEXT NOT NULL,
    code TEXT, provider TEXT, driver TEXT, time TEXT, meter TEXT,
    completed INTEGER NOT NULL DEFAULT 0 CHECK(completed IN (0,1)),
    updated_at TEXT NOT NULL,
    UNIQUE(revision_id, logical_id)
  )''',
  'CREATE INDEX tickets_revision ON tickets(revision_id)',
  '''CREATE TABLE evidence (
    id TEXT PRIMARY KEY,
    ticket_id TEXT NOT NULL UNIQUE REFERENCES tickets(id),
    state TEXT NOT NULL CHECK(state IN ('pending','photo','omitted')),
    private_path TEXT, sha256 TEXT, source TEXT, omission_reason TEXT,
    CHECK((state = 'pending' AND private_path IS NULL AND omission_reason IS NULL) OR
      (state = 'photo' AND private_path IS NOT NULL AND sha256 IS NOT NULL AND source IS NOT NULL AND omission_reason IS NULL) OR
      (state = 'omitted' AND private_path IS NULL AND omission_reason IS NOT NULL AND length(trim(omission_reason)) > 0))
  )''',
  '''CREATE TABLE audit_events (
    id TEXT PRIMARY KEY,
    revision_id TEXT NOT NULL REFERENCES revisions(id),
    ticket_id TEXT REFERENCES tickets(id),
    device_id TEXT NOT NULL,
    occurred_at TEXT NOT NULL,
    action TEXT NOT NULL
  )''',
  'CREATE INDEX audit_revision ON audit_events(revision_id, occurred_at)',
  '''CREATE TRIGGER current_ticket_belongs_to_revision BEFORE UPDATE OF current_ticket_id ON revisions
    WHEN NEW.current_ticket_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM tickets WHERE id = NEW.current_ticket_id AND revision_id = NEW.id AND completed = 0)
    BEGIN SELECT RAISE(ABORT, 'Invalid current ticket'); END''',
  '''CREATE TRIGGER closed_revision_immutable BEFORE UPDATE ON revisions
    WHEN OLD.status = 'closed'
    BEGIN SELECT RAISE(ABORT, 'Closed revision is immutable'); END''',
  '''CREATE TRIGGER closed_revision_no_delete BEFORE DELETE ON revisions
    WHEN OLD.status = 'closed'
    BEGIN SELECT RAISE(ABORT, 'Closed revision is immutable'); END''',
  '''CREATE TRIGGER close_requires_complete BEFORE UPDATE OF status ON revisions
    WHEN NEW.status = 'closed' AND (
      NOT EXISTS (SELECT 1 FROM tickets WHERE revision_id = NEW.id) OR
      EXISTS (SELECT 1 FROM tickets t LEFT JOIN evidence e ON e.ticket_id = t.id
        JOIN reports r ON r.id = NEW.report_id
        WHERE t.revision_id = NEW.id AND (t.completed = 0 OR
          length(trim(coalesce(t.code,''))) = 0 OR length(trim(coalesce(t.provider,''))) = 0 OR
          t.time IS NULL OR t.meter IS NULL OR
          (r.stage = 'entry' AND length(trim(coalesce(t.driver,''))) = 0) OR
          e.state IS NULL OR e.state = 'pending')))
    BEGIN SELECT RAISE(ABORT, 'Incomplete revision'); END''',
  """CREATE TRIGGER report_closed_no_update BEFORE UPDATE ON reports
    WHEN EXISTS (SELECT 1 FROM revisions WHERE report_id=OLD.id AND status='closed')
    BEGIN SELECT RAISE(ABORT, 'Closed report identity is immutable'); END""",
  ..._ticketGuards,
  ..._evidenceGuards,
  '''CREATE TRIGGER audit_no_update BEFORE UPDATE ON audit_events
    BEGIN SELECT RAISE(ABORT, 'Audit is append only'); END''',
  '''CREATE TRIGGER audit_no_delete BEFORE DELETE ON audit_events
    BEGIN SELECT RAISE(ABORT, 'Audit is append only'); END''',
];

const _ticketGuards = [
  '''CREATE TRIGGER ticket_no_insert_closed BEFORE INSERT ON tickets
    WHEN (SELECT status FROM revisions WHERE id = NEW.revision_id) = 'closed'
    BEGIN SELECT RAISE(ABORT, 'Closed revision is immutable'); END''',
  '''CREATE TRIGGER ticket_no_update_closed BEFORE UPDATE ON tickets
    WHEN (SELECT status FROM revisions WHERE id = OLD.revision_id) = 'closed'
      OR NEW.revision_id != OLD.revision_id OR NEW.logical_id != OLD.logical_id
    BEGIN SELECT RAISE(ABORT, 'Ticket revision is immutable'); END''',
  '''CREATE TRIGGER ticket_no_delete_closed BEFORE DELETE ON tickets
    WHEN (SELECT status FROM revisions WHERE id = OLD.revision_id) = 'closed'
    BEGIN SELECT RAISE(ABORT, 'Closed revision is immutable'); END''',
];
const _evidenceGuards = [
  '''CREATE TRIGGER evidence_no_insert_closed BEFORE INSERT ON evidence
    WHEN (SELECT r.status FROM revisions r JOIN tickets t ON t.revision_id=r.id WHERE t.id=NEW.ticket_id) = 'closed'
    BEGIN SELECT RAISE(ABORT, 'Closed evidence is immutable'); END''',
  '''CREATE TRIGGER evidence_no_update_closed BEFORE UPDATE ON evidence
    WHEN (SELECT r.status FROM revisions r JOIN tickets t ON t.revision_id=r.id WHERE t.id=OLD.ticket_id) = 'closed'
      OR NEW.ticket_id != OLD.ticket_id
    BEGIN SELECT RAISE(ABORT, 'Evidence identity is immutable'); END''',
  '''CREATE TRIGGER evidence_no_delete_closed BEFORE DELETE ON evidence
    WHEN (SELECT r.status FROM revisions r JOIN tickets t ON t.revision_id=r.id WHERE t.id=OLD.ticket_id) = 'closed'
    BEGIN SELECT RAISE(ABORT, 'Closed evidence is immutable'); END''',
];
