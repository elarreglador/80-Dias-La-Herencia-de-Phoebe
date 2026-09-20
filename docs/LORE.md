# LORE — 80 Días: La Herencia de Phoebe

> Narrativa pura. No es mecánica jugable en MVP. Complementa a `README.md:Visión` y `AGENTS.md:Invariantes`.

La vuelta al mundo en 80 días no la hace el Sr. Phileas Fogg. En 2026 la retoma su tataranieta **Phoebe Fogg (2005–)**, custodia del cuaderno original de bitácora que Phileas dejó en el gabinete de Savile Row, Londres.

---

## Árbol genealógico: De Phileas a Phoebe (1872 – 2026)

```
        Phileas Fogg (1832–1910)  ═══  Princesa Aouda (1850–1928)
                                  │
                       (Casados en Londres, 1872)
                                  │
                 ┌────────────────┴────────────────┐
                 │                                 │
     Arthur Fogg (1875–1948)          Elena Aouda Fogg (1878–1955)
     ═══ Margaret Sterling                        │
     │                                     (Rama secundaria)
     │
  Thomas Fogg (1908–1982)  ═══  Savitri Nehru (1912–1995)
                           │
             ┌─────────────┴─────────────┐
             │                           │
  Phileas Fogg II (1942–2018)     Alistair Fogg (1946–)
  ═══ Eleanor Vance                      │
  │                               (Sin descendencia)
  │
  Marcus Fogg (1976–)  ═══  Priya Sharma (1978–)
                       │
            ┌──────────┴──────────┐
            │                     │
   Phoebe Fogg (2005–)     Rohan Fogg (2009–)
   [21 años en 2026]      [17 años, cumple 18 en 2027]
```

---

## Desglose por generaciones

### Generación 0 — Los Fundadores (1872)
**Phileas Fogg y Aouda.** Tras completar la hazaña en 80 días, establecen su residencia en Savile Row, Londres. El cuaderno de bitácora original queda custodiado en el gabinete de trabajo de Phileas.

### Generación 1 — Los Hijos de la Era Victoriana / Edwardiana
**Arthur Phileas Fogg (1875–1948):** Primogénito. Tradición británica en la administración pública; hereda la meticulosidad de Phileas y la pasión de Aouda por las culturas orientales. Casado con Margaret Sterling.

**Elena Aouda Fogg (1878–1955):** Rama secundaria, sin descendencia relevante para la herencia del cuaderno.

### Generación 2 — La Segunda Guerra y la posguerra
**Thomas Fogg (1908–1982):** Ingeniero de ferrocarriles. Durante un proyecto en la India conoce a Savitri Nehru (1912–1995), reforzando la herencia cultural anglo-india de la familia.

### Generación 3 — La Era Analógica y los viajes de fin de siglo
**Phileas Fogg II (1942–2018):** Cartógrafo y académico en Londres. Casado con Eleanor Vance.
**Alistair Fogg (1946–):** Sin descendencia.

**Marcus Fogg (1976–):** Padre de Phoebe. Diseñador de software e historiador amateur, fascinado por la libreta de bitácora original del gabinete de Savile Row. Casado con Priya Sharma (1978–).

### Generación 4 — La Heredera Digital

**Phoebe Fogg (2005–):** Nativa digital, curiosa e independiente. **Al cumplir 18 años en 2023** recibe como herencia el cuaderno original de Phileas. Lo custodia durante tres años. En 2026, con **21 años**, decide emprender el mismo viaje hacia el este, sin avión, minuto a minuto, durante 80 días.

**Rohan Fogg (2009–):** Hermano menor, 17 años en 2026. Está a punto de cumplir 18 y de acceder a la universidad, con una deuda de estudios por saldar.

---

## La Apuesta — Idea de Rohan

La propone **su hermano Rohan**, pero Phoebe sabe que necesita una motivación extra y acepta:

- **Si Phoebe pierde** (no completa la vuelta al mundo en 80 días hacia el este, sin avión), el cuaderno original será propiedad de Rohan, quien pretende entregarlo a la **Universidad de Londres** para saldar su deuda de estudios.
- **Si Phoebe gana**, Rohan debe cederle **de por vida el gabinete de trabajo de Phileas** en Savile Row, donde actualmente tiene su sala de estudios.

La apuesta es **narrativa pura en MVP**: justifica el viaje y da peso a la carta diaria, pero no añade mecánica punitiva ni altera las invariantes técnicas (Regla del Este, Sin avión, Ciclo Fogg, BudgetService, etc. — ver `AGENTS.md`).

### Cronología de la apuesta

- **2023:** Phoebe recibe el cuaderno a los 18. Custodia ininterrumpida hasta 2026.
- **Otoño 2026 (START_DATE=2026-10-02):** Rohan, 17 años y a punto de la mayoría, propone la apuesta ante la inminencia de su matrícula universitaria. Phoebe acepta y parte.
- **Durante 80 días:** El diario (`DiaryEntry` + `StoryGenerator`) puede aludir al cuaderno y al gabinete como motivación, sin bloquear el avance.

---

## Notas de autor

- **Tataranieta:** en sentido familiar / coloquial. Genealógicamente, Phoebe es quinta generación desde Phileas (trastataranieta), pero la familia usa "tataranieta" como término afectivo. Se mantiene por coherencia con la petición original.
- **Gabinete de Savile Row:** estancia original de Phileas, hoy sala de estudios de Rohan. Símbolo de continuidad; no es localización jugable en MVP.
- **Tono:** la narrativa permanece en castellano; el código sigue en inglés (`foggPosition`, `Leg`, `DiaryEntry`) — ver `AGENTS.md: Naming`.
- **Futuro:** si la apuesta se volviera mecánica (pantalla de victoria/derrota), se documentará en `README.md:Economía y eventos` sin tocar `TimeEngine` ni `BudgetService`.

---

## Referencias

- Inspiración: *La vuelta al mundo en ochenta días* (Julio Verne, 1872) — dominio público.
- Este archivo es fuente de verdad genealógica para `StoryGenerator` y plantillas de carta.
