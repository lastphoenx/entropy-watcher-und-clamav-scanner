# EntropyWatcher - Server Testing & Verification Guide

Diese Anleitung zeigt, wie du nach Deployment oder Updates das System auf dem Server verifizierst.

---

## 🔧 Vorbereitung

```bash
cd /opt/apps/entropywatcher/main
source ../venv/bin/activate
```

---

## 📊 1. System-Status Überblick

### A) Dashboard - Aktueller Status aller Services

```bash
/opt/apps/entropywatcher/main/scripts/ew_status.sh
```

**Erwartete Ausgabe:**
```
╔════════════════╦════════════╦═══════════════════╦═════════╦════════════╦═══════════════╗
║ Service        ║ Status     ║ Last Scan         ║ Age Min ║ Window Min ║ Buffer übrig %║
╠════════════════╬════════════╬═══════════════════╬═════════╬════════════╬═══════════════╣
║ nas            ║ GREEN      ║ ...               ║     ...  ║         75 ║           ...% ║
║ nas-av         ║ GREEN      ║ ...               ║     ...  ║       1560 ║           ...% ║
║ nas-av-weekly  ║ GREEN      ║ ...               ║     ...  ║      11520 ║           ...% ║
║ os             ║ GREEN      ║ ...               ║     ...  ║       1560 ║           ...% ║
║ os-av          ║ GREEN      ║ ...               ║     ...  ║       1560 ║           ...% ║
║ os-av-weekly   ║ GREEN      ║ ...               ║     ...  ║      11520 ║           ...% ║
╚════════════════╩════════════╩═══════════════════╩═════════╩════════════╩═══════════════╝
```

✅ **PASS:** Alle Services zeigen `GREEN`  
❌ **FAIL:** `YELLOW` oder `RED` → Logs prüfen (siehe Abschnitt 4)

---

### B) Timer-Übersicht - Nächste Scan-Zeiten

```bash
/opt/apps/entropywatcher/main/scripts/ew_forecast_next_run.sh
```

**Oder mit Box-Stil:**
```bash
STYLE=box /opt/apps/entropywatcher/main/scripts/ew_forecast_next_run.sh
```

**Erwartete Ausgabe:**
```
┌─────────────────────────────────────┬─────────┬─────────┬────────────────────┬────────────────────┐
│ Unit                                │ Enabled │ Active  │ LastRun            │ NextRun            │
├─────────────────────────────────────┼─────────┼─────────┼────────────────────┼────────────────────┤
│ entropywatcher-nas.timer            │ enabled │ active  │ ...                │ ...                │
│ entropywatcher-nas-av.timer         │ enabled │ active  │ ...                │ ...                │
│ ...                                 │ ...     │ ...     │ ...                │ ...                │
└─────────────────────────────────────┴─────────┴─────────┴────────────────────┴────────────────────┘
```

✅ **PASS:** Alle Timer `enabled` und `active`  
❌ **FAIL:** Timer `disabled` oder `failed` → `systemctl enable <timer>`

---

### C) Backup-Slot Check - Forecast für Pipeline

```bash
# Heute
/opt/apps/entropywatcher/main/scripts/ew_backup_slot_check.sh 0

# Morgen
/opt/apps/entropywatcher/main/scripts/ew_backup_slot_check.sh 1
```

**Erwartete Ausgabe:**
```
Backup-Slot-Check für Backup-Tag 2025-12-14

Slot 04:00 (2025-12-14 04:00)
Service  EffLastRun                    Window   OK?
nas      2025-12-14 03:22:09           75       OK
nas-av   2025-12-14 02:05:22           1560     OK
...
```

✅ **PASS:** Alle Slots zeigen `OK`  
❌ **FAIL:** `OVERDUE` oder fehlende Scans → Service manuell triggern

---

### D) Safety-Gate Forecast

```bash
# Heute
/opt/apps/entropywatcher/main/scripts/forecast_safety_gate.sh 0

# Morgen  
/opt/apps/entropywatcher/main/scripts/forecast_safety_gate.sh 1
```

**Erwartete Ausgabe:**
```
════════════════════════════════════════════════════════════════════════════
  pCloud Backup Pipeline Forecast für: 2025-12-14
  Pipeline-Starts: 04:00 / 12:00 / 20:00
════════════════════════════════════════════════════════════════════════════

Service       | Last Scan           | Age   | Schedule      | Window | Status
------------- | ------------------- | ----- | ------------- | ------ | ------
nas           | ...                 | ...   | 1h (:20)      |     75 | GREEN
nas-av        | ...                 | ...   | taegl (02:00) |   1560 | GREEN
...
```

