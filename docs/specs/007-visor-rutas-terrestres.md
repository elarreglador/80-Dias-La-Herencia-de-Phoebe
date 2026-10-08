# SPEC 007 — Visor de rutas terrestres junto a las marítimas

> **Estado:** Aprobado

> **Depende de:** SPEC 003 (Visor locations.json), SPEC 005 (Visor de rutas marítimas animadas) y SPEC 006 (Fogg Car Routes)

> **Fecha:** 2026-10-07

> **Objetivo:** Ampliar el visor standalone para cargar `car_routes.json` como capa amarilla independiente y simultánea a la capa azul de rutas marítimas, sin carga automática y sin mover la cámara al cargar.

---

## 1. Por qué existe esta especificación

SPEC 006 generó `assets/data/car_routes.json` con 1001 rutas por carretera, y su criterio de aceptación se cumplió de forma provisional: el selector de rutas existente acepta el fichero porque su esquema es compatible con el de las marítimas. Pero "compatible" no es "integrado": las 1001 rutas terrestres se pintan con el mismo azul `#1E88E5` que las marítimas, el estado de la interfaz dice `rutas marítimas` cuando el fichero cargado es terrestre, y no se puede comparar un trayecto por carretera con su alternativa marítima porque no existe una forma clara de tener ambos a la vez con identidad visual propia.

Esta especificación convierte ese atajo en una funcionalidad deliberada: dos botones juntos, dos capas con color propio, dos estados independientes y un validador único. Además retira el encuadre automático que SPEC 005 introdujo, porque el usuario no quiere que la cámara salte al cargar ninguna capa.

---

## 2. Alcance

**En:**

- **Añade el botón "Cargar rutas terrestres" junto al marítimo — `tools/locations-map/index.html:24` — carga manual de `car_routes.json`** — dos botones apilados y consecutivos dentro del mismo bloque `.route-loader`, sin nada entre ellos
  - **Controles:** `button#load-land-routes`, `input#land-routes-file` con `accept=".json,application/json"` oculto, y `div#land-route-status` con `aria-live="polite"` inicializado en `0 rutas terrestres`
  - **Orden:** el bloque terrestre se coloca **encima** del marítimo; el marítimo conserva `button#load-sea-routes`, `input#sea-routes-file` y su estado, renombrado de `#route-status` a `#sea-route-status`
  - **Pista única:** un solo `<p class="hint">` bajo los dos botones menciona `sea_routes.json` y `car_routes.json` y reitera que no se escribe en disco

- **Dibuja las rutas terrestres en amarillo — `tools/locations-map/app.js` + `tools/locations-map/style.css:206` — capa `landRoutesLayer` superpuesta al mapa** — cada `LineString` de `car_routes.json` se convierte en una polilínea amarilla animada
  - **Estilo:** `className 'land-route-line'`, color `#F9A825`, `weight 3`, `opacity 0.9`, `dashArray '8 12'` y animación `landRouteFlow` de `stroke-dashoffset` en `1.2s` lineal infinita
  - **Animación:** idéntica en duración y sentido a la marítima; con `prefers-reduced-motion: reduce` conserva el patrón discontinuo y no se anima
  - **Estado:** `#land-route-status` muestra `0 rutas terrestres` antes de cargar y tras una carga válida `1001 rutas terrestres · car_routes.json`; el botón pasa a `Recargar rutas terrestres`

- **Mantiene las marítimas en azul e independientes — `tools/locations-map/app.js:44` — dos capas conviven sin reemplazarse** — `landRoutesLayer` y `seaRoutesLayer` son dos `layerGroup` separados con estado propio
  - **Simultaneidad:** cargar un fichero terrestre no borra las marítimas ni viceversa; el reemplazo atómico de SPEC 005 sigue aplicándose pero solo a la capa de su tipo
  - **Filtro:** el filtro de ciudades sigue tocando únicamente `markerLayer` y la lista; ninguna capa de rutas se limpia ni redibuja al filtrar

- **Retira el encuadre automático al cargar — `tools/locations-map/app.js:222` — la cámara no se mueve nunca** — se elimina `fitSeaRoutes` y sus llamadas en ambos flujos de carga
  - **Efecto:** cargar cualquier fichero de rutas cambia el conjunto de líneas visibles pero ni el `center` ni el `zoom` del mapa

