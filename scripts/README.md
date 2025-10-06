# EntropyWatcher Utility Scripts

Optional monitoring and forecasting tools for EntropyWatcher pipeline management. For detailed documentation, see [docs/UTILITIES.md](../docs/UTILITIES.md).

---

## 📋 Quick Reference

| Script | Zweck | Output | Verwendung |
|--------|-------|--------|------------|
| **ew_status.sh** | Service-Health Dashboard | Terminal/HTML/Mail | Monitoring, Reports |
| **ew_forecast_next_run.sh** | Timer-Status Übersicht | ASCII/Box-Tabelle | Quick-Status-Check |
| **forecast_safety_gate.sh** | Safety-Gate Forecasting | Zeitlinien-Tabelle | Backup-Planung |
| **ew_backup_slot_check.sh** | Backup-Slot-Check | Service-Status-Tabelle | Backup-Zeitfenster prüfen |

---

**Hinweis:** `safety_gate.sh` befindet sich im **Root-Verzeichnis** (nicht in scripts/), da es von RTB/pCloud-Pipelines direkt aufgerufen wird. Siehe [Haupt-README](../README.md) für Details.

---

## 📊 ew_status.sh

Umfassendes Dashboard für alle EntropyWatcher-Services.

**Quick Start:**
```bash
# Terminal-Dashboard
./ew_status.sh /opt/apps/entropywatcher/config dashboard

# HTML-Report per Mail
./ew_status.sh /opt/apps/entropywatcher/config mail
```

**Was wird angezeigt:**
- Service-Status (GREEN/YELLOW/RED)
- Letzter Scan-Zeitstempel
- Alter vs. Health-Window
- Buffer-Prozent (wie viel Zeit noch verfügbar)
- AV-Funde (letzte 7 Tage)
- Flagged Files (letzte 7 Tage)

**Output-Beispiel:**
```
╔════════════════╦════════════╦═══════════════════╦═════════╦════════════╦═══════════════╗
║ Service        ║ Status     ║ Last Scan         ║ Age Min ║ Window Min ║ Buffer übrig %║
╠════════════════╬════════════╬═══════════════════╬═════════╬════════════╬═══════════════╣
║ nas            ║ GREEN      ║ 2025-12-14 10:20  ║      15 ║         75 ║         80.0% ║
║ nas-av         ║ YELLOW     ║ 2025-12-13 09:00  ║    1480 ║       1560 ║          5.1% ║
╚════════════════╩════════════╩═══════════════════╩═════════╩════════════╩═══════════════╝
```

---

## ⏱️ ew_forecast_next_run.sh

Zeigt Timer-Status aller EntropyWatcher-Services.

**Quick Start:**
```bash
# ASCII-Stil
./ew_forecast_next_run.sh

# Box-Stil (schöner)
STYLE=box ./ew_forecast_next_run.sh
```

**Output-Beispiel:**
```
Unit                                | Enabled | Active  | LastRun                        | NextRun
------------------------------------+---------+---------+--------------------------------+--------------------------------
entropywatcher-nas.timer            | enabled | active  | Sun 10:20:22 CET (15m ago)     | Sun 11:20:00 CET (45m left)
entropywatcher-os.timer             | enabled | active  | Sun 03:40:00 CET (7h ago)      | Mon 03:40:00 CET (16h left)
```

**Use Cases:**
- Schneller Überblick vor Backup-Start
- Timer-Overlap-Detection
- Systemd-Troubleshooting

---

## 🎯 ew_backup_slot_check.sh

Prüft ob EntropyWatcher-Services für geplante Backup-Slots (04:00, 12:00, 20:00) innerhalb ihrer Health-Windows liegen.

**Quick Start:**
```bash
# Prüfung für nächsten geplanten Backup-Tag (aus backup-pipeline.timer)
./ew_backup_slot_check.sh

# Prüfung für heute
./ew_backup_slot_check.sh 0

# Prüfung für morgen
./ew_backup_slot_check.sh 1

# Prüfung für in 2 Tagen
./ew_backup_slot_check.sh 2
```

**Output-Beispiel:**
```
════════════════════════════════════════════════════════════════
BACKUP SLOT CHECK: 2025-12-15 (Mo)
════════════════════════════════════════════════════════════════

Slot: 04:00
Service  EffLastRun (@ 04:00)         Window   Status
─────────────────────────────────────────────────────────────────
nas      2025-12-15 03:20             75       OK
nas-av   2025-12-14 09:00             1560     OK

Slot: 12:00
...
```

**Was wird geprüft:**
- Für jeden Backup-Slot (04:00, 12:00, 20:00)
- Letzter Scan-Zeitpunkt vor dem Slot (aus systemd-Timer + Frequenz simuliert)
- Alter vs. HEALTH_WINDOW_MIN
- Status: OK (innerhalb Window) oder OLD (außerhalb)

**Use Cases:**
- Backup-Pipeline-Planung (welche Slots sind sicher?)
- Proaktive Warnung bei zukünftigen Engpässen
- Timer-Overlap-Detection

---

## 🔮 forecast_safety_gate.sh

Forecast-Tool für zukünftige Safety-Gate-Zustände.

**Quick Start:**
```bash
# Forecast für morgen
./forecast_safety_gate.sh 1

# Forecast für nächste Woche
./forecast_safety_gate.sh 7

# Forecast für heute (jetzt)
./forecast_safety_gate.sh 0
```

