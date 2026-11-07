# Base aprobada

El prototipo fija el diseño, el flujo y el comportamiento visible. La siguiente definición fija el alcance funcional que el prototipo representa.

## Diseño

| Elemento | Referencia |
| --- | --- |
| Fondo blanco cálido | `#FFFDF8` |
| Botón principal azul noche | `#21355E` |
| Texto | `#182237` |
| Acento LED ámbar | `#FFC45B` |
| Confirmación | Verde suave `#EBF8F0` y un check con texto |
| Error | Rosa suave `#FFF1F3`, borde rojo y mensaje concreto |

Inicio con un botón grande centrado. En captura, una pregunta y una acción principal por pantalla. Conservar texto grande, espacio en blanco y una posición consistente para **Siguiente**. La pantalla saliente se desliza mientras entra la siguiente. **Atrás** invierte el sentido. El borde del horómetro se ilumina una vuelta. La cámara se expande hacia el visor cuadrado. Al guardar aparece un check con un pulso breve. Respetar la preferencia de movimiento reducido.

## Flujo del operador

1. Abrir la app y tocar **Iniciar día** o **Continuar proceso**. Recuperar el paso y el borrador si se interrumpió la captura.
2. Elegir **Registrar entrada** o **Registrar salida**. Son jornadas independientes y pueden registrarse en distintos celulares.
3. Agregar una mula. Para entrada, pedir nombre del mulero, ficha, proveedor, hora, lectura del horómetro y foto. Para salida, pedir ficha, proveedor, hora de salida, lectura final y foto. Cada dato ocupa su propia pantalla.
4. En la foto, encuadrar el tablero completo. Permitir tomar, repetir o cargar una foto guardada, o registrar una omisión expresa. Bloquear el envío si queda una ficha incompleta o una foto pendiente sin omisión registrada.
5. Agregar otra mula o tocar **Ya no hay más mulas**. Mostrar el total y todas las fichas. Permitir corregirlas antes de cerrar la etapa y abrir la vista del PDF.
6. Cerrar el inicio o el cierre. Conservar una copia del reporte y permitir enviar el PDF y el SQLite cifrado juntos mediante WhatsApp. El PDF presenta hasta tres conduces por página según la legibilidad de las fotos.
7. Permitir continuar la jornada si llega otra mula. Si ya se compartió, conservar el envío anterior y generar una revisión diferenciada. El historial permite ver, recuperar o reenviar cada versión cerrada.

## Modelo conceptual

| Entidad | Datos principales |
| --- | --- |
| Reporte de etapa | ID estable, fecha operativa, entrada o salida, equipo emisor, estado y revisión. |
| Ficha | ID propio, ID del reporte, código tal como se capturó, proveedor, mulero en entrada, hora y lectura del horómetro. |
| Evidencia | Ficha asociada, imagen original o estado de omisión, nombre de archivo y origen de la imagen. |
| Vínculo manual | ID de ficha de entrada, ID de ficha de salida y registro del administrador que lo creó. Se conserva aparte de los originales. |
| Evento de auditoría | ID, fecha y hora, operador, equipo, acción y referencia al reporte o ficha cuando corresponda. |

## Archivos y recuperación

- Los celulares operan con almacenamiento local. La transferencia del reporte se hace mediante archivos.
- La carpeta local visible conserva el PDF exacto que se compartió, el SQLite cifrado y las fotos recuperables por separado. Ejemplo de nombre de foto: `DEMO362 7-11-26 inicio.jpg`.
- El envío diario incluye el reporte, las fotos originales y sus eventos de auditoría dentro del SQLite cifrado. El PDF es el otro adjunto. El registro de actividad se incorpora al archivo como parte del flujo.
- El respaldo completo del operador incluye reportes, borradores, historial de auditoría y copias comprimidas de las fotos. Permite restaurar en otro celular configurado con la misma clave. La reconstrucción de PDF en la restauración queda como decisión de implementación.
- La clave compartida se introduce en la configuración inicial. La copia local queda cifrada, fuera de SQLite, con protección de Android Keystore. La clave queda fuera del código y de los archivos transferidos.
- Los conduces en papel y el proceso de gastos y facturas siguen el formato de la empresa.
