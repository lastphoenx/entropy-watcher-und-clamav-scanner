# EntropyWatcher Utility Scripts

Detaillierte Dokumentation für Status-Monitoring, Safety-Gate und Forecasting-Tools. Diese Scripts bieten erweiterte Funktionalität für Pipeline-Überwachung und -Planung.

---

## 📋 Übersicht

| Script | Zweck | Komplexität | Output |
|--------|-------|-------------|--------|
| `safety_gate.sh` | Pre-Backup Security Check | Mittel | Exitcode (0/1/2) |
| `scripts/ew_status.sh` | Service-Health-Dashboard | Hoch | Terminal/HTML/Mail |
| `scripts/ew_forecast_next_run.sh` | Timer-Status-Übersicht | Niedrig | ASCII/Box-Tabelle |
| `scripts/forecast_safety_gate.sh` | Safety-Gate Forecasting | Hoch | Zeitlinien-Tabelle |
| `scripts/ew_backup_slot_check.sh` | Backup-Slot-Check | Mittel | Service-Status-Tabelle |

---

## 🛡️ safety_gate.sh

**Zweck:** Zentraler Pre-Backup-Check für RTB-Wrapper und pCloud-Tools. Prüft Honeyfile-Integrität und EntropyWatcher-Status.

### Funktionsweise

1. **Pre-Flight:** Honeyfile-Check (Fail-Fast bei System-Kompromittierung)
2. **EntropyWatcher-Status:** Prüft `nas` + `nas-av` Services
3. **Exitcode:** 0=GREEN (safe), 1=YELLOW (warning), 2=RED (blocked)

### Usage

```bash
# Standard-Modus (blockiert nur bei RED)
./safety_gate.sh

# Strict-Modus (blockiert auch bei YELLOW)
./safety_gate.sh --strict
```

### Exitcodes

| Code | Status | Bedeutung | Backup erlaubt? |
|------|--------|-----------|-----------------|
| **0** | GREEN | Alle Checks OK | ✅ Ja |
| **1** | YELLOW | Warnungen (z.B. veraltete Scans) | ✅ Ja (❌ Nein im --strict) |
| **2** | RED | Kritisch (Honeyfile-Alarm, AV-Funde) | ❌ Nein |

### Environment Variables

```bash
# Honeyfile-Check deaktivieren (für Testing)
CHECK_HONEYFILES=0 ./safety_gate.sh

# Custom Pfade
HONEYFILE_FLAG=/custom/path/alert ./safety_gate.sh
HONEYFILE_AUDIT_KEY=custom_key ./safety_gate.sh

# EntropyWatcher-Pfade überschreiben
ENTROPYWATCHER_PY=/opt/venv/bin/python \
ENTROPYWATCHER_SCRIPT=/opt/ew/entropywatcher.py \
ENTROPYWATCHER_COMMON_ENV=/opt/config/common.env \
./safety_gate.sh
```

### Architektur

**Checked Services:**
- `nas` - NAS-Dateien Entropy-Scan
- `nas-av` - NAS-AV-Hot-Scan (Downloads, Incoming)

**Nicht geprüft:**
- `os`, `os-av` - OS-Scans sind nicht backup-relevant (Cloud-Backups betreffen nur NAS)
- `*-weekly` - Wöchentliche Scans sind optional

**Honeyfile-Check (Tier 1 + Live):**
1. Flag-File `/var/lib/honeyfile_alert` prüfen
2. Live Audit-Log abfragen (ausearch -k honeyfile_access)
3. Bei **irgendeinem** Treffer → EXIT 2 (RED)

**EntropyWatcher-Status:**
```bash
# Intern ausgeführt:
python entropywatcher.py --env common.env --env nas.env status --json-out /dev/null
```

### Integration

**RTB-Wrapper:**
```bash
# In rtb_wrapper.sh:
if ! /opt/apps/entropywatcher/main/safety_gate.sh; then
  echo "BACKUP BLOCKIERT - Safety-Gate RED/YELLOW"
  exit 1
fi
```

