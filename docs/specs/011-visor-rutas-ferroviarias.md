# SPEC 011 — Añadir botón de rutas ferroviarias al visor de rutas y ciudades

> **Estado:** Implementado

> **Depende de:** SPEC 003 (Visor locations.json), SPEC 005 (Visor de rutas marítimas animadas), SPEC 006 (Fogg Car Routes), SPEC 007 (Visor de rutas terrestres), SPEC 009 (Visor de rutas marítimas ficticias), SPEC 010 (Fogg Rail Routes)

> **Fecha:** 2026-10-10

> **Objetivo:** Ampliar el visor standalone con un cuarto botón "Cargar rutas ferroviarias", con sus propias líneas en color morado, permitiendo mostrar simultáneamente rutas terrestres (amarillas), marítimas reales (azules), marítimas ficticias (verdes) y ferroviarias (moradas), sin carga automática y sin mover la cámara.

---

## 1. Por qué existe esta especificación

Las especificaciones 007 y 009 dotaron al visor dev de tres capas independientes con colores diferenciados: rutas terrestres (`car_routes.json`, amarillo), rutas marítimas reales (`sea_routes.json`, azul) y rutas marítimas ficticias (`sea_routes_fiction.json`, verde). La SPEC 010 generó el trazado ferroviario real en `assets/data/rail_routes.json` (v1.0.0, 307 rutas de 103 orígenes) y dejó explícitamente fuera de su alcance "el botón, capa y color del visor `tools/locations-map` para rutas ferroviarias (spec propia, acordada)".

Esta es esa especificación. El ferrocarril es, en el juego, el modo lento y de larga distancia por excelencia; el visor necesita poder superponerlo a las demás capas para inspeccionar visualmente el catálogo ferroviario antes de que la app Flutter lo consuma. El visor debe seguir siendo puramente manual (sin carga automática) y sin encuadre al cargar ninguna capa.

---

## 2. Alcance

**En:**

- **Añade el botón "Cargar rutas ferroviarias" tras los botones existentes — `tools/locations-map/index.html:24-35` — carga manual de rutas de tren** — inserta el bloque `#load-rail-routes`, `#rail-routes-file` (oculto, `accept=".json,application/json"`) y `#rail-route-status` (inicial `0 rutas ferroviarias`, `aria-live="polite"`) inmediatamente **debajo** del bloque marítimo ficticio, dentro del mismo `.route-loader`. Los cuatro botones quedan apilados consecutivamente: terrestre → marítimo → marítimo ficticio → ferroviario.
  - **Orden en UI:** botón terrestre (amarillo), marítimo (azul), marítimo ficticio (verde), ferroviario (morado). El botón ferroviario recibe clase `route-button--rail` para aplicar estilo morado.
  - **Pista única:** el `<p class="hint">` existente se actualiza para mencionar también `rail_routes.json`, sin duplicar párrafos.

- **Dibuja las rutas ferroviarias en morado — `tools/locations-map/app.js` + `tools/locations-map/style.css` — capa `railRoutesLayer` independiente** — cada `LineString` del fichero cargado se convierte en una polilínea morada con el mismo patrón y animación que las demás.
  - **Estilo:** `className 'rail-route-line'`, color `#6A1B9A`, `weight 3`, `opacity 0.9`, `dashArray '8 12'`, `interactive: true`, asignado a `railRoutesPane`.
  - **Animación:** `railRouteFlow` con `stroke-dashoffset` en `1.2s` lineal infinita. Con `prefers-reduced-motion: reduce` conserva el patrón discontinuo y no se anima.
  - **Estado:** `#rail-route-status` muestra `0 rutas ferroviarias` antes de cargar y tras carga válida `${n} rutas ferroviarias · <nombre-fichero>`; el botón pasa a `Recargar rutas ferroviarias`.

