# SPEC 005 — Visor de rutas marítimas animadas

> **Estado:** Borrador
> **Depende de:** SPEC 003 (Visor locations.json) y SPEC 004 (Fogg Sea Routes)
> **Fecha:** 2026-09-25
> **Objetivo:** Ampliar el visor standalone de ciudades para cargar un `sea_routes.json` mediante un selector y mostrar sus rutas marítimas como polilíneas azules discontinuas animadas sin perder los markers rojos.

---

## 1. Por qué existe esta especificación

`tools/locations-map/` permite inspeccionar `assets/data/locations.json` y validar visualmente la distribución de ciudades sobre OpenStreetMap. `assets/data/sea_routes.json` ya contiene las geometrías marítimas generadas por SPEC 004, pero el visor solo crea una capa de markers y no tiene ninguna forma de inspeccionar esas geometrías.

Sin una capa visual, no se pueden comprobar de un vistazo la continuidad de las rutas, sus extremos, la separación respecto de las ciudades, los cruces de longitud ni la legibilidad sobre el mapa. Esta especificación añade una herramienta exclusivamente de desarrollo para cargar un archivo de rutas y superponerlo al visor existente, sin introducir la ruta marítima en la partida ni modificar el bundle Flutter.

---

## 2. Alcance

**En:**

- **Carga rutas desde el explorador — `tools/locations-map/index.html` — añade un selector independiente para `sea_routes.json`** — mantiene el selector existente de ciudades y permite elegir un archivo local sin cargarlo automáticamente
  - **UI:** botón visible `Cargar rutas marítimas`, `input[type=file]` separado con `accept=".json,application/json"` y texto auxiliar que indica que el archivo no se escribe
  - **Estado:** `#route-status` muestra `0 rutas marítimas` antes de cargar; tras una carga válida, el botón pasa a `Recargar rutas marítimas` y el estado muestra el número de rutas junto al nombre del archivo

- **Dibuja rutas marinas animadas — `tools/locations-map/app.js` + `tools/locations-map/style.css` — superpone cada geometría sobre el mapa** — convierte cada `LineString` GeoJSON en una polilínea azul bajo los markers rojos
  - **Datos:** usa `geometry.coordinates` en orden GeoJSON `[lng, lat]` y lo transforma a `[lat, lng]` para Leaflet
  - **Estilo:** `className 'sea-route-line'`, color `#1E88E5`, `weight 3`, `opacity 0.9`, `dashArray '8 12'` y animación continua de `stroke-dashoffset` en `1.2s` lineal
  - **Sentido:** el desplazamiento del guion avanza desde el primer vértice (origen) hacia el último (destino)
  - **Capas:** el orden visual será `TileLayer < seaRoutesLayer < markerLayer`; los markers rojos actuales seguirán siendo visibles por encima
  - **Movimiento reducido:** con `prefers-reduced-motion: reduce`, la línea conserva el patrón discontinuo pero no se anima

- **Reemplaza la capa al recargar — `tools/locations-map/app.js:loadSeaRoutes` — procesa un único archivo activo** — una carga válida elimina la capa anterior y dibuja todas las rutas del archivo sin acumularlas
  - **Atomicidad:** no se limpia la capa existente hasta que el JSON se ha leído, validado y normalizado correctamente
  - **Cámara:** después de una carga válida, `map.fitBounds` encuadra todos los vértices de las rutas con margen para el panel lateral
  - **Filtro independiente:** el filtro de ciudades solo modifica `markerLayer` y la lista; no elimina ni vuelve a dibujar las rutas marítimas

- **Valida el esquema `sea_routes.json` — `tools/locations-map/app.js:validateSeaRoutes` — rechaza archivos incompatibles sin perder el estado anterior** — muestra un error accionable en `#banner` y no altera la última capa válida
  - **Estructura:** exige un objeto con `routes` no vacío; cada ruta exige `origin`, `destination`, `distanceKm` numérico positivo y `geometry.type === 'LineString'`
  - **Coordenadas:** exige al menos dos pares numéricos finitos dentro de `lng [-180,180]` y `lat [-85.05112878,85.05112878]` en cada geometría
  - **Extremos:** valida que `originLat`, `originLng`, `destinationLat` y `destinationLng` sean números finitos; las latitudes deben estar en `[-85.05112878,85.05112878]` y las longitudes en `[-180,180]`
  - **Error:** un JSON inválido, una ruta sin geometría o un rango imposible rechaza todo el archivo; no se omiten rutas parcialmente

