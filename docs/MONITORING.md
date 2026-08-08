# Monitoring & Logs

Übersicht über Logging, Monitoring und Status-Checks für EntropyWatcher.

---

## 📊 Systemd Journal (empfohlen)

EntropyWatcher nutzt systemd's Journal für zentrale Log-Verwaltung.

### Logs anzeigen

```bash
# Letzte 100 Zeilen von NAS-Scan
journalctl -u entropywatcher-nas.service -n 100 --no-pager

# Letzte 100 Zeilen von OS-Scan (via SyslogIdentifier)
journalctl -t ew-os-scan -n 100

# Alle EntropyWatcher-Services
journalctl -t ew-* -n 200

# Live-Monitoring
journalctl -u entropywatcher-nas.service -f

# Zeitfenster (letzte 24h)
journalctl -u entropywatcher-nas.service --since "24 hours ago"

# Nur Fehler/Warnings
journalctl -u entropywatcher-nas.service -p warning
```

### Beispiel-Output

```
Apr 19 14:22:15 pi-nas ew-nas-scan[12345]: Starting entropy scan: /srv/nas
Apr 19 14:22:25 pi-nas ew-nas-scan[12345]: Scan completed: 1234 files scanned
Apr 19 14:22:25 pi-nas ew-nas-scan[12345]: Flagged files: 0 | Missing: 0
Apr 19 14:22:25 pi-nas ew-nas-scan[12345]: Status: GREEN
```

---

## 🔍 Status-Checks (Ad-hoc)

### Schneller Status-Check

```bash
# Helper-Script (nutzt entropywatcher.py status)
/opt/apps/entropywatcher/main/scripts/ew_status.sh

# Output:
# NAS Status: GREEN ✓
# OS Status: GREEN ✓
# Last Scan: 2026-04-19 14:22:25 (2 hours ago)
```

### Detaillierte Status-Abfrage

```bash
# NAS Status mit JSON-Output
/opt/apps/entropywatcher/venv/bin/python \
  /opt/apps/entropywatcher/main/entropywatcher.py \
  --env /opt/apps/entropywatcher/config/common.env \
  --env /opt/apps/entropywatcher/config/nas.env \
  status --json

# Output:
# {
#   "status": "green",
#   "summary": {
#     "total_files": 1234,
#     "flagged_count": 0,
#     "missing_count": 0,
#     "last_scan": "2026-04-19T14:22:25",
#     "age_minutes": 120
#   }
# }
```

### Safety-Gate Check

```bash
# Pre-Backup Safety-Gate (wie von rtb_wrapper.sh genutzt)
/opt/apps/entropywatcher/main/safety_gate.sh
echo $?  # 0=GREEN, 1=YELLOW, 2=RED

# Mit Details
/opt/apps/entropywatcher/main/safety_gate.sh 2>&1 | tail -10

# Output:
# ✓ Honeyfiles: kein verdächtiger Zugriff
# ✓ nas: GREEN (sicher)
# ✓ nas-av: GREEN (sicher)
# ✓✓✓ SAFETY-GATE: GREEN
#     → RTB/pCloud Backups ERLAUBT
```

---

## ⏰ Timer-Status

### Aktive Timer anzeigen

```bash
# Alle EntropyWatcher-Timer
systemctl list-timers | grep entropywatcher

# Output:
# NEXT                         LEFT           LAST                         PASSED  UNIT                              ACTIVATES
# Sat 2026-04-19 15:00:00 CEST 37min left     Sat 2026-04-19 14:00:00 CEST 22min ago entropywatcher-nas.timer          entropywatcher-nas.service
# Sun 2026-04-20 02:00:00 CEST 11h left       Sat 2026-04-19 02:00:00 CEST 12h ago   entropywatcher-os.timer           entropywatcher-os.service
```

### Timer manuell starten (Test)

```bash
# Service einmalig ausführen (nicht Timer!)
sudo systemctl start entropywatcher-nas.service

# Status prüfen
systemctl status entropywatcher-nas.service

# Logs anzeigen
journalctl -u entropywatcher-nas.service -n 50
```

---

## 📈 Reports & Statistiken

### Ad-hoc Report generieren