✅ **PASS:** Alle Services `GREEN` zu Pipeline-Zeiten  
❌ **FAIL:** `YELLOW`/`RED` → Safety-Gate blockiert Backup

---

## ⏱️ 2. Systemd Timer & Services

### Alle EntropyWatcher Timer auflisten

```bash
systemctl list-timers 'entropywatcher-*' --all
```

**Erwartete Ausgabe:**
```
NEXT                    LEFT      LAST                    PASSED   UNIT                               ACTIVATES
Sun 2025-12-14 16:22:55 10min     Sun 2025-12-14 15:24:08 50min    entropywatcher-nas.timer           entropywatcher-nas.service
...
```

✅ **PASS:** Alle Timer haben NEXT-Zeit und sind aktiv  
❌ **FAIL:** Timer ohne NEXT → `systemctl restart <timer>.timer`

---

### Status einzelner Timer/Services

```bash
systemctl status entropywatcher-nas.timer
systemctl status entropywatcher-nas.service
systemctl status entropywatcher-nas-av.timer
systemctl status entropywatcher-os.timer
```

**Erwartete Ausgabe (Timer):**
```
● entropywatcher-nas.timer - Run EntropyWatcher NAS scan hourly
     Loaded: loaded (/etc/systemd/system/entropywatcher-nas.timer; enabled; preset: enabled)
     Active: active (waiting) since ...
    Trigger: Sun 2025-12-14 16:22:55 CET; 10min left
```

✅ **PASS:** `Active: active (waiting)` mit Trigger-Zeit  
❌ **FAIL:** `failed` oder `inactive` → Logs prüfen

---

### Service User/Group Übersicht

Alle Services nach User/Group durchsuchen:

```bash
for service in /etc/systemd/system/entropywatcher-*.service; do
    echo "=== $(basename $service) ==="
    grep "^User=\|^Group=" "$service" || echo "  (kein User/Group definiert)"
done
```

**Erwartete Konfiguration:**
- **ClamAV-Scans** (nas-av*, os-av*): `User=root` ✅
- **Entropy-Scans** (nas, os): `User=user1` oder `root` (je nach Zugriff)

---

## 📜 3. Journalctl Logs - Letzte Läufe prüfen

### NAS Entropy-Scan (stündlich)

```bash
journalctl -u entropywatcher-nas.service -n 30
```

**Erwartete Ausgabe:**
```
INFO [nas] Timings: discovery=0.02s heavy=0.00s total=0.03s | bytes=0 | ...
INFO [nas] Keine neuen flagged in diesem Lauf – keine Mail.
INFO [nas] scan_summary geschrieben: flagged_new=0 total_after=2 missing=25
Finished entropywatcher-nas.service
```

✅ **PASS:** `Finished` mit `flagged_new=0`  
⚠️ **WARN:** `flagged_new>0` → Neue Anomalien, Mail sollte versendet sein  
❌ **FAIL:** `Failed` oder Python-Traceback → Fehleranalyse

---

### NAS ClamAV-Scan (täglich)

```bash
journalctl -u entropywatcher-nas-av.service -n 30
```

**Erwartete Ausgabe:**
```
INFO [nas-av] ClamAV starte: clamscan --max-filesize 1024M ...
INFO [nas-av] ClamAV: sauber. Findings=0
INFO [nas-av] ClamAV ExitCode=0, Findings=0
Finished entropywatcher-nas-av.service
```

✅ **PASS:** `ExitCode=0, Findings=0`  
⚠️ **WARN:** `Findings>0` → Virusfund! Prüfe av_events in DB  
❌ **FAIL:** `ExitCode=2` → Permission-Fehler (User sollte `root` sein)

---

### OS Entropy-Scan (täglich)

```bash
journalctl -u entropywatcher-os.service -n 30
```

**Mögliche Fehler:**
- **Mail-Fehler:** `socket.gaierror: Temporary failure in name resolution`
  - Ursache: SMTP-Server temporär nicht erreichbar (DNS-Problem)
  - Lösung: SMTP-Retry-Mechanismus (optional), meist harmlos bei temporären Ausfällen

---

### Alle Services auf einmal

