import 'dart:io';

import 'package:administrador/services.dart';
import 'package:admin_data/admin_data.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:mule_data/mule_data.dart';
import 'package:mule_profiles/mule_profiles.dart';
import 'package:operador/services.dart';

/// One capture/backup path for both roles. Installation capability is never restored.
class UnifiedCaptureServices extends OperatorServices {
  UnifiedCaptureServices(
    super.repo,
    super.root,
    this.profiles,
    this.admin, {
    super.publicStorageEnabled = true,
  });
  final ProfileRepository profiles;
  final AdminRepository admin;
  AdminServices get administration =>
      AdminServices(admin, repo, this, access: profiles);

  @override
  Future<bool> backup() async {
    final profile = await profiles.load();
    if (profile == null) {
      throw StateError('Configura el perfil antes de crear un respaldo.');
    }
    if (!profile.canSwitchRoles) return super.backup();
    return administration.backup();
  }

  @override
  Future<bool> restore(String key) async {
    final selected = await FilePicker.platform.pickFiles(type: FileType.any);
    if (selected == null) return false;
    final path = selected.files.single.path;
    if (path == null) throw StateError('No se pudo abrir el respaldo.');
    final source = File(path);
    if (await source.length() > PackageCodec.maxBytes * 2) {
      throw StateError('Archivo demasiado grande.');
    }
    final payload = await compute(decryptPayload, {
      'bytes': await source.readAsBytes(),
      'password': key,
    });
    return restorePayload(payload);
  }

  @override
  Future<bool> restorePayload(Map<String, dynamic> payload) async {
    if (payload['app'] == 'administrator') {
      // Received archives can only enter an Administrator installation/profile.
      await profiles.requireAdministrator();
      return administration.restorePayload(payload, merge: true);
    }
    return super.restorePayload(payload);
  }
}