- **Protege el cruce del antimeridiano — `tools/locations-map/app.js:splitAntimeridian` — evita líneas horizontales falsas** — divide una geometría con salto mayor de `180°` de longitud e intercala los puntos de borde antes de pasar a Leaflet
  - **Salida:** una ruta lógica puede producir varios segmentos dentro de una misma polilínea, conservando el orden origen-destino
  - **Compatibilidad:** el JSON original no se modifica ni se reescribe en disco

- **Muestra información al interactuar — `tools/locations-map/app.js:routePopup` — informa del trayecto seleccionado** — cada ruta abre un popup con origen, destino, distancia en kilómetros y número de vértices
  - **Seguridad:** los valores provenientes del archivo se escapan antes de insertarse en el HTML del popup
  - **Hover:** al pasar el puntero, la ruta aumenta temporalmente su grosor y recupera el estilo base al salir

- **Documenta el uso del visor — `README.md:Configuración` — explica cómo cargar y validar las rutas** — añade la acción de desarrollo, el formato esperado y la confirmación de que es una herramienta standalone
  - **Ejemplo:** documenta `./tools/serve_map.sh` y la selección de `assets/data/sea_routes.json` mediante el botón
  - **Responsive:** el botón, el estado y el panel siguen siendo utilizables en la disposición existente de `320px` y en el breakpoint móvil

**Compartido:** Leaflet `1.9.4` y su renderer SVG existentes; `assets/data/locations.json` y el flujo actual de carga, filtrado, popups y drag&drop de ciudades; `AppColors`/`foggRed` para los markers; `Package by Layer`; `eu.elarreglador.pf`; sin nuevas dependencias Flutter ni JavaScript.

**Fuera del alcance (para futuras especificaciones):**

- Integrar las rutas marítimas en `WorldMapWidget`, `PolylineLayer` o cualquier pantalla Flutter productiva.
- Cargar automáticamente `assets/data/sea_routes.json` al abrir el visor, hacer `fetch` del asset o incluirlo en el bundle PWA mediante `pubspec.yaml`.
- Generar, recalcular, editar o exportar `sea_routes.json` desde el navegador.
- Filtrar las rutas por origen, destino, distancia o texto; las rutas son una capa independiente del filtro de ciudades.
- Añadir una lista lateral de rutas, un toggle de visibilidad, navegación entre rutas o selección de una ruta activa.
- Persistir en `localStorage`, `IndexedDB`, Hive o cualquier backend el archivo seleccionado, el zoom o la capa de rutas.
- Modificar la lógica de generación de SPEC 004, el dataset de ciudades, los dominios de `FoggRoute`, `TransportMode`, `BudgetService` o el ciclo Fogg.
- Integrar la capa nocturna de `SunTerminatorService` o alcanzar paridad exacta con el CRS de `WorldMapWidget`.

---

## 3. Modelo de datos

Esta especificación no introduce entidades de dominio persistidas. Reutiliza `assets/data/sea_routes.json` como fuente de datos externa y mantiene el archivo seleccionado únicamente en memoria del navegador.

### 3.1 Contrato de `sea_routes.json`

El consumidor acepta la forma ya versionada por SPEC 004:

```json
{
  "meta": {
    "project": "eu.elarreglador.pf",
    "name": "Fogg Sea Routes — Herencia de Phoebe",
    "version": "1.0.1",
    "units": "km"
  },
  "routes": [
    {
      "origin": "Londres",
      "originLat": 51.50853,
      "originLng": -0.12574,
      "destination": "Portsmouth",
      "destinationLat": 50.79899,
      "destinationLng": -1.09125,
      "distanceKm": 335.0,
      "geometry": {
        "type": "LineString",
        "coordinates": [[0.2137, 51.4867], [-1.119919, 50.823505]]
      }
    }
  ]
}
```

Reglas de validación:

- `meta` se considera metadato informativo; si existe, `units` debe ser `km` y `project` debe ser `eu.elarreglador.pf` cuando ambos campos estén presentes.
- `routes` debe ser un array con al menos una ruta.
- `distanceKm` debe ser finito y mayor que cero.
- Cada par de `geometry.coordinates` representa `[lng, lat]`, no `[lat, lng]`.
- La latitud se limita al rango Mercator de Leaflet `[-85.05112878, 85.05112878]`.
- El archivo puede contener varias rutas con el mismo origen o destino; no se deduplican en el visor.

### 3.2 Estado efímero del visor

```js
let seaRoutesLayer = L.layerGroup().addTo(map);
let loadedSeaRoutes = [];
let loadedSeaRouteFileName = null;
let seaRouteLoadError = null;
```

- `loadedSeaRoutes` contiene objetos normalizados con `origin`, `destination`, `distanceKm`, `leafletSegments` y `pointCount`.
- `leafletSegments` contiene uno o más arrays de puntos `[lat, lng]` derivados de la geometría original.
- `loadedSeaRouteFileName` solo se usa para el estado visible del panel; no se persiste.
- `seaRouteLoadError` se reinicia al comenzar una lectura válida y solo se muestra en el banner ante un error.

La capa de ciudades existente (`markerLayer`, `allCities` y `filteredCities`) permanece separada. La limpieza de `seaRoutesLayer` no llama a `markerLayer.clearLayers()` ni modifica el filtro activo.

### 3.3 Conversión y segmentación

El flujo de datos será:

```text
FileReader
  -> JSON.parse
  -> validateSeaRoutes(data)
  -> normalizeSeaRoutes(data.routes)
  -> splitAntimeridian(coordinates)
  -> L.polyline(leafletSegments, routeStyle)
```

- La conversión conserva el orden de los vértices.
- Si dos coordenadas consecutivas tienen una diferencia absoluta de longitud mayor que `180`, se insertan los puntos de borde `[-180, lat]` y `[180, lat]` en el orden que mantiene el sentido del segmento.
- Una ruta válida produce un objeto `L.polyline`; si requiere cortes, sus varios segmentos permanecen dentro de esa misma polilínea lógica.
- El popup se construye con `origin`, `destination`, `distanceKm.toFixed(1)` y `geometry.coordinates.length`.

No se añade una entidad Dart, una caja Hive, una clave de persistencia ni una migración de esquema.

---

## 4. Plan de implementación

Cada paso deja el visor ejecutable y mantiene disponible la carga actual de ciudades.

1. **Añade el control de carga — `tools/locations-map/index.html` — incorpora botón, input independiente y estado visible** — el botón `Cargar rutas marítimas` activa el `input#sea-routes-file`; el selector de ciudades existente conserva su ID y comportamiento; `#route-status` empieza en `0 rutas marítimas`. Prueba: abrir `http://localhost:8090` muestra ambos controles y todavía no dibuja rutas.

2. **Implementa la lectura y validación — `tools/locations-map/app.js` — procesa el archivo seleccionado sin tocar el asset** — `FileReader.readAsText`, `JSON.parse`, `validateSeaRoutes` y `normalizeSeaRoutes` deben ejecutarse antes de limpiar o modificar la capa. Prueba: seleccionar un JSON válido activa el estado de carga; seleccionar un JSON inválido muestra error y conserva la capa previa.

3. **Crea la capa de rutas — `tools/locations-map/app.js` — dibuja una polilínea lógica por ruta** — añade `seaRoutesLayer` al mapa por debajo de `markerLayer`, convierte `[lng, lat]` a `[lat, lng]`, aplica `#1E88E5`, `weight 3`, `opacity 0.9` y `dashArray '8 12'`. Prueba: `assets/data/sea_routes.json` actual muestra sus 9 rutas lógicas y conserva los markers rojos.

4. **Añade animación y movimiento reducido — `tools/locations-map/style.css` — hace avanzar el patrón azul en el sentido del viaje** — define `seaRouteFlow` con `stroke-dashoffset` de `0` a `-20` en `1.2s` lineal infinito y una regla `prefers-reduced-motion: reduce` sin animación. Prueba: la animación se observa en una ruta y desaparece cuando el navegador simula movimiento reducido.

