# TODO — Phileas Fogg 2026: Diario de Viaje

Checklist vivo. Marque con `[x]` al completar.

---

## Features

### MVP — versión super simplificada (compatible con final)
- [ ] Scaffold `frontend` Flutter Web `eu.elarreglador.pf2026` (Package by Layer: `presentation/domain/data/services/utils`)
- [ ] `shared_models` (Position, Leg, TransportMode, DiaryEntry, WeatherSnapshot)
- [ ] PWA mínima (`web/manifest.json`, `service_worker`, iconos 192/512, prompt instalación móvil)
- [ ] `flutter_map` + OSM + marcador Fogg + overlay día/noche simplificado
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
- [ ] Overlay día/noche curvo preciso (terminador solar)
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

### Futuro
- [ ] `StoryGenerator` LLM (inyectable, sin tocar dominio)
- [ ] Tema victoriano/steampunk intercambiable
- [ ] Web Push opcional (próxima salida / carta)
- [ ] Modo multijugador / Fogg global compartido

---

## Fix

- [ ] (vacío — añada aquí bugs detectados)

---

## Tareas finalizadas

- [x] Definición del proyecto y decisiones Q1–Q9 (stack, mapa, backend, meteo, fecha, ruta, presupuesto, idioma, estética)
- [x] Ciclo Fogg (descanso local, sleeper, carta antes de dormir)
- [x] Regla asíncrona (auto-reserva más caro) y regla del Este por omisión
- [x] Estructura base (.worktrees, SENSIBLE, .gitignore)
- [x] README.md fundacional (castellano, código en inglés, `eu.elarreglador.pf2026`)
- [x] TODO.md inicial
