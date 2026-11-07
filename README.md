# MuleAgent

Dos aplicaciones Android para registrar entradas y salidas de mulas rentadas. El desarrollo comienza por Operador y continúa con Administrador, con identificadores y almacenamiento independientes.

## Desarrollo iniciado

- [`apps/operador`](apps/operador): aplicación Flutter, captura guiada y persistencia local SQLCipher.
- [`packages/mule_data`](packages/mule_data): modelo, esquema SQLite, validaciones y repositorio transaccional compartido.
- [Arquitectura y pendientes](docs/arquitectura-datos-v1.md).

La base inicial permite registrar entrada y salida, retomar el paso persistido, revisar y editar fichas. Conserva un dato por pantalla. Evidencia mediante omisión expresa con motivo; cámara, cierre, PDF, envío, respaldo y Administrador siguen pendientes. No es todavía una APK terminada para operación en campo.

## Validación

```sh
cd packages/mule_data
dart pub get
dart analyze
dart test
cd ../../apps/operador
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Usar Flutter 3.47.9 y Android SDK para compilar. GitHub Actions verifica análisis, pruebas y compilación de depuración; los tests locales no sustituyen una prueba en Android físico de SQLCipher, Keystore, cámara y compartir.

## Referencias

- [Prototipo aprobado](prototipo/conduces.html)
- [Base original de diseño y flujo](docs/base-aprobada.md)
- [Módulos del Administrador](docs/modulos-administrador.md)
- [Plan maestro v2](https://docs.google.com/document/d/19a6wKi1g6V3FK0fXGAqGsATZPMZln6YXK2bkbEARnmE/edit)

El plan v2 propone un paquete de intercambio cifrado versionado y respaldo con PDF exactos; esas propuestas actualizan la base original cuando se implementen y validen. El prototipo HTML usa datos de muestra y no persiste información.