```bash
# Kurzer Report (nur flagged Files)
/opt/apps/entropywatcher/venv/bin/python \
  /opt/apps/entropywatcher/main/entropywatcher.py \
  --env /opt/apps/entropywatcher/config/common.env \
  --env /opt/apps/entropywatcher/config/nas.env \
  report --only-flagged

# Output:
# ┌────────────────────────────────────┬──────────┬────────────┬──────────┬─────────────────────┐
# │ Path                               │ Entropy  │ Prev       │ Jump     │ Flagged At          │
# ├────────────────────────────────────┼──────────┼────────────┼──────────┼─────────────────────┤
# │ /srv/nas/User1/suspicious.bin      │ 7.95     │ 3.2        │ 4.75     │ 2026-04-18 10:45:00 │
# └────────────────────────────────────┴──────────┴────────────┴──────────┴─────────────────────┘
```

### CSV-Export für Analyse

```bash
# Alle Files mit Statistiken
/opt/apps/entropywatcher/venv/bin/python \
  /opt/apps/entropywatcher/main/entropywatcher.py \
  --env /opt/apps/entropywatcher/config/common.env \
  --env /opt/apps/entropywatcher/config/nas.env \
  report --export /tmp/entropy_report.csv --format csv

# Öffnen mit:
libreoffice /tmp/entropy_report.csv
```

### JSON-Export (für Dashboards)

```bash
# JSON-Format für Monitoring-Integration
/opt/apps/entropywatcher/venv/bin/python \
  /opt/apps/entropywatcher/main/entropywatcher.py \
  --env /opt/apps/entropywatcher/config/common.env \
  --env /opt/apps/entropywatcher/config/nas.env \
  report --export /tmp/entropy_report.json --format json

# Verarbeiten mit jq:
cat /tmp/entropy_report.json | jq '.summary'
```

---

## 🚨 Alerting

### Email-Benachrichtigungen

**Konfiguration:** `.env`-Dateien (`common.env`)

```bash
# SMTP-Einstellungen
SMTP_HOST=mail.example.com
SMTP_PORT=587
SMTP_USER=alerts@example.com
SMTP_PASSWORD=secure_password
SMTP_FROM=entropywatch@pi-nas
ADMIN_EMAIL=admin@example.com

# Alert-Rate-Limiting
MAIL_MIN_ALERT_INTERVAL_MIN=30  # Max 1 Mail pro 30 Minuten
```

**Wann werden Mails verschickt?**
- **EntropyWatcher:** Nur bei **neuen** Flags (nicht Altlasten)
- **ClamAV:** Nur bei echten Funden (Exit 1)
- **Honeyfiles:** Jeder Zugriff = sofort Email

### Test-Email senden

```bash
# SMTP-Konfiguration testen
python3 /opt/apps/entropywatcher/main/tools/test_mail_config.py \
  --env /opt/apps/entropywatcher/config/common.env

# Output:
# ✓ SMTP connection successful
# ✓ Test email sent to admin@example.com
```

---

## 📊 Dashboard-Integration

### Monitoring-Dashboard (Web-UI)

