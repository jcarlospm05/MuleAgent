import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as image_codec;
import 'package:mule_data/mule_data.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'report_filename.dart';
import 'public_reports.dart';
import 'package:flutter/services.dart';

Future<Uint8List> encryptPayload(Map<String, dynamic> args) =>
    PackageCodec().encode(
      args['payload'] as Map<String, dynamic>,
      args['password'] as String,
    );
Future<Map<String, dynamic>> decryptPayload(Map<String, dynamic> args) =>
    PackageCodec().decode(
      args['bytes'] as Uint8List,
      args['password'] as String,
    );

bool validImage(Uint8List bytes) {
  try {
    return image_codec.decodeImage(bytes) != null;
  } catch (_) {
    return false;
  }
}

class OperatorServices {
  OperatorServices(this.repo, this.root, {this.publicStorageEnabled = false});
  final bool publicStorageEnabled;
  final CaptureRepository repo;
  final Directory root;
  static const storage = FlutterSecureStorage();
  final picker = ImagePicker();
  static Future<OperatorServices> create(
    CaptureRepository repo, {
    bool publicStorageEnabled = false,
  }) async {
    final root = Directory(
      p.join((await getApplicationSupportDirectory()).path, 'muleagent'),
    );
    await root.create(recursive: true);
    return OperatorServices(
      repo,
      root,
      publicStorageEnabled: publicStorageEnabled,
    );
  }

  Future<bool> configured() async =>
      (await repo.setting('operator'))?.isNotEmpty == true &&
      (await storage.read(key: 'shared_key_v1')) != null;
  Future<void> configure(String name, String password) async {
    if (name.trim().isEmpty || name.length > 100) {
      throw ArgumentError('Escribe tu nombre.');
    }
    if (password.length < 12) {
      throw ArgumentError('La clave necesita al menos 12 caracteres.');
    }
    await storage.write(key: 'shared_key_v1', value: password);
    await repo.setSetting('operator', name.trim());
    repo.operatorName = name.trim();
  }

  Future<String> password() async {
    final value = await storage.read(key: 'shared_key_v1');
    if (value == null) throw StateError('Configura la clave compartida.');
    return value;
  }

  File file(String relative) {
    if (relative.isEmpty ||
        p.isAbsolute(relative) ||
        relative.contains('\\') ||
        relative.split('/').any((part) => part == '..' || part.isEmpty) ||
        !['media', 'artifacts'].contains(relative.split('/').first)) {
      throw const FormatException('Ruta de archivo inválida.');
    }
    return File(p.join(root.path, relative));
  }

