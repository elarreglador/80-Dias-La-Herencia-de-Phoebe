# 80 Días – La Herencia de Phoebe

> Phileas Fogg 2026: Diario de Viaje — Dar la vuelta al mundo en 80 días, sin avión, minuto a minuto. PWA instalable.
> En 2026, su tataranieta **Phoebe Fogg** retoma la ruta de 1872. Ver [Herencia y árbol genealógico](docs/LORE.md).

[![Flutter](https://img.shields.io/badge/Flutter-Web-02569B?logo=flutter)](https://flutter.dev)
[![PWA](https://img.shields.io/badge/PWA-instalable-5A0FC0)](https://web.dev/progressive-web-apps/)
[![Open-Meteo](https://img.shields.io/badge/meteo-Open--Meteo-2E7D32)](https://open-meteo.com)
[![Licencia](https://img.shields.io/badge/licencia-MIT-informational)](LICENSE)

Simulación visual y narrativa automatizada de 80 días que emula el espíritu del viaje original en la época actual. La aplicación sigue de forma autónoma la ruta terrestre y marítima que Phileas Fogg trazó en 1872, ahora retomada en 2026 por su tataranieta **Phoebe Fogg**, respetando la estricta condición de **no utilizar el avión**. Cada usuario controla su propio viaje. Detalles genealógicos en [docs/LORE.md](docs/LORE.md).

---

## Índice

- [Visión](#visión)
- [MVP actual — versión super simplificada](#mvp-actual--versión-super-simplificada)
- [Características principales](#características-principales)
- [Cómo funciona — el ciclo de Fogg](#cómo-funciona--el-ciclo-de-fogg)
- [Mapamundi interactivo](#mapamundi-interactivo)
- [La regla del Este](#la-regla-del-este)
- [Transportes](#transportes)
- [Economía y eventos](#economía-y-eventos)
- [Carta diaria](#carta-diaria)
- [Arquitectura](#arquitectura)
- [PWA — instalación en móvil](#pwa--instalación-en-móvil)
- [Estructura del proyecto](#estructura-del-proyecto)
- [Configuración](#configuración)
- [Instalación y desarrollo local](#instalación-y-desarrollo-local)
- [Modelo de datos](#modelo-de-datos)
- [Backend — abstracción intercambiable](#backend--abstracción-intercambiable)
- [Roadmap](#roadmap)
- [Contribuir](#contribuir)
- [Licencia y créditos](#licencia-y-créditos)

---

## Visión

Recrear el desafío de Julio Verne en 2026 sin anacronismos aéreos: tren, barco y, cuando la infraestructura no llega, caballo, camello, globo, motocicleta, moto de nieve, a pie o burro — siempre hacia el este, siempre con presupuesto y meteorología reales.

La app no es un juego de acción sino un **diario de seguimiento en tiempo real**: usted observa, decide entre las opciones disponibles y lee cada mañana la carta que **Phoebe Fogg** le ha escrito antes de dormir.

### Herencia — Phoebe Fogg (2005–)

Tataranieta de Phileas Fogg y la princesa Aouda. Nativa digital, curiosa e independiente, recibe al cumplir 18 años (2023) el cuaderno original de bitácora que Phileas dejó en el gabinete de Savile Row. En 2026, con 21 años, decide emprender el mismo viaje hacia el este, sin avión, durante 80 días. Su hermano menor **Rohan Fogg (2009–)**, a punto de cumplir 18 y ante una deuda de estudios, propone la apuesta que motiva el viaje — ver [docs/LORE.md](docs/LORE.md) para el árbol completo y los términos.

## MVP actual — versión super simplificada

> El MVP es un subconjunto, no un prototipo desechable. Todo lo construido ahora escala a la versión final sin reescritura.

**Incluido en el MVP:**

- [x] `Flutter Web` + PWA mínima (`manifest.json` + `service_worker`)
- [x] `flutter_map` (Leaflet + OSM) + marcador de Fogg + overlay día/noche simplificado
- [x] Ruta de 5 ciudades de prueba: Londres → París → Estambul → Bombay → Tokio (todas hacia el este, con `lng` creciente)
- [x] `TimeEngine` con `START_DATE` configurable + `TIME_SCALE` solo en `dev` + ciclo descanso 5–8 h + flag `sleeper`
- [x] Catálogo mock de 3 transportes (tren, barco, a pie) con precio, horario y `sleeper`
- [x] `BudgetService` con 1.000.000 € y `Ledger`
- [x] `EventEngine` con 2 eventos mock (retraso + tormenta Open-Meteo)
- [x] Carta diaria por plantilla antes del descanso
- [x] Selección asíncrona: sin respuesta del usuario, se reserva el transporte **más caro** disponible hacia el este

**Fuera del MVP pero ya previsto (interfaces creadas):**

- Catálogo completo de 10+ medios, horarios reales, leaderboard, LLM narrativo, push, trazado ferroviario/marítimo preciso

## Características principales

| Pilar | Descripción |
|-------|-------------|
| **Seguimiento en tiempo real** | Avance minuto a minuto durante 80 días desde `START_DATE`. Durante la noche local (5–8 h) Phoebe descansa y el avance se detiene, salvo en transportes `sleeper` (tren/barco) donde se viaja durmiendo. |
| **Mapamundi interactivo** | Trazado continuo ajustado a vías férreas y rutas marítimas (GeoJSON). Posición interpolada minuto a minuto y sombreado día/noche por terminador solar. |
| **Carta diaria** | Cada mañana, al terminar el descanso, se publica una entrada con trayecto realizado, meteorología real (Open-Meteo) y balance de presupuesto. |
| **Elección de itinerario** | El usuario elige entre destinos hacia el este según transporte disponible. Ventana asíncrona; sin elección, auto-reserva del más caro. |
| **PWA** | Instalable desde el móvil, funciona offline con caché `Hive` y sincroniza con el backend al reconectar. |

## Cómo funciona — el ciclo de Fogg
> En 2026 el ciclo lo protagoniza **Phoebe Fogg**, heredera del ciclo original de Phileas (1872). El apellido `Fogg` se mantiene como término ubicuo (`foggPosition`).

```
06:00 local ──► Publicación carta del día anterior
                (plantilla + clima Open-Meteo + ledger)
      │
      ▼
07:00 ───────── Ventana de elección de transporte
                (catálogo filtrado: solo este, solo medios viables)
      │
      ▼
08:00–22:00 ─── Avance diurno minuto a minuto
                (interpolación GeoJSON, update mapa)
      │
      ▼
22:00 ───────── Carta de la jornada + descanso 5–8 h
                (si sleeper: carta + avance nocturno simultáneo)
      │
      ▼
   Amanecer ────► repetir
```

* **Descanso local:** calculado por longitud (`localTime = utc + lng/15`). Duración aleatoria 5–8 h, salvo `sleeper`.
* **Tiempo acelerado:** solo en `dev` vía `TIME_SCALE` (ej. `60` → 1 h real = 1 día simulado). Bloqueado en `prod` por guardarraíl.
* **Sin avión:** ningún `TransportMode.flight` existe en el catálogo.

## Mapamundi interactivo

- **Stack:** `flutter_map` (equivalente Leaflet) + teselas OSM (`https://tile.openstreetmap.org/{z}/{x}/{y}.png`).
- **Capas:**
  1. Base OSM
  2. Trazado GeoJSON ferroviario/marítimo (MVP: polilíneas rectas; final: OpenRailwayMap + OpenSeaMap)
  3. Overlay día/noche (cálculo solar por `solar_calculator`, sombreado semitransparente)
  4. Marcador Fogg (`foggPosition`) + popup (ciudad, hora local, transporte, presupuesto) — Phoebe en 2026
- **Actualización:** `PositionStream` emite `LatLng` cada minuto simulado (cada segundo real en `TIME_SCALE=60`).

## La regla del Este

> Los Fogg solo avanzan hacia el este. Phoebe, como Phileas en 1872, no contempla el oeste. Retroceder no es una opción — literalmente no se ofrece.

- El backend filtra el catálogo: solo destinos con `destination.lng > current.lng` y `population > threshold` (gran ciudad).
- El frontend nunca renderiza un botón hacia el oeste. No hay validación punitiva necesaria; la regla se aplica por omisión.

## Transportes

Catálogo extensible. MVP con 3; final con 10+.

| Medio | `TransportMode` | Velocidad | `sleeper` | Condiciones |
|-------|-----------------|-----------|-----------|-------------|
| Tren | `train` | 80–160 km/h | ✅ | Requiere vía férrea |
| Barco | `ship` | 20–40 km/h | ✅ | Requiere puerto/mar |
| A pie | `foot` | 5 km/h | ❌ | Siempre disponible |
| Caballo | `horse` | 15 km/h | ❌ | No en alta mar |
| Camello | `camel` | 12 km/h | ❌ | Desierto |
| Globo | `balloon` | 30 km/h | ❌ | Viento favorable (Open-Meteo) |
| Motocicleta | `motorcycle` | 90 km/h | ❌ | Carretera |
| Moto de nieve | `snowmobile` | 50 km/h | ❌ | Nieve (Open-Meteo) |
| Burro | `donkey` | 6 km/h | ❌ | Montaña |
| ... | ... | ... | ... | ... |

Cada opción declara `price`, `departureTime` (puede ser al día siguiente) y `availabilityRule`. Datos mock basados en corredores reales (ej. Londres–París Eurostar, Suez en barco).

**Selección asíncrona:** si el usuario no elige antes de `departureTime`, `TransportSelector.autoBookMostExpensive()` reserva la opción más cara viable hacia el este y Phoebe embarca. El usuario lo sabrá en la siguiente carta — con el humor seco que corresponde a quien paga de más.

## Economía y eventos

- **Presupuesto inicial:** `1_000_000 €` (`INITIAL_BUDGET`).
- **Ledger:** cada `Leg` debita `price`; eventos pueden penalizar/bonificar.
- **EventEngine:**
  - Aleatorios: huelga, control fronterizo, avería.
  - Dependientes de clima (Open-Meteo): tormenta retrasa barco, nieve bloquea moto, viento impide globo.
  - Notificación diferida: el evento se refleja en la carta siguiente; Phoebe ya habrá tomado el siguiente transporte viable.

## Carta diaria

Publicada **antes** del descanso (o durante el trayecto `sleeper`). Generada por `DiaryService` con plantillas:

```
"Querido Señor, hoy hemos cubierto {{distance}} km en {{transport}} bajo {{weather}}.
 El presupuesto queda en {{balance}} €. {{eventNarrative}}"
```

`StoryGenerator` es una interfaz inyectable — hoy plantillas, mañana LLM sin tocar el dominio.

- Fuente meteo: `Open-Meteo` (`https://api.open-meteo.com/v1/forecast?latitude=&longitude=&current_weather=true`) — gratuita, sin key.
- Persistencia: `DiaryEntry` en backend (fuente de verdad) + caché `Hive` en cliente.

## Arquitectura

**Prefijo:** `eu.elarreglador.pf2026` (notación de dominio inverso).

**Package by Layer** (AGENTS.md) — coherente con ecosistema Flutter:

```
PF2026/
├── frontend/                 # Flutter Web (eu.elarreglador.pf2026)
│   ├── lib/
│   │   ├── presentation/     # pages, widgets, theme (estética minimalista)
│   │   ├── domain/           # entities, value objects, repositories (interfaces)
│   │   ├── data/             # models, datasources, Hive, mappers
│   │   ├── services/         # TimeEngine, BudgetService, EventEngine, PositionStream
│   │   └── utils/            # solar, formatters, constants
│   ├── web/                  # manifest.json, service_worker, icons
│   └── test/
├── backend/                  # abstracción (ver siguiente sección)
├── shared_models/            # DTOs compartidos frontend↔backend (Position, Leg, DiaryEntry)
├── SENSIBLE/                 # secretos, excluido por .gitignore
├── .worktrees/               # worktrees git, excluido
├── TODO.md
└── README.md
```

**Estética:** minimalista y contemporánea, con Design Tokens (`tokens.json` → `ThemeData`) intercambiables. Base CSS/Flutter `Theme` desacoplada del dominio para permitir futuro tema victoriano/steampunk sin refactorizar lógica.

**SOLID / Clean Code:** `TimeEngine` (SRP), `TransportSelector` (OCP via `AvailabilityRule`), `StoryGenerator` (DIP), sin duplicación (DRY), YAGNI en MVP.

## PWA — instalación en móvil

Al visitar la web en móvil, el navegador propone **Instalar app**. Requisitos:

- `web/manifest.json` (`name: "80 Días – La Herencia de Phoebe"`, `short_name: "Herencia Phoebe"`, `display: standalone`, `start_url: /`)
- `web/service_worker.js` (cache-first para shell, network-first para `Position`/`Diary`)
- Iconos 192/512

Sin push en MVP; el usuario descubre eventos en la siguiente carta.

## Estructura del proyecto

```
frontend/lib/presentation/pages/travel_page.dart:42   # mapa + carta
frontend/lib/services/time_engine.dart:1               # ciclo descanso/avance
shared_models/lib/leg.dart                             # Leg, TransportMode
```

(Ejemplos de rutas finales; el MVP creará estos archivos.)

## Configuración

Variables en `.env` (ver `SENSIBLE/.env` local, nunca versionado). Ejemplo `.env.example`:

```env
START_DATE=2026-10-02T18:45:00Z
TIME_SCALE=1
INITIAL_BUDGET=1000000
MAP_TILE_URL=https://tile.openstreetmap.org/{z}/{x}/{y}.png
OPEN_METEO_URL=https://api.open-meteo.com/v1/forecast
```

| Variable | Descripción | MVP | Prod |
|----------|-------------|-----|------|
| `START_DATE` | Fecha fija configurable de salida (UTC) | 2026-10-02 | igual |
| `TIME_SCALE` | Aceleración temporal (1 = real) | 60 en dev | **1 forzado** |
| `INITIAL_BUDGET` | Presupuesto inicial € | 1_000_000 | igual |
| `MAP_TILE_URL` | URL teselas OSM | OSM público | igual |
| `OPEN_METEO_URL` | Endpoint meteo | sin key | igual |

## Instalación y desarrollo local

**Requisitos:** Flutter 3.22+, Dart 3.4+.

```bash
# Clonar
git clone <repo> PF2026 && cd PF2026

# Frontend
cd frontend
flutter pub get
cp ../SENSIBLE/.env .env          # o crear desde .env.example
flutter run -d chrome             # web
flutter build web                 # build PWA

# Backend mock (MVP: InMemory, sin despliegue)
# Cuando exista backend real:
# cd ../backend && dart_frog dev   # o: supabase start

# Tests
flutter test
```

**Modo acelerado (solo dev):**

```bash
TIME_SCALE=60 flutter run -d chrome --dart-define=TIME_SCALE=60
```

En `prod` el guardarraíl `assert(TIME_SCALE==1)` impide aceleración.

## Modelo de datos

Código en inglés (AGENTS.md). Extractos:

```dart
// shared_models/lib/position.dart
class Position {
  final double lat;
  final double lng;
  final DateTime utc;
  final DateTime localTime; // utc + lng/15
  const Position({required this.lat, required this.lng, required this.utc, required this.localTime});
}

// shared_models/lib/leg.dart
enum TransportMode { train, ship, foot, horse, camel, balloon, motorcycle, snowmobile, donkey }

class Leg {
  final String fromCity;
  final String toCity;
  final TransportMode mode;
  final double price;
  final DateTime departureTime;
  final bool sleeper;
  final double distanceKm;
}

// shared_models/lib/diary_entry.dart
class DiaryEntry {
  final DateTime date;
  final Position position;
  final Leg leg;
  final WeatherSnapshot weather;
  final double balance;
  final String narrative;
}
```

Servicios clave: `TimeEngine`, `PositionStream`, `TransportSelector`, `BudgetService`, `EventEngine`, `DiaryService`, `StoryGenerator`.

## Backend — abstracción intercambiable

El backend aún no está decidido — el proyecto no se bloquea. Se define por **interfaces** en `shared_models` / `frontend/lib/domain/repositories/`:

```dart
abstract class TimetableService { Future<List<Leg>> availableLegs(Position current); }
abstract class PositionService { Stream<Position> track(String userId); }
abstract class DiaryService { Future<DiaryEntry> publishDaily(String userId); }
```

**MVP:** `InMemoryBackend` (mock basado en datos reales, en memoria, sin despliegue) implementa las tres interfaces. Permite desarrollar frontend sin backend desplegado.

**Candidatos finales (a elegir):**

| Opción | Stack | Pros | Contras |
|--------|-------|------|---------|
| **A — Dart Frog** | Dart + Postgres (Fly.io/Cloud Run) | Coherencia Dart total, mismo lenguaje que Flutter | Más código boilerplate (auth, cron) |
| **B — Supabase** | Postgres + Auth + Cron + Realtime | Auth y cron listos, realtime para `PositionStream` | Menos control fino, acoplamiento a BaaS |

Ambas opciones cumplen el contrato; el cambio es solo de implementación. El `README` se actualizará cuando usted decida. Secretos en `SENSIBLE/`, nunca en repo.

## Roadmap

| Fase | Alcance | Estado |
|------|---------|--------|
| **MVP** | 5 ciudades, 3 transportes, PWA mínima, mock, carta plantilla, 1M€, modo acelerado dev | ⏳ en curso |
| **v1** | 15 ciudades, 7 transportes, trazado GeoJSON real, Open-Meteo vivo, `Hive` offline | ☐ |
| **Final** | 80 días reales, ruta completa este, 10+ transportes, eventos clima, `InMemory` → backend real, leaderboard | ☐ |
| **Futuro** | LLM narrativo, tema victoriano intercambiable, push opcional, modo multijugador | ☐ |

Ver `TODO.md` para checklist detallado.

## Contribuir

1. Cree rama desde `main` (`git checkout -b feat/…`).
2. Respete `eu.elarreglador.pf2026` y Package by Layer.
3. Código en inglés, documentación en castellano.
4. Añada tests para `TimeEngine`/`BudgetService`/`EventEngine`.
5. No versione secretos (`SENSIBLE/`).

## Licencia y créditos

- **Inspiración:** *La vuelta al mundo en ochenta días* (Julio Verne, 1872) — dominio público.
- **Mapas:** © OpenStreetMap contributors.
- **Meteo:** Open-Meteo (CC BY 4.0).

