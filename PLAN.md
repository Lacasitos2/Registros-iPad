# Plan de desarrollo - Registros iPad

## Objetivo

Crear una app nativa de iPad para registrar datos de alumnos de forma rapida durante la clase: deberes, intervenciones en pizarra, conducta, participacion, observaciones e informes exportables.

La prioridad es que sea comoda con el iPad en la mano, caminando por el aula, con pocos toques y sin obligar a escribir salvo cuando sea necesario.

## Fase 1: Registro rapido de clase

**Objetivo:** que la app pueda usarse caminando por el aula.

- Vista de grupo optimizada para iPad horizontal.
- Botones grandes para deberes: hecho, parcial, no hecho.
- Modo secuencial "pasar por pupitres".
- Deshacer ultimo marcado.
- Contadores visibles de la sesion.
- Guardado automatico.

**Resultado esperado:** registrar los deberes de una clase completa sin entrar alumno por alumno.

## Fase 2: Importacion de grupos

**Objetivo:** cargar grupos reales sin escribir los alumnos manualmente.

- Importar CSV desde Archivos.
- Valorar importacion directa de Excel `.xlsx`.
- Detectar columnas: nombre, apellidos, grupo.
- Previsualizar antes de guardar.
- Editar o borrar alumnos.
- Reordenar alumnos segun lista oficial o distribucion del aula.

**Resultado esperado:** crear varios grupos reales desde listas existentes.

## Fase 3: Registros configurables

**Objetivo:** ampliar la app mas alla de los deberes.

- Tipos de registro:
  - deberes
  - pizarra
  - conducta
  - participacion
  - material
  - observacion
- Valores rapidos configurables.
- Positivos y negativos.
- Nota numerica de pizarra.
- Comentarios rapidos reutilizables.

**Resultado esperado:** registrar lo importante de una sesion con pocos toques.

## Fase 4: Ficha del alumno

**Objetivo:** consultar rapidamente el historial util de cada alumno.

- Historial cronologico.
- Resumen por categorias.
- Porcentaje de deberes hechos.
- Ultimas observaciones.
- Incidencias acumuladas.
- Evolucion de notas de pizarra.
- Filtros por trimestre o rango de fechas.

**Resultado esperado:** al tocar un alumno, ver de un vistazo como va.

## Fase 5: Informes y exportacion

**Estado:** realizada.

**Objetivo:** sacar los datos de forma limpia.

- Exportar CSV por grupo. **Realizado.**
- Exportar CSV por alumno. **Realizado.**
- Exportar por rango de fechas. **Realizado en exportaciones filtradas.**
- Exportar resumen de deberes. **Realizado.**
- Exportar incidencias y observaciones. **Realizado.**
- PDF sencillo por alumno o grupo. **Realizado.**
- Compartir por AirDrop, Mail, Drive, etc.

**Resultado esperado:** poder llevar los datos a Excel, Numbers u otras plataformas.

## Fase 6: Ergonomia de aula

**Estado:** realizada.

**Objetivo:** hacer que la app se sienta como una herramienta de profesor, no como una base de datos.

- Modo claro y oscuro cuidado. **Realizado.**
- Tamanos grandes para usar de pie. **Realizado.**
- Vista compacta y vista amplia. **Realizado.**
- Decidir si las tarjetas de alumno deben ser minimalistas, mostrar toda la informacion o permitir elegir entre ambos modos. **Realizado: selector compacta/completa.**
- Filtros rapidos: pendientes, no hechos, incidencias. **Realizado.**
- Busqueda de alumno. **Realizado.**
- Orden personalizado de grupos. **Realizado.**
- Confirmaciones minimas. **Realizado.**
- Gestos utiles. **Realizado.**

**Resultado esperado:** una experiencia rapida, clara y agradable durante la clase.

## Fase 7: Robustez y seguridad de datos

**Objetivo:** poder confiar en la app.

- Copia de seguridad manual.
- Restaurar desde archivo.
- Exportar todos los datos.
- Evitar perdida accidental de grupos.
- Tests de modelo y exportacion.
- Migraciones de datos si cambia la estructura.
- Valorar sincronizacion con iCloud mas adelante.