- **Permite mostrar las cuatro capas simultáneamente — `tools/locations-map/app.js` — cuatro `layerGroup` independientes** — `landRoutesLayer`, `seaRoutesLayer`, `fakeSeaRoutesLayer` y `railRoutesLayer` conviven sin reemplazarse entre sí.
  - **Simultaneidad:** cargar cualquier fichero no borra las otras tres capas. El reemplazo atómico se aplica **únicamente** a la capa correspondiente al botón pulsado.
  - **Filtro:** el filtro de ciudades sigue afectando únicamente a `markerLayer` y a `#city-list`. Ninguna capa de rutas se limpia ni redibuja al filtrar.

- **Ordena las capas de forma determinista — `tools/locations-map/app.js` + `tools/locations-map/style.css` — morado por encima, manteniendo coherencia** — se añade un cuarto panel con zIndex fijo para que el orden visual no dependa del orden de carga.
  - **Paneles:** `seaRoutesPane` (zIndex 401), `landRoutesPane` (zIndex 402), `fakeSeaRoutesPane` (zIndex 403), `railRoutesPane` (zIndex 404). Todos por debajo de `markerPane` (600) y por encima de `tilePane` (200).
  - **Jerarquía visual recomendada:** las rutas ferroviarias (moradas) se dibujan por encima de las marítimas ficticias (verdes), las terrestres (amarillas) y las marítimas reales (azules), para que resulten claramente visibles cuando se solapan. Este orden se asegura mediante los paneles/zIndex indicados.
  - **Renderers:** cada estilo declara su propio `pane` y `renderer: L.svg({ pane: ... })`.

- **Reutiliza validación, normalización y popup — `tools/locations-map/app.js` — sin duplicar lógica** — se reutiliza `validateRoutes`, `normalizeRoutes`, `splitAntimeridian`, `createRouteLines`, `routePopup` y `loadRoutes(file, config)`.
  - **Popup compartido:** `routePopup` sigue mostrando `origen → destino`, `km · vértices` y añade `· X.X h` **únicamente** si `durationHours` existe (como ya hace SPEC 007). Las rutas ferroviarias comparten exactamente el mismo formato de popup.
  - **Campos ferroviarios ignorados a propósito:** `railOrigin`, `railDest`, `heading`, `explicit` y `meta.profile` **no se validan ni se muestran**. `validateRoutes` no rechaza campos desconocidos, así que `rail_routes.json` se acepta tal cual.
  - **Sin discriminación por contenido:** igual que SPEC 007/009, un fichero cargado desde el botón "equivocado" se aceptará y se pintará con el color del botón usado. El estado nombra siempre el botón/capa, no el contenido.

- **Mantiene el comportamiento sin encuadre — `tools/locations-map/app.js` — cámara inalterada** — no se añade ninguna llamada a `fitBounds`. Cargar rutas ferroviarias deja `center` y `zoom` intactos (coherente con SPEC 007).

- **Expone estado en `window.__foggVisor` — `tools/locations-map/app.js:586-610` — getters para la cuarta capa** — se añaden `get railRoutes()`, `get railRouteFileName()`, `get railRouteError()` y `railRoutesLayer` al objeto expuesto, manteniendo el resto intacto.

- **Actualiza documentación — `README.md:22-28` — instrucciones del visor** — la sección "Visor locations.json (solo dev)" documenta los cuatro botones, ficheros esperados, colores (terrestre amarillo `#F9A825`, marítimo azul `#1E88E5`, marítimo ficticio verde `#2E7D32`, ferroviario morado `#6A1B9A`) y que no hay encuadre automático.

**Compartido:** Leaflet `1.9.4` y renderer SVG; `escapeHtml`; `validateRoutes`/`normalizeRoutes`/`splitAntimeridian`/`routePopup`/`createRouteLines`/`loadRoutes`; flujo de ciudades/drag&drop sin cambios; tokens existentes de `style.css`. Sin nuevas dependencias. No se modifica `lib/`, `pubspec.yaml`, `web/`, `assets/data/`, ni skills de generación de rutas. No se edita `docs/specs/005`, `docs/specs/006`, `docs/specs/007` ni `docs/specs/009` (registros históricos).

**Fuera del alcance (para futuras especificaciones):**