**pCloud-Tools:**
```bash
# In pcloud_sync.sh:
SAFETY_GATE_EXIT=0
/opt/apps/entropywatcher/main/safety_gate.sh || SAFETY_GATE_EXIT=$?

if [[ $SAFETY_GATE_EXIT -eq 2 ]]; then
  echo "CRITICAL: Safety-Gate RED - Upload blockiert"
  exit 2
fi
```

### Troubleshooting

**Problem:** "SYSTEM KOMPROMITTIERT - BACKUP BLOCKIERT"

**Ursache:** Honeyfile wurde zugegriffen.

**Lösung:**
```bash
# 1. Audit-Log prüfen
sudo ausearch -k honeyfile_access --start recent

# 2. Alert-Flag entfernen (nach Prüfung!)
sudo rm /var/lib/honeyfile_alert

# 3. Re-Test
./safety_gate.sh
```

**Problem:** "Service-ENV nicht gefunden"

**Ursache:** `/opt/apps/entropywatcher/config/nas.env` fehlt.

**Lösung:**
```bash
# Konfiguration prüfen
ls -la /opt/apps/entropywatcher/config/
```

---

## 📊 ew_status.sh

**Zweck:** Umfassendes Dashboard für alle EntropyWatcher-Services. Zeigt DB-Status, Service-Gesundheit, AV-Funde, flagged files.

### Usage

```bash
# Terminal-Dashboard (interaktiv)
./ew_status.sh /opt/apps/entropywatcher/config dashboard

# HTML-Report generieren & per Mail versenden
./ew_status.sh /opt/apps/entropywatcher/config mail
```

### Modes

#### 1. Dashboard-Modus (Terminal)

**Output:**
```
╔════════════════╦════════════╦═══════════════════╦═════════╦════════════╦═══════════════╗
║ Service        ║ Status     ║ Last Scan         ║ Age Min ║ Window Min ║ Buffer übrig %║
╠════════════════╬════════════╬═══════════════════╬═════════╬════════════╬═══════════════╣
║ nas            ║ GREEN      ║ 2025-12-14 10:20  ║      15 ║         75 ║         80.0% ║
║ nas-av         ║ YELLOW     ║ 2025-12-13 09:00  ║    1480 ║       1560 ║          5.1% ║
║ os             ║ GREEN      ║ 2025-12-14 03:40  ║     400 ║       1560 ║         74.4% ║
╚════════════════╩════════════╩═══════════════════╩═════════╩════════════╩═══════════════╝
```

**Spalten-Erklärung:**
- **Service:** SOURCE_LABEL aus .env
- **Status:** GREEN (OK), YELLOW (Warnung), RED (Alarm)
- **Last Scan:** Letzter `scanned_at` aus DB
- **Age Min:** Alter des letzten Scans in Minuten
- **Window Min:** `HEALTH_WINDOW_MIN` für diesen Service
- **Buffer übrig %:** Prozent des Zeitfensters noch verfügbar

#### 2. Mail-Modus (HTML)

**Generiert HTML-Report:**
```html
<!DOCTYPE html>
<html>
<head>
  <style>
    /* Dark Theme, Courier Font */
    body { background: #1e1e1e; color: #e0e0e0; }
    .GREEN { color: #28a745; }
    .YELLOW { color: #ffc107; }
    .RED { color: #dc3545; }
  </style>
</head>
<body>
  <h1>EntropyWatcher Status - 2025-12-14 11:00</h1>
  <table>
    <!-- Service-Status-Tabelle -->
  </table>
  
  <h2>AV-Funde (letzte 7 Tage)</h2>
  <pre><!-- ClamAV-Funde-Liste --></pre>
  
  <h2>Flagged Files (letzte 7 Tage)</h2>
  <pre><!-- Entropie-Flags-Liste --></pre>
</body>
</html>
```

