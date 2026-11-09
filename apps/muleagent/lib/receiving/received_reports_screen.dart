import 'package:administrador/incoming.dart';
import 'package:administrador/services.dart';
import 'package:flutter/material.dart';

import '../application/unified_bundle.dart';

/// Stage-2 boundary; date/image consolidation is added in stage 5.
class ReceivedReportsScreen extends StatefulWidget {
  const ReceivedReportsScreen({
    super.key,
    required this.bundle,
    this.incomingPath,
  });
  final UnifiedBundle bundle;
  final String? incomingPath;
  @override
  State<ReceivedReportsScreen> createState() => _ReceivedReportsScreenState();
}

class _ReceivedReportsScreenState extends State<ReceivedReportsScreen> {
  final keyInput = TextEditingController();
  late String? incomingPath = widget.incomingPath;
  bool busy = true;
  String? message;
  List<Map<String, Object?>> rows = [];
  UnifiedBundle get bundle => widget.bundle;
  AdminServices get receiver {
    bundle.admin.actor = bundle.capture.operatorName;
    return AdminServices(
      bundle.admin,
      bundle.capture,
      bundle.services,
      access: bundle.profiles,
    );
  }

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    keyInput.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    try {
      await bundle.profiles.requireAdministrator();
      rows = await bundle.admin.reports();
    } catch (e) {
      message = e is StateError
          ? e.message.toString()
          : 'No se pudieron consultar los reportes.';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> receive() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await bundle.profiles.requireAdministrator();
      final result = incomingPath == null
          ? await receiver.receive(
              key: keyInput.text.isEmpty ? null : keyInput.text,
            )
          : await receiver.importPath(
              incomingPath!,
              keyInput.text.isEmpty
                  ? await bundle.services.password()
                  : keyInput.text,
            );
      if (result != null) {
        if (incomingPath != null) await IncomingReports.remove(incomingPath!);
        incomingPath = null;
        message = result.result.duplicate
            ? 'Reporte reconocido. Las fichas no se duplicaron.'
            : 'Reporte recibido: ${result.report.tickets.length} fichas.';
        rows = await bundle.admin.reports();
      }
    } catch (e) {
      message = e is StateError
          ? e.message.toString()
          : e is FormatException
          ? e.message
          : 'No se pudo importar. Comprueba la clave y el archivo.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> discard() async {
    setState(() => busy = true);
    try {
      await IncomingReports.remove(incomingPath!);
      incomingPath = null;
      message =
          'Se descartó la copia recibida. El archivo de origen se conserva.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Recibir reportes')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Administrador',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text(
            'Recibe el archivo .mule enviado por un supervisor. Los originales se conservan.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: keyInput,
            obscureText: true,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: 'Otra clave, si el archivo usa una distinta',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy ? null : receive,
            icon: const Icon(Icons.file_open_outlined),
            label: Text(
              incomingPath == null
                  ? 'Elegir archivo e importar'
                  : 'Importar archivo recibido',
            ),
          ),
          if (incomingPath != null)
            OutlinedButton.icon(
              onPressed: busy ? null : discard,
              icon: const Icon(Icons.close),
              label: const Text('Descartar archivo recibido'),
            ),
          if (busy) const Center(child: CircularProgressIndicator()),
          if (message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(message!),
            ),
          const SizedBox(height: 24),
          const Text(
            'Reportes recibidos',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          if (!busy && rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Todavía no hay reportes recibidos.'),
            ),
          for (final row in rows)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                row['stage'] == 'entry' ? Icons.login : Icons.logout,
              ),
              title: Text(
                '${row['date']} · ${row['stage'] == 'entry' ? 'Entrada' : 'Salida'}',
              ),
              subtitle: Text(
                'Equipo ${row['device']} · revisión ${row['number']}',
              ),
            ),
        ],
      ),
    ),
  );
}
