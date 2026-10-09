# SPEC 009 — Añadir botón de rutas marítimas ficticias al visor de rutas y ciudades

> **Estado:** Implementado

> **Depende de:** SPEC 003 (Visor locations.json), SPEC 005 (Visor de rutas marítimas animadas), SPEC 006 (Fogg Car Routes), SPEC 007 (Visor de rutas terrestres)

> **Fecha:** 2026-10-08

> **Objetivo:** Ampliar el visor standalone para añadir un tercer botón "Cargar rutas marítimas ficticias", con sus propias líneas en color verde, permitiendo mostrar simultáneamente rutas terrestres (amarillas), rutas marítimas reales (azules) y rutas marítimas ficticias (verdes), sin carga automática y sin mover la cámara.

---

## 1. Por qué existe esta especificación

SPEC 007 añadió dos botones (terrestres y marítimas) con capas independientes y colores diferenciados (amarillo y azul), permitiendo comparar ambos tipos simultáneamente. Ahora se precisa un tercer conjunto: **rutas marítimas ficticias**.

Estas rutas ficticias comparten el mismo esquema JSON que las rutas marítimas reales (`sea_routes.json`), pero representan trayectos hipotéticos o alternativos. Deben tener identidad visual propia (color verde) y convivir con las otras dos capas sin reemplazarse entre sí. El visor debe seguir siendo puramente manual (sin carga automática) y sin encuadre al cargar ninguna capa.

---

## 2. Alcance

**En:**

- **Añade el botón "Cargar rutas marítimas ficticias" tras los botones existentes — `tools/locations-map/index.html:24-32` — carga manual de rutas ficticias** — inserta el bloque `#load-fake-sea-routes`, `#fake-sea-routes-file` (oculto, `accept=".json,application/json"`) y `#fake-sea-route-status` (inicial `0 rutas marítimas ficticias`, `aria-live="polite"`) inmediatamente **debajo** del bloque marítimo, dentro del mismo `.route-loader`. Los tres botones quedan apilados consecutivamente: terrestre → marítimo → marítimo ficticio.
  - **Orden en UI:** botón terrestre (amarillo), botón marítimo (azul por defecto), botón marítimo ficticio (verde). El botón ficticio recibe clase `route-button--fake-sea` para aplicar estilo verde.
  - **Pista única:** el `<p class="hint">` existente se mantiene y sigue mencionando `sea_routes.json` y `car_routes.json`; si se desea mencionar también el fichero ficticio, se actualiza sin duplicar párrafos.

- **Dibuja las rutas ficticias en verde — `tools/locations-map/app.js` + `tools/locations-map/style.css` — capa `fakeSeaRoutesLayer` independiente** — cada `LineString` del fichero cargado se convierte en una polilínea verde con el mismo patrón y animación que las demás.
  - **Estilo:** `className 'fake-sea-route-line'`, color `#2E7D32`, `weight 3`, `opacity 0.9`, `dashArray '8 12'`, `interactive: true`, asignado a `fakeSeaRoutesPane`.
  - **Animación:** `fakeSeaRouteFlow` con `stroke-dashoffset` en `1.2s` lineal infinita. Con `prefers-reduced-motion: reduce` conserva el patrón discontinuo y no se anima.
  - **Estado:** `#fake-sea-route-status` muestra `0 rutas marítimas ficticias` antes de cargar y tras carga válida `${n} rutas marítimas ficticias · <nombre-fichero>`; el botón pasa a `Recargar rutas marítimas ficticias`.

- **Permite mostrar las tres capas simultáneamente — `tools/locations-map/app.js` — tres `layerGroup` independientes** — `landRoutesLayer`, `seaRoutesLayer` y `fakeSeaRoutesLayer` conviven sin reemplazarse entre sí.
  - **Simultaneidad:** cargar cualquier fichero no borra las otras dos capas. El reemplazo atómico se aplica **únicamente** a la capa correspondiente al botón pulsado.
  - **Filtro:** el filtro de ciudades sigue afectando únicamente a `markerLayer` y a `#city-list`. Ninguna capa de rutas se limpia ni redibuja al filtrar.