- Carga automática de ningún fichero de rutas, `fetch` desde assets o inclusión en `pubspec.yaml`.
- Generar, recalcular, editar o exportar rutas ferroviarias desde el navegador.
- Distinguir por `meta.profile` y rechazar ficheros en el botón "equivocado".
- Mostrar el enganche a la vía (`railOrigin.snapKm`/`railDest.snapKm`) o el `heading` en el popup.
- Toggles de visibilidad por capa, leyenda de colores, lista lateral de rutas, filtros por origen/destino/distancia/texto.
- Persistir en `localStorage`/`IndexedDB` el fichero seleccionado, zoom, filtro o estado de capas.
- Integrar rutas ferroviarias en la app Flutter (`WorldMapWidget`, `PolylineLayer`, `TransportMode.train`).
- Cambiar la lógica de generación de `fogg-rail-routes` o editar `assets/data/rail_routes.json`.
- Integrar la capa nocturna/terminador solar en el visor.

---

## 3. Modelo de datos

Esta especificación no introduce entidades persistidas. Reutiliza el **mismo contrato** que `car_routes.json`/`sea_routes.json` (SPEC 004/006). El fichero ferroviario esperado es `assets/data/rail_routes.json` (SPEC 010), cargado manualmente vía `FileReader`.

### 3.1 Contrato esperado (idéntico a terrestres, con campos ferroviarios extra)

```json
{
  "meta": { "project": "eu.elarreglador.pf", "name": "...", "profile": "non_tgv", "units": "km" },
  "routes": [
    {
      "origin": "Lisboa",
      "originLat": 38.72509,
      "originLng": -9.1498,
      "destination": "Madrid",
      "destinationLat": 40.4165,
      "destinationLng": -3.70256,
      "distanceKm": 687.7,
      "durationHours": 6.3,
      "heading": "east",
      "railOrigin": { "lat": 38.71395, "lng": -9.12247, "snapKm": 3.4 },
      "railDest": { "lat": 40.40661, "lng": -3.69061, "snapKm": 2.1 },
      "geometry": { "type": "LineString", "coordinates": [[-9.1498, 38.72509], [4.34878, 50.85045]] }
    }
  ]
}
```

**Reglas del visor:**

- `validateRoutes` aplica las mismas reglas: objeto con `routes` no vacío; `origin`/`destination` no vacíos; `distanceKm > 0`; extremos/coordenadas en rango Mercator; `geometry.type === 'LineString'` con ≥ 2 pares.
- `durationHours` es **opcional**. Si existe, debe ser número finito > 0. Si no existe, el popup lo omite. `rail_routes.json` siempre lo trae (SPEC 010).
- `coordinates` en `[lng, lat]` (GeoJSON). `splitAntimeridian` se aplica igual.
- `railOrigin`, `railDest`, `heading`, `explicit` y `meta.profile` **se ignoran**: no se validan ni se pintan.
- `meta.profile` **no se valida**.

### 3.2 Estado efímero

```js
const landRoutesLayer     = L.layerGroup().addTo(map);
const seaRoutesLayer      = L.layerGroup().addTo(map);
const fakeSeaRoutesLayer  = L.layerGroup().addTo(map);
const railRoutesLayer     = L.layerGroup().addTo(map);
const markerLayer         = L.layerGroup().addTo(map);

let loadedLandRoutes = [];
let loadedLandRouteFileName = null;
let landRouteLoadError = null;

let loadedSeaRoutes = [];
let loadedSeaRouteFileName = null;
let seaRouteLoadError = null;

let loadedFakeSeaRoutes = [];
let loadedFakeSeaRouteFileName = null;
let fakeSeaRouteLoadError = null;

let loadedRailRoutes = [];
let loadedRailRouteFileName = null;
let railRouteLoadError = null;
```

### 3.3 Estilos por capa

```js
const railRouteStyle = {
  pane: 'railRoutesPane',
  renderer: L.svg({ pane: 'railRoutesPane' }),
  className: 'rail-route-line',
  color: '#6A1B9A',
  weight: 3,
  opacity: 0.9,
  dashArray: '8 12',
  interactive: true,
};
```

### 3.4 Configuración parametrizada

Se añade `railRouteConfig` con misma forma que las otras tres:

```js
const railRouteConfig = {
  layer: railRoutesLayer,
  style: railRouteStyle,
  label: 'rutas ferroviarias',
  errorLabel: 'Rutas ferroviarias inválidas',
  statusEl: railRouteStatus,
  buttonEl: loadRailRoutesButton,
  loadText: 'Cargar rutas ferroviarias',
  reloadText: 'Recargar rutas ferroviarias',
  get routes() { return loadedRailRoutes; },
  get fileName() { return loadedRailRouteFileName; },
  setLoaded(routes, fileName) { loadedRailRoutes = routes; loadedRailRouteFileName = fileName; },
  setError(error) { railRouteLoadError = error; },
};
```

Listeners: `#load-rail-routes` abre `#rail-routes-file`; cambio llama `loadRoutes(f, railRouteConfig)` y limpia `e.target.value = ''`.

---

## 4. Plan de implementación

Cada paso deja el visor ejecutable con las tres capas existentes operativas.

1. **Actualiza HTML — `tools/locations-map/index.html` — añade cuarto botón y estado**
   Inserta el bloque ferroviario inmediatamente debajo del bloque marítimo ficticio dentro de `.route-loader`: `button#load-rail-routes` con clase `route-button route-button--rail`, `input#rail-routes-file` oculto con `accept=".json,application/json"`, `div#rail-route-status` con `aria-live="polite"` inicial `0 rutas ferroviarias`. Actualiza el `<p class="hint">` para mencionar `rail_routes.json`. Mantén los tres bloques existentes tal como quedan tras SPEC 009.

2. **Añade refs en JS — `tools/locations-map/app.js` — referencias a nuevos elementos**
   Lee `document.getElementById('rail-routes-file')`, `document.getElementById('load-rail-routes')`, `document.getElementById('rail-route-status')`. Inicializa `updateRouteStatus` también para la config ferroviaria (paso 5).

3. **Crea panel y capa ferroviaria — `tools/locations-map/app.js` — orden determinista**
   `map.createPane('railRoutesPane').style.zIndex = 404`. Declara `const railRoutesLayer = L.layerGroup().addTo(map)`. Añade `railRouteStyle` con `pane: 'railRoutesPane'`, `renderer: L.svg({ pane: 'railRoutesPane' })`, `className: 'rail-route-line'`, `color: '#6A1B9A'`.

4. **Añade estado y config ferroviarios — `tools/locations-map/app.js` — variables + config**
   Añade `loadedRailRoutes`, `loadedRailRouteFileName`, `railRouteLoadError`. Define `railRouteConfig` con getters/setters y textos `Cargar rutas ferroviarias` / `Recargar rutas ferroviarias`, `label: 'rutas ferroviarias'`, `errorLabel: 'Rutas ferroviarias inválidas'`.

5. **Inicializa estado y listeners — `tools/locations-map/app.js` — conecta UI**
   Llama `updateRouteStatus(railRouteConfig)` tras `updateRouteStatus(fakeSeaRouteConfig)`. Añade `loadRailRoutesButton.addEventListener('click', ...)` abriendo `railRoutesFileInput`. Añade `railRoutesFileInput.addEventListener('change', ...)` llamando `loadRoutes(f, railRouteConfig)` y limpiando `e.target.value = ''`.

6. **Expón en API global — `tools/locations-map/app.js:586-610` — añade getters/layer**
   Amplía `window.__foggVisor` con `get railRoutes()`, `get railRouteFileName()`, `get railRouteError()`, `railRoutesLayer`. No elimines ni renombres existentes.

7. **Estilos CSS — `tools/locations-map/style.css` — botón morado + línea morada + animación**
   Añade `.route-button--rail { background: #6A1B9A; color: #fff; border-color: #4A148C; }` y `.route-button--rail:hover { background: #4A148C; border-color: #311B92; }` y su `:focus-visible`.
   Añade `.rail-route-line { stroke-dashoffset: 0; animation: railRouteFlow 1.2s linear infinite; }` y `@keyframes railRouteFlow { from { stroke-dashoffset: 0; } to { stroke-dashoffset: -20; } }`.
   Amplía la regla `@media (prefers-reduced-motion: reduce)` existente para incluir `.rail-route-line`.