- **Muestra la duración en el popup terrestre — `tools/locations-map/app.js:203` — `4.6 h` junto a los kilómetros** — un único `routePopup` compartido por ambas capas
  - **Terrestre:** `Londres → Bruselas` más `370.2 km · 4.6 h · 39 vértices`
  - **Marítimo:** `origen → destino` más `km · vértices` (sin horas, porque `sea_routes.json` no trae `durationHours`)
  - **Seguridad:** todos los valores del fichero se escapan con `escapeHtml` antes de insertarse en el HTML

- **Ordena las capas de forma determinista — `tools/locations-map/app.js` + `tools/locations-map/style.css` — amarilla sobre azul, markers siempre encima** — el orden visual no depende de qué fichero se cargue primero
  - **Paneles:** `seaRoutesPane` (zIndex 401) y `landRoutesPane` (zIndex 402), ambos por debajo de `markerPane` (600) y sobre `tilePane` (200)
  - **Renderers:** cada estilo declara su panel y su propio `L.svg()`, de modo que el orden de inserción de las polilíneas deja de importar

- **Valida ambos ficheros con la misma función — `tools/locations-map/app.js:85` — `validateSeaRoutes` pasa a `validateRoutes`** — una sola validación compartida por los dos botones, sin discriminar por `meta.profile`
  - **Reglas:** se conservan intactas las de SPEC 005 (objeto con `routes` no vacío, `origin`/`destination` no vacíos, `distanceKm > 0`, extremos y coordenadas en rango Mercator, `geometry.type === 'LineString'` con al menos dos pares)
  - **Añadido:** si una ruta trae `durationHours`, debe ser un número finito mayor que cero; si no existe, el popup omite las horas
  - **Sin discriminar:** un `car_routes.json` cargado desde el botón marítimo se acepta y se pinta de azul; la etiqueta de estado describe el botón usado, no el contenido

- **Abre el visor en incognito — `tools/serve_map.sh` — evita la caché del navegador** — al lanzar el script, el navegador se abre en ventana incognito/privada
  - **Detección:** `google-chrome-stable`, `google-chrome`, `chromium` o `chromium-browser` → flag `--incognito`; `firefox` → flag `--private-window`
  - **Fallback:** si no se encuentra ninguno de esos navegadores o no hay `DISPLAY`, se usa `xdg-open` normal (comportamiento actual); la apertura nunca mata el servidor (`|| true`)

- **Documenta las dos cargas — `README.md:28` — instrucciones del visor actualizadas** — la sección `Visor locations.json (solo dev)` explica ambos botones
  - **Contenido:** fichero esperado en cada botón, colores, ausencia de encuadre y carácter local y efímero de la lectura

**Compartido:** Leaflet `1.9.4` y su renderer SVG; `assets/data/locations.json` y el flujo actual de carga, filtrado, popups y drag&drop de ciudades; `splitAntimeridian` existente, que sigue aplicándose a las dos capas; `escapeHtml`; los tokens `--fogg-red` y `--offline-bg` de `style.css`; sin nuevas dependencias JavaScript ni cambios en `lib/`, `pubspec.yaml` ni la skill `fogg-land-routes`.

**Fuera del alcance (para futuras especificaciones):**

- Cargar `car_routes.json` o `sea_routes.json` automáticamente al abrir el visor, hacer `fetch` de los assets o incluirlos en `pubspec.yaml`.
- Generar, recalcular, editar o exportar `car_routes.json` desde el navegador.
- Distinguir el fichero cargado por su `meta.profile` y rechazarlo en el botón "equivocado".
- Un toggle de visibilidad por capa, una leyenda de colores, una lista lateral de rutas o filtros por origen, destino, distancia o texto.
- Persistir en `localStorage`, `IndexedDB` o cualquier backend el fichero seleccionado, el zoom o el estado de las capas.
- Integrar rutas terrestres o marítimas en `WorldMapWidget`, `PolylineLayer` o cualquier pantalla Flutter productiva.
- Modificar la lógica de generación de SPEC 006, la skill `.opencode/skills/fogg-land-routes/` o el dataset de ciudades.
- Revisar o editar el texto de `docs/specs/005` y `docs/specs/006`; esta spec registra sus criterios superados (ver §6).
- Integrar la capa nocturna de `SunTerminatorService`.

---

## 3. Modelo de datos

