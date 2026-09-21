# AGENTS.md — PF2026 (80 Días – La Herencia de Phoebe)

Instrucciones repo-específicas para OpenCode. Complementa a `~/.config/opencode/AGENTS.md` (global). Si hay conflicto, prevalece este archivo.

## Estado actual
- Proyecto en **scaffolding**. Solo existen `README.md`, `TODO.md`, `.gitignore`, `SENSIBLE/` y `.worktrees/`. No hay `frontend/`, `backend/`, `shared_models/` ni `pubspec.yaml` aún; verifique con `ls` antes de asumir que existen.
- No es aún repo git (`git status` falla). Si necesita historial, ejecute `git init` y cree `main` antes de ramificar.
- `TODO.md` es la fuente de verdad del avance (secciones `Features` / `Fix` / `Tareas finalizadas`).

## Stack y convenciones fijas
- **Flutter Web 3.22+ / Dart 3.4+** + PWA. Prefijo obligatorio: `eu.elarreglador.pf` (dominio inverso).
- **Package by Layer**: `presentation/` | `domain/` (entities + repository interfaces) | `data/` (models, datasources, Hive) | `services/` (TimeEngine, BudgetService, EventEngine, PositionStream) | `utils/`.
- **Idioma**: código y variables en inglés; documentación/comentarios en castellano.
- **Secretos**: nunca versionar. Todo en `SENSIBLE/` (ignorado). Variables vía `.env` copiado desde `SENSIBLE/.env` — ver `README.md:Configuración`.

## Estructura planificada (verificar antes de usar)
```
frontend/lib/{presentation,domain,data,services,utils}  # app Flutter
frontend/web/{manifest.json,service_worker.js,icons/}    # PWA
frontend/test/                                           # flutter test
shared_models/lib/{position,leg,diary_entry}.dart        # DTOs + Leg/TransportMode/DiaryEntry
backend/                                                 # abstracción: InMemoryBackend en MVP; futuro Dart Frog o Supabase
SENSIBLE/.env                                            # START_DATE, TIME_SCALE, INITIAL_BUDGET, MAP_TILE_URL, OPEN_METEO_URL
.worktrees/                                              # worktrees git, ignorado
```

## Comandos (frontend aún no existe — fallarán hasta el scaffold)
```bash
cd frontend && flutter pub get
flutter run -d chrome                                    # dev normal
flutter run -d chrome --dart-define=TIME_SCALE=60        # modo acelerado, solo dev
flutter build web                                        # build PWA
flutter test                                             # tests (TimeEngine, BudgetService, TransportSelector, EventEngine)
flutter analyze                                           # typecheck/lint
# backend futuro:
# cd backend && dart_frog dev  # o: supabase start
```
`TIME_SCALE` es **solo dev**; en prod hay guardarraíl `assert(TIME_SCALE==1)` — no lo relaje. Open-Meteo no requiere key (`https://api.open-meteo.com/v1/forecast`).

## Invariantes de dominio — no romper
- **Regla del Este**: solo destinos con `destination.lng > current.lng`. Se aplica por omisión filtrando el catálogo; nunca renderizar botón hacia el oeste. Sin validación punitiva. Los Fogg solo avanzan hacia el este — Phileas en 1872, Phoebe en 2026.
- **Sin avión**: `TransportMode.flight` no existe y no debe crearse.
- **Ciclo Fogg**: en 2026 protagonizado por **Phoebe Fogg** (heredera del ciclo original de Phileas, 1872). `06:00 local` carta → `07:00` ventana elección → `08:00-22:00` avance minuto a minuto → `22:00` carta+descanso `5-8h`. `localTime = utc + lng/15`. `sleeper` (train/ship) permite avanzar de noche. El apellido `Fogg` se mantiene como término ubicuo (`foggPosition`, `Ciclo Fogg`) — no usar `Traveler`.
- **Selección asíncrona**: sin elección antes de `departureTime`, `TransportSelector.autoBookMostExpensive()` reserva el más caro viable hacia el este.
- **Economía**: `INITIAL_BUDGET=1_000_000 €`, `BudgetService`+`Ledger`; eventos se reflejan en la carta siguiente.
- **PWA offline**: `Hive` caché + sync al reconectar; `manifest.json` (`display:standalone`) + `service_worker` requeridos para instalable.
- **Herencia Phoebe**: narrativa pura (ver `docs/LORE.md`). No es mecánica jugable en MVP; no afecta a las invariantes anteriores.

## Estilo y arquitectura
- Design Tokens (`tokens.json` → `ThemeData`) desacoplados del dominio; estética minimalista intercambiable (futuro victoriano). No acoplar tema a lógica.
- `StoryGenerator` es interfaz inyectable (hoy plantillas, mañana LLM) — respete DIP.
- `TimetableService` / `PositionService` / `DiaryService` son interfaces en `domain/repositories`; `InMemoryBackend` las implementa en MVP. No acople frontend a Dart Frog/Supabase concreto.
- **Naming**: usar `Phoebe` o `Fogg` (`foggPosition`, `Ciclo Fogg`) como ubiquitous language. Evitar `Traveler` genérico. El dominio en código permanece en inglés; la narrativa en castellano.

## Workflow
- No commits/pushes sin petición explícita. Ramas `feat/...` desde `main`. Antes de editar, lea el archivo y respete convenciones.
- Actualice `TODO.md` al completar tareas. Revise `diff` antes de finalizar: sin secretos, sin código muerto, sin cambios no solicitados.
- `.worktrees/` y `SENSIBLE/` están en `.gitignore` — no los versione.