5. **Integra reemplazo, cámara e interacción — `tools/locations-map/app.js` — hace atómica cada recarga y enfoca el conjunto** — tras validar, limpia `seaRoutesLayer`, dibuja las rutas normalizadas, registra popups/hover y ejecuta `fitBounds` con padding horizontal suficiente para el panel. Prueba: cargar un segundo archivo elimina la primera capa, no duplica rutas y encuadra las nuevas.

6. **Protege la geografía — `tools/locations-map/app.js:splitAntimeridian` — evita travesías horizontales** — añade los puntos de borde en cada salto de longitud mayor de `180°` y conserva el sentido del primer al último vértice. Prueba: una geometría sintética `179 → -179` produce dos segmentos que llegan a los bordes sin una línea directa a través del mapa.

7. **Documenta y verifica — `README.md:Configuración` + navegador — deja el flujo reproducible y comprueba regresiones** — actualiza la sección del visor con el botón, el asset esperado y la nota de que la carga es local y efímera; ejecuta el servidor, una comprobación visual en Chrome y `flutter analyze && flutter test`. Prueba: el visor conserva la carga de ciudades, la nueva acción y los estilos responsive sin errores de consola.

---

## 5. Criterios de aceptación

- [ ] `tools/locations-map/index.html` contiene un botón visible `Cargar rutas marítimas`, un `input[type=file]` separado con `accept` para JSON y un elemento `#route-status` inicializado en `0 rutas marítimas`; el selector existente de ciudades sigue funcionando.
- [ ] Al abrir el visor no se realiza ninguna petición ni lectura automática de `sea_routes.json`; la capa de rutas comienza vacía.
- [ ] Al seleccionar `assets/data/sea_routes.json`, `#route-status` muestra `9 rutas marítimas` y el nombre `sea_routes.json` para el dataset versionado actual, y se dibuja una polilínea lógica por cada elemento de `routes`.
- [ ] Cada geometría GeoJSON se convierte de `[lng, lat]` a `[lat, lng]` antes de llegar a Leaflet; el popup de una ruta de prueba muestra las coordenadas visuales esperadas.
- [ ] Cada ruta usa color `#1E88E5`, grosor `3`, opacidad `0.9` y patrón discontinuo `8 12` en SVG.
- [ ] El patrón de la línea se desplaza continuamente en `1.2s` lineales desde el origen hacia el destino, sin depender de hover ni de interacción del usuario.
- [ ] Con `prefers-reduced-motion: reduce`, la ruta sigue siendo visible y discontinua, pero no tiene animación de `stroke-dashoffset`.
- [ ] Los markers rojos de las ciudades siguen mostrando `name`, `asciiname`, coordenadas, `timezone` y enlace OSM; las rutas quedan por debajo y no los cubren.
- [ ] El filtro de ciudades actualiza la lista y los markers sin ocultar, limpiar ni volver a dibujar la capa de rutas.
- [ ] Al pulsar una ruta, el popup muestra origen, destino, `distanceKm` con un decimal y el número de vértices; los textos del JSON se escapan y no se interpretan como HTML.
- [ ] Al pasar el puntero sobre una ruta, su grosor aumenta; al salir, vuelve al grosor base sin crear capas adicionales.
- [ ] Tras una carga válida, la cámara encuadra todos los vértices de las rutas con un margen que evita que el panel lateral tape el trayecto.
- [ ] Seleccionar un segundo archivo válido elimina todas las rutas anteriores antes de dibujar las nuevas; el número de rutas no se acumula.
- [ ] Seleccionar un JSON inválido, una geometría vacía, coordenadas fuera de rango o una ruta sin campos requeridos muestra un error y conserva exactamente la última capa válida.
- [ ] Una geometría que cruza `180/-180` se divide en segmentos en el borde y no dibuja una línea horizontal falsa a través del mapa.
- [ ] La herramienta sigue funcionando con `python3 -m http.server 8090 --directory tools/locations-map` y no muestra errores de consola durante la carga de ciudades, la carga de rutas, el zoom, el filtro y el popup.
- [ ] El panel y el botón siguen siendo utilizables en el layout existente de `320px` y en el breakpoint móvil definido en `style.css`, sin scroll horizontal.
- [ ] `README.md:Configuración` documenta el flujo, el archivo esperado y que el archivo seleccionado no se escribe ni se persiste.
- [ ] `flutter analyze` y `flutter test` terminan correctamente; no se modifican `pubspec.yaml`, `lib/`, `web/` ni el generador de SPEC 004.
- [ ] El diff no contiene secretos, datos generados fuera de alcance ni cambios en la rama actual ajenos a esta especificación.