**Mail-Versand:**
- Nutzt Python `smtplib` + SMTP-Config aus `common.env`
- Enthält vollständige Tabellen + Attachment (optional)

### Architektur

**Service-Discovery:**
```bash
# Automatisch alle *.env in CONFIG_DIR scannen
for env_file in /opt/apps/entropywatcher/config/*.env; do
  SOURCE_LABEL=$(grep -E '^SOURCE_LABEL=' "$env_file")
  HEALTH_WINDOW_MIN=$(grep -E '^HEALTH_WINDOW_MIN=' "$env_file")
  SERVICES["$SOURCE_LABEL"]="$env_file"
  WINDOWS["$SOURCE_LABEL"]="$HEALTH_WINDOW_MIN"
done
```

**Health-Status-Berechnung:**
```bash
# Status-Logik (pro Service):
last_scan_epoch=$(mysql_query "SELECT MAX(scanned_at) FROM files WHERE source='$SERVICE'")
age_min=$((current_epoch - last_scan_epoch) / 60)
buffer_pct=$(( (window_min - age_min) * 100 / window_min ))

if [[ $age_min -le $window_min ]]; then
  status="GREEN"
elif [[ $age_min -le $((window_min + 60)) ]]; then
  status="YELLOW"  # Grace Period (60 Min)
else
  status="RED"
fi
```

**DB-Queries:**
- `MAX(scanned_at)` - Letzter Scan-Zeitstempel
- `COUNT(*) WHERE flagged_at IS NOT NULL` - Flagged files
- ClamAV-Findings-Tabelle (falls vorhanden)

### Troubleshooting

**Problem:** "ERROR: common.env nicht gefunden"

**Lösung:**
```bash
# Korrekten Pfad angeben
./ew_status.sh /correct/path/to/config dashboard
```

**Problem:** "Keine Services gefunden"

**Ursache:** Keine `.env`-Dateien mit `SOURCE_LABEL` in config/.

**Lösung:**
```bash
# Prüfen
grep -r "SOURCE_LABEL" /opt/apps/entropywatcher/config/
```

**Problem:** "Status immer YELLOW trotz aktuellem Scan"

**Ursache:** `HEALTH_WINDOW_MIN` zu eng oder System-Clock-Drift.

**Lösung:**
```bash
# Window erweitern (in service.env):
HEALTH_WINDOW_MIN=120  # statt 75

# Clock-Drift prüfen:
timedatectl status
```

---

## ⏱️ ew_forecast_next_run.sh

**Zweck:** Zeigt Timer-Status aller EntropyWatcher-Services an. Kompakte Übersicht über LastRun, NextRun, Enabled/Active.

### Usage

```bash
# ASCII-Stil (Standard)
./ew_forecast_next_run.sh

# Box-Stil (Unicode-Boxen, schöner)
STYLE=box ./ew_forecast_next_run.sh
```

### Output

**ASCII-Stil:**
```
EntropyWatcher / Backup-Pipeline Timer-Status

Unit                                | Enabled | Active  | LastRun                                      | NextRun
------------------------------------+--------+---------+----------------------------------------------+--------------------------------------------
entropywatcher-nas.timer            | enabled| active  | Sun 2025-12-14 10:20:22 CET (15m ago)        | Sun 2025-12-14 11:20:00 CET (45m left)
entropywatcher-os.timer             | enabled| active  | Sun 2025-12-14 03:40:00 CET (7h ago)         | Mon 2025-12-15 03:40:00 CET (16h left)
backup-pipeline.timer               | enabled| active  | Sun 2025-12-14 05:00:00 CET (6h ago)         | Mon 2025-12-15 05:00:00 CET (17h left)
```

