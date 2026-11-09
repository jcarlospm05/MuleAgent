# MuleAgent — aplicación unificada

Único punto de entrada y destino Android de la nueva aplicación: `lib/main.dart`. Supervisor y Administrador usan el mismo recorrido de captura y los mismos servicios. Los directorios operador/administrador se conservan como módulos de transición y para probar/importar datos históricos; no son dos entregas nuevas.

## Etapa 2

- Configuración inicial del perfil, persistida en almacenamiento seguro fuera de SQLite y de los respaldos.
- Supervisor no puede cambiar de rol. Instalación Administrador puede alternar perfiles; recibir exige Administrador activo.
- `com.muleagent.operador` conserva la identidad Android y abre `operador.db` con las mismas claves que Operador 1.0.3. La actualización final debe usar el certificado original.
- Tablas administrativas agregadas transaccionalmente sin reemplazar capturas existentes.
- Respaldos de Operador: vía de restauración compatible. Respaldos de Administrador: importación desde el perfil Administrador, combinando registros iguales y rechazando conflictos sin sobrescribir los actuales.
- Canales Android compartidos en packages/mule_android: guardado público e ingreso desde Abrir con/Compartir.

## Estilo Mule

La paleta, medidas y tipografía aprobadas siguen en `../operador/lib/design/mule_tokens.dart`; la referencia y el prompt están en docs/unificacion/ESTILO-MULE.md. Esta etapa usa el tema anterior compartido: aplicar Estilo Mule y sus temas corresponde a la etapa 3. El logo vectorial aprobado todavía debe producirse como recurso.

La recepción actual mantiene lectura del .mule histórico. Los JPG de captura se incorporan en etapa 4 y la importación por imágenes, consolidación y PDF administrativo en etapa 5. El punto de entrada nuevo no muestra los módulos antiguos de Excel, cruces ni auditoría.

## Verificación

`flutter pub get`, `flutter analyze`, `flutter test --timeout=120s`. CI compila `flutter build apk --debug` para verificar la integración nativa; esa compilación de prueba no se publica como actualización de campo. La APK final y su firma se entregan en etapa 6.