Esta especificación no introduce entidades de dominio persistidas. Reutiliza dos ficheros externos ya versionados y mantiene lo cargado únicamente en memoria del navegador.

### 3.1 Contrato de `assets/data/car_routes.json`

Se acepta la forma ya escrita por SPEC 006 (resumen; el detalle está en esa spec):

```json
{
  "meta": { "project": "eu.elarreglador.pf", "name": "Fogg Land Routes", "profile": "car", "units": "km" },
  "routes": [
    {
      "origin": "Londres", "originLat": 51.50853, "originLng": -0.12574,
      "destination": "Bruselas", "destinationLat": 50.85045, "destinationLng": 4.34878,
      "distanceKm": 370.2, "durationHours": 4.6,
      "roadOrigin": { "name": "Strand", "lat": 51.50851, "lng": -0.12571, "snapKm": 0.0 },
      "roadDest": { "name": "Rue Melsens", "lat": 50.85041, "lng": 4.34876, "snapKm": 0.0 },
      "geometry": { "type": "LineString", "coordinates": [[-0.12574, 51.50853], [4.34878, 50.85045]] },
      "heading": "east"
    }
  ]
}
```

Reglas del visor:

- El validador solo exige los campos que ya exigía para las marítimas, más `durationHours` opcional positivo.
- `roadOrigin`, `roadDest` y `heading` se ignoran: no se pintan ni se validan.
- `geometry.coordinates` es `[lng, lat]` GeoJSON, igual que en `sea_routes.json`.
- Dataset actual: `meta.routes == 1001`, 41430 vértices, 3,4 MB. Las marítimas suman hoy 210 rutas y 11257 vértices.

### 3.2 Estado efímero del visor

```js
const landRoutesLayer = L.layerGroup().addTo(map);   // panel landRoutesPane
const seaRoutesLayer  = L.layerGroup().addTo(map);   // panel seaRoutesPane
const markerLayer     = L.layerGroup().addTo(map);   // markerPane, siempre encima

let loadedLandRoutes = [];
let loadedLandRouteFileName = null;
let loadedSeaRoutes = [];
let loadedSeaRouteFileName = null;
```

- Cada capa lleva sus propias `routes`, `fileName` y mensaje de error; no comparten arrays.
- `landRoutesLayer.clearLayers()` nunca se invoca desde el flujo marítimo ni viceversa.
- `markerLayer`, `allCities` y `filteredCities` quedan exactamente como están.
- Los estilos viven en un objeto por capa:

```js
const landRouteStyle = {
  pane: 'landRoutesPane', renderer: L.svg({ pane: 'landRoutesPane' }),
  className: 'land-route-line', color: '#F9A825',
  weight: 3, opacity: 0.9, dashArray: '8 12', interactive: true,
};
// seaRouteStyle: mismo shape, pane/className/color de SPEC 005
```

### 3.3 Conversión y segmentación

El flujo de datos es el mismo para los dos tipos, con la capa como parámetro:

```text
FileReader
  -> JSON.parse
  -> validateRoutes(data)          // único, compartido
  -> normalizeRoutes(data.routes)  // único, compartido
  -> splitAntimeridian(coordinates) // único, compartido
  -> <capa>.clearLayers()          // solo la capa de este tipo
  -> L.polyline(segments, styleDeCapa)
```

- La conversión sigue transformando `[lng, lat]` a `[lat, lng]`.
- `splitAntimeridian` se aplica a las dos capas; `car_routes.json` declara 0 cruces hoy, pero la geometría sintética `179 → -179` debe seguir partiendo en los bordes.
- El popup se construye con una única función que imprime las horas solo si `durationHours` existe.
- **No existe `fitSeaRoutes`:** ninguna rama del flujo llama a `map.fitBounds`.

No se añade una entidad Dart, una caja Hive, una clave de persistencia ni una migración de esquema.

---

## 4. Plan de implementación

Cada paso deja el visor ejecutable con la carga de ciudades y las rutas marítimas operativas.

1. **Añade los controles terrestres — `tools/locations-map/index.html` — botón, input y estado junto a los marítimos** — inserta el bloque `#load-land-routes` / `#land-routes-file` / `#land-route-status` inmediatamente encima del marítimo dentro de `.route-loader`, renombra `#route-status` a `#sea-route-status` y deja una sola `p.hint` para los dos. Prueba: `./tools/serve_map.sh` muestra dos botones apilados, `0 rutas terrestres` y `0 rutas marítimas`, sin ninguna línea dibujada.