**Box-Stil:**
```
┌─────────────────────────────────────┬─────────┬─────────┬────────────────────────────────────────────┬────────────────────────────────────────────┐
│ Unit                                │ Enabled │ Active  │ LastRun                                    │ NextRun                                    │
├─────────────────────────────────────┼─────────┼─────────┼────────────────────────────────────────────┼────────────────────────────────────────────┤
│ entropywatcher-nas.timer            │ enabled │ active  │ Sun 2025-12-14 10:20:22 CET (15m ago)      │ Sun 2025-12-14 11:20:00 CET (45m left)     │
└─────────────────────────────────────┴─────────┴─────────┴────────────────────────────────────────────┴────────────────────────────────────────────┘
```

### Architektur

**Datenquelle:**
```bash
# systemctl list-timers parsen
systemctl list-timers entropywatcher-nas.timer

# Output-Format (Zeile 2):
# Sun 2025-12-14 11:20:00 CET 45min left  Sun 2025-12-14 10:20:22 CET 15min ago  entropywatcher-nas.timer
```

**Relative Zeit kürzen:**
```bash
# "15 minutes ago" → "15m ago"
# "2 hours left" → "2h left"
# "3 days ago" → "3d ago"
shorten_rel() {
  echo "$1" | sed -E \
    -e 's/([0-9]+)[[:space:]]*days?/\1d/g' \
    -e 's/([0-9]+)[[:space:]]*hours?/\1h/g' \
    -e 's/([0-9]+)[[:space:]]*mins?/\1m/g'
}
```

### Use Cases

**Quick-Check:**
```bash
# Vor Backup-Pipeline-Start
./ew_forecast_next_run.sh | grep -E "(active|enabled)"
```

**Overlap-Detection:**
```bash
# Timer zu eng getaktet?
STYLE=box ./ew_forecast_next_run.sh | grep "left"
```

**Systemd-Integration:**
```bash
# In Monitoring-Cronjob
if ! ./ew_forecast_next_run.sh | grep -q "entropywatcher-nas.timer"; then
  echo "ERROR: NAS-Timer nicht gefunden"
  exit 1
fi
```

---

## 🔮 forecast_safety_gate.sh

**Zweck:** Forecast-Tool für zukünftige Safety-Gate-Zustände. Simuliert ob Backups zu geplanten Zeitpunkten erlaubt wären.

### Usage

```bash
# Forecast für morgen
./forecast_safety_gate.sh 1

# Forecast für nächste Woche
./forecast_safety_gate.sh 7

# Forecast für heute (default: 0)
./forecast_safety_gate.sh
```

### Output

```
════════════════════════════════════════════════════════════════════════
SAFETY-GATE FORECAST: 2025-12-15 (Target: Mo 05:00)
════════════════════════════════════════════════════════════════════════

Service       Schedule         LastRun (@ Target)                Age (min)  Window (min)  Status
───────────────────────────────────────────────────────────────────────────────────────────────────
nas           1h (:20)         Mo 2025-12-15 04:20:00           40         75            GREEN
nas-av        taegl (09:00)    So 2025-12-14 09:00:00           1200       1560          GREEN
os            1d (03:40)       Mo 2025-12-15 03:40:00           80         1560          GREEN

════════════════════════════════════════════════════════════════════════
FORECAST RESULT @ Mo 05:00: GREEN (alle Services im Window)
════════════════════════════════════════════════════════════════════════
```

### Architektur

**Forecast-Algorithmus:**

1. **Ziel-Zeitpunkt berechnen:**
   ```bash
   target_epoch=$(date -d "+${OFFSET_DAYS} days 05:00:00" +%s)
   ```

2. **Pro Service:**
   - Lese `OnCalendar` aus systemd-Timer
   - Parse Schedule-Typ (hourly/daily/weekly)
   - Berechne letzten Run **vor** Ziel-Zeitpunkt
   - Alter = target_epoch - last_run_epoch
   - Status = (age <= window) ? GREEN : YELLOW/RED

3. **Gesamt-Status:**
   - Alle GREEN → GREEN
   - Mind. 1 YELLOW → YELLOW
   - Mind. 1 RED → RED