---

## 6. Decisiones tomadas y descartadas

- **Sí:** ampliar el visor standalone `tools/locations-map` y no la app Flutter. Por qué: replica SPEC 003, mantiene el debugging visual fuera del bundle PWA y satisface la necesidad sin anticipar `PolylineLayer` productivo.
- **Sí:** selector de archivos separado del selector de ciudades. Por qué: las dos entradas tienen esquemas distintos (`cities` frente a `routes`) y una selección accidental no debe reemplazar los markers.
- **No:** carga automática o `fetch` de `assets/data/sea_routes.json`. Por qué: el requisito pide un botón/explorador y la carga manual permite inspeccionar regeneraciones sin cambiar el comportamiento inicial del visor.
- **Sí:** una única polilínea lógica por ruta con segmentos múltiples cuando sea necesario. Por qué: mantiene una unidad clara para popup, hover y reemplazo, sin crear una ruta artificial por cada vértice.
- **Sí:** SVG con `L.polyline`, `dashArray` y animación CSS de `stroke-dashoffset`. Por qué: es la opción nativa de Leaflet 1.9.4, no requiere plugin ni dependencia nueva y permite que la animación respete el sistema.
- **Sí:** patrón azul uniforme `#1E88E5`, grosor `3`, opacidad `0.9`, patrón `8 12` y ciclo `1.2s`. Por qué: mantiene contraste con OpenStreetMap y con los markers rojos sin introducir una leyenda de colores por ruta.
- **Sí:** `prefers-reduced-motion` como modo estático. Por qué: una animación de rutas es decorativa y no debe impedir la lectura del mapa a personas que hayan pedido reducir el movimiento.
- **Sí:** filtro de ciudades independiente de la capa marítima. Por qué: permite localizar una ciudad sin perder la vista contextual de todas las rutas.
- **Sí:** reemplazo atómico tras validar el archivo completo. Por qué: un JSON parcialmente válido podría ocultar información y dejar al usuario creyendo que la carga terminó correctamente.
- **Sí:** encuadre automático de la cámara tras cada carga válida. Por qué: el usuario acaba de solicitar la visualización de un conjunto de trayectos y no debe tener que descubrir manualmente dónde están.
- **Sí:** segmentación del antimeridiano. Por qué: una diferencia de longitud mayor de `180°` representa un salto geográfico, no una línea recta horizontal; el JSON puede ser válido aunque el mapa no deba unirlo así.
- **No:** filtrar rutas por origen/destino, ordenarlas por distancia o mostrar una lista de rutas. Por qué: son mejoras de navegación posteriores y no son necesarias para validar el dataset.
- **No:** editar, exportar o guardar el `sea_routes.json` seleccionado. Por qué: el visor es de lectura y la fuente canónica debe seguir siendo SPEC 004.
- **No:** añadir `sea_routes.json` a `pubspec.yaml`. Por qué: esta funcionalidad es exclusivamente del visor HTML; el archivo se elige mediante `FileReader` y no se distribuye dentro del PWA.
- **Sí:** trabajar sobre la rama actual proporcionada por el usuario y no crear una rama adicional para esta especificación. Por qué: la decisión de flujo ya está cerrada para esta sesión.

---

## 7. Riesgos identificados