8. **Actualiza README — `README.md:22-28` — documenta cuarto botón**
   Actualiza la sección del visor: explica los cuatro botones, fichero esperado por cada uno, colores (`#F9A825`, `#1E88E5`, `#2E7D32`, `#6A1B9A`) y ausencia de encuadre automático. Ajusta la nota de `durationHours` para mencionar que hoy lo traen el terrestre y el ferroviario.

9. **Verificación — navegador + análisis + tests**
   Abre con `./tools/serve_map.sh` (incognito) y comprueba: cuatro botones apilados, estados iniciales correctos. Carga los cuatro ficheros (`car_routes.json`, `sea_routes.json`, `sea_routes_fiction.json`, `rail_routes.json`) y comprueba convivencia, orden visual (morado por encima), popup compartido, sin movimiento de cámara.
   Ejecuta `flutter analyze` y `flutter test`. Verifica que solo se tocan `tools/locations-map/index.html`, `tools/locations-map/app.js`, `tools/locations-map/style.css`, `README.md` y `docs/specs/011-visor-rutas-ferroviarias.md`.

---

## 5. Criterios de aceptación

- [x] `tools/locations-map/index.html` contiene `button#load-rail-routes` con clase `route-button--rail`, `input#rail-routes-file` con `accept=".json,application/json"` oculto y `#rail-route-status` con texto inicial `0 rutas ferroviarias`. El bloque se sitúa **inmediatamente debajo** del bloque marítimo ficticio, dentro de `.route-loader`. Los cuatro botones aparecen consecutivos y apilados.
- [x] Los estados existentes `#land-route-status`, `#sea-route-status` y `#fake-sea-route-status` se mantienen sin cambios de comportamiento.
- [x] Al abrir el visor no se emite ninguna petición de lectura de ficheros de rutas. Las cuatro capas empiezan vacías. El mapa permanece en `center [20,0]`, `zoom 2`.
- [x] Seleccionar `assets/data/rail_routes.json` desde `#load-rail-routes` dibuja tantas polilíneas como elementos tenga `routes` (307). `#rail-route-status` muestra `${count} rutas ferroviarias · <nombre-fichero>`. El botón pasa a `Recargar rutas ferroviarias`.
- [x] Tras cargar los cuatro ficheros, las cuatro capas son visibles **simultáneamente**. Cargar cada uno **no borra** las otras tres.
- [x] Las rutas ferroviarias usan color `#6A1B9A`, `weight 3`, `opacity 0.9`, `dashArray '8 12'`, clase `rail-route-line`. Las terrestres mantienen `#F9A825`/`land-route-line`. Las marítimas reales mantienen `#1E88E5`/`sea-route-line`. Las marítimas ficticias mantienen `#2E7D32`/`fake-sea-route-line`.
- [x] Cuando se solapan rutas de distintas capas, las ferroviarias (moradas) se dibujan **por encima** de las ficticias (verdes), las terrestres (amarillas) y las marítimas reales (azules). Los markers rojos siguen **siempre por encima** de las cuatro capas.
- [x] El patrón discontinuo de las cuatro capas se desplaza en `1.2s` lineal infinito. Con `prefers-reduced-motion: reduce`, las cuatro capas permanecen visibles con patrón discontinuo pero **sin animación**.
- [x] Cargar `rail_routes.json` deja `center` y `zoom` intactos. No existe ninguna llamada a `fitBounds` en `tools/locations-map/app.js`.
- [x] El popup de rutas ferroviarias muestra `origen → destino`, `distancia km · X.X h · vértices` (el fichero siempre trae `durationHours`). Todos los valores se escapan con `escapeHtml`.
- [x] Hover sobre cualquier ruta (de las cuatro capas) cambia `weight` a `5` y al salir vuelve a `3`, sin crear capas adicionales.
- [x] JSON inválido (estructura, rangos, geometría < 2 puntos, `durationHours <= 0`, etc.) muestra banner de error y **conserva exactamente** la última carga válida de **esa misma capa**. Las otras tres capas no se modifican.
- [x] `validateRoutes` se reutiliza sin discriminar `meta.profile` y sin validar `railOrigin`/`railDest`/`heading`/`explicit`. `rail_routes.json` (que los incluye) se acepta sin cambios en la lógica de validación.
- [x] `splitAntimeridian` se aplica a las cuatro capas.
- [x] El filtro de ciudades actualiza lista y markers sin ocultar/limpiar/redibujar ninguna de las cuatro capas de rutas.
- [x] Panel usable en `320px` y breakpoint móvil (`style.css:291`): los cuatro botones se apilan sin scroll horizontal.
- [x] `README.md` documenta los cuatro botones, fichero esperado por cada uno, colores correspondientes y ausencia de encuadre.
- [x] Chromium headless (Playwright) carga visor, cuatro ficheros y filtro sin errores de consola ni banners inesperados.
- [x] `flutter analyze` y `flutter test` finalizan correctamente. No se modifican `pubspec.yaml`, `lib/`, `web/`, `assets/data/`, ni skills de generación de rutas.
- [x] Solo se tocan: `tools/locations-map/index.html`, `tools/locations-map/app.js`, `tools/locations-map/style.css`, `README.md`, `docs/specs/011-visor-rutas-ferroviarias.md`.
- [x] `window.__foggVisor` expone `railRoutes`, `railRouteFileName`, `railRouteError`, `railRoutesLayer`.