2. **Abre el visor en incognito — `tools/serve_map.sh` — evita la caché del navegador** — sustituye el bloque `xdg-open` por detección de Chrome/Chromium (`--incognito`) y Firefox (`--private-window`), con fallback a `xdg-open` normal si ninguno existe o no hay `DISPLAY`; la apertura sigue en segundo plano con `sleep 1` y `|| true`. Prueba: `bash -n tools/serve_map.sh` y lanzamiento manual abren una ventana incognito con el visor accesible y `Ctrl+C` detiene limpio.

3. **Crea los paneles y la capa terrestre — `tools/locations-map/app.js` — orden de dibujo determinista** — `map.createPane('seaRoutesPane')` con zIndex 401 y `map.createPane('landRoutesPane')` con 402, mueve `seaRouteStyle` a su panel y declara `landRoutesLayer` + `landRouteStyle`. Prueba: las marítimas cargadas siguen por debajo de los markers rojos y el mapa arranca en `center [20,0]`, `zoom 2`.

4. **Generaliza validación, normalización y popup — `tools/locations-map/app.js` — una sola implementación para los dos tipos** — renombra `validateSeaRoutes` → `validateRoutes`, `normalizeSeaRoutes` → `normalizeRoutes`, añade la comprobación opcional de `durationHours` y hace que `routePopup` imprima las horas solo si existen; actualiza `window.__foggVisor`. Prueba: cargar `sea_routes.json` se comporta exactamente igual que antes y un JSON con `durationHours: -1` se rechaza.

5. **Extracción del flujo de carga — `tools/locations-map/app.js` — una única función parametrizada por capa** — `loadRoutes(file, capa)` encapsula `FileReader → JSON.parse → validateRoutes → normalizeRoutes → clearLayers (solo esa capa) → dibujo → estado → banner`, y `loadSeaRoutes` pasa a ser una llamada con la configuración marítima. Prueba: recargar marítimas sigue reemplazando su capa sin tocar la terrestre (que aún está vacía).

6. **Conecta el botón terrestre — `tools/locations-map/app.js` — carga real de `car_routes.json`** — listener en `#load-land-routes` y `#land-routes-file` que llama a `loadRoutes` con la configuración terrestre y actualiza `#land-route-status` y el texto del botón. Prueba: seleccionar `assets/data/car_routes.json` muestra `1001 rutas terrestres · car_routes.json` y dibuja 1001 polilíneas amarillas.

7. **Retira el encuadre automático — `tools/locations-map/app.js` — la cámara deja de moverse** — borra `fitSeaRoutes` y sus dos llamadas; no queda ninguna referencia a `fitBounds` en el fichero. Prueba: anotar `center` y `zoom`, cargar los dos ficheros, verificar que no han cambiado.

8. **Estilos amarillos y pista compartida — `tools/locations-map/style.css` — botón legible y animación terrestre** — `.route-button--land` con fondo `#F9A825`, texto `#1A1A1A`, borde `#E6A817` y hover `#E6A817`; `.land-route-line` con `landRouteFlow` `1.2s` lineal infinita y regla `prefers-reduced-motion: reduce`; comprueba que `.route-loader` mantiene los dos botones consecutivos a `320px`. Prueba: el botón amarillo se lee con contraste AA y las dos capas se animan con movimiento reducido desactivado.

9. **Documenta y verifica — `README.md:28` + navegador headless — flujo reproducible** — actualiza la sección del visor con los dos botones, los colores y la nota de que no hay encuadre; comprueba en Chromium headless (Playwright, como en SPEC 006) que no hay errores de consola; ejecuta `flutter analyze` y `flutter test`. Prueba: el diff toca solo `tools/locations-map/`, `tools/serve_map.sh`, `README.md` y esta spec.

---

## 5. Criterios de aceptación