- **Ordena las capas de forma determinista — `tools/locations-map/app.js` + `tools/locations-map/style.css` — verde por encima, manteniendo coherencia** — se crean tres paneles con zIndex fijos para que el orden visual no dependa del orden de carga.
  - **Paneles:** `seaRoutesPane` (zIndex 401), `landRoutesPane` (zIndex 402), `fakeSeaRoutesPane` (zIndex 403). Todos por debajo de `markerPane` (600) y por encima de `tilePane` (200).
  - **Jerarquía visual recomendada:** las rutas marítimas ficticias (verdes) se dibujan por encima de las terrestres (amarillas) y de las marítimas reales (azules), para que resulten claramente visibles cuando se solapan. Este orden se asegura mediante los paneles/zIndex indicados.
  - **Renderers:** cada estilo declara su propio `pane` y `renderer: L.svg({ pane: ... })`.

- **Reutiliza validación, normalización y popup — `tools/locations-map/app.js` — sin duplicar lógica** — se reutiliza `validateRoutes`, `normalizeRoutes`, `splitAntimeridian`, `createRouteLines`, `routePopup` y `loadRoutes(file, config)`.
  - **Popup compartido:** `routePopup` sigue mostrando `origen → destino`, `km · vértices` y añade `· X.X h` **únicamente** si `durationHours` existe (como ya hace SPEC 007). Las rutas ficticias comparten exactamente el mismo formato de popup.
  - **Sin discriminación por contenido:** al igual que SPEC 007, no se valida `meta.profile`. Un fichero cargado desde el botón "equivocado" se aceptará y se pintará con el color del botón usado. El estado nombra siempre el botón/capa, no el contenido.

- **Mantiene el comportamiento sin encuadre — `tools/locations-map/app.js` — cámara inalterada** — no se añade ninguna llamada a `fitBounds`. Cargar rutas ficticias deja `center` y `zoom` intactos (coherente con SPEC 007).

- **Expone estado en `window.__foggVisor` — `tools/locations-map/app.js:543` — getters para la tercera capa** — se añaden `get fakeSeaRoutes()`, `get fakeSeaRouteFileName()`, `get fakeSeaRouteError()` y `fakeSeaRoutesLayer` al objeto expuesto, manteniendo el resto intacto.

- **Actualiza documentación — `README.md:16-28` — instrucciones del visor** — la sección "Visor locations.json (solo dev)" documenta los tres botones, ficheros esperados, colores (terrestre amarillo `#F9A825`, marítimo azul `#1E88E5`, marítimo ficticio verde `#2E7D32`) y que no hay encuadre automático.

**Compartido:** Leaflet `1.9.4` y renderer SVG; `escapeHtml`; flujo de ciudades/drag&drop sin cambios; `splitAntimeridian`; tokens existentes de `style.css`. Sin nuevas dependencias. No se modifica `lib/`, `pubspec.yaml`, `web/`, `assets/data/`, ni skills de generación de rutas. No se edita `docs/specs/005`, `docs/specs/006`, `docs/specs/007` (registros históricos).

**Fuera del alcance (para futuras especificaciones):**
- Carga automática de ningún fichero de rutas, `fetch` desde assets o inclusión en `pubspec.yaml`.
- Generar, recalcular, editar o exportar rutas ficticias desde el navegador.
- Distinguir por `meta.profile` y rechazar ficheros en el botón "equivocado".
- Toggles de visibilidad por capa, leyenda de colores, lista lateral de rutas, filtros por origen/destino/distancia/texto.
- Persistir en `localStorage`/`IndexedDB` el fichero seleccionado, zoom, filtro o estado de capas.
- Integrar rutas ficticias en la app Flutter (`WorldMapWidget`, `PolylineLayer`, `TransportMode`).
- Cambiar lógica de generación en skills existentes.
- Integrar capa nocturna/terminador solar.
- Crear un dataset concreto de rutas ficticias (solo se añade la UI para cargarlo).

---
## 3. Modelo de datos

Esta especificación no introduce entidades persistidas. Reutiliza el **mismo contrato** que `sea_routes.json` (SPEC 004/005). El fichero de rutas ficticias puede tener cualquier nombre (p.ej. `sea_routes_fake.json`, `fake_sea_routes.json`) y se carga manualmente vía `FileReader`.

### 3.1 Contrato esperado (idéntico a marítimas)