**OnCalendar-Parsing:**
```bash
# *-*-* *:20:00 → hourly @ :20
# *-*-* 03:40:00 → daily @ 03:40
# Sun 09:00 → weekly Sunday @ 09:00
# Mon..Sat 09:00 → daily Mon-Sat @ 09:00
```

**Last-Run-Berechnung:**
```bash
# Beispiel: hourly @ :20, Target = Mo 05:00
# → LastRun = Mo 04:20 (40 Min vorher)

# Beispiel: daily @ 03:40, Target = Mo 05:00
# → LastRun = Mo 03:40 (80 Min vorher)
```

### Use Cases

**Backup-Slot-Planung:**
```bash
# Ist Mo 05:00 sicher für RTB-Backup?
./forecast_safety_gate.sh 1

# Ergebnis GREEN → Backup starten
```

**Timer-Overlap-Detektion:**
```bash
# Forecast für mehrere Zeitpunkte
for day in {1..7}; do
  ./forecast_safety_gate.sh $day | grep "FORECAST RESULT"
done
```

**Cronjob-Integration:**
```bash
# Warnung bei zukünftigem RED
if ./forecast_safety_gate.sh 1 | grep -q "RED"; then
  echo "WARNING: Morgen Safety-Gate RED!"
  send_alert_mail
fi
```

### Troubleshooting

**Problem:** "Forecast zeigt falsches LastRun"

**Ursache:** OnCalendar-Parsing-Fehler oder Timezone-Drift.

**Lösung:**
```bash
# Timer-Schedule manuell prüfen
systemctl show entropywatcher-nas.timer | grep OnCalendar

# Manuellen Forecast mit Debug
FORECAST_DEBUG=1 ./forecast_safety_gate.sh 1
```

---

## 📦 scripts/ew_backup_slot_check.sh

**Zweck:** Prüft, ob EntropyWatcher-Services für geplante Backup-Slots (04:00, 12:00, 20:00) innerhalb ihrer Health-Windows liegen.

### Funktionsweise

1. **Backup-Tag ermitteln:** Aus `backup-pipeline.timer` oder via Argument
2. **Für jeden Slot:** Simuliert letzten Scan-Zeitpunkt vor dem Slot
3. **Validierung:** Prüft Alter vs. HEALTH_WINDOW_MIN
4. **Output:** Tabelle mit Service-Status pro Slot

### Usage

```bash
# Nächster geplanter Backup-Tag (aus backup-pipeline.timer)
./scripts/ew_backup_slot_check.sh

# Heute
./scripts/ew_backup_slot_check.sh 0

# Morgen
./scripts/ew_backup_slot_check.sh 1

# Übermorgen
./scripts/ew_backup_slot_check.sh 2
```

### Output-Beispiel

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
Service  EffLastRun (@ 12:00)         Window   Status
─────────────────────────────────────────────────────────────────
nas      2025-12-15 11:20             75       OK
nas-av   2025-12-14 09:00             1560     OK

Slot: 20:00
Service  EffLastRun (@ 20:00)         Window   Status
─────────────────────────────────────────────────────────────────
nas      2025-12-15 19:20             75       OK
nas-av   2025-12-14 09:00             1560     OK
```

### Architektur

**Service-Konfiguration:**
```bash
# In /opt/apps/entropywatcher/config/
SERVICES=(
  "nas:60"       # stündlich (60 min)
  "nas-av:1440"  # täglich (1440 min)
)
```

**Simulation-Logik:**
1. **VERGANGENHEIT:** Letzten echten Scan aus MySQL holen
2. **ZUKUNFT:** Letzten Lauf aus systemd-Timer + Frequenz vorwärts springen

**DB-Zugriff:**
- Benötigt MySQL-Credentials aus `common.env` + Service-ENV
- Query: `SELECT MAX(scan_timestamp) FROM scan_logs WHERE service='$svc' AND scan_timestamp < '$before_ts'`

### Environment Variables

```bash
# CONFIG_DIR (Default: /opt/apps/entropywatcher/config)
CONFIG_DIR=/custom/path ./scripts/ew_backup_slot_check.sh
```

### Use Cases

**Backup-Pipeline-Planung:**
```bash
# Vor Backup-Pipeline: Prüfen ob alle Slots OK
if ./scripts/ew_backup_slot_check.sh | grep -q "OLD"; then
  echo "WARNING: Mindestens ein Slot hat veraltete Scans"
  send_alert
