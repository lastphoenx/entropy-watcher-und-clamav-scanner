# ew_forecast_next_run.sh - Usage Guide

Flexible systemd-Timer-Status-Anzeige für EntropyWatcher und Backup-Pipeline mit mehreren Output-Formaten.

## Syntax

```bash
ew_forecast_next_run.sh [--format FORMAT] [--sort FIELD]
```

## Parameter

### --format FORMAT

Wählt das Ausgabeformat. Verfügbare Formate:

#### **compact** (Default)
Platzsparend, nur relative Zeiten. Ideal für täglichen Quick-Check.

```
Unit                                | Enabled | Active  | Last         | Next
------------------------------------+---------+---------+--------------+--------------
entropywatcher-nas.timer            | enabled | active  | 22m ago      | 23h left
backup-pipeline.timer               | enabled | active  | 1h 22m ago   | 7h 45m left
```

**Vorteile:**
- Kompakt, passt in jedes Terminal
- Schnell erfassbar: "Wann lief es zuletzt? Wann kommt der nächste Lauf?"
- Keine unwichtigen Details

#### **hybrid**
Relative Zeit für "Last", absolutes Datum für "Next". Beste Balance zwischen Übersicht und Planbarkeit.

```
Unit                                | Enabled | Active  | Last         | Next
------------------------------------+---------+---------+--------------+--------------------------------
entropywatcher-nas.timer            | enabled | active  | 22m ago      | 2026-04-11 15:24 (23h left)
backup-pipeline.timer               | enabled | active  | 1h 22m ago   | 2026-04-11 20:00 (7h 45m left)
```

**Vorteile:**
- "Last" als relative Zeit reicht (unwichtig, wann genau)
- "Next" mit Datum (kann man planen/koordinieren)
- Immer noch gut lesbar

#### **full**
Vollständige Informationen mit Datum+Zeit+relativen Angaben.

```
Unit                                | Enabled | Active  | LastRun                        | NextRun
------------------------------------+---------+---------+--------------------------------+--------------------------------
entropywatcher-nas.timer            | enabled | active  | 2026-04-11 14:22 (22m ago)     | 2026-04-11 15:24 (23h left)
backup-pipeline.timer               | enabled | active  | 2026-04-11 12:00 (1h 22m ago)  | 2026-04-11 20:00 (7h 45m left)
```

**Vorteile:**
- Maximum an Information
- Für Logs/Reports/Dokumentation

#### **box**
Kompaktes Format mit schönen Unicode-Rahmen (wie altes `STYLE=box`).

```
┌─────────────────────────────────────┬─────────┬─────────┬──────────────┬──────────────┐
│ Unit                                │ Enabled │ Active  │ Last         │ Next         │
├─────────────────────────────────────┼─────────┼─────────┼──────────────┼──────────────┤
│ entropywatcher-nas.timer            │ enabled │ active  │ 22m ago      │ 23h left     │
│ backup-pipeline.timer               │ enabled │ active  │ 1h 22m ago   │ 7h 45m left  │
└─────────────────────────────────────┴─────────┴─────────┴──────────────┴──────────────┘
```

**Vorteile:**
- Schön für Screenshots/Dashboards
- Klare visuelle Trennung

---

### --sort FIELD

Sortiert die Ausgabe nach verschiedenen Kriterien:

- **next** (Default) - Nach nächstem Lauf sortiert (früher → später)
- **last** - Nach letztem Lauf sortiert (neuer → älter)
- **name** - Alphabetisch nach Service-Name

## Beispiele

### Standard-Aufruf (compact + sort by next)
```bash
./ew_forecast_next_run.sh
```

### Hybrid-Format für Wartungsplanung
```bash
./ew_forecast_next_run.sh --format hybrid
```

### Vollständige Informationen für Report
```bash
./ew_forecast_next_run.sh --format full --sort last
```

### Hübsche Darstellung für Dashboard
```bash
./ew_forecast_next_run.sh --format box
```

### Alphabetische Liste aller Services
```bash
./ew_forecast_next_run.sh --format compact --sort name
```

## Environment-Variablen (Legacy-Kompatibilität)

Für Rückwärtskompatibilität wird die alte `STYLE`-Variable weiterhin unterstützt:

```bash
# Alt (deprecated, aber funktioniert weiterhin):
STYLE=box ./ew_forecast_next_run.sh

# Neu (empfohlen):
./ew_forecast_next_run.sh --format box
```

**Priorität:** Command-line-Parameter `--format` überschreibt `STYLE`-Environment-Variable.

## Anwendungsfälle

### Täglicher Status-Check
```bash
# Schnell: Was läuft als nächstes?
./ew_forecast_next_run.sh
```

### Backup-Koordination
```bash
# Hybrid: Wann genau kommt der nächste Backup-Lauf?
./ew_forecast_next_run.sh --format hybrid | grep backup-pipeline
```

### Troubleshooting
```bash
# Full: Details zu allen Läufen
./ew_forecast_next_run.sh --format full --sort last
```

### Dokumentation/Screenshot
```bash
# Box: Schön für Doku
./ew_forecast_next_run.sh --format box > /tmp/timer_status.txt
```

## Technische Details

### Zeitzone-Robustheit
Das Script ist **zeitzone-agnostisch**. Es sucht nicht nach "CET" oder "CEST", sondern matched generisch:
```bash
[0-9]{2}:[0-9]{2}:[0-9]{2} [A-Z]+
```

**Funktioniert mit:** CET, CEST, UTC, PST, EST, etc.

### Relative Zeit-Parsing
Rohe systemd-Ausgabe wird gekürzt:
- `2 days 3 hours left` → `2d 3h left`
- `1 hour 22 minutes ago` → `1h 22m ago`

### Sortierung
Nutzt Unix-Epoch-Timestamps für korrekte chronologische Sortierung (nicht String-basiert).

### Fehlerbehandlung
- Timer existiert nicht → "n/a" in allen Feldern
- systemctl-Error → "-" für enabled/active
- Parsing fehlgeschlagen → "n/a" für Zeitangaben

## Migration vom alten Format

**Alt:**
```bash
# Einzelner Parameter via Environment
STYLE=box ./ew_forecast_next_run.sh
```

**Neu:**
```bash
# Mehrere Parameter, flexibler
./ew_forecast_next_run.sh --format box --sort next
```

**Kompatibilität:** Beide Varianten funktionieren! Das neue Script erkennt automatisch, ob `STYLE` gesetzt ist und mappt es auf `--format`.
