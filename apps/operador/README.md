# Operador · base 0.1.0

Flutter 3.47.9 / Dart 3.13.7. Android mínimo API 23. Identificador `com.muleagent.operador`.

```sh
flutter pub get
flutter analyze
flutter test
flutter run
flutter build apk --debug
```

Ejecutar desde este directorio con Flutter y Android SDK instalados. Flutter regenera el wrapper de Gradle y `local.properties` cuando faltan. El APK de depuración no requiere secretos de firma. La firma de producción aún debe configurarse; no se entrega una versión de producción firmada con claves de depuración.

Permite capturar entrada/salida en pasos individuales, guardar cada campo, retomar el borrador y editar fichas. Esta versión solo permite evidencias mediante omisión con motivo. No incluye cámara, PDF, cierre, envío ni respaldo.

El almacenamiento real usa SQLCipher y Android Keystore; los tests de escritorio usan SQLite normal y no acreditan el cifrado Android. No usar todavía para registros reales sin un procedimiento de recuperación probado. Ver [arquitectura](../../docs/arquitectura-datos-v1.md).
