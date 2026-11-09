import 'dart:async';
import 'dart:convert';

enum AppRole {
  supervisor,
  administrator;

  String get label => this == supervisor ? 'Supervisor' : 'Administrador';
}

abstract interface class ProfileStorage {
  Future<String?> read();
  Future<void> write(String value);
}

abstract interface class AdministrativeAccess {
  Future<void> requireAdministrator();
}

class InstallationProfile {
  const InstallationProfile._(this.installedAs, this.activeRole);
  final AppRole installedAs;
  final AppRole activeRole;
  bool get canSwitchRoles => installedAs == AppRole.administrator;
  bool get canReceiveReports =>
      canSwitchRoles && activeRole == AppRole.administrator;

  String encode() => jsonEncode({
    'version': 1,
    'installed_as': installedAs.name,
    'active_role': activeRole.name,
  });

  factory InstallationProfile.decode(String value) {
    try {
      final raw = jsonDecode(value) as Map<String, dynamic>;
      if (raw.length != 3 || raw['version'] != 1) throw const FormatException();
      final installed = AppRole.values.byName(raw['installed_as'] as String);
      final active = AppRole.values.byName(raw['active_role'] as String);
      if (installed == AppRole.supervisor && active != AppRole.supervisor) {
        throw const FormatException();
      }
      return InstallationProfile._(installed, active);
    } catch (_) {
      throw const FormatException(
        'No se pudo leer el perfil guardado. No se modificaron los datos.',
      );
    }
  }
}

/// The secure installation record is separate from SQLite and all backups.
class ProfileRepository implements AdministrativeAccess {
  ProfileRepository(this.storage);
  final ProfileStorage storage;
  Future<void> _pending = Future<void>.value();

  Future<InstallationProfile?> load() async {
    await _pending;
    final raw = await storage.read();
    return raw == null ? null : InstallationProfile.decode(raw);
  }

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<InstallationProfile> configure(AppRole installedAs) =>
      _exclusive(() async {
        if (await storage.read() != null) {
          throw StateError('El perfil inicial ya está configurado.');
        }
        final profile = InstallationProfile._(installedAs, installedAs);
        await storage.write(profile.encode());
        return profile;
      });

  Future<InstallationProfile> switchTo(AppRole role) => _exclusive(() async {
    final raw = await storage.read();
    if (raw == null) {
      throw StateError('Primero configura el perfil de la instalación.');
    }
    final current = InstallationProfile.decode(raw);
    if (!current.canSwitchRoles) {
      throw StateError('Esta instalación solo permite el perfil Supervisor.');
    }
    final next = InstallationProfile._(current.installedAs, role);
    await storage.write(next.encode());
    return next;
  });

  @override
  Future<void> requireAdministrator() async {
    if ((await load())?.canReceiveReports != true) {
      throw StateError(
        'Recibir reportes requiere el perfil Administrador activo.',
      );
    }
  }
}