fi
```

**Proaktive Warnungen:**
```bash
# Cronjob: Täglich um 18:00 für morgigen Backup-Tag
0 18 * * * /opt/apps/entropywatcher/scripts/ew_backup_slot_check.sh 1 | grep -q "OLD" && alert_admin
```

**Timer-Overlap-Detection:**
```bash
# Prüfen ob Timer-Frequenz für Slots ausreicht
./scripts/ew_backup_slot_check.sh 0
```

### Troubleshooting

**Problem:** "PARSE-ERROR" oder "DATE-ERROR"

**Ursache:** systemd-Timer-Output konnte nicht geparst werden.

**Lösung:**
```bash
# Timer-Status prüfen
systemctl list-timers entropywatcher-nas.timer

# Manueller Parse-Test
systemctl list-timers entropywatcher-nas.timer | awk 'NR==2 {print $5, $6}'
```

**Problem:** "TIMER-DISABLED"

**Ursache:** Service-Timer ist nicht enabled/active.

**Lösung:**
```bash
# Timer enablen + starten
sudo systemctl enable entropywatcher-nas.timer
sudo systemctl start entropywatcher-nas.timer
```

**Problem:** DB-Zugriff schlägt fehl

**Ursache:** MySQL-Credentials fehlen oder falsch.

**Lösung:**
```bash
# Credentials prüfen
grep -E '^DB_' /opt/apps/entropywatcher/config/common.env

# MySQL-Verbindung testen
mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT 1"
```

---

## 🔒 honeyfile_monitor.sh

**Zweck:** Überwacht Honeyfile-Zugriffe via auditd und sendet Alert-Mails bei unbefugten Zugriffen.

**Hinweis:** Wird typischerweise als systemd-Service im Hintergrund ausgeführt, nicht manuell.

### Funktionsweise

1. **Audit-Log überwachen:** Prüft alle 60 Sekunden auf neue Honeyfile-Zugriffe (audit-key: `honeyfile_access`)
2. **Alert-Flag setzen:** Schreibt `/var/lib/honeyfile_alert` (blockiert Safety-Gate)
3. **Mail-Versand:** Sendet Alarm-Mail mit Details (Zeitpunkt, User, Pfad, Prozess)
4. **Logging:** Schreibt Ereignisse nach `/var/log/honeyfile_monitor.log`

### Usage

```bash
# Manueller Start (für Testing)
sudo ./honeyfile_monitor.sh

# Als systemd-Service (Production)
sudo systemctl start honeyfile-monitor.service
sudo systemctl enable honeyfile-monitor.service
```

### Architektur

**Config-Files:**
- `/opt/apps/entropywatcher/config/honeyfile_paths` - Liste aller Honeyfile-Pfade
- `/opt/apps/entropywatcher/config/common.env` - SMTP-Credentials für Mail-Versand

**State-Files:**
- `/var/lib/honeyfile_alert` - Flag-File (Safety-Gate prüft dieses)
- `/var/lib/honeyfile_last_alert_ts` - Timestamp des letzten Alerts (verhindert Spam)

**Audit-Log:**
```bash
# Manuelle Prüfung
sudo ausearch -k honeyfile_access --start recent

