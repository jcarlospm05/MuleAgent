import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mule_data/mule_data.dart';

String canonical(Object? value) {
  Object? sort(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final k in keys) k: sort(v[k])};
    }
    if (v is List) return v.map(sort).toList();
    return v;
  }

  return jsonEncode(sort(value));
}

String digest(List<int> bytes) => sha256.convert(bytes).toString();

class ReceivedReport {
  ReceivedReport._(
    this.report,
    this.revision,
    this.tickets,
    this.evidence,
    this.events,
    this.files,
    this.pdfPath,
  );
  final Map<String, dynamic> report, revision;
  final List<Map<String, dynamic>> tickets, evidence, events;
  final Map<String, Uint8List> files;
  final String pdfPath;
  String get id => revision['id'] as String;
  String get reportId => report['id'] as String;
  String get date => report['operational_date'] as String;
  String get stage => report['stage'] as String;
  int get number => revision['number'] as int;
  Map<String, dynamic> get core => {
    'reports': [report],
    'revisions': [revision],
    'tickets': tickets,
    'evidence': evidence,
    'pdf_sha256': digest(files[pdfPath]!),
  };
  String get fingerprint => digest(utf8.encode(canonical(core)));
  Map<String, dynamic> toJson() => {...core, 'audit_events': events};

  factory ReceivedReport.parse(Map<String, dynamic> payload) {
    Never fail() => throw const FormatException(
      'El paquete no contiene un reporte válido y completo del Operador.',
    );
    if (payload['kind'] != 'report' || payload['schema'] != 1) fail();
    final raw = payload['tables'];
    if (raw is! Map) fail();
    List<Map<String, dynamic>> list(String name) {
      final value = raw[name];
      if (value is! List || value.length > 20000) fail();
      try {
        return value.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {
        fail();
      }
    }

    final reports = list('reports'),
        revisions = list('revisions'),
        tickets = list('tickets'),
        evidence = list('evidence'),
        events = list('audit_events');
    if (reports.length != 1 ||
        revisions.length != 1 ||
        tickets.isEmpty ||
        tickets.length > 1000 ||
        tickets.length != evidence.length) {
      fail();
    }
    final report = reports.single, revision = revisions.single;
    bool id(Object? x) =>
        x is String && RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(x);
    if (!id(report['id']) ||
        !id(revision['id']) ||
        !id(report['device_id']) ||
        revision['report_id'] != report['id'] ||
        revision['status'] != 'closed' ||
        revision['current_ticket_id'] != null ||
        revision['number'] is! int ||
        revision['number'] < 1 ||
        revision['closed_at'] is! String ||
        report['operational_date'] is! String ||
        !['entry', 'exit'].contains(report['stage'])) {
      fail();
    }
    final date = report['operational_date'] as String;
    if (DateTime.tryParse(date)?.toIso8601String().substring(0, 10) != date) {
      fail();
    }
    final stage = Stage.values.byName(report['stage'] as String);
    final ticketIds = <String>{},
        logicalIds = <String>{},
        evidenceIds = <String>{},
        evidenceTickets = <String>{};
    for (final t in tickets) {
      if (!id(t['id']) ||
          !id(t['logical_id']) ||
          !ticketIds.add(t['id']) ||
          !logicalIds.add(t['logical_id']) ||
          t['revision_id'] != revision['id'] ||
          t['completed'] != 1) {
        fail();
      }
      for (final f in CaptureField.forStage(
        stage,
      ).where((f) => f.column != 'omission_reason')) {
        if (t[f.column] is! String ||
            f.validate(t[f.column] as String) != null) {
          fail();
        }
      }
    }
    final rawFiles = payload['files'];
    if (rawFiles is! Map || rawFiles.length > 2002) fail();
    final files = <String, Uint8List>{};
    var total = 0;
    for (final entry in rawFiles.entries) {
      final path = entry.key;
      if (path is! String ||
          !RegExp(r'^(media|artifacts)/[a-zA-Z0-9._/-]+$').hasMatch(path) ||
          path.split('/').any((p) => p.isEmpty || p == '.' || p == '..')) {
        fail();
      }
      final f = entry.value;
      if (f is! Map || f['bytes'] is! String || f['sha256'] is! String) fail();
      Uint8List bytes;
      try {
        bytes = base64Decode(f['bytes'] as String);
      } catch (_) {
        fail();
      }
      total += bytes.length;
      if (total > 100 * 1024 * 1024 || digest(bytes) != f['sha256']) fail();
      files[path] = bytes;
    }
    for (final e in evidence) {
      if (!id(e['id']) ||
          !evidenceIds.add(e['id']) ||
          !ticketIds.contains(e['ticket_id']) ||
          !evidenceTickets.add(e['ticket_id'])) {
        fail();
      }
      if (e['state'] == 'photo') {
        if (e['private_path'] is! String ||
            files[e['private_path']] == null ||
            files[e['private_path']]!.length > 20 * 1024 * 1024 ||
            digest(files[e['private_path']]!) != e['sha256'] ||
            e['omission_reason'] != null) {
          fail();
        }
      } else if (e['state'] == 'omitted') {
        if (e['omission_reason'] is! String ||
            (e['omission_reason'] as String).trim().isEmpty ||
            e['private_path'] != null) {
          fail();
        }
      } else {
        fail();
      }
    }
    final eventIds = <String>{};
    for (final e in events) {
      if (!id(e['id']) ||
          !eventIds.add(e['id']) ||
          e['revision_id'] != revision['id'] ||
          (e['ticket_id'] != null && !ticketIds.contains(e['ticket_id'])) ||
          e['occurred_at'] is! String ||
          e['device_id'] is! String ||
          e['action'] is! String) {
        fail();
      }
    }
    final pdf = payload['pdf'];
    if (pdf is! Map ||
        pdf['path'] is! String ||
        files[pdf['path']] == null ||
        digest(files[pdf['path']]!) != pdf['sha256']) {
      fail();
    }
    final expectedFiles = <String>{
      pdf['path'] as String,
      ...evidence
          .where((e) => e['state'] == 'photo')
          .map((e) => e['private_path'] as String),
    };
    if (files.length != expectedFiles.length ||
        !files.keys.every(expectedFiles.contains)) {
      fail();
    }
    final pdfBytes = files[pdf['path']]!;
    if (pdfBytes.length < 4 ||
        ascii.decode(pdfBytes.take(4).toList(), allowInvalid: true) != '%PDF') {
      fail();
    }
    tickets.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    evidence.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    events.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    return ReceivedReport._(
      report,
      revision,
      tickets,
      evidence,
      events,
      files,
      pdf['path'] as String,
    );
  }
}
