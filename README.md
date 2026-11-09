# MuleAgent

Aplicaciones Android para registrar entradas y salidas de mulas rentadas. La entrega actual es **Operador 1.0.1**, con un objetivo por pantalla, funcionamiento sin conexión y almacenamiento cifrado. Administrador es el segundo APK planificado.

- [`apps/operador`](apps/operador): captura, cámara, revisión, cierres, PDF, intercambio, historial y respaldos.
- [`packages/mule_data`](packages/mule_data): dominio, SQLite, auditoría, revisiones, restauración y cifrado autenticado.
- [Guía de instalación, funciones y límites](docs/operador-v1.0.md).
- [Arquitectura y contrato de intercambio](docs/arquitectura-datos-v1.md).

## Compilación y pruebas

```sh
cd packages/mule_data
dart pub get
dart analyze
dart test
cd ../../apps/operador
flutter pub get
flutter analyze
flutter test --timeout=120s
flutter build apk --debug
```

Flutter 3.47.9, JDK 17 y Android SDK. GitHub Actions analiza, prueba y compila; conserva el APK como artefacto y publica una prerelease de desarrollo en la rama de implementación. No equivale a validación física ni a una distribución firmada para producción.

## Referencias de producto

- [Prototipo aprobado](prototipo/conduces.html)
- [Base original](docs/base-aprobada.md)
- [Módulos del Administrador](docs/modulos-administrador.md)
- [Plan maestro v2](https://docs.google.com/document/d/19a6wKi1g6V3FK0fXGAqGsATZPMZln6YXK2bkbEARnmE/edit)

El plan v2 actualiza el intercambio a un paquete cifrado versionado y conserva los PDF exactos en el respaldo. El prototipo HTML es una referencia visual con datos de muestra.


## Aplicación unificada en desarrollo

El nuevo punto de entrada es apps/muleagent. Ver docs/unificacion/MASTER.md para acuerdos y etapas, docs/unificacion/ESTILO-MULE.md para el diseño aprobado y docs/unificacion/ETAPA-2.md para perfiles y migración. La rama de trabajo es refactor/mule-unificada. Las apps anteriores permanecen como módulos de compatibilidad; la nueva entrega será una sola APK.