# Output-Format:
# type=SYSCALL ... exe="/usr/bin/cat" ... key="honeyfile_access"
```

### Environment Variables

```bash
# Alle in common.env:
MAIL_FROM="alert@example.com"
MAIL_TO="admin@example.com"
MAIL_SMTP_HOST="smtp.example.com"
MAIL_SMTP_PORT=587
MAIL_SMTP_USER="user"
MAIL_SMTP_PASS="password"
MAIL_SMTP_TLS=true

# Optional:
HONEYFILE_LOG_FILE=/custom/path/honeyfile.log
COMMON_ENV=/custom/path/common.env
```

### Integration

**systemd-Service:**
```ini
# /etc/systemd/system/honeyfile-monitor.service
[Unit]
Description=Honeyfile Access Monitor
After=auditd.service

[Service]
Type=simple
User=root
ExecStart=/opt/apps/entropywatcher/honeyfile_monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**Safety-Gate-Check:**
```bash
# In safety_gate.sh:
if [[ -f /var/lib/honeyfile_alert ]]; then
  echo "❌ SYSTEM KOMPROMITTIERT - Honeyfile-Zugriff detektiert!"
  exit 2  # RED
fi
```

### Troubleshooting

**Problem:** "Config nicht gefunden: /opt/apps/entropywatcher/config/honeyfile_paths"

**Ursache:** Honeyfile-Pfade nicht konfiguriert.

**Lösung:**
```bash
# setup_honeyfiles.sh ausführen (erstellt Config automatisch)
sudo /opt/apps/entropywatcher/tools/setup_honeyfiles.sh
```

**Problem:** Mail-Versand schlägt fehl

**Ursache:** SMTP-Credentials in `common.env` fehlen oder falsch.

**Lösung:**
```bash
# SMTP-Credentials prüfen
grep -E '^MAIL_' /opt/apps/entropywatcher/config/common.env

# Manueller Mail-Test (mit Python)
python3 -c "import smtplib; smtplib.SMTP('$MAIL_SMTP_HOST', $MAIL_SMTP_PORT).quit()"
```

**Problem:** Audit-Log zeigt keine Events

**Ursache:** auditd-Regeln nicht geladen.

**Lösung:**
```bash
# Audit-Regeln prüfen
sudo auditctl -l | grep honeyfile

# Falls leer: setup_honeyfiles.sh erneut ausführen
sudo /opt/apps/entropywatcher/tools/setup_honeyfiles.sh
```

**Problem:** Alert-Flag bleibt nach Check bestehen

**Ursache:** Alert-Flag muss **manuell** entfernt werden (nach Incident-Response).

**Lösung:**
```bash
# OnCalendar manuell prüfen
systemctl cat entropywatcher-nas.timer | grep OnCalendar

# Timezone prüfen
timedatectl status
```

**Problem:** "Status immer RED"

**Ursache:** `HEALTH_WINDOW_MIN` zu eng für Forecast-Zeitpunkt.

**Lösung:**
```bash
# Window erweitern (in service.env):
HEALTH_WINDOW_MIN=1560  # 26 Stunden für tägliche Scans
```

---

## 🔄 Zusammenspiel der Scripts

**Typischer Backup-Workflow:**

```bash
# 1. Pre-Backup: Safety-Gate prüfen (honeyfile_monitor.sh hat Flag gesetzt?)
if ! /opt/apps/entropywatcher/main/safety_gate.sh; then
  echo "Backup blockiert - Safety-Gate nicht GREEN"
  exit 1
fi

# 2. Backup durchführen (RTB/pCloud)
rsync_time_backup ...

# 3. Status-Dashboard anzeigen (nach Backup)
./scripts/ew_status.sh /opt/apps/entropywatcher/config dashboard

# 4. Forecast für morgen (Planung)
./scripts/forecast_safety_gate.sh 1

# 5. Backup-Slots für morgen prüfen
./scripts/ew_backup_slot_check.sh 1
```

**Monitoring-Integration:**

