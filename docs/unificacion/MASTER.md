# MuleAgent unificada — documento maestro

Estado: acuerdos aprobados; implementación por etapas. Este documento y ESTILO-MULE.md son la referencia del proyecto. No confundir decisiones de producto con funciones ya entregadas.

## Base y forma de trabajo

- Base Supervisor: Operador 1.0.3, commit a4573e7830004ffe79379ecfa9899200fe26654f.
- Base Administrador: 1.0.1, commit 6eb02430d86014d09844d972a1cd04ea8ce556a3.
- La nueva app se llama MuleAgent. Operador pasa a llamarse Supervisor.
- Una sola aplicación y un único recorrido compartido de captura, fichas, guardado y envío.
- Trabajar en cambios pequeños, verificables y guardados en GitHub; actualizar este documento en cada etapa. No recompilar/publicar APK por una separación interna de código sin cambios nativos.
- Conservar datos, originales, contratos antiguos y una vía de actualización/importación desde las dos instalaciones existentes. No borrar reportes para acomodar el nuevo diseño.

## Perfiles y capacidades

| Configuración inicial | Perfiles permitidos después |
| --- | --- |
| Supervisor | Solo Supervisor; no puede ascender desde la interfaz |
| Administrador | Puede alternar Administrador/Supervisor y regresar cuando necesite |

Distinguir la capacidad de la instalación del perfil activo. Cambiar de perfil no elimina datos. El control se aplica también a las operaciones de recepción, no solamente a la visibilidad del botón. La configuración inicial ocurre en la primera apertura, no durante el instalador Android.

## Funciones compartidas

1. Registrar entradas y salidas con el mismo recorrido para ambos perfiles.
2. Entrada abierta: botón Continuar entrada y aviso discreto “Entrada en proceso. Continúa para agregar mulas o cerrar”. Abrir el proceso existente; no crear otro por error. Salida abierta: comportamiento equivalente.
3. Salida de mula en naranja, icono de salida, sin camión genérico en ese botón.
4. Dos botones principales grandes. Opciones secundarias menores y separadas, como filas ligeras con icono y separadores. Una acción dominante en las demás pantallas.
5. Solo puntos rojos, sin números, para tareas reales: continuar/cerrar, datos incompletos, fallos de guardado. No hay estado pendiente de envío, contador de mensajes ni confirmación obligatoria al volver de WhatsApp.
6. Hora y minutos en dos campos numéricos; guardar un valor HH:mm válido. Siguiente mueve el foco manteniendo el teclado durante la escritura. La acción principal queda visible por encima del teclado. Cambiar a foto/confirmación permite cerrar el teclado.
7. Miniatura legible del horómetro en la ficha; tocar para ampliar. Conservar originales sin recomprimir.
8. Cierre: guardar automáticamente una ficha JPG por mula, las fotos originales y el paquete .mule en Descargas/MuleAgent, organizado por fecha, inicio/salida y revisión. Nombres legibles con fecha y hora. Verificar archivos antes de informar éxito; recuperar fallos y cierres interrumpidos.
9. Un solo botón de envío: adjuntar todos los JPG de fichas junto con el .mule. Reenviar desde historial las veces necesarias. No crear un botón separado para enviar al Administrador. Comprobar la presentación de adjuntos mixtos en WhatsApp en Android.
10. No generar PDF en el cierre/captura del Supervisor ni en ese recorrido compartido del Administrador. Los nuevos respaldos se basarán en imágenes y .mule; compatibilidad de lectura con archivos históricos.
11. Quitar botones redundantes Guardar copia y Guardar PDF del cierre; mantener recuperación en el módulo de archivos cuando exista un fallo.
12. Guardado: texto breve, pequeño y verde apagado. Evitar rutas extensas y mensajes técnicos en la confirmación principal.
13. Claro/oscuro con elección persistente; usar Estilo Mule.

## Funciones adicionales del Administrador: alcance cerrado

Solo recepción/consolidación y reportes incompletos. Retirar cruces manuales y Excel de la interfaz nueva. Auditoría/paneles adicionales quedan para más adelante; conservar registros internos necesarios para integridad y exclusiones.

### Recepción

- Elegir etapa Entrada/Salida, fecha de jornada y fuente .mule o varias imágenes.
- La fecha elegida es la de trabajo, independiente de la recepción. Una salida recibida mañana puede completar una jornada anterior.
- Admitir varios supervisores y varios reportes por fecha/etapa. Agregar, no reemplazar.
- Para .mule, reconocer reporte, origen y revisiones sin duplicar reenvíos. Mostrar discrepancia de fecha/etapa antes de consolidar; no alterar el original importado.
- Para JPG generados por MuleAgent: una ficha por mula. Detectar archivos idénticos. Diseñar identificación de ficha para detectar también .mule + JPG del mismo origen; no asumir que WhatsApp conservará metadatos.
- Imágenes externas sin identidad fiable: revisión del usuario. No prometer identificación automática por apariencia ni eliminar fichas por compartir número.
- Mantener etapa, fecha asignada, origen y pertenencia a jornada separadas del documento original.

