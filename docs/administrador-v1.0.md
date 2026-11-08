# MuleAgent Administrador 1.0.0

Aplicación Android independiente, compatible con el paquete `.mule` del Operador 1.0.1. Android 7.0 (API 24) o posterior. Identificador `com.muleagent.administrador`, almacenamiento SQLCipher y claves Keystore propios. Se puede instalar junto al Operador.

## Primer uso

1. Instalar la APK del ZIP, abrir Administrador y configurar nombre y clave. Usar la misma clave compartida que en el Operador.
2. Descargar desde WhatsApp el archivo `.mule` recibido. Abrir Recibir reporte → Elegir archivo e importar. El PDF por sí solo no contiene los datos necesarios. Si el archivo utiliza otra clave, introducirla en esa pantalla.
3. Ver jornadas → elegir fecha. Consultar entradas y despachos con sus fotos, origen y revisión. Los originales recibidos son de solo lectura.
4. En Cruce manual, seleccionar entrada y despacho y confirmar. Los códigos originales pueden ser diferentes. Quitar un vínculo conserva su historial de auditoría. Se permiten fichas sin vincular.
5. Exportar PDF de etapa o jornada, vínculos y pendientes, Excel con miniaturas de fotos incorporadas y ZIP de fotos JPG. El PDF original recibido sigue accesible en Reportes y revisiones. Guardar foto original conserva sus bytes; exportar JPG crea una copia y no modifica el original.
6. Captura propia abre el mismo recorrido guiado del Operador, con evidencia, cierre, PDF y envío. Al regresar, los cierres propios se incorporan a la jornada con su origen diferenciado. Los borradores permanecen en ese módulo hasta completarlos.
7. Auditoría permite filtrar por fecha, operador, equipo y acción y exportar Excel. La vista pagina en grupos de 100 eventos; la exportación incluye todos los resultados del filtro.
8. Respaldo y restauración guarda reportes recibidos, capturas propias, vínculos, auditoría, fotos y adjuntos en un respaldo cifrado. Restaurar en una instalación sin jornadas con la clave del respaldo. Los registros actuales no se sobrescriben.

## Integridad

Los reenvíos no duplican fichas ni eventos. Las revisiones se identifican por reporte, número e ID; si el mismo identificador llega con otro contenido se rechaza y se conserva el original. La versión vigente es la de mayor número, incluso si llega una versión antigua después. Las versiones anteriores permanecen disponibles.

Importar otra revisión no modifica los vínculos existentes: los señala como pendientes de revisar. Para actualizarlos se quita el vínculo anterior y se confirma uno nuevo. Entrada y despacho deben ser de la misma fecha. Una ficha solo participa en un vínculo activo por reporte e identidad lógica.

La importación verifica AES-GCM, formato, versiones, referencias, fotos y PDF por SHA-256 antes de incorporar registros. Guarda originales antes de una transacción SQLite y limpia las nuevas copias ante un fallo. Las tablas de originales y auditoría tienen triggers que bloquean edición y borrado.

La clave compartida nunca se guarda en SQLite ni en paquetes sin cifrar. Un cambio de clave no modifica archivos anteriores. La auditoría identifica el origen declarado por los dispositivos; una clave común no equivale a una firma individual verificable.

## Validación y límites

Pruebas de repositorio: reenvíos, eventos nuevos, versiones fuera de orden, conflictos, inmutabilidad, cruces, vínculos afectados por revisiones y respaldo/restauración. Pruebas de interoperabilidad: generar un archivo cifrado con el código real del Operador, importarlo, conservar originales, exportar PDF y Excel con imágenes y restaurar sus archivos en otro almacén. Las pruebas de interfaz cubren menú y captura propia. CI también verifica las pruebas previas del Operador.

Las pruebas automáticas no sustituyen una prueba en Android real de instalación conjunta, permisos, cámara, selector de archivos, impresión, WhatsApp y restauración. Esta entrega es una APK firmada para desarrollo. La clave de firma se crea explícitamente y se conserva mediante caché de CI; la distribución productiva requiere una firma estable custodiada fuera de esa caché.

Se conservan los límites del intercambio del Operador: hasta 1.000 fichas por paquete, 20 MB por foto y 100 MB de archivos por conjunto exportado, con 150 MB de contenido estructurado antes de cifrar. Los respaldos grandes no se dividen automáticamente. Conservar paquetes originales y respaldos fuera del celular.

La recepción se inicia desde el selector de archivos de la aplicación. Esta versión no registra una asociación automática del tipo `.mule` en la hoja Abrir con de Android.