```bash
# Cronjob: Täglich um 06:00 Status-Mail
0 6 * * * /opt/apps/entropywatcher/main/scripts/ew_status.sh /opt/apps/entropywatcher/config mail

# Cronjob: Stündlich Timer-Check
0 * * * * /opt/apps/entropywatcher/main/scripts/ew_forecast_next_run.sh | grep -qE "(active|enabled)" || alert_admin

# Cronjob: Vor Backup-Slot (04:50) Forecast prüfen
50 4 * * * /opt/apps/entropywatcher/main/scripts/forecast_safety_gate.sh 0 | grep -q "GREEN" || skip_backup

# Cronjob: Täglich um 18:00 Backup-Slots für morgen prüfen
0 18 * * * /opt/apps/entropywatcher/main/scripts/ew_backup_slot_check.sh 1 | grep -q "OLD" && alert_admin
```

**Hinweis zu Python-venv:**

Einige Scripts (besonders `scripts/ew_status.sh` und `scripts/ew_backup_slot_check.sh`) benötigen DB-Zugriff und damit die **Python-venv**:

```bash
# Manueller Aufruf mit venv-Aktivierung:
cd /opt/apps/entropywatcher/main
source ../venv/bin/activate
./scripts/ew_status.sh ../config dashboard

# Oder direkt mit venv-Python:
/opt/apps/entropywatcher/venv/bin/python entropywatcher.py --env /opt/apps/entropywatcher/config/common.env --env /opt/apps/entropywatcher/config/nas.env status
```

**Für Cronjobs:**
```bash
# Option 1: venv in Cronjob aktivieren
0 6 * * * cd /opt/apps/entropywatcher/main && source ../venv/bin/activate && ./scripts/ew_status.sh ../config mail

# Option 2: Wrapper-Script mit venv-Aktivierung
0 6 * * * /opt/apps/entropywatcher/main/run_with_venv.sh ./scripts/ew_status.sh ../config mail
```

# Cronjob: Stündlich Timer-Check
0 * * * * /opt/apps/entropywatcher/scripts/ew_forecast_next_run.sh | grep -qE "(active|enabled)" || alert_admin

# Cronjob: Vor Backup-Slot (04:50) Forecast prüfen
50 4 * * * /opt/apps/entropywatcher/scripts/forecast_safety_gate.sh 0 | grep -q "GREEN" || skip_backup
```

---

## 📚 Siehe auch

- **[README.md](../README.md)** - Hauptdokumentation
- **[docs/CONFIG.md](CONFIG.md)** - ENV-Variablen-Referenz
- **[docs/HONEYFILE_SETUP.md](HONEYFILE_SETUP.md)** - Intrusion Detection
- **[tools/README.md](../tools/README.md)** - Helper-Scripts

---

## 🛠️ Entwickler-Notizen

### Performance

**ew_status.sh:**
- MySQL-Queries: ~100ms pro Service
- HTML-Generierung: ~50ms
- Gesamt: < 1 Sekunde für 6 Services

**forecast_safety_gate.sh:**
- systemctl-Aufrufe: ~200ms pro Service
- OnCalendar-Parsing: ~10ms
- Gesamt: < 2 Sekunden für 6 Services

### Erweiterungen

**Neue Checks in safety_gate.sh:**
```bash
# Beispiel: Disk-Space-Check hinzufügen
check_disk_space() {
  local available=$(df /srv/nas | awk 'NR==2 {print $4}')
  if [[ $available -lt 10485760 ]]; then  # < 10 GB
    log "✗ CRITICAL: Disk space < 10 GB"
    return 1
  fi
  return 0
}
```

**Neue Service-Types in forecast_safety_gate.sh:**
```bash
# Beispiel: Monatliche Scans unterstützen
parse_schedule() {
  # ... existing patterns ...
  
  # *-*-01 HH:MM → monthly
  elif [[ "$oncalendar" =~ ^\*-\*-01[[:space:]]+ ]]; then
    echo "monthly:2592000"
  fi
}
```
