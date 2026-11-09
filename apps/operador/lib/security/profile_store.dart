import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mule_profiles/mule_profiles.dart';

class SecureProfileStorage implements ProfileStorage {
  static const key = 'mule_installation_profile_v1';
  static const _secure = FlutterSecureStorage();
  @override
  Future<String?> read() => _secure.read(key: key);
  @override
  Future<void> write(String value) => _secure.write(key: key, value: value);
}