- [ ] `tools/locations-map/index.html` contiene `button#load-land-routes`, `input#land-routes-file` con `accept` para JSON y `#land-route-status` en `0 rutas terrestres`, colocados **inmediatamente encima** del bloque marítimo, sin ningún elemento entre ambos botones.
- [ ] El estado marítimo existe como `#sea-route-status`, arranca en `0 rutas marítimas` y el botón marítimo conserva su comportamiento actual.
- [ ] Al abrir el visor no se emite ninguna petición ni lectura de `car_routes.json` ni `sea_routes.json`; ambas capas empiezan con 0 polilíneas y el mapa está en `center [20,0]`, `zoom 2`.
- [ ] Seleccionar `assets/data/car_routes.json` desde su botón dibuja 1001 polilíneas y `#land-route-status` muestra `1001 rutas terrestres · car_routes.json`; el botón pasa a `Recargar rutas terrestres`.
- [ ] Seleccionar `assets/data/sea_routes.json` desde su botón dibuja una polilínea por elemento de `routes` (hoy 210) y `#sea-route-status` muestra ese número junto al nombre del fichero.
- [ ] Las dos capas están visibles a la vez tras cargar los dos ficheros; ninguna carga borra la capa de la otra.
- [ ] Cada ruta terrestre usa color `#F9A825`, grosor `3`, opacidad `0.9`, patrón `8 12` y la clase `land-route-line`; cada marítima conserva `#1E88E5` y `sea-route-line`.
- [ ] Cuando una ruta terrestre cruza sobre una marítima, la amarilla se dibuja por encima, sea cual sea el orden de carga; los markers rojos siguen por encima de ambas.
- [ ] El patrón discontinuo de las dos capas se desplaza en `1.2s` lineales sin depender de hover; con `prefers-reduced-motion: reduce` ambas siguen visibles y discontinuas pero sin animación.
- [ ] Cargar cualquier fichero de rutas deja `center` y `zoom` del mapa intactos; no queda ninguna llamada a `fitBounds` en `tools/locations-map/app.js`.
- [ ] El popup terrestre muestra `Londres → Bruselas`, `370.2 km · 4.6 h · 39 vértices`; el marítimo sigue mostrando `km · vértices` sin horas.
- [ ] Todos los valores procedentes de los JSON se escapan con `escapeHtml` antes de renderizarse en un popup.
- [ ] Al pasar el puntero sobre una ruta de cualquier capa su grosor pasa a `5` y al salir vuelve a `3`, sin crear capas adicionales.
- [ ] Un JSON inválido, una geometría vacía, coordenadas fuera de rango o `durationHours <= 0` muestra el banner de error y conserva exactamente la última carga válida de **esa** capa; la otra capa no se modifica.
- [ ] Un `car_routes.json` cargado desde el botón marítimo se acepta y se pinta de azul; no existe ninguna comprobación de `meta.profile`.
- [ ] La geometría sintética `179 → -179` se segmenta en los bordes en las dos capas y no dibuja una línea horizontal falsa.
- [ ] El filtro de ciudades actualiza la lista y los markers sin ocultar, limpiar ni redibujar ninguna capa de rutas.
- [ ] El panel sigue siendo usable en `320px` y en el breakpoint móvil de `style.css:252`, con los dos botones apilados y sin scroll horizontal.
- [ ] `README.md:16` documenta los dos botones, el fichero esperado en cada uno, sus colores y la ausencia de encuadre.
- [ ] Chromium headless (Playwright) carga el visor, los dos ficheros y el filtro sin errores de consola ni banner inesperado.
- [ ] `flutter analyze` y `flutter test` terminan correctamente; no se modifican `pubspec.yaml`, `lib/`, `web/` ni las skills de generación de rutas.
- [ ] `./tools/serve_map.sh` abre el visor en ventana incognito/privada (Chrome/Chromium `--incognito` o Firefox `--private-window`); sin ninguno de esos navegadores cae a `xdg-open` normal, y la apertura nunca interrumpe el servidor.
- [ ] El diff contiene solo `tools/locations-map/index.html`, `tools/locations-map/app.js`, `tools/locations-map/style.css`, `tools/serve_map.sh`, `README.md` y `docs/specs/007-visor-rutas-terrestres.md`, sin secretos ni `SENSIBLE/`.

---

## 6. Decisiones tomadas y descartadas

