import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mule_data/mule_data.dart';
import 'database.dart';
import 'services.dart';
import 'motion.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OperatorApp());
}

class OperatorApp extends StatelessWidget {
  const OperatorApp({super.key, this.repository});
  final CaptureRepository? repository;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MuleAgent · Operador',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFFFFDF8),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF21355E),
        primary: const Color(0xFF21355E),
        surface: const Color(0xFFFFFDF8),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: Color(0xFF182237),
        ),
        bodyMedium: TextStyle(fontSize: 18),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 64),
          textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    ),
    home: OperatorScreen(repository: repository),
  );
}

class OperatorScreen extends StatefulWidget {
  const OperatorScreen({super.key, this.repository});
  final CaptureRepository? repository;
  @override
  State<OperatorScreen> createState() => _OperatorScreenState();
}

class _OperatorScreenState extends State<OperatorScreen> {
  CaptureRepository? repo;
  OperatorServices? services;
  CaptureSession? session;
  Draft? draft;
  final input = TextEditingController();
  Future<void> pending = Future.value();
  String screen = 'home';
  String? error, notice;
  bool busy = true, closed = false;
  bool reverseMotion = false;
  List<Map<String, Object?>> rows = [], items = [];
  Stage chosenStage = Stage.entry;
  DateTime chosenDate = DateTime.now();
  String setupName = '', setupKey = '';

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    try {
      repo = widget.repository ?? await openRepository();
      if (widget.repository == null) {
        services = await OperatorServices.create(repo!);
        repo!.operatorName = await repo!.setting('operator') ?? '';
        if (!await services!.configured()) {
          screen = 'setupName';
        }
        try {
          await services!.recoverPhoto();
        } catch (_) {
          notice =
              'No se recuperó una foto pendiente. Puedes volver a tomarla.';
        }
      }
      session = await repo!.resume();
    } catch (_) {
      error =
          'No se pudo abrir el almacenamiento seguro. Tus datos no se borraron. Cierra y vuelve a abrir la app.';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> act(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      reverseMotion = false;
      error = null;
      notice = null;
    });
    try {
      await pending;
      await action();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is StateError
              ? e.message.toString()
              : e is ArgumentError
              ? e.message?.toString()
              : e is FormatException
              ? e.message
              : 'No se completó la operación. Comprueba la clave, los permisos y el espacio disponible e intenta de nuevo.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load() async {
    final revision = (await repo!.db.query(
      'revisions',
      where: 'id=?',
      whereArgs: [session!.id],
    )).single;
    closed = revision['status'] == 'closed';
    draft = closed ? null : await repo!.draft(session!);
    rows = await repo!.tickets(session!);
    input.text = draft?.value ?? '';
    screen = closed
        ? 'closed'
        : draft == null
        ? 'review'
        : 'capture';
  }

  void changed(String value) {
    final editing = draft!;
    pending = pending.then((_) async {
      try {
        await repo!.saveValue(editing, value);
      } catch (_) {
        if (mounted) {
          setState(
            () => error =
                'No se guardó el último cambio. Pulsa Siguiente para reintentar.',
          );
        }
      }
    });
  }

