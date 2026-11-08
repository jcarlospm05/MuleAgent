import 'package:mule_data/mule_data.dart';

/// A revision keeps the same name when it is saved or sent again.
String reportFilenameBase(Stage stage, String date, DateTime closedAt) {
  final local = closedAt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(local.hour)}-${two(local.minute)}-${two(local.second)}';
  return '${stage == Stage.entry ? 'entrada' : 'salida'}_${date}_$time-${local.millisecond.toString().padLeft(3, '0')}';
}