| Riesgo | Mitigación |
| --- | --- |
| La animación CSS de muchas geometrías puede elevar el consumo de CPU | El dataset actual contiene 9 rutas y 273 vértices; además, `prefers-reduced-motion` desactiva la animación y el renderer SVG existente es suficiente para esta herramienta de desarrollo. |
| El signo de `stroke-dashoffset` puede parecer invertido en distintos navegadores o al cambiar el CRS | Verificar visualmente el sentido origen-destino en Chrome y documentar el valor CSS en `style.css`; no depender de una animación JS sincronizada con el mapa. |
| Una geometría válida con salto `179 → -179` puede crear una línea horizontal a través del mundo | Detectar saltos mayores de `180°`, interpolar los puntos de borde y verificar el caso sintético durante la implementación. |
| Un archivo local puede contener HTML malicioso en nombres o notas | Construir popups con `textContent` o escapar todos los valores antes de usar HTML; no interpolar el JSON directamente. |
| El panel lateral puede ocultar parte del trayecto al encuadrar automáticamente | Aplicar padding lateral explícito y verificar el resultado en el layout de `320px` y en móvil. |
| El filtro de ciudades puede limpiar accidentalmente la nueva capa si se reutiliza un `layerGroup` compartido | Mantener `markerLayer` y `seaRoutesLayer` separados y hacer que `clearLayers()` solo se aplique a la capa que corresponde. |
| Un JSON inválido puede dejar una combinación de rutas viejas y nuevas | Construir y validar todas las rutas en memoria antes de limpiar la capa existente; hacer el `clearLayers()` únicamente después de la normalización completa. |
| El visor abierto desde `file://` no puede cargar automáticamente las ciudades por CORS | Mantener el mensaje existente y no ampliar esta especificación; el selector de rutas seguirá funcionando para inspección local cuando el usuario ya tenga ciudades visibles. |

---

## 8. Lo que **no** está en esta especificación

- Renderizado de rutas marítimas en la pantalla Flutter del juego.
- Carga automática del asset, inclusión en `pubspec.yaml` o distribución dentro del PWA.
- Generación, edición, exportación o persistencia de `sea_routes.json`.
- Filtros por ruta, lista de rutas, selección activa, toggle de visibilidad o navegación entre viajes.
- Persistencia del archivo elegido, zoom, filtro o estado de la capa.
- Integración con `BudgetService`, `Ledger`, `TransportMode.ship`, `TimeEngine`, `DiaryService` o `EventEngine`.
- Capa nocturna, terminador solar o paridad completa con `WorldMapWidget`.
- Pruebas de generación de rutas o cambios en SPEC 004.

Cada uno, si aterriza, irá en su propia especificación.

---

## 9. Referencias

- `assets/data/sea_routes.json:1` — dataset GeoJSON versionado por SPEC 004, con 9 rutas y coordenadas `[lng, lat]`.
- `docs/specs/003-visor-locations-mapa.md:23` — alcance y convenciones del visor standalone existente.
- `docs/specs/004-fogg-sea-routes.md:57` — contrato de datos de `sea_routes.json` y reglas de la geometría.
- `tools/locations-map/index.html:12` — mapa, panel, selector de ciudades y scripts existentes.
- `tools/locations-map/app.js:20` — inicialización de Leaflet y orden de capas actual.
- `tools/locations-map/app.js:37` — estado de ciudades, `markerLayer` y `renderMarkers`.
- `tools/locations-map/app.js:209` — flujo actual de `FileReader` para comparar archivos locales.
- `tools/locations-map/style.css:166` — estilo visual del marker rojo y convención de la interfaz.
- `tools/serve_map.sh:1` — servidor estático del visor en el puerto `8090`.
- `README.md:16` — sección de configuración y uso del visor de ciudades.
- Leaflet `1.9.4` — `Path`, `Polyline`, eventos de capa, panes y opciones `dashArray` en `https://leafletjs.com/reference.html`.

---

## 10. Preguntas abiertas (resueltas por esta especificación)

- Alcance limitado al visor standalone: no modifica la app Flutter
- Carga manual mediante botón y explorador: sí
- Rutas como capa independiente del filtro de ciudades: sí
- Animación azul discontinua continua con origen-destino: sí
- Modo estático con movimiento reducido: sí
- Reemplazo atómico de la capa y conservación de la última carga válida: sí
- Popup con origen, destino, distancia y número de vértices: sí
- Encuadre automático de las rutas cargadas: sí
- Segmentación del antimeridiano: sí
- Documentación en `README.md:Configuración`: sí
- Rama de trabajo: la rama actual proporcionada por el usuario

> Siguiente paso tras aprobar esta spec: ejecutar `/spec-impl 005-visor-rutas-maritimas-animadas` siguiendo el plan de la sección 4.