  Future<void> next() async {
    final field = draft!.fields[draft!.step];
    final isPhoto =
        field.column == 'omission_reason' &&
        draft!.values['evidence_state'] == 'photo';
    final validation = isPhoto ? null : field.validate(input.text);
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    await act(() async {
      if (field.column == 'code') {
        final duplicates = await repo!.db.query(
          'tickets',
          where: 'revision_id=? AND id!=? AND trim(code)=? AND completed=1',
          whereArgs: [draft!.revisionId, draft!.ticketId, input.text.trim()],
        );
        if (duplicates.isNotEmpty) {
          if (!mounted) return;
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Esta ficha ya está registrada'),
              content: const Text(
                'Revisa el código. ¿Quieres registrar otra mula con el mismo código?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Corregir'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Registrar otra'),
                ),
              ],
            ),
          );
          if (confirmed != true) return;
        }
      }
      if (!isPhoto) await repo!.saveValue(draft!, input.text);
      if (draft!.step == draft!.fields.length - 1) {
        await repo!.complete(session!, draft!);
      } else {
        await repo!.move(draft!, draft!.step + 1);
      }
      await load();
      if (field.column == 'omission_reason') notice = '✓ Ficha guardada.';
    });
  }

  Future<void> back() => act(() async {
    reverseMotion = true;
    if (screen == 'capture') {
      if (draft!.values['evidence_state'] != 'photo' ||
          draft!.fields[draft!.step].column != 'omission_reason') {
        await repo!.saveValue(draft!, input.text);
      }
      if (draft!.step > 0) {
        await repo!.move(draft!, draft!.step - 1);
        await load();
      } else {
        screen = 'home';
      }
    } else if (screen == 'confirmClose') {
      screen = 'review';
    } else if (screen == 'setupKey') {
      input.text = setupName;
      screen = 'setupName';
    } else if (screen == 'setupConfirm') {
      input.clear();
      screen = 'setupKey';
    } else if (screen == 'setupName' && !await services!.configured()) {
      return;
    } else {
      screen = 'home';
      input.clear();
    }
  });
  void go(String target) {
    setState(() {
      reverseMotion = false;
      screen = target;
      error = null;
      notice = null;
      input.clear();
    });
  }

  Widget primary(String label, VoidCallback action) => FilledButton(
    onPressed: busy ? null : action,
    child: Text(label, textAlign: TextAlign.center),
  );
  Widget secondary(String label, VoidCallback action) => TextButton(
    onPressed: busy ? null : action,
    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    child: Text(label, textAlign: TextAlign.center),
  );
  Widget title(String text, [String? hint]) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(text, style: Theme.of(context).textTheme.headlineMedium),
      if (hint != null)
        Padding(padding: const EdgeInsets.only(top: 12), child: Text(hint)),
      const SizedBox(height: 24),
    ],
  );
  Widget field({bool secret = false, String? label, VoidCallback? submit}) =>
      TextField(
        controller: input,
        enabled: !busy,
        obscureText: secret,
        autocorrect: !secret,
        enableSuggestions: !secret,
        style: const TextStyle(fontSize: 24),
        onSubmitted: (_) => submit?.call(),
        decoration: InputDecoration(labelText: label),
      );
  Widget stack(List<Widget> children) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  );

  Widget content() {
    if (repo == null) {
      return busy
          ? const Center(child: CircularProgressIndicator())
          : title('No se pudo abrir la app');
    }
    switch (screen) {
      case 'setupName':
        return stack([
          title(
            '¿Quién registra?',
            'Escribe tu nombre para identificar los registros de este celular.',
          ),
          field(label: 'Nombre del operador'),
          const SizedBox(height: 24),
          primary('Siguiente →', () {
            if (input.text.trim().isEmpty || input.text.length > 100) {
              setState(
                () => error = 'Escribe tu nombre, hasta 100 caracteres.',
              );
              return;
            }
            setupName = input.text.trim();
            go('setupKey');
          }),
        ]);
      case 'setupKey':
        return stack([
          title(
            'Clave compartida',
            'Usa la misma clave en los celulares que intercambian reportes. Necesita al menos 12 caracteres. Guárdala: sin ella no se recuperan los respaldos. Cambiarla no cambia los archivos anteriores.',
          ),
          field(secret: true, label: 'Clave compartida'),
          const SizedBox(height: 24),
          primary('Siguiente →', () {
            if (input.text.length < 12) {
              setState(() => error = 'Usa al menos 12 caracteres.');
              return;
            }
            setupKey = input.text;
            go('setupConfirm');
          }),
        ]);
      case 'setupConfirm':
        return stack([
          title(
            'Repite la clave',
            'Comprueba que la escribiste correctamente.',
          ),
          field(secret: true, label: 'Confirmar clave'),
          const SizedBox(height: 24),
          primary(
            'Guardar configuración',
            () => act(() async {
              if (input.text != setupKey) {
                throw StateError(
                  'Las claves no coinciden. Vuelve a escribirla.',
                );
              }
              await services!.configure(setupName, setupKey);
              setupKey = '';
              input.clear();
              screen = 'home';
            }),
          ),
        ]);
      case 'home':
        return stack([
          if (session != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text('${session!.stage.label} · ${session!.date}'),
            ),
          primary(
            session == null ? 'Iniciar día' : 'Continuar proceso',
            () => act(() async {
              if (session != null) {
                await load();
              } else {
                screen = 'select';
              }
            }),
          ),
          secondary('Registrar otra etapa', () => go('select')),
          secondary('Jornadas pendientes', () => listSessions(false)),
          secondary('Historial y archivos', () => listSessions(true)),
          if (services != null) ...[
            secondary('Respaldo y restauración', () => go('backup')),
            secondary('Configuración', () {
              setupName = repo!.operatorName;
              go('setupName');
              input.text = setupName;
            }),
          ],
        ]);
      case 'select':
        return stack([
          title('¿Qué vas a registrar?'),
          primary('Registrar entrada', () => choose(Stage.entry)),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: busy ? null : () => choose(Stage.exit),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 64),
            ),
            child: const Text(
              'Registrar salida',
              style: TextStyle(fontSize: 22),
            ),
          ),
        ]);
      case 'date':
        return stack([
          title(
            'Fecha de la jornada',
            '${chosenStage.label} · ${chosenDate.day}/${chosenDate.month}/${chosenDate.year}',
          ),
          primary('Continuar', start),
          secondary('Cambiar fecha', () async {
            final date = await showDatePicker(
              context: context,
              initialDate: chosenDate,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (date != null && mounted) setState(() => chosenDate = date);
          }),
        ]);
      case 'capture':
        return capture();
      case 'review':
        return stack([
          Text('${session!.stage.label} · ${session!.date}'),
          const SizedBox(height: 16),
          title(
            '${rows.length} fichas registradas',
            'Toca una ficha para revisarla o corregirla.',
          ),
          ...rows.map((r) => ticketTile(r, editable: true)),
          const SizedBox(height: 24),
          primary(
            'Agregar otra mula',
            () => act(() async {
              await repo!.addTicket(session!);
              await load();
            }),
          ),
          secondary('Ya no hay más mulas', () => go('confirmClose')),
        ]);
      case 'confirmClose':
        return stack([
          title(
            'Cerrar ${session!.stage.label.toLowerCase()}',
            '${session!.date} · ${rows.length} fichas. Se conservará esta revisión y se prepararán el PDF y el archivo cifrado.',
          ),
          primary(
            'Cerrar y preparar archivos',
            () => act(() async {
              if (rows.isEmpty) {
                throw StateError('Registra al menos una ficha.');
              }
              await repo!.closeRevision(session!);
              await load();
              await services!.ensureArtifacts(session!);
              notice = 'Etapa cerrada. Los archivos están listos.';
            }),
          ),
        ]);
      case 'closed':
        return stack([
          title(
            '${session!.stage.label} cerrada',
            '${session!.date} · ${rows.length} fichas. Los archivos de esta revisión se conservan para reenviarlos.',
          ),
          primary(
            'Compartir por WhatsApp',
            () => act(() async {
              await services!.share(session!);
              notice =
                  'Se abrió el flujo de compartir. Elige WhatsApp y comprueba ambos adjuntos. La app no confirma entrega.';
            }),
          ),
          secondary(
            'Ver e imprimir PDF',
            () => act(() => services!.previewPdf(session!)),
          ),
          secondary(
            'Guardar PDF y archivo cifrado',
            () => act(() => services!.exportArtifacts(session!)),
          ),
          secondary('Ver fichas y fotos', () => go('details')),
          secondary(
            'Continuar esta jornada',
            () => act(() async {
              session = await repo!.reopen(session!);
              await load();
              notice = 'Nueva revisión creada. El cierre anterior se conserva.';
            }),
          ),
          secondary(
            'Volver al inicio',
            () => act(() async {
              session = await repo!.resume();
              screen = 'home';
            }),
          ),
        ]);
      case 'details':
        return stack([
          title(
            'Fichas y evidencias',
            '${session!.stage.label} · ${session!.date}',
          ),
          ...rows.map((r) => ticketTile(r)),
          secondary('Volver al reporte', () => go('closed')),
        ]);
      case 'sessions':
        return stack([
          title(closed ? 'Historial de cierres' : 'Jornadas pendientes'),
          if (items.isEmpty)
            const Text('Todavía no hay jornadas en esta lista.'),
          ...items.map(
            (row) => ListTile(
              title: Text(
                '${Stage.values.byName(row['stage'] as String).label} · ${row['operational_date']}',
              ),
              subtitle: Text('Revisión ${row['number']}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: busy
                  ? null
                  : () => act(() async {
                      session = await repo!.sessionById(row['id'] as String);
                      await load();
                    }),
            ),
          ),
        ]);
      case 'backup':
        return stack([
          title(
            'Respaldo y restauración',
            'Conserva jornadas, borradores, fotos originales y archivos exactos de los cierres en un respaldo cifrado. Se restaura con la clave usada al crearlo.',
          ),
          primary(
            'Guardar respaldo completo',
            () => act(() async {
              final saved = await services!.backup();
              if (!saved) return;
              notice =
                  'Si elegiste un destino, el respaldo quedó guardado allí.';
            }),
          ),
          secondary('Restaurar un respaldo', () => go('restore')),
        ]);
      case 'restore':
        return stack([
          title(
            'Clave del respaldo',
            'Escribe la clave con la que se creó. Los registros existentes distintos no se sobrescriben.',
          ),
          field(secret: true, label: 'Clave del respaldo'),
          const SizedBox(height: 24),
          primary(
            'Elegir respaldo y restaurar',
            () => act(() async {
              if (input.text.isEmpty) {
                throw StateError('Escribe la clave del respaldo.');
              }
              final restored = await services!.restore(input.text);
              if (!restored) return;
              input.clear();
              session = await repo!.resume();
              screen = 'home';
              notice =
                  'Proceso terminado. Las jornadas restauradas aparecen en pendientes e historial.';
            }),
          ),
        ]);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget capture() {
    final f = draft!.fields[draft!.step];
    final photoStep = f.column == 'omission_reason';
    final hasPhoto = draft!.values['evidence_state'] == 'photo';
    return stack([
      Text(
        '${session!.stage.label} · ${draft!.step + 1} de ${draft!.fields.length}',
      ),
      const SizedBox(height: 16),
      LinearProgressIndicator(
        value: (draft!.step + 1) / draft!.fields.length,
        color: const Color(0xFF966018),
        semanticsLabel: 'Progreso de captura',
      ),
      const SizedBox(height: 28),
      title(
        f.title,
        photoStep
            ? 'Incluye el tablero completo y comprueba que se lea el horómetro.'
            : f.hint,
      ),
      if (photoStep && services != null) ...[
        if (hasPhoto) ...[
          GestureDetector(
            onTap: () =>
                showPhoto(services!.file(draft!.values['private_path']!)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.file(
                services!.file(draft!.values['private_path']!),
                height: 220,
                fit: BoxFit.contain,
              ),
            ),
          ),
          secondary(
            'Repetir o cambiar foto',
            () => act(() async {
              await repo!.clearPhoto(draft!);
              await load();
            }),
          ),
        ] else ...[
          if (draft!.values['evidence_state'] == 'omitted')
            secondary('Tomar foto en su lugar', () => photo(ImageSource.camera))
          else
            primary('Tomar foto del tablero', () => photo(ImageSource.camera)),
          secondary('Cargar foto guardada', () => photo(ImageSource.gallery)),
          if (draft!.values['evidence_state'] != 'omitted')
            secondary('Registrar omisión de foto', () {
              setState(() {
                draft!.values['evidence_state'] = 'omitted';
                input.clear();
              });
            }),
        ],
      ],
      if (!photoStep ||
          (!hasPhoto &&
              (services == null ||
                  draft!.values['evidence_state'] == 'omitted'))) ...[
        captureInput(f),
      ],
      const SizedBox(height: 24),
      if (!photoStep ||
          hasPhoto ||
          services == null ||
          draft!.values['evidence_state'] == 'omitted')
        primary(photoStep ? 'Guardar ficha' : 'Siguiente →', next),
    ]);
  }

  Widget captureInput(CaptureField f) {
    final child = TextField(
      key: ValueKey('${draft!.ticketId}:${draft!.step}'),
      controller: input,
      enabled: !busy,
      onChanged: changed,
      onSubmitted: (_) => next(),
      textInputAction: TextInputAction.next,
      keyboardType: f.column == 'meter'
          ? const TextInputType.numberWithOptions(decimal: true)
          : f.column == 'time'
          ? TextInputType.datetime
          : TextInputType.text,
      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: f.column == 'omission_reason'
            ? 'Motivo de la omisión'
            : f.title,
      ),
    );
    return f.column == 'meter'
        ? MeterBorder(key: ValueKey(draft!.ticketId), child: child)
        : child;
  }

  void photo(ImageSource source) => act(() async {
    await services!.selectPhoto(draft!, source);
    await load();
  });
  Future<void> showPhoto(File image) => showDialog<void>(
    context: context,
    builder: (_) => Dialog.fullscreen(
      child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Image.file(image),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget ticketTile(Map<String, Object?> row, {bool editable = false}) => Card(
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: stack([
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${row['code']} · ${row['provider']}'),
          subtitle: Text(
            '${row['driver'] ?? ''}\n${row['time']} · ${row['meter']} h\n${row['evidence_state'] == 'photo' ? 'Foto disponible' : 'Foto omitida: ${row['omission_reason']}'}',
          ),
          trailing: editable ? const Icon(Icons.edit_outlined) : null,
          onTap: editable && !busy
              ? () => act(() async {
                  await repo!.edit(session!, row['id'] as String);
                  await load();
                })
              : null,
        ),
        if (row['evidence_state'] == 'photo' && services != null)
          Row(
            children: [
              Expanded(
                child: secondary(
                  'Ver foto',
                  () =>
                      showPhoto(services!.file(row['private_path'] as String)),
                ),
              ),
              Expanded(
                child: secondary(
                  'Guardar original',
                  () => act(() => services!.exportPhoto(row, session!)),
                ),
              ),
            ],
          ),
      ]),
    ),
  );
  void choose(Stage stage) {
    chosenStage = stage;
    chosenDate = DateTime.now();
    if (widget.repository != null) {
      start();
    } else {
      go('date');
    }
  }

  void start() => act(() async {
    final date = chosenDate.toIso8601String().substring(0, 10);
    session = await repo!.start(chosenStage, date);
    final revision = (await repo!.db.query(
      'revisions',
      where: 'id=?',
      whereArgs: [session!.id],
    )).single;
    if (revision['status'] == 'draft' &&
        await repo!.draft(session!) == null &&
        (await repo!.tickets(session!)).isEmpty) {
      await repo!.addTicket(session!);
    }
    await load();
  });
  void listSessions(bool history) => act(() async {
    items = await repo!.sessions(closed: history);
    closed = history;
    screen = 'sessions';
  });
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: screen == 'home',
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !busy) back();
    },
    child: Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 48).clamp(
                  0,
                  double.infinity,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (screen != 'home')
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: busy ? null : back,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Atrás'),
                      ),
                    ),
                  AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 240),
                    transitionBuilder: (child, animation) {
                      final entering =
                          child.key ==
                          ValueKey(
                            '$screen:${screen == 'capture' ? draft?.step : ''}',
                          );
                      final direction = reverseMotion ? -.08 : .08;
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: Offset(entering ? direction : -direction, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey(
                        '$screen:${screen == 'capture' ? draft?.step : ''}',
                      ),
                      child: content(),
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          error!,
                          style: const TextStyle(
                            color: Color(0xFF9D1D3C),
                            fontSize: 18,
                          ),
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
                  if (busy && repo != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