```json
{
  "meta": { "project": "eu.elarreglador.pf", "name": "...", "profile": "...", "units": "km" },
  "routes": [
    {
      "origin": "Londres",
      "originLat": 51.50853,
      "originLng": -0.12574,
      "destination": "Bruselas",
      "destinationLat": 50.85045,
      "destinationLng": 4.34878,
      "distanceKm": 370.2,
      "durationHours": 4.6,
      "geometry": { "type": "LineString", "coordinates": [[-0.12574, 51.50853], [4.34878, 50.85045]] }
    }
  ]
}
```

**Reglas del visor:**

- `validateRoutes` aplica las mismas reglas: objeto con `routes` no vacío; `origin`/`destination` no vacíos; `distanceKm > 0`; extremos/coordenadas en rango Mercator; `geometry.type === 'LineString'` con ≥ 2 pares.
- `durationHours` es **opcional**. Si existe, debe ser número finito > 0. Si no existe, el popup lo omite.
- `coordinates` en `[lng, lat]` (GeoJSON). `splitAntimeridian` se aplica igual.
- `meta.profile` **no se valida**.

### 3.2 Estado efímero

```js
const landRoutesLayer     = L.layerGroup().addTo(map);
const seaRoutesLayer      = L.layerGroup().addTo(map);
const fakeSeaRoutesLayer  = L.layerGroup().addTo(map);
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
```

### 3.3 Estilos por capa

```js
const fakeSeaRouteStyle = {
  pane: 'fakeSeaRoutesPane',
  renderer: L.svg({ pane: 'fakeSeaRoutesPane' }),
  className: 'fake-sea-route-line',
  color: '#2E7D32',
  weight: 3,
  opacity: 0.9,
  dashArray: '8 12',
  interactive: true,
};
```

### 3.4 Configuración parametrizada

Se añade `fakeSeaRouteConfig` con misma forma que `seaRouteConfig`/`landRouteConfig`:

```js
const fakeSeaRouteConfig = {
  layer: fakeSeaRoutesLayer,
  style: fakeSeaRouteStyle,
  label: 'rutas marítimas ficticias',
  errorLabel: 'Rutas marítimas ficticias inválidas',
  statusEl: fakeSeaRouteStatus,
  buttonEl: loadFakeSeaRoutesButton,
  loadText: 'Cargar rutas marítimas ficticias',
  reloadText: 'Recargar rutas marítimas ficticias',
  get routes() { return loadedFakeSeaRoutes; },
  get fileName() { return loadedFakeSeaRouteFileName; },
  setLoaded(routes, fileName) { loadedFakeSeaRoutes = routes; loadedFakeSeaRouteFileName = fileName; },
  setError(error) { fakeSeaRouteLoadError = error; },
};
```

Listeners: `#load-fake-sea-routes` abre `#fake-sea-routes-file`; cambio llama `loadRoutes(f, fakeSeaRouteConfig)` y limpia `e.target.value = ''`.

---
## 4. Plan de implementación

Cada paso deja el visor ejecutable con las dos capas existentes operativas.

1. **Actualiza HTML — `tools/locations-map/index.html` — añade tercer botón y estado**  
   Inserta el bloque ficticio inmediatamente debajo del bloque marítimo dentro de `.route-loader`: `button#load-fake-sea-routes` con clase `route-button route-button--fake-sea`, `input#fake-sea-routes-file` oculto con `accept=".json,application/json"`, `div#fake-sea-route-status` con `aria-live="polite"` inicial `0 rutas marítimas ficticias`. Mantén `#sea-route-status` y `#land-route-status` tal como quedan tras SPEC 007. No añadas párrafos extra innecesarios.

2. **Añade refs en JS — `tools/locations-map/app.js` — referencias a nuevos elementos**  
   Lee `document.getElementById('fake-sea-routes-file')`, `document.getElementById('load-fake-sea-routes')`, `document.getElementById('fake-sea-route-status')`. Inicializa `updateRouteStatus` también para la config ficticia (paso 5).

3. **Crea panel y capa ficticia — `tools/locations-map/app.js` — orden determinista**  
   `map.createPane('fakeSeaRoutesPane').style.zIndex = 403`. Declara `const fakeSeaRoutesLayer = L.layerGroup().addTo(map)`. Añade `fakeSeaRouteStyle` con `pane: 'fakeSeaRoutesPane'`, `renderer: L.svg({ pane: 'fakeSeaRoutesPane' })`, `className: 'fake-sea-route-line'`, `color: '#2E7D32'`.