- **Sí:** capas simultáneas e independientes (`landRoutesLayer` y `seaRoutesLayer`). Por qué: la comparación carretera vs marítima entre dos ciudades es el motivo de la herramienta.
- **Sí:** retirar `fitSeaRoutes` también para las marítimas. Por qué: decisión explícita del usuario — "el encuadre no se mueve al cargar ninguna capa". Consecuencia registrada: los criterios 185 de SPEC 005 (encuadre tras carga) y 176 (ID `#route-status`) quedan **superados** por esta spec; los documentos 005 y 006 no se editan, son registros históricos.
- **Sí:** un único validador `validateRoutes` sin discriminar por `meta.profile`. Por qué: decisión del usuario; evita que un fichero correcto se rechace por un error de botón y mantiene una sola implementación que mantener (DRY).
- **No:** rechazar `car_routes.json` en el botón marítimo. Por qué: sería una validación de intención, no de datos, y obligaría a mantener dos validadores.
- **Sí:** amarillo `#F9A825` con los mismos `weight 3`, `opacity 0.9`, `dashArray '8 12'` y animación `1.2s` que el azul. Por qué: recomendación aceptada; el color distingue el tipo y todo lo demás queda isomorfo, así que el código de estilo es único parametrizado.
- **No:** distinguir los tipos por movimiento (una animada, otra estática). Por qué: perdería coherencia visual sin aportar información que el color ya da.
- **Sí:** botón amarillo con texto negro `#1A1A1A` y borde `#E6A817`. Por qué: blanco sobre `#F9A825` no alcanza contraste AA.
- **Sí:** dos líneas de estado independientes bajo cada botón. Por qué: recomendación aceptada; una línea combinada obligaría a mirar dos cifras para saber el estado de una capa.
- **Sí:** botón terrestre encima del marítimo y capa terrestre encima de la marítima. Por qué: recomendación aceptada; de lo cercano a lo lejano en el panel y de lo terrestre a lo marítimo en el mapa.
- **Sí:** paneles personalizados con zIndex fijo en lugar de confiar en el orden de inserción. Por qué: con dos `layerGroup` el orden de dibujo depende de qué fichero se cargue primero; los paneles lo hacen determinista.
- **Sí:** popup único con `durationHours` opcional. Por qué: recomendación aceptada — el mismo código para los dos tipos y las horas solo cuando el fichero las trae; `heading` no se muestra porque el fichero ya lo conserva y añade ruido al popup.
- **Sí:** renombrar `#route-status` → `#sea-route-status` y `validateSeaRoutes` → `validateRoutes`. Por qué: con dos capas, un ID y una función genérica en singular son ambiguos.
- **No:** carga automática de `car_routes.json` al abrir. Por qué: el requisito pide carga manual y el fichero pesa 3,4 MB.
- **No:** toggle de visibilidad, leyenda de colores o lista de rutas. Por qué: mejoras de navegación; el usuario no las pidió y con dos botones el estado ya es explícito.
- **No:** persistir nada entre sesiones. Por qué: el visor es una herramienta de desarrollo de solo lectura.
- **Sí:** mantener `splitAntimeridian` para las dos capas aunque `car_routes.json` declare 0 cruces. Por qué: la función es gratis, ya está probada y protege ante regeneraciones futuras.
- **Sí:** apertura del visor en incognito/privada desde `serve_map.sh`, con fallback a `xdg-open` normal. Por qué: el usuario quiere evitar problemas de caché al reabrir el visor; si falta Chrome/Chromium/Firefox, mejor abrir sin incognito que no abrir.
- **Sí:** verificación con Chromium headless vía Playwright, como en SPEC 006. Por qué: 1001 polilíneas no se validan bien a ojo y hay precedente en el repo.

---

## 7. Riesgos identificados

| Riesgo | Mitigación |
| --- | --- |
| 1001 polilíneas con `stroke-dashoffset` animado pueden disparar el consumo de CPU | `prefers-reduced-motion` desactiva la animación; es una herramienta de desarrollo local; se verifica en Chromium headless y, si el rendimiento fuera miserable, la animación terrestre se puede desactivar sin tocar el resto (contingencia, no alcance). |
| Parsear 3,4 MB en el hilo principal puede congelar la interfaz un instante | `FileReader.readAsText` ya es asíncrono y el `JSON.parse` de 3,4 MB ronda las decenas de ms; se hace una sola vez por carga. |
| Dos `layerGroup` y dos renderers SVG pueden invertir el orden visual según qué fichero se cargue primero | Paneles dedicados con zIndex 401/402; el criterio "amarilla sobre azul" se comprueba cruzando rutas deliberadamente. |
| El validador compartido acepta un fichero cargado desde el botón "equivocado" | Es una decisión consciente (§6); el estado siempre nombra el botón usado, no el contenido. |
| Renombrar `#route-status` y `validateSeaRoutes` rompe referencias externas | Búsqueda previa: solo `index.html`, `app.js` y los textos históricos de SPEC 005 los mencionan; no hay tests JavaScript en el repo. |
| Retirar `fitSeaRoutes` contradice un criterio ya marcado como implementado en SPEC 005 | Queda registrado en §6 y en esta spec; SPEC 005 no se edita porque es un histórico. |
| `file://` sigue bloqueado por CORS para el `fetch` de ciudades | Comportamiento preexistente; los dos botones usan `FileReader` y funcionan igual. |

