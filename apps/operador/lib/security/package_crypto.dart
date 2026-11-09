import 'dart:typed_data';
import 'package:mule_data/mule_data.dart';

// Top-level functions remain usable with Flutter compute/isolate.
Future<Uint8List> encryptPayload(Map<String, dynamic> args) =>
    PackageCodec().encode(
      args['payload'] as Map<String, dynamic>,
      args['password'] as String,
    );
Future<Map<String, dynamic>> decryptPayload(Map<String, dynamic> args) =>
    PackageCodec().decode(
      args['bytes'] as Uint8List,
      args['password'] as String,
    );