4. **Añade estado y config ficticios — `tools/locations-map/app.js` — variables + config**  
   Añade `loadedFakeSeaRoutes`, `loadedFakeSeaRouteFileName`, `fakeSeaRouteLoadError`. Define `fakeSeaRouteConfig` con getters/setters y textos `Cargar rutas marítimas ficticias` / `Recargar rutas marítimas ficticias`, `label: 'rutas marítimas ficticias'`, `errorLabel: 'Rutas marítimas ficticias inválidas'`.

5. **Inicializa estado y listeners — `tools/locations-map/app.js` — conecta UI**  
   Llama `updateRouteStatus(fakeSeaRouteConfig)` tras `updateRouteStatus(landRouteConfig)`. Añade `loadFakeSeaRoutesButton.addEventListener('click', ...)` abriendo `fakeSeaRoutesFileInput`. Añade `fakeSeaRoutesFileInput.addEventListener('change', ...)` llamando `loadRoutes(f, fakeSeaRouteConfig)` y limpiando `e.target.value = ''`.

6. **Expón en API global — `tools/locations-map/app.js:543` — añade getters/layer**  
   Amplía `window.__foggVisor` con `get fakeSeaRoutes()`, `get fakeSeaRouteFileName()`, `get fakeSeaRouteError()`, `fakeSeaRoutesLayer`. No elimines ni renombres existentes.

7. **Estilos CSS — `tools/locations-map/style.css` — botón verde + línea verde + animación**  
   Añade `.route-button--fake-sea { background: #2E7D32; color: #fff; border-color: #1B5E20; }` y `.route-button--fake-sea:hover { background: #1B5E20; border-color: #0D3F12; }`.  
   Añade `.fake-sea-route-line { stroke-dashoffset: 0; }` (hereda comportamiento base) y `@keyframes fakeSeaRouteFlow { to { stroke-dashoffset: -48; } }` con `.fake-sea-route-line { animation: fakeSeaRouteFlow 1.2s linear infinite; }`.  
   Añade regla `@media (prefers-reduced-motion: reduce) { .fake-sea-route-line { animation: none; } }` junto a las existentes para `.sea-route-line` y `.land-route-line`.

8. **Actualiza README — `README.md:16-28` — documenta tercer botón**  
   Actualiza la sección del visor: explica los tres botones, fichero esperado por cada uno, colores (`#F9A825`, `#1E88E5`, `#2E7D32`) y ausencia de encuadre automático. Mantén tono conciso.

9. **Verificación — navegador + análisis + tests**  
   Abre con `./tools/serve_map.sh` (incognito) y comprueba: tres botones apilados, estados iniciales correctos. Carga los tres ficheros (si existen `sea_routes.json`, `car_routes.json` y un ficticio) y comprueba convivencia, orden visual (verde por encima), popup compartido con/ sin `durationHours`, sin movimiento de cámara.  
   Ejecuta `flutter analyze` y `flutter test`. Verifica que solo se tocan `tools/locations-map/index.html`, `tools/locations-map/app.js`, `tools/locations-map/style.css`, `README.md` y `docs/specs/009-visor-rutas-maritimas-ficticias.md`.

---
## 5. Criterios de aceptación

