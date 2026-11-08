import 'dart:convert';
import 'dart:math';
import 'package:admin_data/admin_data.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mule_data/mule_data.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

Future<CaptureRepository> openAdminDatabase() async {
  const storage = FlutterSecureStorage();
  final path = p.join(await getDatabasesPath(), 'administrador.db');
  var key = await storage.read(key: 'admin_database_key_v1');
  if (key == null && await databaseExists(path)) {
    throw StateError('Falta la clave local. La base existente se conservó.');
  }
  if (key == null) {
    final r = Random.secure();
    key = base64UrlEncode(List.generate(32, (_) => r.nextInt(256)));
    await storage.write(key: 'admin_database_key_v1', value: key);
  }
  var device = await storage.read(key: 'admin_device_v1');
  if (device == null) {
    device = const Uuid().v4();
    await storage.write(key: 'admin_device_v1', value: device);
  }
  final db = await openDatabase(
    path,
    password: key,
    version: 1,
    onConfigure: configureDatabase,
    onCreate: (db, _) async {
      await createSchema(db, schemaVersion);
      await createAdminSchema(db);
    },
  );
  return CaptureRepository(db, deviceId: device);
}
