import 'dart:convert';
import 'dart:io';
import 'package:admin_data/admin_data.dart';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;
import 'package:mule_data/mule_data.dart';
import 'package:operador/services.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'workbook.dart';

ReceivedReport parseIncoming(Map<String, dynamic> payload) =>
    ReceivedReport.parse(payload);

class Receipt {
  Receipt(this.report, this.result);
  final ReceivedReport report;
  final ImportResult result;
}

class AdminServices {
  AdminServices(this.repo, this.capture, this.storage);
  final AdminRepository repo;
  final CaptureRepository capture;
  final OperatorServices storage;
  Future<void> checkExportPhotos(Iterable<Map<String, Object?>> rows) async {
    var size = 0;
    for (final row in rows) {
      if (row['photo_path'] != null) {
        size += await storage.file(row['photo_path'] as String).length();
      }
      if (size > 100 * 1024 * 1024) {
        throw StateError(
          'La selección supera 100 MB de fotos. Exporta por etapa o por reporte.',
        );
      }
    }
  }

  Future<Receipt?> receive({String? key}) async {
    final selected = await FilePicker.platform.pickFiles(type: FileType.any);
    if (selected == null) return null;
    final path = selected.files.single.path;
    if (path == null) throw StateError('No se pudo abrir el archivo.');
    final file = File(path);
    if (await file.length() > PackageCodec.maxBytes * 2) {
      throw StateError('Archivo demasiado grande.');
    }
    return importBytes(
      await file.readAsBytes(),
      key ?? await storage.password(),
    );
  }

  Future<Receipt> importBytes(Uint8List bytes, String key) async {
    final payload = await compute(decryptPayload, {
      'bytes': bytes,
      'password': key,
    });
    final report = await compute(parseIncoming, payload);
    return saveReport(report, source: 'received', package: bytes);
  }

  Future<Receipt> saveReport(
    ReceivedReport report, {
    required String source,
    Uint8List? package,
  }) async {
    final paths = <String, String>{}, created = <File>[];
    try {
      for (final entry in report.files.entries) {
        final prefix = entry.key.startsWith('media/') ? 'media' : 'artifacts';
        final extension = p
            .extension(entry.key)
            .replaceAll(RegExp(r'[^a-zA-Z0-9.]'), '');
        final path =
            '$prefix/imports/${report.id}/${digest(utf8.encode(entry.key))}$extension';
        final file = storage.file(path);
        if (await file.exists()) {
          if (digest(await file.readAsBytes()) != digest(entry.value)) {
            throw StateError(
              'El archivo recibido difiere de un original existente.',
            );
          }
        } else {
          await storage.writeAtomic(path, entry.value);
          created.add(file);
        }
        paths[entry.key] = path;
      }
      String? packagePath;
      if (package != null) {
        packagePath = 'artifacts/imports/${report.id}/original.mule';
        final target = storage.file(packagePath);
        if (!await target.exists()) {
          await storage.writeAtomic(packagePath, package);
          created.add(target);
        }
      }
      final result = await repo.importReport(
        report,
        paths,
        source: source,
        packagePath: packagePath,
      );
      return Receipt(report, result);
    } catch (_) {
      for (final file in created) {
        if (await file.exists()) await file.delete();
      }
      rethrow;
    }
  }

  Future<void> syncOwn() async {
    for (final row in await capture.sessions(closed: true)) {
      if ((await repo.db.query(
        'admin_revisions',
        where: 'id=?',
        whereArgs: [row['id']],
      )).isNotEmpty) {
        continue;
      }
      final session = await capture.sessionById(row['id'] as String);
      final artifacts = await storage.ensureArtifacts(session);
      final payload = await storage.includeFiles(
        await capture.snapshot(revisionId: session.id),
        extra: [artifacts['pdf_path'] as String],
      );
      payload['pdf'] = {
        'path': artifacts['pdf_path'],
        'sha256': artifacts['pdf_sha256'],
      };
      final report = await compute(parseIncoming, payload);
      await saveReport(report, source: 'own');
    }
  }