```bash
echo "=== NAS (hourly) ==="
journalctl -u entropywatcher-nas.service -n 20 --no-pager

echo "=== NAS-AV (daily) ==="
journalctl -u entropywatcher-nas-av.service -n 20 --no-pager

echo "=== NAS-AV-WEEKLY ==="
journalctl -u entropywatcher-nas-av-weekly.service -n 20 --no-pager

echo "=== OS (daily) ==="
journalctl -u entropywatcher-os.service -n 20 --no-pager

echo "=== OS-AV (daily) ==="
journalctl -u entropywatcher-os-av.service -n 20 --no-pager

echo "=== OS-AV-WEEKLY ==="
journalctl -u entropywatcher-os-av-weekly.service -n 20 --no-pager
```

---

## 🛡️ 4. Honeyfile-Monitor

### Honeyfile Status

```bash
systemctl status honeyfile-monitor.timer
systemctl status honeyfile-monitor.service
```

**Erwartete Ausgabe (Timer):**
```
● honeyfile-monitor.timer - Honeyfile Monitor Timer - Run every 5 minutes
     Active: active (waiting) since ...
    Trigger: ... (in ~5min)
```

**Erwartete Ausgabe (Service - letzter Run):**
```
[2025-12-14 15:57:32] ✓ 7 Honeyfile(s) aus Config geladen
[2025-12-14 15:57:32] Prüfe auf Zugriffe seit letzter Verarbeitung...
[2025-12-14 15:57:32] ✓ Keine verdächtigen Zugriffe
Finished honeyfile-monitor.service
```

✅ **PASS:** `✓ Keine verdächtigen Zugriffe`  
🚨 **CRITICAL:** Alarm-Meldung → SOFORT reagieren! Intrusion detected!

---

### Honeyfile Alarm-Flag prüfen

```bash
cat /var/lib/honeyfile_alert 2>/dev/null && echo "⚠️ HONEYFILE ALARM AKTIV!" || echo "✓ Keine Honeyfile-Alarme"
```

✅ **PASS:** `✓ Keine Honeyfile-Alarme`  
🚨 **CRITICAL:** Alarm-Flag existiert → System kompromittiert!

---

### Honeyfile Logs

```bash
ls -la /var/log/honeyfiles.log
journalctl -u honeyfile-monitor.service -n 20
```

---

### Auditd Rules prüfen

```bash
sudo auditctl -l | grep honeyfile_access
```

**Erwartete Ausgabe:**
```
-a always,exit -S all -F path=/root/.aws/credentials_... -F perm=ra -F auid!=0 -F key=honeyfile_access
-a always,exit -S all -F path=/root/_....git-credentials -F perm=ra -F auid!=0 -F key=honeyfile_access
...
```

✅ **PASS:** 7 Audit-Rules für 7 Honeyfiles  
❌ **FAIL:** Keine Rules → `setup_honeyfiles.sh` erneut ausführen

---

## 💾 5. Datenbank-Checks

### Verbindung herstellen

```bash
sudo mysql
```

```sql
USE entropywatcher;
```

---

### Dashboard-Query

```sql
SELECT 
    (SELECT COUNT(*) FROM files) AS total_files,
    (SELECT COUNT(*) FROM files WHERE flagged=1) AS flagged_files,
    (SELECT COUNT(*) FROM files WHERE missing_since IS NOT NULL) AS missing_files,
    (SELECT COUNT(*) FROM av_events) AS av_detections,
    (SELECT MAX(last_time) FROM files) AS last_scan;
```

✅ **PASS:** Zahlen plausibel, `last_scan` aktuell  
⚠️ **WARN:** `flagged_files>0` → Anomalien vorhanden (kann normal sein)  
❌ **FAIL:** `total_files=0` oder `last_scan` veraltet

---

### Geflaggde Dateien (Anomalien)

```sql
SELECT source, path, last_entropy, note, last_time, missing_since
FROM files
WHERE flagged = 1
ORDER BY last_time DESC;
```

**Interpretation:**
- **Test-Dateien** (`/usr/local/ew-test/`, `/srv/nas/test/`): Normal, können gecleard werden
- **Produktiv-Dateien mit hoher Entropy** (>=7.8): Verschlüsselung oder Ransomware-Verdacht!
- **Jump-Anomalien**: Dateien mit plötzlichem Entropy-Anstieg

---

