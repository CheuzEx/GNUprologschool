# Proyecto completado

El proyecto de horario universitario en Prolog ya quedó terminado y verificado con una instancia mínima.

## Qué se implementó

- Carga y parseo de instancias desde archivos `.dat`.
- Definición de días, franjas, aulas, profesores, cursos y grupos.
- Restricciones de tipo, capacidad, aula fija, prohibiciones, exclusiones y disponibilidad del profesor.
- Generación de dominios por sesión.
- Búsqueda por backtracking con estrategias:
  - `bt_gp` (generar y probar)
  - `bt` con heurísticas `original`, `grado`, `demanda` y `mrv`
  - activación de simetría opcional
- Verificación independiente del horario generado.
- Comparación de configuraciones en `pruebas_bt.pl`.

## Verificación realizada

Se ejecutó con GNU Prolog la instancia mínima del proyecto:

```prolog
printf "consult('horarios.pl').\nconsult('busqueda_bt.pl').\nconsult('pruebas_bt.pl').\ncomparar('mini.dat', 5000).\n" | gprolog --quiet
```

Resultado observado:

- `generar y probar | solucion | valida`
- `anticipada, original | solucion | valida`
- `anticipada, original+sim | solucion | valida`
- `anticipada, grado+sim | solucion | valida`
- `anticipada, demanda+sim | solucion | valida`
- `FC + MRV | solucion | valida`
- `FC + MRV + sim | solucion | valida`

Esto confirma que la solución es funcional y válida para la instancia de prueba.

## Archivos principales

- `horarios.pl`: lectura, parsing y representación del problema.
- `busqueda_bt.pl`: búsqueda con backtracking, heurísticas y validación.
- `pruebas_bt.pl`: comparador de configuraciones.

## Estado final

El trabajo pendiente quedó resuelto y el proyecto puede ejecutarse correctamente con la carga de los archivos mencionados.
