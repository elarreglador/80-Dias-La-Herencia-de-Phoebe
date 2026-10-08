# TODO — 80 Días – La Herencia de Phoebe

Checklist vivo. Marque con `[x]` al completar.

---

## Features

### MVP — versión super simplificada (compatible con final)
- [ ] `shared_models` (Position, Leg, TransportMode, DiaryEntry, WeatherSnapshot)
- [ ] PWA mínima (`web/manifest.json`, `service_worker`, iconos 192/512, prompt instalación móvil)
- [x] `flutter_map` + OSM + marcador Fogg (`foggPosition`, Phoebe) + overlay día/noche simplificado → **curvo preciso** `SunTerminatorService` 2° `PolygonLayer` `#000511` 45% recálculo 5 min (spec 001 `docs/specs/001-terminador-solar.md`)
- [ ] `TimeEngine` (START_DATE configurable, TIME_SCALE dev-only con guardarraíl prod, ciclo descanso 5–8 h, flag `sleeper`)
- [ ] Ruta 5 ciudades este (Londres → París → Estambul → Bombay → Tokio) + interpolación minuto a minuto (GeoJSON recto)
- [ ] Catálogo mock 3 transportes (train/ship/foot) con `price | departureTime | sleeper | availabilityRule`
- [ ] `TransportSelector` + regla asíncrona auto-reserva más caro + filtro `lng > actual`
- [ ] `BudgetService` + `Ledger` (1.000.000 € inicial)
- [ ] `EventEngine` mock (2 eventos: retraso + tormenta Open-Meteo)
- [ ] `DiaryService` + `StoryGenerator` plantillas (carta antes de dormir, publica al amanecer)
- [ ] Integración Open-Meteo (sin key) + `WeatherSnapshot`
- [ ] `InMemoryBackend` (implementa Timetable/Position/Diary) — mock basado en datos reales
- [ ] `Hive` cache offline + sync al reconectar
- [ ] Design Tokens + Theme minimalista contemporáneo intercambiable
- [ ] Tests: `TimeEngine`, `BudgetService`, `TransportSelector`, `EventEngine`

### v1
- [ ] Ampliar a 15 ciudades + 7 transportes
- [ ] Trazado GeoJSON real (OpenRailwayMap + rutas marítimas)
- [x] Overlay día/noche curvo preciso (terminador solar) — entregado en MVP vía spec 001 (ver item MVP overlay)
- [ ] Open-Meteo vivo por cada posición + caché
- [ ] EventEngine completo (huelga, frontera, avería, viento, nieve)
- [ ] Ledger con historial y gráfica

### Final — 80 días reales
- [ ] Ruta completa este (gran ciudad, 80 días, sin avión)
- [ ] Catálogo 10+ transportes (horse, camel, balloon, motorcycle, snowmobile, donkey…)
- [ ] Horarios mock refinados desde datos reales por corredor
- [ ] Migración `InMemoryBackend` → backend real (Dart Frog o Supabase) sin cambiar interfaces
- [ ] Leaderboard por usuario (quién llega con más presupuesto)
- [ ] Build PWA prod + deploy

### Narrativa / Lore (solo narrativa, no mecánica MVP)
- [ ] `docs/LORE.md` — árbol genealógico Phileas → Phoebe (2005) / Rohan (2009) + apuesta del hermano (idea de Rohan, deuda estudios)

### Futuro
- [ ] `StoryGenerator` LLM (inyectable, sin tocar dominio)
- [ ] Tema victoriano/steampunk intercambiable
- [ ] Web Push opcional (próxima salida / carta)
- [ ] Modo multijugador / Fogg global compartido (Phoebe como anfitriona)

---

## Fix

- [ ] (vacío — añada aquí bugs detectados)

---

## Tareas finalizadas

- [x] Scaffold `frontend` Flutter Web `eu.elarreglador.pf`
- [x] Definición del proyecto y decisiones Q1–Q9 (stack, mapa, backend, meteo, fecha, ruta, presupuesto, idioma, estética)
- [x] Ciclo Fogg (descanso local, sleeper, carta antes de dormir) — en 2026 protagonizado por Phoebe Fogg
- [x] Regla asíncrona (auto-reserva más caro) y regla del Este por omisión
- [x] Estructura base (.worktrees, SENSIBLE, .gitignore)
- [x] README.md fundacional (castellano, código en inglés, `eu.elarreglador.pf`)
- [x] TODO.md inicial
- [x] Rutas marítimas hacia el Este: `sea_routes.json` v3.1.0, 210 rutas de 42 orígenes (specs 004/005), geometría anclada a las coordenadas de la ciudad y segmentación de antimeridiano. Pendiente solo el consumo desde el mapa Flutter (ítem v1 de arriba)
- [x] Rutas por carretera hacia el Este: `car_routes.json` v1.1.0, 1001 rutas de 236 orígenes con `durationHours` (68 orígenes isleños o sin camino quedan con 0 rutas; spec 006 `docs/specs/006-fog-car-routes.md`), geometría `simplified` anclada a la ciudad. Pendiente el consumo desde el mapa Flutter (ítem v1 de arriba)
- [x] Toda ciudad puede ser origen (2026-10-07, addenda §11 spec 004 y §12 spec 006): 9 costeras forzadas por `FORCED_COASTAL_KM`, Teresina resuelta por carretera, `heading east|west` + fallback al Oeste hasta `minRoutesPerOrigin = 2`, merge `--resume` en ambas skills, fix de nulos espurios del `/table` de OSRM. Las 10 ciudades antes "solo destino" tienen ≥2 rutas de salida. Actualizadas `SKILL.md` de ambas skills.
- [x] Visor con rutas terrestres y marítimas simultáneas (spec 007 `docs/specs/007-visor-rutas-terrestres.md`): dos botones con estado propio, capa amarilla `#F9A825` sobre la azul (paneles 401/402), validador único `validateRoutes` con `durationHours` opcional, popup con horas, sin encuadre automático (`fitSeaRoutes` retirado), `serve_map.sh` abre en incognito y README actualizado. Verificado con Playwright headless + `flutter analyze`/`flutter test`.
- [x] Cobertura de rutas (spec 008 `docs/specs/008-cobertura-rutas-ciudades.md`, pasos 1–7 y 9–10): verificador `tools/route_coverage.py` (con `--write-report`), cierre de huecos `--close-gaps` en ambas skills (`gapClosed: true`, `meta.coverage`/`meta.gapClosedRoutes`), cobertura integrada en `validate_dataset` de mar y tierra, `docs/ciudades-sin-rutas.md` regenerado (59 → 50 pendientes: 9 cerradas por tierra), `test/data/route_coverage_test.dart` y documentación en SKILL.md/README. **Pendiente (paso 8, del Señor):** pase manual de excepciones sobre las 50 ciudades restantes; hasta entonces `validate_dataset` y el test de cobertura quedan en rojo por diseño (la spec lo admite en sus riesgos).