---

## 6. Decisiones tomadas y descartadas

- **Sí:** solo el visor dev `tools/locations-map/`. Por qué: es donde ya viven las capas terrestre/marítima/ficticia; el mapa Flutter aún no dibuja rutas y su integración es una spec mayor y separada.
- **Sí:** cuarto botón independiente con su propia capa `railRoutesLayer`. Por qué: permite comparar cuatro conjuntos simultáneamente sin mezclar lógicas.
- **Sí:** color morado `#6A1B9A` para rutas ferroviarias. Por qué: máxima separación cromática frente al amarillo (`#F9A825`), azul (`#1E88E5`), verde (`#2E7D32`) y el rojo de marcador (`#C0392B`). Texto blanco con borde `#4A148C`/`#311B92` para contraste legible.
- **Sí:** panel `railRoutesPane` con zIndex 404 (por encima de ficticias 403, tierra 402 y mar 401). Por qué: hace determinista el orden visual; el ferrocarril queda "encima" para máxima visibilidad al solaparse.
- **Sí:** reutilizar `loadRoutes`, `validateRoutes`, `normalizeRoutes`, `routePopup`. Por qué: DRY, coherente con SPEC 007/009. No se duplica código. `validateRoutes` ya acepta `rail_routes.json` sin cambios.
- **Sí:** ignorar `railOrigin`/`railDest`/`heading`/`explicit` y `meta.profile`. Por qué: el popup compartido ya basta; mostrar `snapKm` añadiría lógica específica de un modo, contra el patrón DRY de las otras capas.
- **No:** validar `meta.profile`. Por qué: decisión coherente con SPEC 007/009 (evita rechazos por botón equivocado). El estado identifica la capa.
- **No:** renombrar nada existente. Por qué: mínimos cambios, bajo riesgo.
- **No:** añadir toggle/leyenda/lista. Por qué: fuera de alcance; cuatro botones ya hacen explícito el estado.
- **No:** carga automática ni persistencia. Por qué: visor dev manual y efímero.
- **No:** integrar con Flutter. Por qué: se mantiene acotado al visor standalone `tools/locations-map/`.
- **Sí:** definición directa sin aclaración sección por sección. Por qué: encargo explícito del Señor ("implementa el documento hasta finalizarlo") y decisiones ya cerradas en la fase de preguntas.

---

## 7. Riesgos identificados