### Fehlende Dateien (verschwunden)

```sql
SELECT
    SUBSTRING_INDEX(path, '/', 3) AS base_dir,
    COUNT(*) AS cnt
FROM files
WHERE missing_since IS NOT NULL
GROUP BY base_dir
ORDER BY cnt DESC
LIMIT 20;
```

**Interpretation:**
- Viele fehlende Dateien in `/opt/apps` oder `/etc` → Software-Updates, normal
- Fehlende User-Dateien in `/srv/nas` → Manuell gelöscht oder Ransomware!

---

### Virusfunde (ClamAV)

```sql
SELECT detected_at, source, signature, action, path
FROM av_events
WHERE detected_at > NOW() - INTERVAL 7 DAY
ORDER BY detected_at DESC;
```

✅ **PASS:** Empty set (keine Funde)  
🚨 **CRITICAL:** Virusfund → Quarantäne prüfen, System untersuchen

---

### Test-Dateien clearen (optional)

```sql
-- DRY-RUN: Zeige was gelöscht wird
SELECT source, path, note 
FROM files 
WHERE path LIKE '/usr/local/ew-test/%' 
   OR path LIKE '/srv/nas/test/%';

-- Ausführen:
UPDATE files
SET flagged = 0, note = 'cleared: test files'
WHERE path LIKE '/usr/local/ew-test/%'
   OR path LIKE '/srv/nas/test/%';
```

---

## 🔄 6. Backup-System Tests

### Safety-Gate Test (RTB - rsync)

```bash
sudo bash /opt/apps/rtb/rtb_wrapper.sh --dry-run 2>&1 | head -50
```

**Erwartete Ausgabe (GREEN):**
```
[SafetyGate] ✓ Honeyfiles: kein verdächtiger Zugriff erkannt
[SafetyGate]   ✓ nas: GREEN (sicher)
[SafetyGate]   ✓ nas-av: GREEN (sicher)
[SafetyGate] ✓✓✓ SAFETY-GATE: GREEN
[SafetyGate]     → RTB/pCloud Backups ERLAUBT
```

**Erwartete Ausgabe (YELLOW - zu frisch):**
```
[SafetyGate]   ⚠ nas: YELLOW (Warnungen)
[SafetyGate] ✗✗✗ SAFETY-GATE: BLOCKED (YELLOW im Strict-Mode)
[SafetyGate]     → RTB/pCloud Backups BLOCKIERT (--strict aktiv)
```

**Interpretation:**
- **GREEN:** Backup darf laufen ✅
- **YELLOW (too_fresh_to_trust):** Scan < 10min alt → Warte 10min, dann nochmal testen
- **RED:** Ransomware-Verdacht → KEIN Backup! System untersuchen 🚨

✅ **PASS:** GREEN nach 10+ Minuten  
⚠️ **WARN:** YELLOW ist normal kurz nach Scan  
❌ **FAIL:** RED → System kompromittiert

---

### pCloud Sync Test

```bash
sudo bash /opt/apps/pcloud-tools/main/wrapper_pcloud_sync_1to1.sh --dry-run
```

**Erwartete Ausgabe:**
```
[ok] pCloud Preflight ok
[skip] Snapshot 2025-11-23-082336 bereits auf pCloud vorhanden.
```

✅ **PASS:** Preflight OK, Snapshot-Status klar  
❌ **FAIL:** pCloud Auth-Fehler → Token prüfen

---

### pCloud Manifest erstellen (Test)

```bash
python3 /opt/apps/pcloud-tools/main/pcloud_json_manifest.py \
  --root /mnt/backup/rtb_nas/2025-11-22-161159 \
  --hash sha256 \
  --out /tmp/test_manifest.json && \
  echo "✓ OK" && \
  cat /tmp/test_manifest.json | head -10
```

**Erwartete Ausgabe:**
```
Manifest OK: snapshot=20251214-163155 items=7
✓ OK
{
  "schema": 2,
  "snapshot": "20251214-163155",
  "root": "/mnt/backup/rtb_nas/2025-11-22-161159",
  ...
}
```

✅ **PASS:** Manifest erstellt, JSON valide  
❌ **FAIL:** Python-Fehler oder JSON ungültig

---

## 🧪 7. ClamAV Manueller Test

### Als user1 (Standard-User)

```bash
clamscan --max-filesize 1024M --recursive=yes --infected /srv/nas 2>&1 | head -20
```