---

## 8. Lo que **no** está en esta especificación

- Carga automática de los ficheros de rutas o inclusión en `pubspec.yaml`.
- Generación, edición, exportación o persistencia de `car_routes.json`.
- Validación por `meta.profile` o rechazo de ficheros en el botón equivocado.
- Toggles de visibilidad, leyenda, lista de rutas, filtros por ruta o selección activa.
- Persistencia del fichero elegido, el zoom, el filtro o el estado de las capas.
- Renderizado de rutas en la app Flutter (`WorldMapWidget`, `PolylineLayer`, `TransportMode`).
- Cambios en la skill `fogg-land-routes`, en el dataset de ciudades o en SPEC 006.
- Edición de los documentos `docs/specs/005` y `docs/specs/006`.
- Capa nocturna, terminador solar o paridad con `WorldMapWidget`.

Cada uno, si aterriza, irá en su propia especificación.

---

## 9. Referencias

- `assets/data/car_routes.json:1` — 1001 rutas terrestres, esquema SPEC 006, `meta.profile == "car"`, 3,4 MB.
- `assets/data/sea_routes.json:1` — 210 rutas marítimas, esquema SPEC 004/005, coordenadas `[lng, lat]`.
- `docs/specs/005-visor-rutas-maritimas-animadas.md:174` — criterios de la capa marítima que esta spec extiende y en parte supera.
- `docs/specs/006-fog-car-routes.md:169` — criterio provisional de carga del fichero terrestre sin cambiar `app.js`.
- `tools/locations-map/index.html:24` — bloque `.route-loader` actual con el único botón marítimo.
- `tools/locations-map/app.js:44` — creación de `seaRoutesLayer`, `markerLayer` y `seaRouteStyle`.
- `tools/locations-map/app.js:85` — `validateSeaRoutes`, futuro `validateRoutes`.
- `tools/locations-map/app.js:163` — `splitAntimeridian`, compartido por las dos capas.
- `tools/locations-map/app.js:222` — `fitSeaRoutes`, que se elimina.
- `tools/locations-map/app.js:247` — `loadSeaRoutes`, base del flujo parametrizado.
- `tools/locations-map/app.js:489` — `window.__foggVisor`, que expondrá la capa terrestre.
- `tools/locations-map/style.css:140` — `.route-loader` y `.route-button` existentes.
- `tools/locations-map/style.css:206` — `.sea-route-line` y `seaRouteFlow`, plantilla de `.land-route-line`.
- `tools/locations-map/style.css:252` — breakpoint móvil.
- `README.md:16` — sección del visor a actualizar.
- Leaflet `1.9.4` — capas (`createPane`, zIndex) y `Path` en `https://leafletjs.com/reference.html`.

---

## 10. Preguntas abiertas (resueltas por esta especificación)

- Alcance limitado al visor standalone: no modifica la app Flutter — sí.
- Carga manual, ninguna capa por defecto — sí, para los dos tipos.
- Capas simultáneas e independientes — sí.
- Sin encuadre automático en ninguna carga (retira el de SPEC 005) — sí.
- Amarillo `#F9A825`, animación idéntica a la azul — sí, según recomendación.
- Dos estados independientes, uno por botón — sí, según recomendación.
- Un único validador, sin discriminar `meta.profile` — sí.
- Popup compartido con `durationHours` cuando exista; sin `heading` — sí, según recomendación.
- Botón terrestre encima del marítimo; capa terrestre encima de la marítima — sí, según recomendación.
- Documentación en `README.md` — sí.
- Próximo número de spec: `007`, slug `visor-rutas-terrestres`.
