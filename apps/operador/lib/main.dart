import 'package:flutter/material.dart';
import 'package:mule_data/mule_data.dart';
import 'database.dart';

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
  CaptureSession? session;
  Draft? draft;
  final input = TextEditingController();
  Future<void> pending = Future.value();
  String screen = 'home';
  String? error;
  bool busy = true;
  bool saveFailed = false;
  List<Map<String, Object?>> rows = [];

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    try {
      repo = widget.repository ?? await openRepository();
      session = await repo!.resume();
      if (mounted) setState(() => busy = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error =
              'No se pudo abrir el almacenamiento seguro. Tus datos no se borraron. Cierra y vuelve a abrir la app.';
        });
      }
    }
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
      error = null;
    });
    try {
      await pending;
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se pudo guardar. Conserva esta pantalla e intenta de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load() async {
    draft = await repo!.draft(session!);
    rows = await repo!.tickets(session!);
    input.text = draft?.value ?? '';
    saveFailed = false;
    screen = draft == null ? 'review' : 'capture';
  }

  void changed(String value) {
    final editing = draft!;
    pending = pending.then((_) async {
      try {
        await repo!.saveValue(editing, value);
        if (mounted && saveFailed) {
          setState(() {
            saveFailed = false;
            error = null;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            saveFailed = true;
            error =
                'No se pudo guardar el último cambio. Pulsa Siguiente para reintentar.';
          });
        }
      }
    });
  }

  Future<void> next() async {
    final field = draft!.fields[draft!.step];
    final validation = field.validate(input.text);
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    await act(() async {
      // Retry the visible value even if an automatic save failed.
      await repo!.saveValue(draft!, input.text);
      if (draft!.step == draft!.fields.length - 1) {
        await repo!.complete(session!, draft!);
      } else {
        await repo!.move(draft!, draft!.step + 1);
      }
      await load();
    });
  }

  Future<void> back() => act(() async {
    if (screen == 'capture') {
      await repo!.saveValue(draft!, input.text);
      if (draft!.step > 0) {
        await repo!.move(draft!, draft!.step - 1);
        await load();
      } else {
        screen = 'home';
      }
    } else {
      screen = 'home';
    }
  });

  Widget primary(String label, VoidCallback action) => FilledButton(
    onPressed: busy ? null : action,
    child: Text(label, textAlign: TextAlign.center),
  );

  @override
  Widget build(BuildContext context) {
    final field = draft == null ? null : draft!.fields[draft!.step];
    final Widget body;
    if (busy && repo == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (repo == null) {
      body = const Text('Almacenamiento no disponible');
    } else if (screen == 'home') {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (session != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text('${session!.stage.label} · ${session!.date}'),
            ),
          primary(session == null ? 'Iniciar día' : 'Continuar proceso', () {
            act(() async {
              if (session != null) {
                await load();
              } else {
                screen = 'select';
              }
            });
          }),
          if (session != null)
            TextButton(
              onPressed: busy ? null : () => setState(() => screen = 'select'),
              child: const Text('Registrar otra etapa'),
            ),
        ],
      );
    } else if (screen == 'select') {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '¿Qué vas a registrar?',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 24),
          for (final stage in Stage.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: stage == Stage.entry
                  ? primary('Registrar entrada', () => start(stage))
                  : OutlinedButton(
                      onPressed: busy ? null : () => start(stage),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 64),
                      ),
                      child: const Text(
                        'Registrar salida',
                        style: TextStyle(fontSize: 22),
                      ),
                    ),
            ),
        ],
      );
    } else if (screen == 'capture') {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          Text(field!.title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(field.hint, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 24),
          TextField(
            key: ValueKey('${draft!.ticketId}:${draft!.step}'),
            controller: input,
            enabled: !busy,
            onChanged: changed,
            onSubmitted: (_) => next(),
            textInputAction: TextInputAction.next,
            keyboardType: field.column == 'meter'
                ? const TextInputType.numberWithOptions(decimal: true)
                : field.column == 'time'
                ? TextInputType.datetime
                : TextInputType.text,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: field.column == 'omission_reason'
                  ? 'Motivo de la omisión'
                  : field.title,
            ),
          ),
          const SizedBox(height: 24),
          primary(
            draft!.step == draft!.fields.length - 1
                ? 'Guardar ficha'
                : 'Siguiente →',
            next,
          ),
        ],
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${session!.stage.label} · ${session!.date}'),
          const SizedBox(height: 16),
          Text(
            '${rows.length} fichas registradas',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          for (final row in rows)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${row['code']} · ${row['provider']}'),
              subtitle: Text(
                '${row['time']} · ${row['meter']} h\nFoto omitida: ${row['omission_reason']}',
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: busy
                  ? null
                  : () => act(() async {
                      await repo!.edit(session!, row['id'] as String);
                      await load();
                    }),
            ),
          const SizedBox(height: 24),
          primary(
            'Agregar otra mula',
            () => act(() async {
              await repo!.addTicket(session!);
              await load();
            }),
          ),
          const SizedBox(height: 16),
          const Text(
            'Borrador guardado en este celular. El cierre, las fotos y el envío se incorporarán en la siguiente etapa.',
          ),
        ],
      );
    }
    return PopScope(
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
                    body,
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

  void start(Stage stage) => act(() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    session = await repo!.start(stage, today);
    if (await repo!.draft(session!) == null &&
        (await repo!.tickets(session!)).isEmpty) {
      await repo!.addTicket(session!);
    }
    await load();
  });
}