**Output-Beispiel:**
```
════════════════════════════════════════════════════════════════
SAFETY-GATE FORECAST: 2025-12-15 (Target: Mo 05:00)
════════════════════════════════════════════════════════════════

Service  Schedule      LastRun (@ Target)          Age    Window  Status
─────────────────────────────────────────────────────────────────────────
nas      1h (:20)      Mo 2025-12-15 04:20:00      40     75      GREEN
nas-av   taegl (09:00) So 2025-12-14 09:00:00      1200   1560    GREEN
os       1d (03:40)    Mo 2025-12-15 03:40:00      80     1560    GREEN

════════════════════════════════════════════════════════════════
FORECAST RESULT @ Mo 05:00: GREEN (alle Services im Window)
════════════════════════════════════════════════════════════════
```

**Use Cases:**
- Backup-Slot-Planung
- Timer-Optimierung
- Proaktive Warnung bei zukünftigen RED-Zuständen

---

## 🔄 Typischer Workflow

**1. Vor Backup: Safety-Gate prüfen**
```bash
if ! ./safety_gate.sh; then
  echo "Backup blockiert - Safety-Gate nicht GREEN"
  exit 1
fi
```

**2. Nach Backup: Status prüfen**
```bash
./ew_status.sh /opt/apps/entropywatcher/config dashboard
```

**3. Timer-Status checken**
```bash
STYLE=box ./ew_forecast_next_run.sh
```

**4. Morgen forecasten**
```bash
./forecast_safety_gate.sh 1 | grep "FORECAST RESULT"
```

---

## 📚 Detaillierte Dokumentation

Für ausführliche Informationen siehe:
- **[docs/UTILITIES.md](../docs/UTILITIES.md)** - Vollständige Dokumentation aller 4 Scripts
  - Architektur-Details
  - Environment Variables
  - Troubleshooting
  - Entwickler-Notizen

---

## 🛠️ Integration

### Cronjob-Beispiele

**Täglich Status-Mail:**
```bash
# /etc/cron.d/entropywatcher-status
0 6 * * * /opt/apps/entropywatcher/main/scripts/ew_status.sh /opt/apps/entropywatcher/config mail
```

**Stündlich Timer-Check:**
```bash
# /etc/cron.d/entropywatcher-timers
0 * * * * /opt/apps/entropywatcher/main/scripts/ew_forecast_next_run.sh | grep -qE "(active|enabled)" || alert_admin
```

**Vor Backup: Forecast prüfen**
```bash
# In Backup-Script (04:50 vor 05:00 Backup)
if ! /opt/apps/entropywatcher/main/scripts/forecast_safety_gate.sh 0 | grep -q "GREEN"; then
  echo "Forecast nicht GREEN - Backup übersprungen"
  exit 0
fi
```

### RTB-Wrapper Integration

```bash
# In rtb_wrapper.sh (KORREKT - so ist es auf dem Server)
SAFETY_GATE="/opt/apps/entropywatcher/main/safety_gate.sh"

if ! "$SAFETY_GATE"; then
  echo "[$(date)] RTB Backup blockiert - Safety-Gate nicht GREEN"
  exit 1
fi

# ... RTB Backup durchführen ...
```

### pCloud-Tools Integration

```bash
# In pcloud_sync.sh (Beispiel)
SAFETY_EXIT=0
/opt/apps/entropywatcher/main/safety_gate.sh || SAFETY_EXIT=$?

if [[ $SAFETY_EXIT -eq 2 ]]; then
  echo "CRITICAL: Safety-Gate RED - Upload blockiert"
  send_alert_mail
  exit 2
fi

# ... pCloud Upload durchführen ...
```

---

## 🎯 Wann nutzt man welches Script?

| Situation | Script | Command |
|-----------|--------|---------|
| **Vor jedem Backup** | safety_gate.sh | `./safety_gate.sh` |
| **Täglicher Status-Report** | ew_status.sh | `./ew_status.sh ... mail` |
| **Quick Timer-Check** | ew_forecast_next_run.sh | `STYLE=box ./ew_forecast_next_run.sh` |
| **Backup-Slot planen** | forecast_safety_gate.sh | `./forecast_safety_gate.sh 1` |
| **Troubleshooting langsame Scans** | ew_status.sh | `./ew_status.sh ... dashboard` |
| **Timer-Overlap finden** | ew_forecast_next_run.sh | `./ew_forecast_next_run.sh \| grep left` |
| **Proaktive Warnung** | forecast_safety_gate.sh | `./forecast_safety_gate.sh 7` |

---

## ⚠️ Wichtige Hinweise

**safety_gate.sh:**
- Wird von RTB/pCloud **vor jedem Backup** aufgerufen
- **Nicht manuell deaktivieren** (außer für Testing mit `CHECK_HONEYFILES=0`)
- Bei Honeyfile-Alarm: System sofort prüfen

**ew_status.sh:**
- Mail-Modus benötigt SMTP-Config in `common.env`
- DB-Credentials aus `common.env` werden genutzt
- HTML-Report wird in `/tmp/` gespeichert

**ew_forecast_next_run.sh:**
- Benötigt `systemctl list-timers` (funktioniert nur mit systemd)
- Box-Stil benötigt UTF-8-Terminal

**forecast_safety_gate.sh:**
- Simulation basiert auf OnCalendar-Patterns
- Berücksichtigt keine manuellen Service-Starts
- Forecast > 7 Tage kann ungenau sein

---

## 🔗 Siehe auch

- **[../README.md](../README.md)** - Hauptdokumentation
- **[../docs/UTILITIES.md](../docs/UTILITIES.md)** - Detaillierte Script-Dokumentation
- **[../docs/CONFIG.md](../docs/CONFIG.md)** - ENV-Variablen-Referenz
- **[../tools/README.md](../tools/README.md)** - Helper-Scripts (setup_honeyfiles, etc.)