Das [pCloud-Tools Monitoring-Dashboard](https://github.com/lastphoenx/pcloud-tools/tree/main/dashboard) zeigt EntropyWatcher-Status in Echtzeit:

- **Safety-Gate Status:** GREEN/YELLOW/RED mit kontextuellen Links zu Troubleshooting-Docs
- **EntropyWatcher Counters:** Flagged Files, Missing Files
- **Last Scan Timestamps:** Alle Services
- **ClamAV Findings:** Viren-Treffer
- **Live Safety-Gate Details:** Zeigt YELLOW/RED Reasons pro Komponente

**Installation & URLs:**
- Setup-Anleitung: [pCloud-Tools Dashboard README](https://github.com/lastphoenx/pcloud-tools/blob/main/dashboard/README.md)
- Dashboard URL (nach April 2026 Update): `http://server-ip:8080/pcloud-tools/dashboard/index.html`
- Diese Dokumentation im Dashboard: `http://server-ip:8080/entropy-watcher-und-clamav-scanner/docs/`

> **💡 April 2026 Update:** Das Dashboard verwendet jetzt absolute Pfade für Multi-Repo Navigation. Der Webserver läuft aus `/opt/apps/` (siehe [DEPLOYMENT_UPDATE_2026.md](https://github.com/lastphoenx/pcloud-tools/blob/main/docs/DEPLOYMENT_UPDATE_2026.md) — Root-Stub: `DEPLOYMENT_UPDATE_2026.md`).

### Status-JSON für Monitoring

Das Dashboard nutzt `aggregate_status.sh`, das wiederum `safety_gate.sh` und EntropyWatcher-Status abfragt:

```bash
# Status-Aggregation ausführen
/opt/apps/pcloud-tools/main/scripts/aggregate_status.sh --verbose

# Generiert: /opt/apps/monitoring/status.json
cat /opt/apps/monitoring/status.json | jq '.services.entropywatcher'

# Output:
# {
#   "nas": {
#     "status": "active",
#     "last_run": "2026-04-19T14:22:25",
#     "flagged_count": 0,
#     "missing_count": 0
#   },
#   "nas-av": {
#     "status": "active",
#     "last_scan": "2026-04-19T03:00:00",
#     "findings": 0
#   }
# }
```

---

## � API Reference - entropywatcher.py status Response

### JSON Response Schema

Wenn `entropywatcher.py status --json` aufgerufen wird, gibt es ein strukturiertes JSON zurück:

```json
{
  "status": "yellow",
  "since": "2026-04-24T17:27:10",
  "window_min": 75,
  "counters": {
    "av_findings": 0,
    "flagged": 0,
    "age_min": 3.48,
    "safeage_min": 10
  },
  "last_runs": {
    "scan": "2026-04-24T17:23:41",
    "av_scan": null
  },
  "reasons": [
    "too_fresh_to_trust"
  ]
}
```

### Status-Werte

| Status | Exit Code | Bedeutung |
|--------|-----------|-----------|
| `green` | 0 | Alle Checks OK, Backup erlaubt |
| `yellow` | 1 | Warnung, Backup mit Vorsicht (im strict-mode blockiert) |
| `red` | 2 | Kritisch, Backup blockiert |

### Reasons-Array

Das `reasons`-Array enthält die **konkreten Gründe** für YELLOW oder RED Status:

| Reason Code | Status | Bedeutung | Action |
|-------------|--------|-----------|--------|
| `too_fresh_to_trust` | YELLOW | Scan jünger als `HEALTH_SAFEAGE_MIN` (meist 10 min) | Warten auf "Abkühlzeit" - System wartet ab, ob eine laufende Ransomware-Verschlüsselung noch nicht erkannt wurde |
| `no_recent_runs` | YELLOW | Kein Scan innerhalb `HEALTH_WINDOW_MIN` (meist 120 min) | Timer/Service prüfen: `systemctl status entropywatcher-nas.timer` |
| `av_findings_present` | RED | AV-Scanner (ClamAV) hat Malware gefunden | Logs prüfen: `journalctl -u entropywatcher-nas-av.service`, Quarantine checken |
| `flagged_files_present` | RED | EntropyWatcher hat Entropy-Anomalien gefunden | Report ausführen: `entropywatcher.py report --only-flagged` |
| `missing_files_detected` | YELLOW/RED | Dateien aus vorherigem Scan fehlen (gelöscht) | Prüfen ob legitim oder Ransomware-Löschung |

### Verwendung in Safety-Gate

Das Safety-Gate-Script (`safety_gate.sh`) nutzt diese Reasons, um detaillierte Logs zu schreiben:

```bash
# Beispiel-Log mit Reason:
2026-04-24 17:27:10 [SafetyGate]   ⚠ nas: YELLOW (too_fresh_to_trust)
```

Diese Reasons werden dann von `aggregate_status.sh` in die `status.json` übernommen und im Dashboard angezeigt:

```json
{
  "scripts": {
    "rtb_wrapper": {
      "live_sg_details": "Honeyfiles: OK | nas: YELLOW (too_fresh_to_trust) | nas-av: GREEN"
    }
  }
}
```

---

## Live Safety-Gate Details (`live_sg_details`)

**Feature:** Echtzeit-Statusanzeige aller Safety-Gate-Komponenten mit individuellen Reasons

**Eingeführt:** April 2026  
**Script:** `aggregate_status.sh` sammelt diese Information während der Live-Prüfung

### Format

```text
Honeyfiles: <STATUS> [(<reason>)] | <component1>: <STATUS> [(<reason>)] | <component2>: <STATUS> [(<reason>)]
```

**Beispiel:**
```text
Honeyfiles: OK | nas: YELLOW (too_fresh_to_trust) | nas-av: GREEN | os: GREEN | os-av: GREEN
```

### Verwendung im Dashboard

Das Dashboard zeigt `live_sg_details` in der **Backup-Tile** an:
- **Label:** "Safety-Gate (live)" wenn verfügbar, sonst "Safety-Gate (hist.)"
- **Anzeige:** Vollständige Details in der Detail-Ansicht unter "└ Komponenten"
- **Farbe:** Basierend auf dem schlechtesten Status (GREEN → YELLOW → RED)

### Unterschied: Live vs. Historical

| Feld | Quelle | Zeitpunkt | Verwendung |
|------|--------|-----------|------------|
| `live_safety_gate` | Aktueller `safety_gate.sh` Aufruf | Während Backup-Check | Zeigt **aktuellen** Sicherheitsstatus |
| `safety_gate` | Letzter erfolgreicher Backup | Nach Backup-Completion | Zeigt historischen Status vom letzten Lauf |
| `live_sg_details` | Aktueller Safety-Gate mit Reasons | Während Backup-Check | **Debugging**: Zeigt welche Komponente YELLOW/RED ist |

### Beispiel-Szenarien

#### Szenario 1: Scan zu frisch (too_fresh_to_trust)
```json
{
  "live_safety_gate": "YELLOW",
  "live_sg_details": "Honeyfiles: OK | nas: YELLOW (too_fresh_to_trust) | nas-av: GREEN",
  "safety_gate": "GREEN"
}
```
**Interpretation:** Letztes Backup war GREEN, aber aktueller Check zeigt YELLOW weil nas-Scan erst 3 Minuten alt ist (< SAFEAGE_MIN=10min).

#### Szenario 2: ClamAV Fund (av_findings_present)
```json
{
  "live_safety_gate": "RED",
  "live_sg_details": "Honeyfiles: OK | nas: GREEN | nas-av: RED (av_findings_present)",
  "safety_gate": "GREEN"
}
```
**Interpretation:** ClamAV hat bei nas-av Malware gefunden → Backup wird blockiert.

#### Szenario 3: Alles normal
```json
{
  "live_safety_gate": "GREEN",
  "live_sg_details": "Honeyfiles: OK | nas: GREEN | nas-av: GREEN | os: GREEN | os-av: GREEN",
  "safety_gate": "GREEN"
}
```
**Interpretation:** Alle Komponenten sind GREEN → Backup wird durchgeführt.

### Troubleshooting mit live_sg_details

Bei YELLOW/RED-Status:
1. **Identifiziere betroffene Komponente** in `live_sg_details`
2. **Lese Reason-Code** aus Klammern (siehe Tabelle oben)
3. **Prüfe Component-Logs:**
   ```bash
   # Für "nas: YELLOW (too_fresh_to_trust)"
   /opt/apps/entropywatcher/venv/bin/python \
     /opt/apps/entropywatcher/main/entropywatcher.py \
     --env /opt/apps/entropywatcher/config/common.env \
     --env /opt/apps/entropywatcher/config/nas.env \
     status --json
   ```
4. **Führe entsprechende Aktion aus** (siehe Tabelle in "API Reference" oben)

---

### Beispiel: Status-Abfrage mit Reason-Parsing

```bash
# Status als JSON abrufen
JSON_OUTPUT=$(
  /opt/apps/entropywatcher/venv/bin/python \
    /opt/apps/entropywatcher/main/entropywatcher.py \
    --env /opt/apps/entropywatcher/config/common.env \
    --env /opt/apps/entropywatcher/config/nas.env \
    status --json
)

# Status-Code extrahieren
STATUS=$(echo "$JSON_OUTPUT" | jq -r '.status')

# Reasons extrahieren
REASONS=$(echo "$JSON_OUTPUT" | jq -r '.reasons[]' | paste -sd ',' -)

echo "Status: $STATUS"
echo "Gründe: $REASONS"

# Output:
# Status: yellow
# Gründe: too_fresh_to_trust
```

### Troubleshooting anhand von Reasons

**Bei `too_fresh_to_trust`:**
```bash
# Warte einfach die SAFEAGE_MIN ab (meist 10 Minuten)
# Dann nochmal prüfen:
sleep 600
/opt/apps/entropywatcher/main/safety_gate.sh
```

**Bei `no_recent_runs`:**
```bash
# Timer prüfen
systemctl list-timers | grep entropywatcher-nas

# Timer manuell starten
sudo systemctl start entropywatcher-nas.service
```

**Bei `av_findings_present`:**
```bash
# Letzte AV-Scan Ergebnisse anzeigen
journalctl -u entropywatcher-nas-av.service -n 100 | grep "FOUND"

# Quarantine-Verzeichnis prüfen
ls -la /var/lib/clamav/quarantine/
```

**Bei `flagged_files_present`:**
```bash
# Detaillierter Report mit nur flagged Files
/opt/apps/entropywatcher/venv/bin/python \
  /opt/apps/entropywatcher/main/entropywatcher.py \
  --env /opt/apps/entropywatcher/config/common.env \
  --env /opt/apps/entropywatcher/config/nas.env \
  report --only-flagged

# Einzelne Datei untersuchen
file /srv/nas/User1/suspicious.bin
hexdump -C /srv/nas/User1/suspicious.bin | head -20
```

---

## �🐛 Debugging

### Service startet nicht

```bash
# Prüfe Service-Status
systemctl status entropywatcher-nas.service

# Prüfe ob Timer aktiviert ist
systemctl is-enabled entropywatcher-nas.timer

# Prüfe .env-Dateien
ls -la /opt/apps/entropywatcher/config/*.env

# Test-Run (manuell)
sudo -u nasuser /opt/apps/entropywatcher/venv/bin/python \
  /opt/apps/entropywatcher/main/entropywatcher.py \
  --env /opt/apps/entropywatcher/config/common.env \
  --env /opt/apps/entropywatcher/config/nas.env \
  scan --paths /srv/nas
```

### DB-Verbindung prüfen

```bash
# Interactive DB-Tool
/opt/apps/entropywatcher/main/tools/db_interactive.sh

# Output:
# MariaDB [entropywatcher]> SELECT COUNT(*) FROM files;
# +----------+
# | COUNT(*) |
# +----------+
# |     1234 |
# +----------+
```

### Safety-Gate zeigt RED

```bash
# Debug: Warum ist Safety-Gate RED?
/opt/apps/entropywatcher/main/tools/debug_status_check.sh

# Prüft:
# - Honeyfile-Flag (/var/lib/honeyfile_alert)
# - Audit-Log (auditdausearch -k honeyfile_access)
# - EntropyWatcher Status (nas + nas-av)
# - Letzte Scan-Timestamps

# Siehe auch: Developer Guide
# docs/DEVELOPER_GUIDE.md#debugging-tipps
```

---

## 📝 Log-Rotation

EntropyWatcher nutzt systemd-Journal (automatische Rotation). Optional: logrotate für separate Log-Files.

**Journal-Konfiguration:**

```bash
# /etc/systemd/journald.conf
SystemMaxUse=500M
SystemKeepFree=1G
MaxRetentionSec=2weeks
```

**Logs manuell aufräumen:**

```bash
# Lösche Logs älter als 7 Tage
sudo journalctl --vacuum-time=7d

# Begrenze auf 500 MB
sudo journalctl --vacuum-size=500M
```

---

## 🔗 Weiterführende Links

- [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md) - systemd Security, Debugging
- [INSTALLATION.md](INSTALLATION.md) - systemd-Services einrichten
- [CONFIG.md](CONFIG.md) - .env-Dateien, Schwellwerte
- [pCloud-Tools Dashboard](https://github.com/lastphoenx/pcloud-tools/tree/main/dashboard) - Web-UI

---

**Zurück zu:** [Hauptdokumentation](../README.md)