| Riesgo | Mitigación |
|---|---|
| Cuarto conjunto de polilíneas añade carga de renderizado (307 rutas, ~1,9 MB) | Cuatro capas independientes con SVG renderer; `prefers-reduced-motion` desactiva animación. Verificación headless con el fichero real. |
| Confusión entre "ferroviarias" y "terrestres" en UI | Etiquetas claras: `Cargar rutas ferroviarias` vs `Cargar rutas terrestres`; estados independientes con `label` explícito y color morado distinto. |
| Invertir orden visual por carga | Paneles con zIndex fijos (401/402/403/404). Criterio verifica morado por encima cruzando rutas. |
| Regresión en capas existentes | No se toca lógica de `seaRoutesLayer`/`landRoutesLayer`/`fakeSeaRoutesLayer` salvo añadir nueva config/capa; reutilización estricta de código probado. |
| `rail_routes.json` trae campos que `validateRoutes` no conoce | `validateRoutes` no rechaza campos desconocidos (verificado en `app.js:168-233`); se acepta tal cual. Criterio de aceptación lo verifica con el fichero real. |
| CSS/animación nueva | Clave `railRouteFlow` aislada; regla `prefers-reduced-motion: reduce` ampliada. |

---

## 8. Lo que **no** está en esta especificación

- Carga automática, `fetch` de assets o inclusión en `pubspec.yaml`.
- Generación, edición o exportación de rutas ferroviarias.
- Validación por `meta.profile` o rechazo en botón equivocado.
- Mostrar `railOrigin.snapKm`/`railDest.snapKm` o `heading` en el popup.
- Toggles, leyenda, lista lateral, filtros por ruta.
- Persistencia entre sesiones.
- Renderizado en app Flutter.
- Cambios en la skill `fogg-rail-routes` o en `assets/data/rail_routes.json`.
- Edición de SPEC 005/006/007/009.
- Capa nocturna/terminador solar.

Cada uno, si aterriza, irá en su propia especificación.

---

## 9. Referencias

- `tools/locations-map/index.html:24-35` — bloque actual con botones terrestre+marítimo+ficticio (SPEC 007/009).
- `tools/locations-map/app.js:44-49` — paneles zIndex.
- `tools/locations-map/app.js:55-141` — capas, estilos y configs.
- `tools/locations-map/app.js:168-233` — `validateRoutes` compartido (acepta campos desconocidos).
- `tools/locations-map/app.js:250-289` — `splitAntimeridian` + `normalizeRoutes`.
- `tools/locations-map/app.js:291-299` — `routePopup` con `durationHours` opcional.
- `tools/locations-map/app.js:319-345` — `loadRoutes` parametrizado.
- `tools/locations-map/app.js:544-577` — listeners + `updateRouteStatus`.
- `tools/locations-map/app.js:586-610` — `window.__foggVisor`.
- `tools/locations-map/style.css:146-178` — estilos de botones.
- `tools/locations-map/style.css:224-259` — líneas + animaciones + `prefers-reduced-motion`.
- `tools/locations-map/style.css:291+` — breakpoint móvil.
- `docs/specs/007-visor-rutas-terrestres.md` / `docs/specs/009-visor-rutas-maritimas-ficticias.md` — referencias de implementación a extender.
- `docs/specs/010-fogg-rail-routes.md:69` — deja fuera esta spec explícitamente.
- `assets/data/rail_routes.json` — dataset v1.0.0 (SPEC 010).
- Leaflet 1.9.4 panes: https://leafletjs.com/reference.html#map-createpane

---

## 10. Preguntas abiertas (resueltas)

- ¿Dónde? → Solo la tool visor `tools/locations-map/`.
- ¿Color? → Morado `#6A1B9A`.
- ¿Orden visual capas? → Ferroviarias por encima (zIndex 404).
- ¿Compartir validación/popup? → Sí, reutilizar tal cual; ignorar campos ferroviarios extra.
- ¿Carga/cámara? → Manual, sin carga automática ni `fitBounds`.
- ¿Nombre del botón? → "Cargar rutas ferroviarias".
- ¿Añadir clase CSS específica? → `route-button--rail`, `rail-route-line`, `railRouteFlow`.
- ¿Exponer en visor global? → Sí, con getters + layer.
- ¿Actualizar README? → Sí.

**Número:** 011. **Slug:** visor-rutas-ferroviarias.
