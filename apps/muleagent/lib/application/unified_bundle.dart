import 'package:admin_data/admin_data.dart';
import 'package:mule_data/mule_data.dart';
import 'package:mule_profiles/mule_profiles.dart';
import 'package:operador/database.dart';
import 'package:operador/security/profile_store.dart';
import 'package:operador/services.dart';

import 'unified_capture_services.dart';

class UnifiedBundle {
  UnifiedBundle(this.capture, this.admin, this.profiles, this.services);
  final CaptureRepository capture;
  final AdminRepository admin;
  final ProfileRepository profiles;
  final OperatorServices services;

  static Future<UnifiedBundle> open() async {
    final profiles = ProfileRepository(SecureProfileStorage());
    // A damaged profile is an error, never an excuse to choose a new privilege.
    await profiles.load();
    final capture = await openRepository();
    try {
      await ensureAdminSchema(capture.db);
      capture.operatorName = await capture.setting('operator') ?? '';
      final admin = AdminRepository(
        capture.db,
        device: capture.deviceId,
        actor: capture.operatorName,
      );
      final storage = await OperatorServices.create(capture);
      final services = UnifiedCaptureServices(
        capture,
        storage.root,
        profiles,
        admin,
      );
      try {
        await services.recoverPhoto();
      } catch (_) {
        /* Capture offers another photo if recovery failed. */
      }
      return UnifiedBundle(capture, admin, profiles, services);
    } catch (_) {
      await capture.db.close();
      rethrow;
    }
  }
}
