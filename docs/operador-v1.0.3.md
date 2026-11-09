# MuleAgent Operador 1.0.3

Guarda automáticamente una copia visible de cada cierre en Descargas/MuleAgent, antes de abrir WhatsApp. Conserva además el almacenamiento privado que ya tenía la app.

## Carpeta del dispositivo

Al abrir la aplicación se crea Descargas/MuleAgent con una guía LEEME.txt. Android ejecuta este código al abrir la app por primera vez, no durante la instalación. Android 10 o posterior usa MediaStore Downloads, sin permiso general de archivos. Android 7–9 requiere el permiso de almacenamiento del sistema.

Cada cierre usa una carpeta por fecha, etapa (inicio o salida), hora, revisión e identificador. Ejemplo:

Descargas/MuleAgent/2026-11-08/inicio/inicio_2026-11-08_11-03-25-123_r1_ab12cd34/

Dentro se guardan:
- inicio_2026-11-08_11-03-25-123.pdf (o salida_...pdf).
- entrada_2026-11-08_11-03-25-123.mule (o salida_...mule). Se mantiene la extensión .mule compatible con Administrador.
- foto_000362_2026-11-08_inicio_...jpg/png: bytes exactos de cada foto original, sin recompresión. Si se omitió una foto, el motivo queda en el PDF y en los datos; no se inventa una imagen.

La fecha es la jornada, la hora es la del cierre. Cada revisión tiene su carpeta independiente. Compartir sigue usando los nombres de Operador 1.0.2.

## Guardado y recuperación

Cerrar conserva la revisión en SQLite, prepara el PDF y el paquete privado y escribe las copias públicas. Compartir vuelve a verificar/guardar las copias antes de abrir WhatsApp. El resultado del envío no altera los archivos conservados. La pantalla confirma la carpeta solo cuando se verificaron todos los archivos.

Si faltan permisos, hay poco espacio o se interrumpe el guardado, los originales privados permanecen y no se registra éxito público. Se muestra un aviso y el botón Guardar copia en Descargas. Al volver a abrir se reintentan los cierres sin copia confirmada, incluidos cierres antiguos. Carpeta de reportes → Guardar o recuperar todos los cierres verifica también los ya guardados y recupera copias públicas eliminadas.

Cada archivo se verifica por SHA-256. Las copias iguales se reutilizan; si se encuentra una copia pública distinta, no se sobrescribe: se conserva y se crea otra. En Android 10+ se publican archivos completos mediante IS_PENDING; un fallo elimina únicamente la fila incompleta creada en ese intento. Los originales y las revisiones no cambian.

La copia automática se activa en la app Operador. No se cambia el comportamiento de las capturas propias del Administrador ya distribuido. Mantener respaldos fuera del teléfono: estas copias locales protegen frente a un envío fallido, pero no frente a pérdida o daño del dispositivo.

## Validación

Pruebas automatizadas de plan de copia con PDF, paquete y foto original; nombres y bytes estables; fallo de escritura, falta de permiso y reintento al iniciar. Regresión de captura e interfaz, paquetes cifrados y núcleo de datos. CI compila Android. La ruta nativa usa MediaStore en Android 10+ y escritura con permiso en Android 7–9; validar permisos y visibilidad con la aplicación Archivos en un teléfono real.

Se distribuye APK de desarrollo. Antes de entregar, verificar la misma firma que Operador 1.0.2 para actualizar sin desinstalar.
