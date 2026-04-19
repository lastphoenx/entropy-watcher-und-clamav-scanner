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

- **Safety-Gate Status:** GREEN/YELLOW/RED
- **EntropyWatcher Counters:** Flagged Files, Missing Files
- **Last Scan Timestamps:** Alle Services
- **ClamAV Findings:** Viren-Treffer

**Installation:** Siehe [pCloud-Tools Dashboard README](https://github.com/lastphoenx/pcloud-tools/blob/main/dashboard/README.md)

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

## 🐛 Debugging

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
