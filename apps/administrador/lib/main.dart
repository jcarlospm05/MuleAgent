import 'package:admin_data/admin_data.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'incoming.dart';
import 'package:mule_data/mule_data.dart';
import 'package:mule_profiles/mule_profiles.dart';
import 'package:operador/security/profile_store.dart';
import 'package:operador/brand.dart';
import 'package:operador/main.dart';
import 'package:operador/services.dart';
import 'database.dart';
import 'services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AdministratorApp());
}

class AdminBundle {
  AdminBundle(this.capture, this.repo, this.services);
  final CaptureRepository capture;
  final AdminRepository repo;
  final AdminServices services;
  static Future<AdminBundle> open() async {
    final capture = await openAdminDatabase();
    capture.operatorName = await capture.setting('operator') ?? '';
    final repo = AdminRepository(
      capture.db,
      device: capture.deviceId,
      actor: capture.operatorName,
    );
    final storage = await OperatorServices.create(capture);
    final access = ProfileRepository(SecureProfileStorage());
    if (await access.load() == null) {
      await access.configure(AppRole.administrator);
    }
    return AdminBundle(
      capture,
      repo,
      AdminServices(repo, capture, storage, access: access),
    );
  }
}

class AdministratorApp extends StatelessWidget {
  const AdministratorApp({super.key, this.bundle});
  final AdminBundle? bundle;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MuleAgent Administrador',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFFFFDF8),
      fontFamily: 'Roboto',
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF21355E),
        primary: const Color(0xFF21355E),
        surface: const Color(0xFFFFFDF8),
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 18),
        headlineMedium: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          color: Color(0xFF182237),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 80),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 64),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    home: AdminScreen(bundle: bundle),
  );
}

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, this.bundle});
  final AdminBundle? bundle;
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  AdminBundle? b;
  bool busy = true;
  String route = 'home';
  String? error, notice;
  String? incomingPath;
  bool checkingIncoming = false;
  final trail = <String>[];
  final input = TextEditingController(),
      personFilter = TextEditingController(),
      deviceFilter = TextEditingController(),
      actionFilter = TextEditingController();
  String name = '',
      key = '',
      date = DateTime.now().toIso8601String().substring(0, 10),
      scope = 'all',
      stage = 'entry';
  bool allDates = false;
  int auditPage = 0;
  List<Map<String, Object?>> rows = [],
      historicalRows = [],
      revisions = [],
      pairs = [],
      auditRows = [];
  Map<String, Object?>? ticket, entry, exit, report;
  @override
  void initState() {
    super.initState();
    IncomingReports.channel.setMethodCallHandler((call) async {
      if (call.method == 'available') await offerIncoming();
    });
    initialize();
  }

  Future<void> initialize() async {
    try {
      b = widget.bundle ?? await AdminBundle.open();
      if (widget.bundle == null) {
        try {
          await b!.services.storage.recoverPhoto();
        } catch (_) {
          notice = 'Puedes volver a tomar la foto que quedó pendiente.';
        }
      }
      if (widget.bundle == null && !await b!.services.storage.configured()) {
        route = 'name';
      } else {
        await b!.services.syncOwn();
      }
    } catch (_) {
      error =
          'No se pudo abrir el almacenamiento seguro. Los datos se conservaron.';
    }
    if (mounted) {
      setState(() => busy = false);
      await offerIncoming();
    }
  }

  Future<void> offerIncoming() async {
    if (!mounted ||
        busy ||
        checkingIncoming ||
        incomingPath != null ||
        b == null ||
        ['name', 'key', 'confirmKey'].contains(route)) {
      return;
    }
    checkingIncoming = true;
    try {
      final path = await IncomingReports.peek();
      if (mounted && path != null) {
        setState(() {
          incomingPath = path;
          trail.add(route);
          route = 'receive';
          input.clear();
          notice =
              'Archivo recibido desde Android. Confirma para verificarlo e importarlo.';
        });
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => error = e.message ?? 'No se pudo recibir el archivo.');
      }
    } on MissingPluginException {
      // Other Flutter platforms use the regular file picker.
    } finally {
      checkingIncoming = false;
    }
  }

  @override
  void dispose() {
    IncomingReports.channel.setMethodCallHandler(null);
    input.dispose();
    personFilter.dispose();
    deviceFilter.dispose();
    actionFilter.dispose();
    super.dispose();
  }

  Future<void> act(Future<void> Function() task) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await task();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message.toString()
              : e is FormatException
              ? e.message
              : 'No se completó la operación. Comprueba la clave, el archivo, los permisos y el espacio disponible.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        unawaited(offerIncoming());
      }
    }
  }

  void go(String next) {
    setState(() {
      trail.add(route);
      route = next;
      error = null;
      input.clear();
    });
  }

  void back() {
    if (busy) return;
    if (route == 'name' && trail.isEmpty) return;
    setState(() {
      if (trail.isNotEmpty) {
        route = trail.removeLast();
      } else {
        route = 'home';
      }
      error = null;
    });
  }

  void routeAfter(String next) {
    trail.add(route);
    route = next;
    input.clear();
  }

  Widget button(
    String label,
    IconData icon,
    VoidCallback action, {
    bool primary = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: primary
        ? FilledButton(
            onPressed: busy ? null : action,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 88),
              padding: const EdgeInsets.all(18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: buttonLabel(label, icon, true),
          )
        : OutlinedButton(
            onPressed: busy ? null : action,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 68),
              padding: const EdgeInsets.all(16),
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFCDD6E5), width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: buttonLabel(label, icon, false),
          ),
  );
  Widget buttonLabel(String label, IconData icon, bool primary) => Row(
    children: [
      Icon(icon, size: 28),
      const SizedBox(width: 14),
      Expanded(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: primary ? 22 : 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(width: 28),
    ],
  );
  Widget title(String text, [String? help]) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: Theme.of(context).textTheme.headlineMedium),
        if (help != null) ...[const SizedBox(height: 12), Text(help)],
      ],
    ),
  );
  Widget field(
    String label, {
    bool secret = false,
    TextEditingController? controller,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      controller: controller ?? input,
      enabled: !busy,
      obscureText: secret,
      autocorrect: !secret,
      enableSuggestions: !secret,
      style: const TextStyle(fontSize: 23),
      decoration: InputDecoration(labelText: label),
    ),
  );
  Widget column(List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: children,
  );
  String labelStage(Object? value) => value == 'entry' ? 'Entrada' : 'Despacho';
  String origin(Object? value) =>
      value == 'own' ? 'Captura propia' : 'Recibido';
  Future<void> refresh() async {
    await b!.services.syncOwn();
    rows = await b!.repo.tickets(date);
    revisions = await b!.repo.reports(date: date, latest: false);
    pairs = await b!.repo.links(date);
  }

  void openDate(String selected) => act(() async {
    date = selected;
    await refresh();
    routeAfter('journey');
  });
  void days() => act(() async {
    await b!.services.syncOwn();
    revisions = await b!.repo.reports();
    routeAfter('days');
  });
  Widget ticketButton(Map<String, Object?> t, VoidCallback action) => button(
    '${t['code']} · ${t['provider']}\n${t['time']} · ${t['meter']} h\n${origin(t['source'])} · r${t['revision_number']}',
    t['stage'] == 'entry' ? Icons.login_rounded : Icons.local_shipping_outlined,
    action,
  );
  void detail(Map<String, Object?> selected) => act(() async {
    ticket = selected;
    await b!.repo.event(
      'ticket_viewed',
      date: date,
      details: {'revision': selected['revision_id'], 'ticket': selected['id']},
    );
    routeAfter('detail');
  });
  bool linked(Map<String, Object?> t) => pairs.any(
    (l) => t['stage'] == 'entry'
        ? l['entry_report'] == t['report_id'] &&
              l['entry_logical'] == t['logical_id']
        : l['exit_report'] == t['report_id'] &&
              l['exit_logical'] == t['logical_id'],
  );
  Future<void> showPhoto(String path) => showDialog<void>(
    context: context,
    builder: (ctx) => Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('MuleAgent · Evidencia'),
          leading: const Padding(padding: EdgeInsets.all(8), child: AppLogo()),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close),
              label: const Text('Cerrar'),
            ),
          ],
        ),
        body: InteractiveViewer(
          minScale: .5,
          maxScale: 5,
          child: Center(child: Image.file(b!.services.storage.file(path))),
        ),
      ),
    ),
  );
  Widget content() {
    if (b == null) {
      return title(
        'Almacenamiento seguro',
        busy ? 'Abriendo datos…' : 'Vuelve a abrir la aplicación.',
      );
    }
    switch (route) {
      case 'name':
        return column([
          title(
            '¿Quién administra?',
            'Este nombre identifica importaciones, cruces y exportaciones.',
          ),
          field('Nombre del administrador'),
          button('Siguiente', Icons.arrow_forward, () {
            if (input.text.trim().isEmpty || input.text.length > 100) {
              setState(
                () => error = 'Escribe tu nombre, hasta 100 caracteres.',
              );
              return;
            }
            name = input.text.trim();
            go('key');
          }, primary: true),
        ]);
      case 'key':
        return column([
          title(
            'Clave compartida',
            'Usa la misma clave que el Operador. Debe tener al menos 12 caracteres. Guárdala para recuperar respaldos.',
          ),
          field('Clave compartida', secret: true),
          button('Siguiente', Icons.arrow_forward, () {
            if (input.text.length < 12) {
              setState(() => error = 'Usa al menos 12 caracteres.');
              return;
            }
            key = input.text;
            go('confirmKey');
          }, primary: true),
        ]);
      case 'confirmKey':
        return column([
          title('Confirma la clave'),
          field('Repite la clave', secret: true),
          button(
            'Guardar configuración',
            Icons.save_outlined,
            () => act(() async {
              if (input.text != key) {
                throw StateError('Las claves no coinciden.');
              }
              await b!.services.storage.configure(name, key);
              b!.repo.actor = name;
              key = '';
              input.clear();
              trail.clear();
              route = 'home';
            }),
            primary: true,
          ),
        ]);
      case 'home':
        return column([
          title('Administrador', 'Reportes recibidos y capturas propias.'),
          button(
            'Recibir reporte del Operador',
            Icons.download_outlined,
            () => go('receive'),
            primary: true,
          ),
          button('Ver jornadas', Icons.calendar_month_outlined, days),
          button('Cruce manual', Icons.compare_arrows, days),
          button(
            'Captura propia',
            Icons.local_shipping_outlined,
            () => act(() async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => OperatorScreen(
                    repository: b!.capture,
                    captureServices: b!.services.storage,
                    roleLabel: 'Captura propia · Administrador',
                    showSettings: false,
                    onExit: () => Navigator.of(context).pop(),
                  ),
                ),
              );
              b!.repo.actor = b!.capture.operatorName;
              await b!.services.syncOwn();
            }),
          ),
          button('Auditoría', Icons.history, () => go('auditFilters')),
          button(
            'Respaldo y restauración',
            Icons.backup_outlined,
            () => go('backup'),
          ),
          button('Configuración', Icons.settings_outlined, () {
            name = b!.capture.operatorName;
            go('name');
            input.text = name;
          }),
        ]);
      case 'receive':
        return column([
          title(
            'Recibir reporte',
            'Selecciona el archivo .mule enviado por el Operador. La fecha y la etapa se toman del reporte. Los reenvíos no duplican fichas.',
          ),
          field('Otra clave, si el archivo usa una distinta', secret: true),
          button(
            incomingPath == null
                ? 'Elegir archivo e importar'
                : 'Importar archivo recibido',
            Icons.file_open_outlined,
            () => act(() async {
              final result = incomingPath == null
                  ? await b!.services.receive(
                      key: input.text.isEmpty ? null : input.text,
                    )
                  : await b!.services.importPath(
                      incomingPath!,
                      input.text.isEmpty
                          ? await b!.services.storage.password()
                          : input.text,
                    );
              if (result != null && incomingPath != null) {
                await IncomingReports.remove(incomingPath!);
                incomingPath = null;
              }
              if (result == null) return;
              date = result.report.date;
              await refresh();
              routeAfter('journey');
              notice = result.result.duplicate
                  ? 'Reenvío reconocido. ${result.result.newEvents} eventos nuevos; fichas sin duplicados.'
                  : 'Reporte recibido: ${result.report.tickets.length} fichas.';
            }),
            primary: true,
          ),
          if (incomingPath != null)
            button(
              'Descartar archivo recibido',
              Icons.close,
              () => act(() async {
                await IncomingReports.remove(incomingPath!);
                incomingPath = null;
                notice =
                    'Copia recibida descartada. El archivo original se conserva en la aplicación que lo envió.';
              }),
            ),
        ]);
      case 'days':
        final dates = revisions.map((r) => r['date'] as String).toSet().toList()
          ..sort((a, b) => b.compareTo(a));
        return column([
          title('Elige una jornada'),
          if (dates.isEmpty)
            const Text(
              'Todavía no hay reportes. Importa un archivo o completa una captura propia.',
            ),
          ...dates.map(
            (d) => button(d, Icons.calendar_today, () => openDate(d)),
          ),
        ]);
      case 'journey':
        return column([
          title(
            'Jornada $date',
            '${rows.where((t) => t['stage'] == 'entry').length} entradas · ${rows.where((t) => t['stage'] == 'exit').length} despachos',
          ),
          button('Ver entradas', Icons.login_rounded, () {
            stage = 'entry';
            go('tickets');
          }, primary: true),
          button('Ver despachos', Icons.local_shipping_outlined, () {
            stage = 'exit';
            go('tickets');
          }, primary: true),
          button(
            'Cruzar fichas manualmente',
            Icons.compare_arrows,
            () => go('links'),
          ),
          button(
            'Reportes y exportaciones',
            Icons.picture_as_pdf_outlined,
            () => go('exportScope'),
          ),
          button(
            'Reportes y revisiones',
            Icons.layers_outlined,
            () => go('reports'),
          ),
          button('Actualizar jornada', Icons.refresh, () => act(refresh)),
        ]);
      case 'tickets':
        return column([
          title(
            '${labelStage(stage)} · $date',
            'Fichas originales en solo lectura. Se muestran las revisiones vigentes de cada reporte.',
          ),
          if (!rows.any((r) => r['stage'] == stage))
            const Text('No hay fichas para esta etapa.'),
          ...rows
              .where((r) => r['stage'] == stage)
              .map((r) => ticketButton(r, () => detail(r))),
        ]);
      case 'detail':
        final t = ticket!;
        return column([
          title(
            'Ficha ${t['code']}',
            '${labelStage(t['stage'])} · ${t['date']} · ${origin(t['source'])}',
          ),
          if (t['driver'] != null) Text('Mulero: ${t['driver']}'),
          Text('Proveedor: ${t['provider']}'),
          Text('Hora: ${t['time']}'),
          Text('Horómetro: ${t['meter']} h'),
          Text('Revisión: ${t['revision_number']}'),
          Text('Equipo: ${t['device']}'),
          if (t['photo_path'] != null) ...[
            const SizedBox(height: 16),
            Image.file(
              b!.services.storage.file(t['photo_path'] as String),
              height: 240,
              fit: BoxFit.contain,
            ),
            button(
              'Ampliar foto',
              Icons.zoom_in,
              () => showPhoto(t['photo_path'] as String),
            ),
            button(
              'Guardar foto original',
              Icons.save_alt,
              () => act(() => b!.services.originalPhoto(t)),
            ),
          ] else
            Text('Foto omitida: ${t['omission_reason']}'),
        ]);
      case 'reports':
        return column([
          title(
            'Revisiones · $date',
            'Los reportes anteriores conservan sus originales.',
          ),
          ...revisions.map(
            (r) => button(
              '${labelStage(r['stage'])} · Revisión ${r['number']}\n${origin(r['source'])} · ${r['device']}',
              Icons.description_outlined,
              () {
                report = r;
                go('report');
              },
            ),
          ),
        ]);
      case 'report':
        return column([
          title(
            '${labelStage(report!['stage'])} · Revisión ${report!['number']}',
            origin(report!['source']),
          ),
          button(
            'Ver e imprimir PDF original',
            Icons.picture_as_pdf_outlined,
            () => act(() => b!.services.originalPdf(report!['id'] as String)),
            primary: true,
          ),
          button(
            'Consultar fichas de esta revisión',
            Icons.assignment_outlined,
            () => act(() async {
              final original = await b!.repo.revisionTickets(
                report!['id'] as String,
              );
              historicalRows = original;
              stage = report!['stage'] as String;
              routeAfter('historical');
            }),
          ),
        ]);
      case 'historical':
        return column([
          title(
            'Fichas originales',
            'Revisión ${report!['number']} · ${origin(report!['source'])}',
          ),
          ...historicalRows.map((r) => ticketButton(r, () => detail(r))),
        ]);
      case 'links':
        return column([
          title(
            'Cruce manual · $date',
            'Los códigos originales se conservan aunque sean diferentes. Puedes terminar con fichas sin vincular.',
          ),
          button('Crear vínculo', Icons.add_link, () {
            entry = null;
            exit = null;
            go('pickEntry');
          }, primary: true),
          ...pairs.map(
            (l) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: column([
                  Text(
                    '${l['entry_code']} ↔ ${l['exit_code']}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    l['stale'] == true
                        ? 'Revisar: llegó una revisión nueva.'
                        : 'Vínculo confirmado.',
                  ),
                  button(
                    'Quitar vínculo',
                    Icons.link_off,
                    () => act(() async {
                      await b!.repo.unlink(l['id'] as String);
                      await refresh();
                    }),
                  ),
                ]),
              ),
            ),
          ),
          button(
            'Imprimir vínculos y pendientes',
            Icons.print_outlined,
            () => act(() => b!.services.preview(date, 'links')),
          ),
        ]);
      case 'pickEntry':
        return column([
          title('Elige una entrada'),
          ...rows
              .where((r) => r['stage'] == 'entry' && !linked(r))
              .map(
                (r) => ticketButton(r, () {
                  entry = r;
                  go('pickExit');
                }),
              ),
          if (!rows.any((r) => r['stage'] == 'entry' && !linked(r)))
            const Text(
              'No hay entradas disponibles. Revisa los vínculos existentes.',
            ),
        ]);
      case 'pickExit':
        return column([
          title('Elige un despacho', 'Entrada seleccionada: ${entry!['code']}'),
          ...rows
              .where((r) => r['stage'] == 'exit' && !linked(r))
              .map(
                (r) => ticketButton(r, () {
                  exit = r;
                  go('confirmLink');
                }),
              ),
          if (!rows.any((r) => r['stage'] == 'exit' && !linked(r)))
            const Text(
              'No hay despachos disponibles. Revisa los vínculos existentes.',
            ),
        ]);
      case 'confirmLink':
        return column([
          title(
            'Confirmar vínculo',
            'Entrada ${entry!['code']} ↔ Despacho ${exit!['code']}',
          ),
          const Text(
            'Esta relación se guarda aparte de las fichas originales.',
          ),
          button(
            'Guardar vínculo',
            Icons.link,
            () => act(() async {
              await b!.repo.link(entry!, exit!);
              await refresh();
              route = 'links';
              trail.removeWhere(
                (r) => [
                  'pickEntry',
                  'pickExit',
                  'confirmLink',
                  'links',
                ].contains(r),
              );
              notice = 'Vínculo guardado.';
            }),
            primary: true,
          ),
        ]);
      case 'exportScope':
        return column([
          title('¿Qué quieres exportar?'),
          ...{
            'all': 'Jornada completa',
            'entry': 'Solo entradas',
            'exit': 'Solo despachos',
            'links': 'Vínculos y pendientes',
          }.entries.map(
            (e) => button(e.value, Icons.description_outlined, () {
              scope = e.key;
              go('exports');
            }),
          ),
        ]);
      case 'exports':
        return column([
          title(
            'Exportar · $date',
            {
              'all': 'Jornada completa',
              'entry': 'Entradas',
              'exit': 'Despachos',
              'links': 'Vínculos y pendientes',
            }[scope],
          ),
          button(
            'Ver e imprimir PDF',
            Icons.print_outlined,
            () => act(() => b!.services.preview(date, scope)),
            primary: true,
          ),
          button(
            'Guardar PDF',
            Icons.picture_as_pdf_outlined,
            () => act(() => b!.services.exportPdf(date, scope)),
          ),
          button(
            'Guardar Excel con fotos',
            Icons.table_chart_outlined,
            () => act(() => b!.services.exportExcel(date, scope)),
          ),
          button(
            'Exportar fotos JPG',
            Icons.photo_library_outlined,
            () => act(() => b!.services.exportPhotos(date, scope)),
          ),
        ]);
      case 'backup':
        return column([
          title(
            'Respaldo del Administrador',
            'Incluye reportes recibidos, capturas propias, fotos, archivos, vínculos y auditoría. Se restaura con la clave con la que fue creado.',
          ),
          button(
            'Guardar respaldo completo',
            Icons.backup_outlined,
            () => act(() async {
              if (await b!.services.backup()) {
                notice = 'Respaldo guardado en el destino elegido.';
              }
            }),
            primary: true,
          ),
          button(
            'Restaurar en esta instalación',
            Icons.restore,
            () => go('restore'),
          ),
        ]);
      case 'restore':
        return column([
          title(
            'Restaurar respaldo',
            'La instalación debe estar sin jornadas. No se sobrescriben registros existentes.',
          ),
          field('Clave del respaldo', secret: true),
          button(
            'Elegir respaldo y restaurar',
            Icons.restore,
            () => act(() async {
              if (input.text.isEmpty) {
                throw StateError('Escribe la clave del respaldo.');
              }
              if (await b!.services.restore(input.text)) {
                input.clear();
                route = 'home';
                trail.clear();
                notice = 'Respaldo restaurado.';
              }
            }),
            primary: true,
          ),
        ]);
      case 'auditFilters':
        return column([
          title('Filtrar auditoría'),
          SwitchListTile(
            title: const Text('Todas las fechas'),
            value: allDates,
            onChanged: busy ? null : (v) => setState(() => allDates = v),
          ),
          if (!allDates)
            button('Fecha: $date', Icons.calendar_month, () async {
              final d = await showDatePicker(
                context: context,
                initialDate: DateTime.parse(date),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (d != null && mounted) {
                setState(() => date = d.toIso8601String().substring(0, 10));
              }
            }),
          field('Operador', controller: personFilter),
          field('Equipo', controller: deviceFilter),
          field('Acción', controller: actionFilter),
          button(
            'Consultar actividad',
            Icons.search,
            () => act(() async {
              auditRows = await b!.repo.audit(
                date: allDates ? null : date,
                operator: personFilter.text,
                equipment: deviceFilter.text,
                action: actionFilter.text,
              );
              auditPage = 0;
              routeAfter('audit');
            }),
            primary: true,
          ),
        ]);
      case 'audit':
        return column([
          title(
            'Auditoría',
            '${auditRows.length} eventos · Página ${auditPage + 1}',
          ),
          ...auditRows
              .skip(auditPage * 100)
              .take(100)
              .map(
                (r) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '${r['occurred_at']}\n${r['actor']} · ${r['device']}\n${r['action']} · ${r['origin']}\n${r['details']}',
                    ),
                  ),
                ),
              ),
          if (auditPage > 0)
            button(
              'Página anterior',
              Icons.chevron_left,
              () => setState(() => auditPage--),
            ),
          if ((auditPage + 1) * 100 < auditRows.length)
            button(
              'Página siguiente',
              Icons.chevron_right,
              () => setState(() => auditPage++),
            ),
          button(
            'Exportar auditoría Excel',
            Icons.table_chart_outlined,
            () => act(
              () => b!.services.exportAudit(
                date: allDates ? null : date,
                operator: personFilter.text,
                device: deviceFilter.text,
                action: actionFilter.text,
              ),
            ),
          ),
        ]);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: route == 'home',
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) back();
    },
    child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight:
            ((MediaQuery.textScalerOf(context).scale(23) +
                            MediaQuery.textScalerOf(context).scale(14)) *
                        1.4 +
                    24)
                .clamp(88, 240),
        titleSpacing: 24,
        backgroundColor: const Color(0xFFFFFDF8),
        surfaceTintColor: Colors.transparent,
        title: const Row(
          children: [
            AppLogo(),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MuleAgent',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
                  ),
                  Text('Administrador', style: TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: column([
            if (route != 'home' &&
                !['name', 'key', 'confirmKey'].contains(route)) ...[
              button('Atrás', Icons.arrow_back, back),
              const SizedBox(height: 24),
            ],
            content(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error!,
                    style: const TextStyle(color: Color(0xFF9D1D3C)),
                  ),
                ),
              ),
            if (notice != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    notice!,
                    style: const TextStyle(color: Color(0xFF166443)),
                  ),
                ),
              ),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(),
              ),
          ]),
        ),
      ),
    ),
  );
}