**Erwartete Ausgabe:**
```
----------- SCAN SUMMARY -----------
Known viruses: 8709007
Engine version: 1.0.9
Scanned files: 22
Infected files: 0
Total errors: 2           ← Normal! Permission-Probleme für 2 Dateien
```

✅ **PASS:** `Infected files: 0`, `Total errors: 2` ist OK  
❌ **FAIL:** `Infected files: >0` → Virusfund!

---

### Als root (voller Zugriff)

```bash
sudo clamscan --max-filesize 1024M --recursive=yes --infected /srv/nas 2>&1 | head -20
```

**Erwartete Ausgabe:**
```
Infected files: 0
Total errors: 0           ← Mit root keine Fehler!
```

✅ **PASS:** Keine Errors, keine Funde  
❌ **FAIL:** Errors auch als root → ClamAV-Config prüfen

---

## 📧 8. Mail-Versand Test

### SMTP-Verbindung testen

```bash
cd /opt/apps/entropywatcher/main
python3 << 'EOF'
import os
import smtplib
from email.mime.text import MIMEText

# Load common.env
env_file = "/opt/apps/entropywatcher/config/common.env"
config = {}
with open(env_file) as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, val = line.split("=", 1)
            config[key] = val.strip('"').strip("'")

print(f"MAIL_ENABLE: {config.get('MAIL_ENABLE')}")
print(f"MAIL_SMTP_HOST: {config.get('MAIL_SMTP_HOST')}")
print(f"MAIL_SMTP_PORT: {config.get('MAIL_SMTP_PORT')}")
print(f"MAIL_TO: {config.get('MAIL_TO')}")
print()

if config.get("MAIL_ENABLE") != "1":
    print("❌ MAIL_ENABLE ist nicht 1 - Versand deaktiviert")
    exit(1)

# Test-Mail senden
msg = MIMEText("Test-Mail von EntropyWatcher\n\nDies ist ein Test des Mail-Systems.")
msg['Subject'] = '[TEST] EntropyWatcher Mail-Check'
msg['From'] = config.get('MAIL_FROM', 'entropywatcher@localhost')
msg['To'] = config.get('MAIL_TO')

print("Verbinde zu SMTP-Server...")
with smtplib.SMTP(config.get('MAIL_SMTP_HOST'), int(config.get('MAIL_SMTP_PORT', 587))) as s:
    if config.get('MAIL_STARTTLS') == '1':
        print("Starte TLS...")
        s.starttls()
    
    if config.get('MAIL_USER'):
        print("Authentifiziere...")
        s.login(config.get('MAIL_USER'), config.get('MAIL_PASS'))
    
    print("Sende Mail...")
    s.send_message(msg)
    print("✅ Mail erfolgreich versendet!")
EOF
```

✅ **PASS:** `✅ Mail erfolgreich versendet!`  
❌ **FAIL:** DNS-Fehler, Auth-Fehler → common.env prüfen

---

## 💽 9. Disk Space

```bash
df -h /srv/nas /mnt/backup /opt/apps
```

**Erwartete Ausgabe:**
```
Filesystem      Size  Used Avail Use% Mounted on
1:2             3.6T  220K  3.4T   1% /srv/nas
/dev/sda1       7.3T  212K  6.9T   1% /mnt/backup
/dev/mmcblk0p2   15G  4.4G  9.0G  33% /
```

✅ **PASS:** Genug Platz (NAS <80%, Backup <80%)  
⚠️ **WARN:** >80% → Platzmangel, Cleanup nötig  
❌ **FAIL:** >95% → Kritisch! Sofort Platz schaffen

---

### Backup-Verzeichnis prüfen

```bash
ls -lh /mnt/backup/
find /mnt/backup/ -type d -name "202*" | head -10
```

**Erwartete Struktur:**
```
/mnt/backup/rtb_nas/
  ├── 2025-11-23-082336/  (neuester Snapshot)
  ├── 2025-11-22-161159/
  └── ...
```

✅ **PASS:** Snapshot-Struktur vorhanden  
❌ **FAIL:** Leer oder keine aktuellen Snapshots → RTB läuft nicht

---

## 🔐 10. Permissions Check

### NAS-Verzeichnis lesbar?

```bash
ls -ld /srv/nas
find /srv/nas -type d ! -readable 2>&1 | head -5
```

