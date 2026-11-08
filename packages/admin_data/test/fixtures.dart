import 'dart:convert';
import 'package:admin_data/admin_data.dart';

Map<String, dynamic> packet({
  String stage = 'entry',
  String report = 'report-e',
  String revision = 'revision-e1',
  int number = 1,
  String code = '000362',
  String date = '2026-11-07',
}) {
  final pdf = utf8.encode('%PDF-1.4\n$revision\n%%EOF');
  final path = 'artifacts/$revision.pdf';
  return {
    'kind': 'report',
    'schema': 1,
    'created_at': '2026-11-07T20:00:00Z',
    'tables': {
      'reports': [
        {
          'id': report,
          'operational_date': date,
          'stage': stage,
          'device_id': 'device-op',
          'created_at': '2026-11-07T07:00:00Z',
        },
      ],
      'revisions': [
        {
          'id': revision,
          'report_id': report,
          'number': number,
          'status': 'closed',
          'current_ticket_id': null,
          'current_step': 0,
          'updated_at': '2026-11-07T19:00:00Z',
          'closed_at': '2026-11-07T19:00:00Z',
        },
      ],
      'tickets': [
        {
          'id': '$revision-ticket',
          'revision_id': revision,
          'logical_id': '$report-logical',
          'code': code,
          'provider': 'Proveedor A',
          'driver': stage == 'entry' ? 'Julio' : null,
          'time': stage == 'entry' ? '07:04' : '19:16',
          'meter': stage == 'entry' ? '111410.7' : '111421.9',
          'completed': 1,
          'updated_at': '2026-11-07T19:00:00Z',
        },
      ],
      'evidence': [
        {
          'id': '$revision-evidence',
          'ticket_id': '$revision-ticket',
          'state': 'omitted',
          'private_path': null,
          'sha256': null,
          'source': null,
          'omission_reason': 'No se pudo tomar la foto',
        },
      ],
      'audit_events': [
        {
          'id': '$revision-event',
          'revision_id': revision,
          'ticket_id': '$revision-ticket',
          'device_id': 'device-op',
          'occurred_at': '2026-11-07T19:00:00Z',
          'actor': 'Julio',
          'action': 'ticket_completed',
          'details': null,
        },
      ],
    },
    'files': {
      path: {'bytes': base64Encode(pdf), 'sha256': digest(pdf)},
    },
    'pdf': {'path': path, 'sha256': digest(pdf)},
  };
}

Map<String, String> paths(ReceivedReport r) => {
  for (final p in r.files.keys)
    p: 'artifacts/imports/${r.id}/${p.split('/').last}',
};