- [ ] `tools/locations-map/index.html` contiene `button#load-fake-sea-routes` con clase `route-button--fake-sea`, `input#fake-sea-routes-file` con `accept=".json,application/json"` oculto y `#fake-sea-route-status` con texto inicial `0 rutas marítimas ficticias`. El bloque se sitúa **inmediatamente debajo** del bloque marítimo, dentro de `.route-loader`. Los tres botones aparecen consecutivos y apilados.
- [ ] Los estados existentes `#land-route-status` (inicial `0 rutas terrestres`) y `#sea-route-status` (inicial `0 rutas marítimas`) se mantienen sin cambios de comportamiento.
- [ ] Al abrir el visor no se emite ninguna petición de lectura de ficheros de rutas. Las tres capas empiezan vacías. El mapa permanece en `center [20,0]`, `zoom 2`.
- [ ] Seleccionar un fichero JSON válido desde `#load-fake-sea-routes` dibuja tantas polilíneas como elementos tenga `routes`. `#fake-sea-route-status` muestra `${count} rutas marítimas ficticias · <nombre-fichero>`. El botón pasa a `Recargar rutas marítimas ficticias`.
- [ ] Tras cargar los tres ficheros (terrestre, marítimo real, marítimo ficticio), las tres capas son visibles **simultáneamente**. Cargar cada uno **no borra** las otras dos.
- [ ] Las rutas ficticias usan color `#2E7D32`, `weight 3`, `opacity 0.9`, `dashArray '8 12'`, clase `fake-sea-route-line`. Las terrestres mantienen `#F9A825`/`land-route-line`. Las marítimas reales mantienen `#1E88E5`/`sea-route-line`.
- [ ] Cuando se solapan rutas de distintas capas, las rutas marítimas ficticias (verdes) se dibujan **por encima** de las terrestres (amarillas) y de las marítimas reales (azules). Los markers rojos siguen **siempre por encima** de las tres capas.
- [ ] El patrón discontinuo de las tres capas se desplaza en `1.2s` lineal infinito. Con `prefers-reduced-motion: reduce`, las tres capas permanecen visibles con patrón discontinuo pero **sin animación**.
- [ ] Cargar cualquier fichero de rutas ficticias deja `center` y `zoom` intactos. No existe ninguna llamada a `fitBounds` en `tools/locations-map/app.js`.
- [ ] El popup de rutas ficticias muestra `origen → destino`, `distancia km · vértices`. Si `durationHours` existe y es válido (>0), añade `· X.X h`. Si no existe, **no** se añade. Todos los valores se escapan con `escapeHtml`.
- [ ] Hover sobre cualquier ruta (de las tres capas) cambia `weight` a `5` y al salir vuelve a `3`, sin crear capas adicionales.
- [ ] JSON inválido (estructura, rangos, geometría < 2 puntos, `durationHours <= 0`, etc.) muestra banner de error y **conserva exactamente** la última carga válida de **esa misma capa**. Las otras dos capas no se modifican.
- [ ] `validateRoutes` se reutiliza sin discriminar `meta.profile`. Un fichero cargado desde botón "equivocado" se acepta y se pinta con el color del botón usado.
- [ ] `splitAntimeridian` se aplica a las tres capas (protección ante cruces antimeridiano).
- [ ] El filtro de ciudades actualiza lista y markers sin ocultar/limpiar/redibujar ninguna de las tres capas de rutas.
- [ ] Panel usable en `320px` y breakpoint móvil (`style.css:252`): los tres botones se apilan sin scroll horizontal.
- [ ] `README.md` documenta los tres botones, fichero esperado por cada uno, colores correspondientes y ausencia de encuadre.
- [ ] Chromium headless (Playwright) carga visor, tres ficheros y filtro sin errores de consola ni banners inesperados.
- [ ] `flutter analyze` y `flutter test` finalizan correctamente. No se modifican `pubspec.yaml`, `lib/`, `web/`, `assets/data/`, ni skills de generación de rutas.
- [ ] Solo se tocan: `tools/locations-map/index.html`, `tools/locations-map/app.js`, `tools/locations-map/style.css`, `README.md`, `docs/specs/009-visor-rutas-maritimas-ficticias.md`.
- [ ] `window.__foggVisor` expone `fakeSeaRoutes`, `fakeSeaRouteFileName`, `fakeSeaRouteError`, `fakeSeaRoutesLayer`.

---
## 6. Decisiones tomadas y descartadas