  Future<void> originalPdf(String revision) async {
    final row = await repo.revision(revision);
    final bytes = await storage.file(row['pdf_path'] as String).readAsBytes();
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Reporte original.pdf',
    );
    await repo.event(
      'original_pdf_opened',
      date: row['date'] as String,
      details: {'revision': revision},
    );
  }

  Future<bool> save(String filename, Uint8List bytes) async =>
      await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar $filename',
        fileName: filename,
        bytes: bytes,
      ) !=
      null;
  Future<void> originalPhoto(Map<String, Object?> row) async {
    final path = row['photo_path'] as String;
    final code = row['code'].toString().replaceAll(
      RegExp(r'[^a-zA-Z0-9 _-]'),
      '_',
    );
    if (await save(
      '$code ${row['date']} ${row['stage']}-${row['id'].toString().substring(0, 8)}${p.extension(path)}',
      await storage.file(path).readAsBytes(),
    )) {
      await repo.event(
        'original_photo_exported',
        date: row['date'] as String,
        details: {'ticket': row['id']},
      );
    }
  }

  Future<Uint8List> pdf(String date, String scope) async {
    var rows = await repo.tickets(date);
    final links = await repo.links(date);
    if (scope == 'entry' || scope == 'exit') {
      rows = rows.where((r) => r['stage'] == scope).toList();
    }
    if (scope != 'links') await checkExportPhotos(rows);
    final doc = pw.Document();
    if (scope == 'links') {
      final all = await repo.tickets(date);
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (_) => [
            pw.Text(
              'MuleAgent · Cruce manual · $date',
              style: const pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headers: ['Entrada', 'Despacho', 'Estado'],
              data: links
                  .map(
                    (l) => [
                      l['entry_code'],
                      l['exit_code'],
                      l['stale'] == true
                          ? 'Revisar nueva versión'
                          : 'Confirmado',
                    ],
                  )
                  .toList(),
            ),
            pw.SizedBox(height: 16),
            pw.Text('Fichas sin vínculo vigente'),
            pw.TableHelper.fromTextArray(
              headers: ['Etapa', 'Ficha', 'Proveedor'],
              data: all
                  .where(
                    (t) => !links.any(
                      (l) =>
                          l['stale'] != true &&
                          (l['entry_ticket'] == t['id'] ||
                              l['exit_ticket'] == t['id']),
                    ),
                  )
                  .map(
                    (r) => [
                      r['stage'] == 'entry' ? 'Entrada' : 'Despacho',
                      r['code'],
                      r['provider'],
                    ],
                  )
                  .toList(),
            ),
          ],
        ),
      );
    } else {
      if (rows.isEmpty) {
        doc.addPage(
          pw.Page(
            build: (_) =>
                pw.Text('MuleAgent · $date · Sin fichas en esta selección.'),
          ),
        );
      }
      for (final row in rows) {
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(28),
            build: (_) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(
                  'MuleAgent · ${row['stage'] == 'entry' ? 'Entrada' : 'Despacho'} · $date',
                  style: const pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'Ficha ${row['code']}',
                  style: const pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (row['driver'] != null) pw.Text('Mulero: ${row['driver']}'),
                pw.Text('Proveedor: ${row['provider']}'),
                pw.Text('Hora: ${row['time']} · Horómetro: ${row['meter']} h'),
                pw.Text(
                  'Origen: ${row['source'] == 'own' ? 'Captura propia' : 'Recibido'} · Revisión ${row['revision_number']}',
                ),
                pw.SizedBox(height: 16),
                if (row['photo_path'] != null)
                  pw.Image(
                    pw.MemoryImage(
                      storage
                          .file(row['photo_path'] as String)
                          .readAsBytesSync(),
                      dpi: 180,
                    ),
                    height: 300,
                    fit: pw.BoxFit.contain,
                  )
                else
                  pw.Text('Foto omitida: ${row['omission_reason']}'),
                pw.Spacer(),
                pw.Text(
                  'Reporte ${row['report_id']}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
          ),
        );
      }
    }
    return doc.save();
  }

  Future<void> preview(String date, String scope) async {
    final bytes = await pdf(date, scope);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'MuleAgent $date.pdf',
    );
    await repo.event(
      'pdf_print_flow_opened',
      date: date,
      details: {'scope': scope},
    );
  }

  Future<void> exportPdf(String date, String scope) async {
    if (await save('MuleAgent $date $scope.pdf', await pdf(date, scope))) {
      await repo.event('pdf_exported', date: date, details: {'scope': scope});
    }
  }

  Future<Uint8List> excel(String date, String scope) async {
    final all = await repo.tickets(date), links = await repo.links(date);
    await checkExportPhotos(
      all.where(
        (r) => !['entry', 'exit'].contains(scope) || r['stage'] == scope,
      ),
    );
    final sheets = <WorkbookSheet>[];
    for (final stage in ['entry', 'exit']) {
      if ((scope == 'entry' || scope == 'exit') && scope != stage) continue;
      final rows = <List<Object?>>[
        [
          'Ficha',
          'Mulero',
          'Proveedor',
          'Hora',
          'Horómetro',
          'Evidencia',
          'Foto',
          'SHA-256 original',
          'Origen',
          'Revisión',
          'Equipo',
          'ID de reporte',
          'ID de ficha',
        ],
      ];
      final photos = <int, Uint8List>{};
      for (final t in all.where((r) => r['stage'] == stage)) {
        rows.add([
          t['code'],
          t['driver'],
          t['provider'],
          t['time'],
          t['meter'],
          t['evidence_state'] == 'photo'
              ? 'Foto original disponible'
              : 'Omitida: ${t['omission_reason']}',
          '',
          t['sha256'],
          t['source'] == 'own' ? 'Propio' : 'Recibido',
          t['revision_number'],
          t['device'],
          t['report_id'],
          t['logical_id'],
        ]);
        if (t['photo_path'] != null) {
          final original = image.decodeImage(
            await storage.file(t['photo_path'] as String).readAsBytes(),
          );
          if (original == null) {
            throw StateError('No se pudo leer una foto original.');
          }
          photos[rows.length] = Uint8List.fromList(
            image.encodeJpg(
              image.copyResize(original, width: 400),
              quality: 80,
            ),
          );
        }
      }
      sheets.add(
        WorkbookSheet(
          stage == 'entry' ? 'Entradas' : 'Despachos',
          rows,
          photos: photos,
        ),
      );
    }
    sheets.add(
      WorkbookSheet('Vínculos', [
        ['Entrada', 'Despacho', 'Estado', 'ID entrada', 'ID despacho'],
        ...links.map(
          (l) => [
            l['entry_code'],
            l['exit_code'],
            l['stale'] == true ? 'Revisar' : 'Confirmado',
            l['entry_ticket'],
            l['exit_ticket'],
          ],
        ),
        ...all
            .where(
              (t) => !links.any(
                (l) =>
                    l['stale'] != true &&
                    (l['entry_ticket'] == t['id'] ||
                        l['exit_ticket'] == t['id']),
              ),
            )
            .map(
              (t) => [
                t['stage'] == 'entry' ? t['code'] : '',
                t['stage'] == 'exit' ? t['code'] : '',
                'Pendiente',
                t['id'],
                '',
              ],
            ),
      ]),
    );
    sheets.add(auditSheet(await repo.audit(date: date)));
    return workbook(sheets);
  }

  WorkbookSheet auditSheet(List<Map<String, Object?>> records) =>
      WorkbookSheet('Auditoría', [
        [
          'Fecha operativa',
          'Instante UTC',
          'Operador',
          'Equipo',
          'Acción',
          'Origen',
          'Detalle',
          'ID',
        ],
        ...records.map(
          (r) => [
            r['date'],
            r['occurred_at'],
            r['actor'],
            r['device'],
            r['action'],
            r['origin'],
            r['details'],
            r['id'],
          ],
        ),
      ]);
  Future<void> exportExcel(String date, String scope) async {
    if (await save('MuleAgent $date.xlsx', await excel(date, scope))) {
      await repo.event('excel_exported', date: date, details: {'scope': scope});
    }
  }

  Future<void> exportAudit({
    String? date,
    String operator = '',
    String device = '',
    String action = '',
  }) async {
    final rows = await repo.audit(
      date: date,
      operator: operator,
      equipment: device,
      action: action,
    );
    if (await save('MuleAgent auditoria.xlsx', workbook([auditSheet(rows)]))) {
      await repo.event(
        'audit_exported',
        date: date,
        details: {'rows': rows.length},
      );
    }
  }

  Future<Map<String, dynamic>> backupPayload() async {
    final tables = await repo.backup();
    final extra = <String>{
      for (final f in tables['admin_files'] as List) f['local_path'] as String,
      for (final r in tables['admin_revisions'] as List)
        if (r['package_path'] != null) r['package_path'] as String,
    };
    final payload = await storage.includeFiles({
      'schema': 1,
      'kind': 'backup',
      'app': 'administrator',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'tables': tables,
    }, extra: extra.toList());
    return payload;
  }

  Future<bool> backup() async {
    final payload = await backupPayload();
    final bytes = await compute(encryptPayload, {
      'payload': payload,
      'password': await storage.password(),
    });
    final success = await save(
      'MuleAgent Administrador respaldo ${DateTime.now().toIso8601String().substring(0, 10)}.mulebackup',
      bytes,
    );
    if (success) await repo.event('backup_created');
    return success;
  }

  Future<bool> restore(String key) async {
    final selected = await FilePicker.platform.pickFiles(type: FileType.any);
    if (selected == null) return false;
    final path = selected.files.single.path;
    if (path == null) throw StateError('No se pudo abrir el respaldo.');
    final file = File(path);
    if (await file.length() > PackageCodec.maxBytes * 2) {
      throw StateError('Archivo demasiado grande.');
    }
    final payload = await compute(decryptPayload, {
      'bytes': await file.readAsBytes(),
      'password': key,
    });
    if (payload['kind'] != 'backup' || payload['app'] != 'administrator') {
      throw const FormatException(
        'Selecciona un respaldo completo del Administrador.',
      );
    }
    return restorePayload(payload);
  }

  Future<bool> restorePayload(Map<String, dynamic> payload) async {
    if (payload['kind'] != 'backup' ||
        payload['app'] != 'administrator' ||
        payload['schema'] != 1) {
      throw const FormatException('Respaldo incompatible.');
    }
    final tables = payload['tables'] as Map<String, dynamic>,
        files = payload['files'] as Map<String, dynamic>;
    final created = <File>[];
    try {
      for (final entry in files.entries) {
        final target = storage.file(entry.key);
        final bytes = base64Decode(entry.value['bytes'] as String);
        if (digest(bytes) != entry.value['sha256']) {
          throw const FormatException('Un archivo del respaldo está alterado.');
        }
        if (await target.exists()) {
          if (digest(await target.readAsBytes()) != digest(bytes)) {
            throw StateError('Conflicto con un archivo existente.');
          }
        } else {
          await storage.writeAtomic(entry.key, bytes);
          created.add(target);
        }
      }
      void require(Object? path, [Object? hash]) {
        if (path is! String ||
            !files.containsKey(path) ||
            (hash != null && files[path]['sha256'] != hash)) {
          throw const FormatException(
            'Faltan archivos originales en el respaldo.',
          );
        }
      }

      for (final e in tables['evidence'] as List) {
        if (e['state'] == 'photo') require(e['private_path'], e['sha256']);
      }
      for (final a in tables['artifacts'] as List) {
        require(a['pdf_path'], a['pdf_sha256']);
        require(a['package_path']);
      }
      for (final f in tables['admin_files'] as List) {
        require(f['local_path'], f['sha256']);
      }
      for (final r in tables['admin_revisions'] as List) {
        require(r['pdf_path']);
        if (r['package_path'] != null) require(r['package_path']);
      }
      await repo.restoreBackup(tables);
      return true;
    } catch (_) {
      for (final file in created) {
        if (await file.exists()) await file.delete();
      }
      rethrow;
    }
  }

  Future<void> exportPhotos(String date, String scope) async {
    final archive = Archive();
    for (final row in await repo.tickets(
      date,
      stage: ['entry', 'exit'].contains(scope) ? scope : null,
    )) {
      if (row['photo_path'] == null) continue;
      final photo = image.decodeImage(
        await storage.file(row['photo_path'] as String).readAsBytes(),
      );
      if (photo == null) throw StateError('No se pudo leer una foto.');
      final bytes = image.encodeJpg(photo, quality: 95);
      final name = '${row['code']}'.replaceAll(RegExp(r'[^a-zA-Z0-9 _-]'), '_');
      archive.addFile(
        ArchiveFile(
          '$name $date ${row['stage']}-${row['id']}.jpg',
          bytes.length,
          bytes,
        ),
      );
    }
    if (archive.isEmpty) throw StateError('No hay fotos en esta selección.');
    if (await save(
      'MuleAgent fotos $date.zip',
      Uint8List.fromList(ZipEncoder().encode(archive)),
    )) {
      await repo.event('jpg_exported', date: date, details: {'scope': scope});
    }
  }
}
