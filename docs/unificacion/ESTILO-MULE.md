# Estilo Mule

Nombre corto aprobado: **Estilo Mule**. Esta es la referencia visual para toda la aplicación unificada, Supervisor y Administrador. Imagen aprobada: propuesta flat con cuatro pantallas (inicio claro, inicio oscuro, hora separada y revisión administrativa), generada en la conversación el 9 de noviembre de 2026.

Referencia visual conservada en Drive: https://drive.google.com/file/d/1pIABDT7b3el-3hKXaHNkArPyFgRky44N/view

## Prompt reutilizable

Diseña MuleAgent con Estilo Mule: una interfaz flat, limpia y legible para trabajo de campo. Usa superficies sólidas, esquinas moderadamente redondeadas, bordes finos, separadores discretos y sombras mínimas. Conserva una tarea principal por pantalla. No introducir brillo, biseles, apariencia inflada ni degradados notorios. Usa Roboto y espacios amplios. No añadir dashboards, gráficos ni navegación decorativa.

### Paleta y roles

| Token | Valor | Uso |
| --- | --- | --- |
| navy | #0B132B | Fondo oscuro; texto y acción principal claros |
| deepBlue | #1C2541 | Superficies oscuras |
| mutedBlue | #3A506B | Elementos secundarios |
| cyan | #5BC0DE | Acción principal oscura, foco y progreso |
| cream | #F4D6B0 | Acento moderado |
| orange | #D97706 | Salida de mula |
| lightBackground | #F8F6F3 | Fondo claro cálido |
| lightSurface | #FFFFFF | Superficie clara |
| lightSecondaryText | #596273 | Texto secundario claro |
| lightBorder | #D7DADF | Separadores claros |
| darkText | #F5F5F2 | Texto principal sobre oscuro |
| darkSecondaryText | #BBC5D3 | Texto secundario oscuro |
| darkBorder | #41516A | Bordes oscuros |
| pending | #E53935 | Punto rojo de tarea pendiente, sin números |
| successLightBackground | #E0EBDC | Aviso de guardado claro |
| successLightText | #355C43 | Texto de guardado claro |
| successDarkBackground | #213C34 | Aviso de guardado oscuro |
| successDarkText | #B7D6BF | Texto de guardado oscuro |

En claro: acción principal azul noche con texto blanco. En oscuro: acción principal celeste con texto azul noche. Salida siempre naranja; texto blanco grande y negrita como la referencia, comprobando contraste en los tamaños usados. No usar naranja como fondo de texto blanco pequeño. Estados comunicados también con palabras/iconos, no solo color.

### Medidas y tipografía

- Márgenes laterales 20–24; sistema de espaciado múltiplo de 8.
- Separación normal 12–16; entre botones principales y menú secundario 32–40.
- Radio principal 16; tarjetas/campos 12–16; bordes de aproximadamente 1.
- Acción principal: ancho completo, altura mínima 72, texto 20–22 negrita.
- Opciones secundarias: filas visualmente ligeras, icono lineal, separador fino y área táctil mínima 48. No una columna de grandes cápsulas con borde.
- Nombre MuleAgent 24; título 28–30; sección 20–22; cuerpo 16–18; auxiliar 13–14; hora/minutos 36–40.
- Roboto, escalado del sistema y adaptación a pantallas pequeñas. Preferir etiquetas breves de una línea; no recortar ni reducir excesivamente texto ampliado.

### Disposición

Encabezado compacto: logo a la izquierda, MuleAgent al lado, perfil debajo y luna/sol a la derecha. Mismo orden y geometría en ambos temas. Persistir elección del tema.

Inicio: encabezado, aviso discreto de proceso abierto con línea celeste, Entrada/Continuar entrada grande, Salida de mula naranja grande, separación amplia y filas secundarias. Punto rojo superior derecho solo en tareas pendientes. Sin estado de envío pendiente.

Captura: Atrás, etapa/paso, progreso fino, título, ayuda breve, campo grande y Siguiente. Hora/Minutos separados con dos puntos fuera de los campos, teclado numérico y botón visible sobre el teclado. Mantener foco al avanzar entre campos editables.

Ficha: miniatura legible del horómetro con ampliación al tocar; en detalle dar mayor espacio a la foto, sin cortar los números. Datos jerarquizados. Administrador: origen, selección y ficha excluida atenuada con etiqueta y Volver a incluir.

Avisos: guardado breve, pequeño y verde apagado, por ejemplo “Guardado en Descargas/MuleAgent”. Errores separados, con explicación y recuperación; no rutas extensas ni trazas técnicas en la confirmación principal.

### Logo

Tractor de patio (mule truck) de la foto aprobada, vista de tres cuartos, cabina blanca, cristales y chasis oscuros, baliza naranja, sin remolque ni marca del fabricante. Caricatura realista con formas limpias y acabado vectorial, reconocible a tamaño pequeño. El SVG final todavía debe crearse; las imágenes de propuesta no son un recurso vectorial listo para la app.

## Aplicación en código

Tokens preparados en apps/operador/lib/design/mule_tokens.dart. En la etapa 1 no se conectan a las pantallas existentes: la aplicación de temas y componentes pertenece a la etapa 3. Las medidas son parámetros de implementación, no una medición exacta del mockup.