- **Sí:** tercer botón independiente con su propia capa `fakeSeaRoutesLayer`. Por qué: permite comparar tres conjuntos simultáneamente sin mezclar lógicas.
- **Sí:** color verde `#2E7D32` para rutas marítimas ficticias. Por qué: clara distinción visual frente a azul (`#1E88E5`, marítimas reales) y amarillo (`#F9A825`, terrestres). Texto blanco en botón verde con borde `#1B5E20`/`#0D3F12` para contraste legible.
- **Sí:** panel `fakeSeaRoutesPane` con zIndex 403 (por encima de land 402 y sea 401). Por qué: hace determinista el orden visual; las ficticias quedan "encima" para máxima visibilidad al solaparse.
- **Sí:** reutilizar `loadRoutes`, `validateRoutes`, `normalizeRoutes`, `routePopup`. Por qué: DRY, coherente con SPEC 007. No se duplica código.
- **Sí:** mantener `durationHours` opcional con misma regla (>0). Por qué: el esquema puede variar; el popup debe ser fiel al fichero.
- **No:** validar `meta.profile`. Por qué: decisión coherente con SPEC 007 (evita rechazos por botón equivocado). El estado identifica la capa.
- **No:** renombrar nada existente. Por qué: mínimos cambios, bajo riesgo.
- **No:** añadir toggle/leyenda/lista. Por qué: fuera de alcance; tres botones ya hacen explícito el estado.
- **No:** carga automática ni persistencia. Por qué: visor dev manual y efímero.
- **No:** integrar con Flutter. Por qué: se mantiene acotado al visor standalone `tools/locations-map/`.

---
## 7. Riesgos identificados

| Riesgo | Mitigación |
|---|---|
| Tercer conjunto de polilíneas añade carga de renderizado | Tres capas independientes con SVG renderer; `prefers-reduced-motion` desactiva animación. Verificación headless con ficheros reales. |
| Confusión entre "marítimas" y "marítimas ficticias" en UI | Etiquetas claras: `Cargar rutas marítimas` vs `Cargar rutas marítimas ficticias`; estados independientes con `label` explícito. |
| Invertir orden visual por carga | Paneles con zIndex fijos (401/402/403). Criterio verifica verde por encima cruzando rutas. |
| Regresión en capas existentes | No se toca lógica de `seaRoutesLayer`/`landRoutesLayer` salvo añadir nueva config/capa; reutilización estricta de código probado. |
| CSS/animación nueva | Claves `fakeSeaRouteFlow` aisladas; regla `prefers-reduced-motion: reduce` añadida. |

---
## 8. Lo que **no** está en esta especificación

- Carga automática, `fetch` de assets o inclusión en `pubspec.yaml`.
- Generación/edición/exportación de rutas ficticias.
- Validación por `meta.profile` o rechazo en botón equivocado.
- Toggles, leyenda, lista lateral, filtros por ruta.
- Persistencia entre sesiones.
- Renderizado en app Flutter.
- Cambios en skills o datasets existentes.
- Edición de SPEC 005/006/007.
- Capa nocturna/terminador solar.

Cada uno, si aterriza, irá en su propia especificación.

---
## 9. Referencias

- `tools/locations-map/index.html:24-32` — bloque actual con botones terrestre+marítimo (SPEC 007).
- `tools/locations-map/app.js:44-110` — paneles, capas, estilos y configs (SPEC 007).
- `tools/locations-map/app.js:136-201` — `validateRoutes` compartido (SPEC 007).
- `tools/locations-map/app.js:218-257` — `splitAntimeridian` + `normalizeRoutes`.
- `tools/locations-map/app.js:259-267` — `routePopup` con `durationHours` opcional.
- `tools/locations-map/app.js:287-317` — `loadRoutes` parametrizado.
- `tools/locations-map/app.js:543-564` — `window.__foggVisor`.
- `tools/locations-map/style.css:140-210, 252+` — estilos botones/capas/animaciones + breakpoint.
- `docs/specs/007-visor-rutas-terrestres.md` — referencia de implementación a extender.
- `assets/data/sea_routes.json` / `assets/data/car_routes.json` — contratos existentes.
- Leaflet 1.9.4 panes: https://leafletjs.com/reference.html#map-createpane

---
## 10. Preguntas abiertas (resueltas)

- ¿Nombre del botón? → "Cargar rutas marítimas ficticias".
- ¿Color verde? → `#2E7D32`.
- ¿Orden UI? → terrestre, marítimo real, marítimo ficticio (apilados).
- ¿Orden visual capas? → ficticias por encima (zIndex 403) para visibilidad.
- ¿Compartir validación/popup? → Sí, reutilizar tal cual.
- ¿Añadir clase CSS específica? → `route-button--fake-sea`, `fake-sea-route-line`, `fakeSeaRouteFlow`.
- ¿Exponer en visor global? → Sí, con getters + layer.
- ¿Actualizar README? → Sí.

**Siguiente número:** 009. **Slug:** visor-rutas-maritimas-ficticias.
