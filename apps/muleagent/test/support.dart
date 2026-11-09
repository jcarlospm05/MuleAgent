import 'dart:io';
import 'package:admin_data/admin_data.dart';
import 'package:mule_data/mule_data.dart';
import 'package:mule_profiles/mule_profiles.dart';
import 'package:muleagent/application/unified_bundle.dart';
import 'package:muleagent/application/unified_capture_services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MemoryProfiles implements ProfileStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

class TestCaptureServices extends UnifiedCaptureServices {
  TestCaptureServices(super.repo, super.root, super.profiles, super.admin)
    : super(publicStorageEnabled: false);
  @override
  Future<bool> configured() async => true;
  @override
  Future<String> password() async => 'mule-unified-test-key-123';
}

class TestInstallation {
  TestInstallation(this.db, this.root, this.bundle);
  final Database db;
  final Directory root;
  final UnifiedBundle bundle;
  static Future<TestInstallation> create({AppRole? role}) async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        version: schemaVersion,
        onConfigure: configureDatabase,
        onCreate: createSchema,
      ),
    );
    await ensureAdminSchema(db);
    final root = await Directory.systemTemp.createTemp('unified_test_');
    final capture = CaptureRepository(db, deviceId: 'unified-test')
      ..operatorName = 'Julio';
    final profiles = ProfileRepository(MemoryProfiles());
    if (role != null) await profiles.configure(role);
    final admin = AdminRepository(
      db,
      device: capture.deviceId,
      actor: capture.operatorName,
    );
    final services = TestCaptureServices(capture, root, profiles, admin);
    return TestInstallation(
      db,
      root,
      UnifiedBundle(capture, admin, profiles, services),
    );
  }

  Future<void> close() async {
    await db.close();
    await root.delete(recursive: true);
  }
}