  Future<void> writeAtomic(String relative, List<int> bytes) async {
    final target = file(relative);
    await target.parent.create(recursive: true);
    final temp = File('${target.path}.${const Uuid().v4()}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(target.path);
  }

  Future<void> selectPhoto(Draft draft, ImageSource source) async {
    await repo.setSetting(
      'pending_photo',
      jsonEncode({'revision': draft.revisionId, 'ticket': draft.ticketId}),
    );
    final image = await picker.pickImage(
      source: source,
      requestFullMetadata: false,
    );
    if (image != null) await attachImage(draft, image, source.name);
    await repo.setSetting('pending_photo', '');
  }

  Future<void> attachImage(Draft draft, XFile image, String source) async {
    if (await image.length() > 20 * 1024 * 1024) {
      throw StateError('La foto supera 20 MB. Elige otra imagen.');
    }
    final bytes = await image.readAsBytes();
    // Verify PDF can decode the image before accepting it as usable evidence.
    final pdfImage = pw.MemoryImage(bytes);
    if ((pdfImage.width ?? 0) <= 0 || (pdfImage.height ?? 0) <= 0) {
      throw StateError('Imagen no compatible. Usa JPG o PNG.');
    }
    if ((pdfImage.width ?? 0) * (pdfImage.height ?? 0) > 40000000 ||
        !await compute(validImage, bytes)) {
      throw StateError(
        'La foto está dañada o es demasiado grande. Usa otra imagen de hasta 40 megapíxeles.',
      );
    }
    final format = image_codec.findDecoderForData(bytes)!.format.name;
    final extension = format == 'jpeg' ? 'jpg' : format;
    final relative = 'media/${const Uuid().v4()}.$extension';
    await writeAtomic(relative, bytes);
    await repo.attachPhoto(
      draft,
      relative,
      sha256.convert(bytes).toString(),
      source,
    );
  }

  Future<void> recoverPhoto() async {
    final pending = await repo.setting('pending_photo');
    final result = await picker.retrieveLostData();
    if (pending != null &&
        pending.isNotEmpty &&
        result.files?.isNotEmpty == true) {
      final ids = jsonDecode(pending) as Map<String, dynamic>;
      final session = await repo.sessionById(ids['revision'] as String);
      final draft = await repo.draft(session);
      if (draft != null && draft.ticketId == ids['ticket']) {
        await attachImage(draft, result.files!.first, 'recovered');
      }
    }
    await repo.setSetting('pending_photo', '');
    if (result.exception != null) {
      throw StateError('No se recuperó la foto. Puedes volver a tomarla.');
    }
  }

  Future<void> previewPhoto(String relative, void Function(File) show) async =>
      show(file(relative));

  Future<Map<String, Object?>> ensureArtifacts(CaptureSession session) async {
    final existing = await repo.db.query(
      'artifacts',
      where: 'revision_id=?',
      whereArgs: [session.id],
    );
    if (existing.isNotEmpty) {
      final record = existing.single;
      final pdf = file(record['pdf_path'] as String),
          package = file(record['package_path'] as String);
      if (await pdf.exists() &&
          await package.exists() &&
          sha256.convert(await pdf.readAsBytes()).toString() ==
              record['pdf_sha256']) {
        return record;
      }
      throw StateError(
        'Faltan archivos originales de este cierre. Restaura un respaldo que los conserve.',
      );
    }
    final snapshot = await repo.snapshot(revisionId: session.id);
    final pdfBytes = await renderPdf(session);
    final revision = (await repo.db.query(
      'revisions',
      where: 'id=?',
      whereArgs: [session.id],
    )).single;
    final closedAt = DateTime.parse(revision['closed_at'] as String);
    final base = reportFilenameBase(session.stage, session.date, closedAt);
    final pdfPath = 'artifacts/${session.id}/$base.pdf';
    final packagePath = 'artifacts/${session.id}/$base.mule';
    await writeAtomic(pdfPath, pdfBytes);
    final payload = await includeFiles(snapshot, extra: [pdfPath]);
    payload['pdf'] = {
      'path': pdfPath,
      'sha256': sha256.convert(pdfBytes).toString(),
    };
    final encoded = await compute(encryptPayload, {
      'payload': payload,
      'password': await password(),
    });
    await writeAtomic(packagePath, encoded);
    final record = <String, Object?>{
      'revision_id': session.id,
      'pdf_path': pdfPath,
      'package_path': packagePath,
      'pdf_sha256': sha256.convert(pdfBytes).toString(),
      'created_at': closedAt.toUtc().toIso8601String(),
    };
    await repo.db.insert('artifacts', record);
    return record;
  }

  Future<void> preparePublicStorage() async {
    if (!publicStorageEnabled) return;
    await PublicReports.prepare();
  }

  String publicCopyKey(CaptureSession session) =>
      'public_copy_v1_${session.id}';

  Future<String?> publicFolder(CaptureSession session) async {
    final value = await repo.setting(publicCopyKey(session));
    if (value == null || value.isEmpty) return null;
    try {
      final saved = jsonDecode(value) as Map<String, dynamic>;
      return saved['device'] == repo.deviceId
          ? saved['folder'] as String?
          : null;
    } catch (_) {
      return null;
    }
  }

  /// A success marker is written only after every public file is verified.
  Future<String?> savePublicReport(
    CaptureSession session, {
    bool prepared = false,
  }) async {
    if (!publicStorageEnabled) {
      await ensureArtifacts(session);
      return null;
    }
    await repo.setSetting(publicCopyKey(session), '');
    try {
      final record = await ensureArtifacts(session);
      if (!prepared) await preparePublicStorage();
      final revision = (await repo.db.query(
        'revisions',
        where: 'id=?',
        whereArgs: [session.id],
      )).single;
      if (revision['status'] != 'closed') {
        throw StateError('Primero cierra la etapa.');
      }
      final stored = p.basenameWithoutExtension(
        record['package_path'] as String,
      );
      final base =
          RegExp(
            r'^(entrada|salida)_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}-\d{3}$',
          ).hasMatch(stored)
          ? stored
          : reportFilenameBase(
              session.stage,
              session.date,
              DateTime.parse(record['created_at'] as String),
            );
      final publicBase = base.replaceFirst('entrada_', 'inicio_');
      final stage = session.stage == Stage.entry ? 'inicio' : 'salida';
      final directory =
          'MuleAgent/${session.date}/$stage/${publicBase}_r${revision['number']}_${session.id.substring(0, 8)}';
      final files = <Map<String, String>>[];
      Future<void> add(
        File source,
        String name,
        String mime, [
        String? expected,
      ]) async {
        final hash = (await sha256.bind(source.openRead()).first).toString();
        if (expected != null && hash != expected) {
          throw StateError('Un original no coincide con su huella.');
        }
        files.add({
          'source': source.path,
          'name': name,
          'mime': mime,
          'sha256': hash,
        });
      }

      await add(
        file(record['pdf_path'] as String),
        '$publicBase.pdf',
        'application/pdf',
        record['pdf_sha256'] as String,
      );
      await add(
        file(record['package_path'] as String),
        '$base.mule',
        'application/octet-stream',
      );
      for (final row in await repo.tickets(session)) {
        if (row['evidence_state'] != 'photo') continue;
        final photo = file(row['private_path'] as String);
        final code = (row['code'] as String).replaceAll(
          RegExp(r'[^a-zA-Z0-9_-]'),
          '_',
        );
        final extension = p.extension(photo.path);
        await add(
          photo,
          'foto_${code}_${session.date}_${stage}_${(row['id'] as String).substring(0, 8)}$extension',
          extension == '.png'
              ? 'image/png'
              : extension == '.jpg' || extension == '.jpeg'
              ? 'image/jpeg'
              : 'application/octet-stream',
          row['sha256'] as String,
        );
      }
      final result = await PublicReports.publish(directory, files);
      await repo.setSetting(
        publicCopyKey(session),
        jsonEncode({
          'device': repo.deviceId,
          'folder': result['folder'],
          'count': result['count'],
          'saved_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      return result['folder'] as String;
    } catch (e) {
      final detail = e is PlatformException
          ? e.message
          : e is StateError
          ? e.message
          : 'Comprueba el espacio disponible y los permisos.';
      throw StateError(
        'El cierre se conserva dentro de la app, pero falta completar la copia en Descargas. $detail Usa Guardar copia en Descargas para reintentar.',
      );
    }
  }

  /// Also recovers closures interrupted before their PDF or public copy was finished.
  Future<int> recoverPublicReports({bool verifyAll = false}) async {
    if (!publicStorageEnabled) return 0;
    await preparePublicStorage();
    var count = 0;
    for (final row in await repo.sessions(closed: true)) {
      final session = await repo.sessionById(row['id'] as String);
      if (!verifyAll && await publicFolder(session) != null) continue;
      await savePublicReport(session, prepared: true);
      count++;
    }
    return count;
  }

  Future<Uint8List> renderPdf(CaptureSession session) async {
    final rows = await repo.tickets(session);
    final revision = (await repo.db.query(
      'revisions',
      where: 'id=?',
      whereArgs: [session.id],
    )).single;
    final doc = pw.Document();
    final perPage =
        rows.any(
          (row) => [
            'code',
            'driver',
            'provider',
            'omission_reason',
          ].any((key) => (row[key]?.toString().length ?? 0) > 80),
        )
        ? 1
        : 2;
    for (var i = 0; i < rows.length; i += perPage) {
      final cards = <pw.Widget>[];
      for (final row in rows.skip(i).take(perPage)) {
        cards.add(
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 16),
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Ficha ${row['code']}',
                  style: const pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (session.stage == Stage.entry)
                  pw.Text('Mulero: ${row['driver']}'),
                pw.Text('Proveedor: ${row['provider']}'),
                pw.Text(
                  'Hora: ${row['time']}  |  Horómetro: ${row['meter']} h',
                ),
                pw.SizedBox(height: 8),
                if (row['evidence_state'] == 'photo')
                  pw.Image(
                    pw.MemoryImage(
                      await file(row['private_path'] as String).readAsBytes(),
                      dpi: 180,
                    ),
                    height: 175,
                    fit: pw.BoxFit.contain,
                  )
                else
                  pw.Text('Foto omitida: ${row['omission_reason']}'),
              ],
            ),
          ),
        );
      }
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text(
                'MuleAgent · ${session.stage.label}',
                style: const pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                '${session.date} · Revisión ${revision['number']} · ${rows.length} fichas',
              ),
              pw.SizedBox(height: 16),
              ...cards,
              pw.Spacer(),
              pw.Text(
                'Reporte ${revision['report_id']} · Página ${i ~/ perPage + 1}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ),
        ),
      );
    }
    return doc.save();
  }

  Future<void> previewPdf(CaptureSession session) async {
    final record = await ensureArtifacts(session);
    final bytes = await file(record['pdf_path'] as String).readAsBytes();
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: '${session.stage.label} ${session.date}.pdf',
    );
  }

  Future<void> share(CaptureSession session) async {
    await savePublicReport(session);
    final record = await ensureArtifacts(session);
    final base = reportFilenameBase(
      session.stage,
      session.date,
      DateTime.parse(record['created_at'] as String),
    );
    await repo.recordShare(session);
    await SharePlus.instance.share(
      ShareParams(
        subject: base,
        text:
            'Reporte de ${session.stage.label.toLowerCase()} · ${session.date}',
        files: [
          XFile(
            file(record['pdf_path'] as String).path,
            mimeType: 'application/pdf',
          ),
          XFile(
            file(record['package_path'] as String).path,
            mimeType: 'application/octet-stream',
          ),
        ],
        fileNameOverrides: ['$base.pdf', '$base.mule'],
      ),
    );
  }

  Future<Map<String, dynamic>> includeFiles(
    Map<String, dynamic> snapshot, {
    List<String> extra = const [],
  }) async {
    final payload = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
    final tables = payload['tables'] as Map<String, dynamic>;
    final paths = <String>{...extra};
    for (final e in tables['evidence'] as List<dynamic>) {
      if (e['state'] == 'photo') paths.add(e['private_path'] as String);
    }
    for (final a in tables['artifacts'] as List<dynamic>? ?? []) {
      paths.add(a['pdf_path'] as String);
      paths.add(a['package_path'] as String);
    }
    var total = 0;
    final files = <String, dynamic>{};
    for (final path in paths) {
      final source = file(path);
      if (!await source.exists()) {
        throw StateError(
          'Falta una foto o archivo original. No se generó un respaldo incompleto.',
        );
      }
      total += await source.length();
      if (total > 100 * 1024 * 1024) {
        throw StateError(
          'El conjunto supera 100 MB de archivos. Conserva los reportes individuales y divide el respaldo antes de continuar.',
        );
      }
      final bytes = await source.readAsBytes();
      files[path] = {
        'bytes': base64Encode(bytes),
        'sha256': sha256.convert(bytes).toString(),
      };
    }
    payload['files'] = files;
    return payload;
  }

  Future<bool> backup() async {
    final payload = await includeFiles(await repo.snapshot());
    final bytes = await compute(encryptPayload, {
      'payload': payload,
      'password': await password(),
    });
    final saved = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar respaldo cifrado',
      fileName:
          'MuleAgent respaldo ${DateTime.now().toIso8601String().substring(0, 10)}.mulebackup',
      bytes: bytes,
    );
    if (saved != null) {
      await repo.setSetting('last_backup', DateTime.now().toIso8601String());
    }
    return saved != null;
  }

  Future<bool> restore(String key) async {
    final selected = await FilePicker.platform.pickFiles(type: FileType.any);
    if (selected == null) return false;
    final selectedPath = selected.files.single.path;
    if (selectedPath == null) throw StateError('No se pudo leer el archivo.');
    final source = File(selectedPath);
    if (await source.length() > PackageCodec.maxBytes * 2) {
      throw StateError('Archivo demasiado grande.');
    }
    final payload = await compute(decryptPayload, {
      'bytes': await source.readAsBytes(),
      'password': key,
    });
    if (payload['kind'] != 'backup') {
      throw const FormatException(
        'Selecciona un respaldo completo, no un reporte diario.',
      );
    }
    final files = payload['files'] as Map<String, dynamic>;
    final newFiles = <File>[];
    try {
      for (final entry in files.entries) {
        final target = file(entry.key);
        final bytes = base64Decode(entry.value['bytes'] as String);
        if (sha256.convert(bytes).toString() != entry.value['sha256']) {
          throw const FormatException(
            'El respaldo contiene un archivo alterado.',
          );
        }
        if (await target.exists()) {
          if (sha256.convert(await target.readAsBytes()).toString() !=
              entry.value['sha256']) {
            throw StateError('Conflicto con un archivo existente.');
          }
        } else {
          await writeAtomic(entry.key, bytes);
          newFiles.add(target);
        }
      }
      final tables = payload['tables'] as Map<String, dynamic>;
      for (final row in tables['evidence'] as List<dynamic>) {
        if (row['state'] == 'photo' &&
            (files[row['private_path']] == null ||
                files[row['private_path']]['sha256'] != row['sha256'])) {
          throw const FormatException('Falta evidencia válida en el respaldo.');
        }
      }
      for (final row in tables['artifacts'] as List<dynamic>) {
        if (!files.containsKey(row['pdf_path']) ||
            !files.containsKey(row['package_path']) ||
            files[row['pdf_path']]['sha256'] != row['pdf_sha256']) {
          throw const FormatException('Faltan los archivos de un cierre.');
        }
      }
      await repo.restore(payload);
      return true;
    } catch (_) {
      for (final f in newFiles) {
        if (await f.exists()) await f.delete();
      }
      rethrow;
    }
  }

  Future<void> exportArtifacts(CaptureSession session) async {
    final record = await ensureArtifacts(session);
    final base = reportFilenameBase(
      session.stage,
      session.date,
      DateTime.parse(record['created_at'] as String),
    );
    for (final item in [('pdf_path', 'pdf'), ('package_path', 'mule')]) {
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar ${item.$2.toUpperCase()}',
        fileName: '$base.${item.$2}',
        bytes: await file(record[item.$1] as String).readAsBytes(),
      );
      if (saved == null) return;
    }
  }

  Future<void> exportPhoto(
    Map<String, Object?> row,
    CaptureSession session,
  ) async {
    final original = file(row['private_path'] as String);
    final code = (row['code'] as String).replaceAll(
      RegExp(r'[^a-zA-Z0-9 _-]'),
      '_',
    );
    await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar foto original',
      fileName:
          '$code ${session.date} ${session.stage == Stage.entry ? 'inicio' : 'cierre'}-${(row['id'] as String).substring(0, 8)}${p.extension(original.path)}',
      bytes: await original.readAsBytes(),
    );
  }
}
