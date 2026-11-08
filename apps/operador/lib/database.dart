import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mule_data/mule_data.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

Future<CaptureRepository> openRepository() async {
  const storage = FlutterSecureStorage();
  final dbPath = path.join(await getDatabasesPath(), 'operador.db');
  var key = await storage.read(key: 'local_database_key_v1');
  // Never replace a lost key for an existing database with a newly generated key.
  if (key == null && await databaseExists(dbPath)) {
    throw StateError('Falta la clave local. No se modificó la base existente.');
  }
  if (key == null) {
    final random = Random.secure();
    key = base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)));
    await storage.write(key: 'local_database_key_v1', value: key);
  }
  var deviceId = await storage.read(key: 'device_id_v1');
  if (deviceId == null) {
    deviceId = const Uuid().v4();
    await storage.write(key: 'device_id_v1', value: deviceId);
  }
  final db = await openDatabase(
    dbPath,
    password: key,
    version: schemaVersion,
    onConfigure: configureDatabase,
    onCreate: createSchema,
    onUpgrade: upgradeSchema,
  );
  return CaptureRepository(db, deviceId: deviceId);
}
