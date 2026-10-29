# SPEC 021 — Barra indicadora de cansancio y estado de Phoebe en FoggAppBar

> **Estado:** Borrador

> **Depende de:** SPEC 012 (GameSession, Fatigue, GameNotifier), SPEC 002 (FoggAppBar, MainScaffold)

> **Fecha:** 2026-10-29

> **Objetivo:** Integrar en la `FoggAppBar` una barra indicadora del cansancio de 1-2 píxeles de grosor junto al texto del estado de Phoebe, ubicados bajo la fecha actual con colores según umbrales de fatiga.

---

## 1. Por qué existe esta especificación

Hoy el estado de fatiga (`Fatigue`) de Phoebe rige la lógica de bloqueo de trayectos cuando está extenuada o agotada sin sleeper, pero no se visualiza de forma continua en la cabecera de la aplicación. Esta especificación añade un indicador visual sutil (barra de 2 px) y textual en la `FoggAppBar` bajo la fecha, facilitando al jugador la monitorización constante de la salud y energía de Phoebe.

---

## 2. Alcance

**En:**

- **Definición de estados y umbrales de fatiga:**
  - `> 75.0%`: **Descansada** (Verde — `Colors.green` / token correspondiente)
  - `> 50.0% y <= 75.0%`: **Fatiga ligera** (Azul — `Colors.blue`)
  - `> 20.0% y <= 50.0%`: **Cansada** (Amarillo/Ámbar — `Colors.amber`)
  - `> 1.0% y <= 20.0%`: **Extenuada** (Naranja — `Colors.orange`)
  - `<= 1.0%`: **Agotada** (Rojo — `Colors.red`)
- **Exposición de Fatiga en Proveedor (`gameNotifierProvider` / `gameSessionProvider`):** Asegurar acceso reactivo a la fatiga actual en la UI.
- **Actualización de `FoggAppBar` (`lib/presentation/widgets/fogg_app_bar.dart`):**
  - Añadir en la columna de título, bajo la fecha actual:
    1. Texto de estado en tamaño pequeño (ej. `11px`, peso `w500`), con el color correspondiente al umbral.
    2. Espaciado vertical mínimo (`2px`).
    3. Barra de progreso lineal o contenedor de altura `2.0` píxeles con ancho proporcional a la fatiga (`value / 100.0`), con esquinas redondeadas y el color correspondiente.
- **Pruebas unitarias y de widgets:**
  - Tests para la función de resolución de estado y color según porcentaje de fatiga.
  - Test de widget para `FoggAppBar` comprobando la renderización de los diferentes estados de cansancio.

**Fuera del alcance:**
- Nuevas mecánicas de sueño o penalizaciones de eventos.
- Modificaciones en otras vistas que no sean la cabecera principal (`FoggAppBar`).

---

## 3. Modelo y Lógica de Estado

```dart
class FatigueDisplayInfo {
  const FatigueDisplayInfo({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  static FatigueDisplayInfo resolve(double value) {
    if (value > 75.0) {
      return const FatigueDisplayInfo(label: 'Descansada', color: Colors.green);
    } else if (value > 50.0) {
      return const FatigueDisplayInfo(label: 'Fatiga ligera', color: Colors.blue);
    } else if (value > 20.0) {
      return const FatigueDisplayInfo(label: 'Cansada', color: Colors.amber);
    } else if (value > 1.0) {
      return const FatigueDisplayInfo(label: 'Extenuada', color: Colors.orange);
    } else {
      return const FatigueDisplayInfo(label: 'Agotada', color: Colors.red);
    }
  }
}
```

---

## 4. Plan de Verificación

1. Ejecutar tests unitarios y de widgets nuevos.
2. Comprobar `flutter analyze` y `flutter test`.