**Resultado esperado:** usar la app sin miedo a perder registros.

## Prioridad inicial

Empezar por la Fase 1 y parte de la Fase 2:

1. Mejorar la experiencia de registro rapido.
2. Anadir modo secuencial para pasar por pupitres.
3. Permitir importar grupos reales desde archivo CSV.
4. Mantener exportacion simple pero fiable.

Con eso la app deberia pasar de prototipo compilable a herramienta util en una clase real.

## Estado de fases iniciales

### Fase 1: Registro rapido de clase

**Estado:** realizada.

Ya permite usar la app caminando por el aula: ver el grupo completo, marcar deberes rapidamente, usar el modo secuencial "Pupitres", deshacer la ultima marca, ver contadores de sesion y guardar automaticamente.

Queda solo como mejora futura:

- Pulir ergonomia visual tras probarla en iPad real.
- Valorar filtros rapidos como pendientes o no marcados, aunque encajan mejor en la Fase 6.

### Fase 2: Importacion de grupos

**Estado:** realizada.

Ya permite importar grupos desde Excel `.xlsx`, CSV o texto, previsualizar alumnos antes de crear el grupo y ajustar despues la lista desde la app: anadir, editar, borrar y reordenar alumnos.

Queda solo como mejora futura:

- Probar con varios Excel reales de notas para pulir casos raros de cabeceras o formatos.
- Valorar si conviene guardar una plantilla de importacion por tipo de archivo.

### Fase 3: Registros configurables

**Estado:** realizada.

Ya se ha ampliado el registro diario mas alla de los deberes con acciones rapidas de participacion, material, pizarra y conducta desde la tarjeta del alumno. Tambien permite observaciones escritas y comentarios rapidos reutilizables y editables.

Queda solo como mejora futura:

- Anadir otros tipos frecuentes de aula si aparecen durante el uso real.

### Fase 4: Ficha del alumno

**Estado:** realizada.

Ya existe una ficha del alumno con edicion del registro diario, resumen por categorias, historial cronologico escaneable y filtros por todo el historial, ultimos 30 dias, trimestre o rango de fechas.

Queda solo como mejora futura:

- Ajustar los periodos de trimestre si se quiere reflejar exactamente el calendario del centro.
- Valorar graficas sencillas de evolucion para notas de pizarra y deberes.

## Avances

### 2026-06-08

- Agregada pantalla de modo secuencial "Pupitres" para marcar deberes alumno por alumno.
- Agregados botones grandes de hecho, parcial y no hecho con avance automatico.
- Agregada navegacion anterior/siguiente dentro del modo secuencial.
- Agregado boton de deshacer ultima marca de deberes.
- Verificada compilacion de Swift con `xcodebuild` y `CODE_SIGNING_ALLOWED=NO`.
- Agregada importacion desde archivos Excel `.xlsx` usando la primera hoja.
- Mantenida importacion CSV/texto como respaldo.
- Agregada previsualizacion de alumnos detectados antes de crear el grupo.

### 2026-06-09

