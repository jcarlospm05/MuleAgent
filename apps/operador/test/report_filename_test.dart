import 'package:flutter_test/flutter_test.dart';
import 'package:mule_data/mule_data.dart';
import 'package:operador/report_filename.dart';

void main() {
  test(
    'entry and exit use safe filenames with operational date and closure time',
    () {
      final closed = DateTime(2026, 11, 9, 1, 3, 5, 7);
      expect(
        reportFilenameBase(Stage.entry, '2026-11-08', closed),
        'entrada_2026-11-08_01-03-05-007',
      );
      expect(
        reportFilenameBase(Stage.exit, '2026-11-08', closed),
        'salida_2026-11-08_01-03-05-007',
      );
    },
  );
  test('re-sends retain the closure name and distinct milliseconds differ', () {
    final time = DateTime(2026, 11, 8, 11, 3, 25, 123);
    final name = reportFilenameBase(Stage.entry, '2026-11-08', time);
    expect(reportFilenameBase(Stage.entry, '2026-11-08', time), name);
    expect(
      reportFilenameBase(
        Stage.entry,
        '2026-11-08',
        time.add(const Duration(milliseconds: 1)),
      ),
      isNot(name),
    );
  });
}
