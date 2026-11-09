import 'package:flutter/services.dart';

class PublicReports {
  static const channel = MethodChannel('muleagent/public-reports');
  static Future<void> prepare() async => channel.invokeMethod<void>('prepare');
  static Future<Map<String, dynamic>> publish(
    String directory,
    List<Map<String, String>> files,
  ) async {
    final result = await channel.invokeMapMethod<String, dynamic>('publish', {
      'directory': directory,
      'files': files,
    });
    if (result == null ||
        result['count'] != files.length ||
        result['folder'] != 'Descargas/$directory') {
      throw StateError('No se confirmó la copia completa en Descargas.');
    }
    return result;
  }
}
