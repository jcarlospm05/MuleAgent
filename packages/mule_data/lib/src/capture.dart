enum Stage { entry, exit }

extension StageLabel on Stage {
  String get label => this == Stage.entry ? 'Entrada' : 'Salida';
}

class CaptureField {
  const CaptureField(this.column, this.title, this.hint);
  final String column, title, hint;
  static List<CaptureField> forStage(Stage stage) => [
    if (stage == Stage.entry)
      const CaptureField(
        'driver',
        'Nombre del mulero',
        'Escribe el nombre completo.',
      ),
    const CaptureField(
      'code',
      'Número de ficha',
      'Conserva letras y ceros iniciales.',
    ),
    const CaptureField(
      'provider',
      'Proveedor',
      'Escribe el nombre del proveedor.',
    ),
    const CaptureField(
      'time',
      'Hora del registro',
      'Usa el formato de 24 horas: 07:04.',
    ),
    CaptureField(
      'meter',
      stage == Stage.entry ? 'Lectura del horómetro' : 'Lectura final',
      'Escribe las horas que muestra el tablero.',
    ),
    const CaptureField(
      'omission_reason',
      'Evidencia del tablero',
      'En esta primera versión puedes registrar una omisión con su motivo. La cámara se incorporará después.',
    ),
  ];
  String? validate(String value) {
    if (value.trim().isEmpty) return 'Completa este dato para continuar.';
    if (value.length > 200) return 'Usa como máximo 200 caracteres.';
    if (column == 'time' &&
        !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value.trim())) {
      return 'Escribe una hora válida, por ejemplo 07:04.';
    }
    if (column == 'meter' &&
        !RegExp(r'^\d{1,9}([.,]\d{1,3})?$').hasMatch(value.trim())) {
      return 'Escribe una lectura válida con hasta tres decimales.';
    }
    return null;
  }
}

class Draft {
  Draft({
    required this.revisionId,
    required this.ticketId,
    required this.stage,
    required this.date,
    required this.step,
    required this.values,
  });
  final String revisionId, ticketId, date;
  final Stage stage;
  final int step;
  final Map<String, String> values;
  List<CaptureField> get fields => CaptureField.forStage(stage);
  String get value => values[fields[step].column] ?? '';
}
