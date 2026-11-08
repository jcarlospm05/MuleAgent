# MuleAgent Operador 1.0.1

Flutter 3.47.9 / Dart 3.13.7 · Android mínimo API 24 · `com.muleagent.operador`.

```sh
flutter pub get
flutter analyze
flutter test --timeout=120s
flutter run
flutter build apk --debug
```

Incluye captura guiada, cámara/galería, SQLCipher/Keystore, recuperación, revisión, cierre, PDF, paquete cifrado, compartir ambos adjuntos, historial, reapertura y respaldo/restauración. Ver [instalación y límites](../../docs/operador-v1.0.md) y [arquitectura](../../docs/arquitectura-datos-v1.md).

El APK de CI es de desarrollo y se publica como prerelease para prueba de campo. La firma productiva no está configurada. Los tests de repositorio usan SQLite normal; la validación física de SQLCipher, permisos, cámara y WhatsApp debe realizarse en Android.
