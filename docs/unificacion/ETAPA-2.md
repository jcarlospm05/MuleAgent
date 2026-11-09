# Etapa 2 — aplicación única y perfiles

Estado: completada, con 52 pruebas, análisis y compilación Android aprobados en CI. Base: checkpoint 1, 744f695a720652339a196366bc91120804c9b6a5. Rama refactor/mule-unificada.

## Estructura

- apps/muleagent/lib/main.dart: único arranque de la nueva aplicación.
- application/unified_shell.dart: carga/configuración del perfil y composición de módulos.
- application/unified_bundle.dart: única base de captura más tablas administrativas; mismas claves y rutas de la app Supervisor anterior.
- application/unified_capture_services.dart: mismo servicio de captura para ambos perfiles; respaldo/restauración según el contenido y las capacidades de la instalación.
- profiles/profile_setup_screen.dart: elección inicial explícita y confirmada.
- receiving/received_reports_screen.dart: frontera de recepción, sin rutas heredadas de Excel/cruces/auditoría.
- packages/mule_profiles: modelo y política sin dependencias de Flutter. Estado seguro separado de los respaldos.
- packages/mule_android: una sola implementación Kotlin para guardado público y recepción; las actividades son adaptadores de ciclo de vida.

Se reutilizan los módulos de captura y recepción existentes. Los directorios legacy no son nuevos APK a distribuir; permiten comprobar compatibilidad durante la transición y se terminarán de reorganizar al sustituir sus pantallas/servicios en etapas 3–5. No hay copia del recorrido de captura para cada rol.

## Reglas

La instalación configurada Supervisor no tiene cambio a Administrador. La instalación configurada Administrador conserva esa capacidad aunque su perfil activo sea Supervisor. Recibir reportes exige Administrador activo en el servicio, antes de abrir un selector, leer un archivo, descifrar o guardar registros. Un cambio de perfil se vuelve a comprobar incluso en instancias de servicio creadas antes del cambio.

Los errores de lectura del perfil fallan de forma cerrada; no reinician la elección. Las mutaciones de perfil se serializan para que dos pulsaciones no cambien la configuración inicial. Restaurar datos de SQLite no modifica capacidades guardadas en el almacenamiento seguro.

El perfil puede elegirse en la primera apertura de la aplicación unificada, también al actualizar desde una versión anterior que todavía no tenía esta configuración. La elección no borra los registros existentes. Si se migrará información administrativa, se debe elegir Administrador en esa configuración inicial.

## Conservación de datos

1. Identidad Android de actualización: com.muleagent.operador; nombre visible MuleAgent. SQLCipher sigue abriendo operador.db con local_database_key_v1 y device_id_v1. No se mueve ni se recifra automáticamente esa base.
2. Se añaden tablas administrativas en una transacción con versión de función independiente; se conservan filas, borradores y archivos. La tabla técnica de versiones no entra en respaldos.
3. La aplicación Administrador anterior usa otro sandbox Android. No se puede leer su base privada desde la nueva app: usar su respaldo cifrado e importarlo con la clave original. No desinstalar la app anterior antes de verificar la importación.
4. La restauración administrativa en la app nueva admite combinación: registros iguales se reutilizan; registros distintos con la misma identidad producen error y rollback. Las fotos y adjuntos existentes también se comparan por hash. Los nuevos archivos de un intento fallido se limpian sin borrar archivos preexistentes.
5. Se conservan archivos, vínculos y eventos históricos aunque las pantallas de Excel/cruces no formen parte del arranque nuevo. Su presencia en un respaldo antiguo no habilita funciones ni perfiles.
6. Respaldos recibidos o ajustes SQLite no pueden ascender una instalación Supervisor. Los archivos .mule diarios no se confunden con respaldos completos.

## Android y compilación

Una única compilación funcional: apps/muleagent. El manifest combina los permisos de guardado de Android 7–9 y las asociaciones VIEW/SEND/SEND_MULTIPLE ya implementadas. La actividad compone ambos canales compartidos. Android 10+ conserva MediaStore sin permiso general de archivos.

La compilación de CI de esta etapa es de integración y no una APK para actualizar el teléfono. La caché de firma está vinculada a la rama histórica de distribución: al entregar en etapa 6, usar la identidad de firma de Operador 1.0.3 y comprobar el certificado. No generar una firma nueva silenciosamente para una actualización.

## Límite de la etapa

No aplica todavía Estilo Mule a las pantallas, no sustituye el logo, no cambia el contrato a JPG, no agrega importación de imágenes ni reglas de consolidación. Estas decisiones siguen aprobadas en MASTER.md y ESTILO-MULE.md; su ejecución pertenece a las siguientes etapas.

## Verificación requerida

Política de perfiles y errores de almacenamiento; elección inicial/reinicio; alternancia de Administrador y conservación de borrador; bloqueo directo de recepción; migración de esquema con datos; importación combinada de respaldo administrativo, reimportación y conflicto; rechazo de escalada por respaldo; regresión de ambas apps previas y compilación nativa del punto de entrada único.


## Cierre y reanudación

Código verificado: 73dc6d1845409913e079999ca059a3cac0bc3ab8.
Ejecución aprobada: https://github.com/jcarlospm05/MuleAgent/actions/runs/42649490843
52 pruebas: perfiles 6, núcleo 12, repositorio administrativo 11, captura/archivos 12, receptor previo 3 y aplicación unificada 8. El build Android único terminó correctamente. No se publicó una APK de actualización de campo.

Siguiente: etapa 3, Estilo Mule y captura, manteniendo el mismo punto de entrada y la política de perfiles. Usar la paleta y referencia ya aprobadas; no rediseñarlas. La instalación/actualización física, cámara, selectores y WhatsApp se verificarán en la entrega final.