**Erwartete Ausgabe:**
```
drwxr-xr-x 9 root root 4096 Oct 12 15:16 /srv/nas
(keine Ausgabe von find = alles lesbar)
```

✅ **PASS:** `/srv/nas` ist lesbar für alle  
❌ **FAIL:** Permission-Errors → Entropy-Scan als `root` laufen lassen

---

## 🎯 11. Integration Tests

### Kompletter Dashboard-Run

```bash
# A) Status Dashboard
/opt/apps/entropywatcher/main/scripts/ew_status.sh

# B) Timer Übersicht
/opt/apps/entropywatcher/main/scripts/ew_forecast_next_run.sh

# C) Backup-Slot Check
/opt/apps/entropywatcher/main/scripts/ew_backup_slot_check.sh 0

# D) Safety-Gate Forecast
/opt/apps/entropywatcher/main/scripts/forecast_safety_gate.sh 0
```

✅ **PASS:** Alle 4 Scripts laufen ohne Fehler, zeigen GREEN  
❌ **FAIL:** Fehler oder RED-Status → Fehleranalyse

---

## 🚀 12. Nach Deployment: Vollständiger Testlauf

Nach Git-Pull oder Config-Änderungen:

```bash
# 1. Services neu laden
sudo systemctl daemon-reload

# 2. Status prüfen
/opt/apps/entropywatcher/main/scripts/ew_status.sh

# 3. Einen Service manuell triggern (Test)
sudo systemctl start entropywatcher-nas.service

# 4. Logs prüfen
journalctl -u entropywatcher-nas.service -n 20

# 5. Safety-Gate testen
sudo bash /opt/apps/rtb/rtb_wrapper.sh --dry-run 2>&1 | head -30
```

✅ **PASS:** Alle Schritte erfolgreich  
❌ **FAIL:** Fehler in einem Schritt → Rollback oder Fix

---

## 🛠️ 13. Troubleshooting

### Service startet nicht

```bash
systemctl status entropywatcher-nas.service
journalctl -u entropywatcher-nas.service -n 50
```

**Häufige Ursachen:**
- Python venv fehlt oder kaputt
- Config-Datei nicht lesbar
- Datenbank nicht erreichbar
- Permission-Probleme

---

### Timer triggert nicht

```bash
systemctl list-timers entropywatcher-nas.timer
systemctl restart entropywatcher-nas.timer
journalctl -u entropywatcher-nas.timer -n 20
```

---

### ClamAV RC=2 (Fehler)

```bash
# Prüfe User des Service
grep "^User=" /etc/systemd/system/entropywatcher-nas-av.service

# Sollte sein: User=root (für vollen Dateizugriff)
```

**Fix:**
```bash
sudo sed -i 's/^User=user1$/User=root/' /etc/systemd/system/entropywatcher-nas-av.service
sudo systemctl daemon-reload
sudo systemctl restart entropywatcher-nas-av.service
```

---

### Mail-Versand schlägt fehl

```bash
# DNS-Test
ping -c 3 mail.gmx.net

# SMTP-Test (siehe Abschnitt 8)
```

**Häufige Ursachen:**
- Temporäres DNS-Problem (nachts, Router-Reboot)
- Firewall blockiert Port 587/465
- Falsche Credentials in common.env

---

## ✅ Erfolgs-Kriterien

Nach erfolgreicher Verifikation sollten alle diese Punkte erfüllt sein:

- ✅ Alle 6 Timer aktiv und enabled
- ✅ `ew_status.sh` zeigt alle Services GREEN
- ✅ Letzte Scans in letzten 24h (außer weekly)
- ✅ Keine Critical-Errors in Logs
- ✅ Honeyfile-Monitor läuft ohne Alarm
- ✅ Safety-Gate zeigt GREEN (nach 10min nach letztem Scan)
- ✅ ClamAV ExitCode=0 (als root)
- ✅ Mail-Versand funktioniert
- ✅ Datenbank erreichbar und konsistent
- ✅ Backup-System ready (RTB + pCloud)

---

## 📚 Weiterführende Dokumentation

- **Datenbank-Queries:** [db-queries.md](db-queries.md)
- **Honeyfiles Setup:** [HONEYFILE_SETUP.md](HONEYFILE_SETUP.md)
- **Architecture:** [architecture.html](architecture.html)
- **Timing-Diagramme:** [timing-diagram-all-scenarios.html](timing-diagram-all-scenarios.html)
