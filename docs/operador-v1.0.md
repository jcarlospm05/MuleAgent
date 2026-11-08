# MuleAgent Operador 1.0.1

APK instalable de prueba de campo, firmada para desarrollo. Android 7.0 (API 24) o posterior. No requiere cuenta ni conexión para capturar. El APK Administrador es una aplicación independiente y no forma parte de esta entrega.

## Cambios de interfaz en 1.0.1

Inicio con dos botones principales grandes: **Entrada de mulas** y **Despacho mulas**. Los accesos secundarios usan botones con borde, letrero e icono en todas las pantallas. El encabezado común incorpora el mismo logo M de la aplicación. Se conserva el acceso a los procesos pendientes y los registros existentes; el identificador interno de la etapa de despacho sigue siendo `exit`.

## Funciones

- Configuración guiada del nombre del operador y clave compartida, con confirmación. La clave queda en almacenamiento seguro de Android.
- Entrada y salida independientes, fecha operativa seleccionable, una pregunta por pantalla, guardado automático y recuperación de borradores.
- Cámara, galería, imagen original, ampliación para comprobar legibilidad, repetición u omisión expresa con motivo. Recuperación de imagen devuelta por Android después de interrumpir el proceso.
- Revisión y corrección; aviso ante un código de ficha ya registrado; bloqueo de cierre incompleto.
- Cierre inmutable con PDF (hasta dos fichas por página para conservar legibilidad) y paquete `.mule` cifrado con datos, originales, auditoría y PDF. Reintentar la preparación de archivos desde el cierre cuando una operación se interrumpe.
- Envío de ambos adjuntos por la hoja de compartir de Android: elegir WhatsApp y comprobar los dos adjuntos. Se registra apertura del flujo, nunca entrega supuesta.
- Historial de todas las revisiones, vista e impresión de PDF, exportación de fotos originales y reapertura en una revisión nueva.
- Respaldo `.mulebackup` cifrado de borradores, jornadas, auditoría, fotos y adjuntos exactos. Restauración con validación, sin sobrescribir registros locales distintos, y protección transaccional ante un conflicto.

## Actualización desde 1.0.0

La compilación 1.0.0 publicada no conservó su clave de firma: la caché apuntaba a un archivo que no existía. Android no acepta la 1.0.1 como actualización directa sobre esa instalación. Antes de desinstalar, guardar desde la app anterior un respaldo completo `.mulebackup` en Descargas o Drive, comprobar que existe y conservar la clave con la que se creó. Después instalar 1.0.1, configurar y restaurar el respaldo. No confundir el ZIP de instalación con el respaldo de registros.

La nueva compilación crea el archivo de firma antes de compilar, lo usa explícitamente en Gradle y lo conserva en la caché de CI. Las claves privadas quedan fuera del repositorio. La distribución productiva requiere custodiar una firma estable independiente de la caducidad de las cachés de desarrollo.

## Primer uso

1. Instalar el APK y abrir MuleAgent Operador. Android puede pedir habilitar la instalación desde el navegador o gestor de archivos utilizado.
2. Escribir el nombre y configurar una clave compartida de al menos 12 caracteres. Guardarla fuera del celular: sin ella no se descifran respaldos ni paquetes.
3. Registrar entrada o salida, comprobar la fecha y completar cada campo. Al volver atrás se conserva el contenido.
4. Confirmar la foto o registrar su omisión, revisar las fichas y cerrar. Compartir el PDF y `.mule` juntos; elegir WhatsApp en Android.
5. Guardar un respaldo en una ubicación elegida. Para restaurar, instalar la app en otro celular, configurarla, elegir Restaurar e introducir la clave del respaldo.

La clave local SQLCipher es aleatoria y distinta de la clave compartida. El nuevo celular genera su propio identificador; los orígenes históricos se conservan. Cambiar la clave compartida no modifica los archivos ya emitidos.

## Límites actuales y validación pendiente

Cada imagen admite hasta 20 MB y 40 megapíxeles; un conjunto exportado admite hasta 100 MB de archivos originales y 150 MB de contenido estructurado antes de cifrar. Si se excede, la operación falla con un mensaje y conserva los datos. Esta versión no ofrece todavía división automática de un respaldo grande. Conviene comprobar el volumen de una jornada real antes del uso continuo.

La firma de desarrollo se conserva mediante caché de CI mientras esté disponible. Antes de una distribución productiva y de actualizaciones a largo plazo se debe configurar y custodiar una firma de producción estable. No se incluyen claves privadas en el repositorio. Hacer respaldo antes de cambiar de instalación.

Las pruebas automáticas cubren persistencia, recuperación, validación, cierres, revisiones, restauración, cifrado autenticado, PDF y paquete diario. No sustituyen pruebas en un teléfono real de permisos, cámara, consumo de memoria, SQLCipher/Keystore, envío conjunto por WhatsApp y restauración desde una ubicación elegida. Esas pruebas físicas no se han realizado en este entorno.
