import 'dart:async';

import 'package:administrador/incoming.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mule_profiles/mule_profiles.dart';
import 'package:operador/main.dart';

import '../profiles/profile_setup_screen.dart';
import '../receiving/received_reports_screen.dart';
import 'unified_bundle.dart';

class UnifiedShell extends StatefulWidget {
  const UnifiedShell({super.key, this.bundle});
  final UnifiedBundle? bundle;
  @override
  State<UnifiedShell> createState() => _UnifiedShellState();
}

class _UnifiedShellState extends State<UnifiedShell> {
  UnifiedBundle? bundle;
  InstallationProfile? profile;
  bool loading = true,
      choosing = false,
      receiving = false,
      checkingInbox = false;
  String? error, notice;

  @override
  void initState() {
    super.initState();
    IncomingReports.channel.setMethodCallHandler((call) async {
      if (call.method == 'available') await offerIncoming();
    });
    initialize();
  }

  @override
  void dispose() {
    IncomingReports.channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> initialize() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      bundle ??= widget.bundle ?? await UnifiedBundle.open();
      profile = await bundle!.profiles.load();
    } catch (e) {
      error = e is FormatException
          ? e.message
          : 'No se pudo abrir la instalación. Los datos existentes se conservaron.';
    }
    if (mounted) {
      setState(() => loading = false);
      await offerIncoming();
    }
  }

  Future<void> configure(AppRole role) async {
    setState(() {
      choosing = true;
      error = null;
    });
    try {
      profile = await bundle!.profiles.configure(role);
    } catch (e) {
      error = e is StateError
          ? e.message.toString()
          : 'No se pudo guardar el perfil. Inténtalo de nuevo.';
    } finally {
      if (mounted) setState(() => choosing = false);
    }
    await offerIncoming();
  }

  Future<void> switchRole() async {
    try {
      final current = await bundle!.profiles.load();
      if (current == null || !current.canSwitchRoles) {
        throw StateError('Esta instalación solo permite Supervisor.');
      }
      final next = current.activeRole == AppRole.administrator
          ? AppRole.supervisor
          : AppRole.administrator;
      final updated = await bundle!.profiles.switchTo(next);
      if (mounted) {
        setState(() {
          profile = updated;
          notice = null;
        });
      }
      await offerIncoming();
    } catch (e) {
      if (mounted) {
        setState(
          () => notice = e is StateError
              ? e.message.toString()
              : 'No se pudo cambiar el perfil.',
        );
      }
    }
  }

  Future<String?> peek() async {
    try {
      return await IncomingReports.peek();
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> offerIncoming() async {
    if (!mounted ||
        loading ||
        choosing ||
        receiving ||
        checkingInbox ||
        profile == null ||
        bundle == null) {
      return;
    }
    checkingInbox = true;
    try {
      if (!await bundle!.services.configured()) return;
      final path = await peek();
      if (path == null || !mounted) return;
      final current = await bundle!.profiles.load();
      if (current?.canReceiveReports != true) {
        if (current?.canSwitchRoles == true) {
          setState(
            () => notice =
                'Hay un archivo recibido. Cambia a Administrador para importarlo.',
          );
        } else {
          // Remove only our temporary copies; the sender's originals remain intact.
          var pending = path;
          while (true) {
            await IncomingReports.remove(pending);
            final next = await peek();
            if (next == null) break;
            pending = next;
          }
          if (mounted) {
            setState(
              () => notice =
                  'Esta instalación es Supervisor. Recibir reportes requiere Administrador.',
            );
          }
        }
        return;
      }
      await openReceiver(path);
    } on PlatformException catch (e) {
      if (mounted) {
        setState(
          () => notice = e.message ?? 'No se pudo abrir el archivo recibido.',
        );
      }
    } on StateError catch (e) {
      if (mounted) setState(() => notice = e.message.toString());
    } finally {
      checkingInbox = false;
    }
  }

  Future<void> openReceiver([String? path]) async {
    if (receiving) return;
    try {
      await bundle!.profiles.requireAdministrator();
      if (!mounted) return;
      receiving = true;
      final selected = path ?? await peek();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ReceivedReportsScreen(bundle: bundle!, incomingPath: selected),
        ),
      );
    } on StateError catch (e) {
      if (mounted) setState(() => notice = e.message.toString());
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => notice = e.message ?? 'No se pudo abrir la recepción.');
      }
    } finally {
      receiving = false;
    }
  }

  List<Widget> homeActions(BuildContext context) => [
    if (notice != null)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(notice!),
      ),
    if (profile!.canReceiveReports)
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: OutlinedButton.icon(
          onPressed: () => openReceiver(),
          icon: const Icon(Icons.file_download_outlined),
          label: const Text('Recibir reportes'),
        ),
      ),
    if (profile!.canSwitchRoles)
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: OutlinedButton.icon(
          onPressed: switchRole,
          icon: const Icon(Icons.switch_account_outlined),
          label: Text(
            profile!.activeRole == AppRole.administrator
                ? 'Cambiar a Supervisor'
                : 'Volver a Administrador',
          ),
        ),
      ),
  ];
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (error != null && (bundle == null || profile == null)) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(error!),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: initialize,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (profile == null) {
      return ProfileSetupScreen(
        busy: choosing,
        onSelected: configure,
        error: error,
      );
    }
    return OperatorScreen(
      key: ValueKey(profile!.activeRole),
      repository: bundle!.capture,
      captureServices: bundle!.services,
      roleLabel: profile!.activeRole.label,
      homeActions: homeActions,
      onConfigured: () => unawaited(offerIncoming()),
    );
  }
}
