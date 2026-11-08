import 'package:flutter/services.dart';

/// Android copies granted content URIs into its private inbox before notifying Dart.
class IncomingReports {
  static const channel = MethodChannel('muleagent/incoming');
  static Future<String?> peek() => channel.invokeMethod<String>('peek');
  static Future<void> remove(String path) =>
      channel.invokeMethod<void>('remove', {'path': path});
}