- Agregada gestion de alumnos dentro de cada grupo: anadir, editar, borrar y reordenar.
- Mejorada la importacion de listas con deteccion de columnas de nombre, apellidos y grupo.
- Permitida la creacion de varios grupos desde un mismo CSV o Excel cuando existe una columna de grupo.
- Agregada previsualizacion por grupo con conteo de alumnos y avisos de filas dudosas o duplicados.
- Agregada seleccion manual de columnas en Excel para numero de lista y nombre, usando el numero para ordenar alumnos.
- Agregada opcion al importar Excel para unir todos los alumnos en un solo grupo o separarlos por la clase detectada.
- Guardado el numero de lista como dato opcional del alumno y anadido a la exportacion CSV actual.
- Agregada seleccion de hoja al importar Excel con varias hojas.
- Mejorados los avisos de importacion para columnas incompletas, hoja vacia, numeros de lista vacios o repetidos y columnas mal elegidas.
- Permitida la edicion manual del numero de lista junto al nombre del alumno.
- Agregado borrado explicito de alumnos con confirmacion desde la gestion del grupo.
- Agregada busqueda rapida de alumnos por nombre o numero de lista en la vista del grupo.
- Marcadas como realizadas las fases 1 y 2 del plan.
- Iniciada la fase 3 con botones rapidos de participacion, pizarra y conducta en cada alumno.
- Anadida la participacion a la ficha del alumno, al historial y a la exportacion CSV.
- Ajustada la participacion como marca unica que se pone o se quita, y aclarado el boton de pizarra mostrando la nota actual.
- Anadida marca rapida de material en la tarjeta, ficha, historial y exportacion CSV.
- Anadidos comentarios rapidos reutilizables en la ficha del alumno.
- Evitado que un comentario rapido se duplique si se toca varias veces.
- Anadido el aviso como conducta rapida visible en la tarjeta del alumno.
- Permitido anadir y borrar plantillas de comentarios rapidos desde la ficha del alumno.
- Anotada para fases finales la decision de diseno sobre tarjetas minimalistas frente a tarjetas con toda la informacion.
- Marcada como realizada la fase 3 de registros configurables.
- Iniciada la fase 4 con resumen del alumno en su ficha: deberes, pizarra, participacion, material, conducta y ultima observacion.

### 2026-06-15

- Anadidos filtros temporales en la ficha del alumno: todo, ultimos 30 dias, trimestre y rango personalizado.
- Hecho que el resumen de la ficha responda al periodo seleccionado.
- Mejorado el historial del alumno con filas mas escaneables y etiquetas compactas para deberes, pizarra, participacion, material y conducta.
- Anadido estado vacio cuando no hay registros en el periodo seleccionado.
- Marcada como realizada la fase 4 de ficha del alumno.
- Iniciada la fase 5 con exportacion CSV por alumno desde su ficha.
- La exportacion por alumno respeta el periodo seleccionado en la ficha y comparte el archivo mediante la hoja nativa de iPadOS.
- Anadida exportacion CSV de resumen de deberes por grupo.
- El resumen de deberes permite elegir todo, ultimos 30 dias, trimestre o rango personalizado antes de compartirlo.
- Anadida exportacion CSV de incidencias y observaciones por grupo.
- La exportacion de incidencias usa el mismo selector de periodo y lista solo registros con conducta marcada u observacion escrita.
- Anadida exportacion PDF por alumno desde la ficha.
- El PDF por alumno respeta el periodo seleccionado e incluye resumen, historial y observaciones.
- Anadida exportacion PDF por grupo.
- El PDF por grupo respeta el periodo seleccionado e incluye resumen por alumno y cronologia de registros.
- Anadida exportacion PDF de informes individuales de todo el grupo en un unico archivo.
- El PDF de informes individuales genera una seccion por alumno con el mismo estilo de informe que la ficha individual.
- Anadido el periodo de referencia en los PDFs de alumno, grupo e informes individuales.
- Marcada como realizada la fase 5 de informes y exportacion.

### 2026-06-16

- Iniciada la fase 6 de ergonomia de aula.
- Anadidos filtros rapidos en la vista del grupo: todos, pendientes, no hechos e incidencias.
- Combinada la busqueda de alumno con los filtros rapidos.
- Anadido selector de vista compacta o completa para las tarjetas de alumnos.
- La vista compacta conserva el marcado rapido de deberes y reduce la altura de las tarjetas para ver mas alumnos a la vez.
- Mejorada la cabecera de clase con fecha visible de la sesion, metricas rapidas y controles adaptables.
- Anadidos contadores destacados de pendientes, no hechos e incidencias para revisar la sesion de un vistazo.
- Permitido renombrar grupos desde la lista lateral.
- Permitido reordenar grupos desde la lista lateral con el modo de edicion.
- Pulido el aspecto de la pantalla de clase con fondos de sistema adaptados a modo claro y oscuro.
- Reforzada la legibilidad de la cabecera, tarjetas de alumno y modo pupitres con superficies y bordes consistentes.
- Marcada como realizada la fase 6 de ergonomia de aula.
- Verificada compilacion de Swift con `xcodebuild` y `CODE_SIGNING_ALLOWED=NO`.