### Consolidación y duplicados

- Visualizar miniatura, datos disponibles y supervisor de origen.
- Seleccionar una o varias fichas y excluirlas del consolidado tras confirmar.
- No borrar el documento recibido: conservar original, motivo/registro de exclusión y opción Volver a incluir.
- Excluidas no cuentan y no aparecen en PDF nuevo. Corregir cantidades y avisos al incluir/excluir.
- Generar PDF de entrada y PDF de salida por separado a partir de fichas incluidas, tanto importadas de .mule como de imágenes. Poder regenerar al agregar reportes o cambiar exclusiones.
- Los PDF son una función explícita del Administrador sobre reportes importados; no vuelven al envío compartido del Supervisor.

### Reportes incompletos

- Falta entrada.
- Falta salida.
- Cantidades distintas entre entrada/salida, sumando fichas incluidas de todos los supervisores.
- Con ambas etapas y cantidades iguales, retirar de incompletos. Igualdad de cantidades no certifica identidad de las mulas: no hay cruces en esta versión.

## Separación prevista

| Módulo | Responsabilidad |
| --- | --- |
| Perfiles | Configuración inicial, capacidades, perfil activo y cambio autorizado |
| Inicio | Procesos abiertos, mensajes y puntos rojos |
| Captura | Campos, validación, foco, teclado y borradores |
| Evidencia | Cámara/galería, originales y miniaturas |
| Fichas JPG | Representación por mula e identidad de ficha |
| Paquetes | Contrato .mule, cifrado y compatibilidad |
| Almacenamiento | Rutas privadas, guardado público, integridad y recuperación |
| Envío | Preparar adjuntos, abrir compartir y reenviar |
| Recepción | Importar .mule/JPG y clasificar jornada sin alterar fuente |
| Consolidación | Fichas incluidas/excluidas y cantidades |
| PDF administrativo | PDF separado de entrada/salida |
| Historial y respaldos | Consulta, reenvíos, recuperación y portabilidad |
| Diseño | Tokens Estilo Mule, temas y componentes compartidos |

Evitar que un módulo de interfaz escriba archivos o que un módulo de almacenamiento decida perfiles. No sustituir clases grandes por un único archivo de extensiones con el mismo acoplamiento.

## Entregas y estado

1. **Separación inicial y acuerdos**: extraer rutas/escritura privada, manifiestos de adjuntos y funciones de cifrado; preparar tokens de diseño sin aplicarlos. Verificar recorridos existentes. Estado: completada y verificada localmente (12 pruebas de captura/almacenamiento y 3 de interoperabilidad/interfaz del receptor; ambos análisis sin incidencias).
2. **Una app y perfiles**: punto de entrada único, capacidades, migraciones y composición de módulos compartidos. No borrar la vía de migración desde Administrador existente.
3. **Estilo Mule y captura**: temas, componentes, inicio contextual, hora/minutos, teclado y evidencia visible.
4. **JPG + .mule**: generador de fichas, contratos/migraciones, adjuntos únicos, guardado automático y respaldos sin nuevos PDF del recorrido de captura.
5. **Administrador simplificado**: recepción múltiple por fecha/etapa, consolidación, exclusión reversible y PDF administrativo; retirar Excel/cruces de las rutas visibles.
6. **Verificación y entrega**: actualizaciones con datos existentes, compatibilidad, Android/WhatsApp/archivos, firmas y APK única en ZIP.

Cada etapa tendrá su propio cambio y resumen. Una etapa técnica aprobada no equivale a la app unificada terminada. La versión distribuida permanece 1.0.3 hasta producir una entrega funcional nueva.

## Próximo punto de reanudación

Al terminar la etapa 1: usar su commit como base, comenzar etapa 2 y leer ambos documentos antes de editar. No reabrir decisiones ya aprobadas. Resolver elecciones técnicas ordinarias sin pedir confirmaciones de nuevo.


## Checkpoint 1: estructura real

- apps/operador/lib/storage/private_file_store.dart: rutas privadas y escritura atómica.
- apps/operador/lib/storage/payload_files.dart: colección de adjuntos, huellas y límite de tamaño del contrato vigente.
- apps/operador/lib/security/package_crypto.dart: funciones de cifrado/descifrado utilizables desde isolates.
- apps/operador/lib/design/mule_tokens.dart: paleta, medidas y escala tipográfica aprobadas; no aplicadas todavía.
- apps/operador/lib/services.dart conserva una fachada compatible, delega en los módulos anteriores y reexporta los puntos de entrada criptográficos para no romper los consumidores actuales.
- .github/workflows/mule-unificada.yml verifica ambos recorridos y sus paquetes de datos, sin generar/publicar APK en cada checkpoint interno. Las compilaciones antiguas se omiten para el PR de esta rama.
- Rama de trabajo: refactor/mule-unificada. Base de integración: Administrador 1.0.1 + guardado automático del Operador 1.0.3. Las ramas distribuidas se conservan.

Pendiente al reanudar: etapa 2. No presentar estos cambios internos como la nueva interfaz o como la APK unificada terminada.
