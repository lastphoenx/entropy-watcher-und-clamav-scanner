# ClamAV Integration in EntropyWatcher

EntropyWatcher integriert ClamAV für vollständige Malware-Scanning-Funktionalität neben der Entropy-basierten Ransomware-Erkennung.

## Architektur-Überblick

**Zwei unabhängige Erkennungsschichten:**
1. **Entropy-basierte Erkennung** - Erkennt verschlüsselte/komprimierte Dateien (Ransomware-Indikator)
2. **ClamAV-Signatur-Scan** - Erkennt bekannte Malware via Virensignaturen

**Beide Systeme nutzen dieselbe MySQL-Datenbank** für zentrale Auswertung und Reporting.

## Konfiguration

### Environment-Variablen (.env)

```bash
# ClamAV aktivieren/deaktivieren
CLAMAV_ENABLE=1                    # 0=deaktiviert, 1=aktiviert

# Scanner-Modus
CLAMAV_USE_CLAMD=0                 # 0=clamscan (standalone), 1=clamdscan (Daemon)

# Performance
CLAMAV_THREADS=2                   # Anzahl Threads (nur clamscan)
CLAMAV_TIMEOUT=1800                # Timeout in Sekunden (30 Min default)
CLAMAV_MAX_FILESIZE_MB=0           # Max. Dateigröße (0=unbegrenzt)

# Excludes (nur clamscan)
CLAMAV_EXCLUDES=/mnt/nas/Backup,/proc,/sys
CLAMAV_EXCLUDES_MODE=glob          # "glob" oder "regex"

# Quarantäne
AV_QUARANTINE_DIR=/var/quarantine/clamav
AV_QUARANTINE_ACTION=move          # "move", "copy", "chmod", "none"
AV_QUARANTINE_MODE=0600            # Berechtigungen für quarantinierte Dateien
```

### clamscan vs. clamdscan

| Parameter | clamscan (standalone) | clamdscan (daemon) |
|-----------|----------------------|-------------------|
| **Setup** | Kein Daemon nötig | `clamd` muss laufen |
| **Performance** | Langsamer (lädt DB neu) | Schneller (DB im RAM) |
| **Threads** | Via `--threads` | Via `--multiscan` (nutzt Daemon-Threads) |
| **Excludes** | Via `--exclude` | In `/etc/clamav/clamd.conf` (ExcludePath) |
| **Berechtigungen** | Läuft als Scan-User | Via `--fdpass` (nutzt Daemon-User) |

**Empfehlung:**
- **Hot-Scans (täglich):** `clamdscan` für bessere Performance
- **Weekly Full-Scans:** `clamscan` für mehr Kontrolle (Excludes, Limits)

## Datenbank-Schema

### Tabelle: `av_events`

```sql
CREATE TABLE av_events (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  detected_at DATETIME NOT NULL,           -- Zeitpunkt der Erkennung (UTC)
  source VARCHAR(32),                      -- z.B. "nas-av", "os-av-weekly"
  path TEXT NOT NULL,                      -- Voller Pfad der infizierten Datei
  signature VARCHAR(255) NOT NULL,         -- z.B. "Eicar-Test-Signature"
  engine VARCHAR(32) NOT NULL,             -- "clamscan" oder "clamd"
  action VARCHAR(32) NOT NULL,             -- "quarantine", "copy", "chmod", "none"
  quarantine_path TEXT NULL,               -- Pfad in Quarantäne (falls action=quarantine)
  extra JSON NULL,                         -- Zusätzliche Metadaten
  
  UNIQUE KEY uniq_event (detected_at, signature(120), engine, path(255)),
  INDEX idx_detected (detected_at),
  INDEX idx_source (source)
);
```

**Wichtig:** UNIQUE-Constraint verhindert Duplikate (idempotent via `INSERT IGNORE`).

### Tabelle: `av_whitelist`

```sql
CREATE TABLE av_whitelist (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  signature VARCHAR(255) NOT NULL,         -- z.B. "Eicar-Test-Signature"
  pattern TEXT NULL,                       -- Optional: Pfad-Pattern (für spätere Erweiterung)
  reason TEXT NULL,                        -- Begründung für Whitelist-Entry
  
  UNIQUE KEY uniq_sig (signature(120))
);
```

**Verwendung:** False-Positives können hier eingetragen werden. Events mit whitelisted Signaturen werden nicht in `av_events` geschrieben.

### Scan-Summary Integration

Die Tabelle `scan_summary` trackt auch ClamAV-Statistiken:

```sql
av_found_count INT NOT NULL,              -- Anzahl gefundene Malware
av_quarantined_count INT NOT NULL,        -- Anzahl quarantinierte Dateien
```

## Workflow

### 1. Scan-Ausführung

```bash
# Standalone AV-Scan (ohne Entropy-Scan)
./entropywatcher.py av-scan --paths /mnt/nas/Downloads,/mnt/nas/Incoming

# Mit Entropy-Scan kombiniert (systemd-Service)
# Nutzt SCAN_PATHS aus .env (z.B. entropywatcher-nas-av.service)
./entropywatcher.py scan --scan-paths /mnt/nas/Downloads,/mnt/nas/Incoming
```

**Ablauf intern:**
1. `_clamav_build_cmd()` - Baut ClamAV-Kommando (clamscan/clamdscan + Parameter)
2. `_clamav_run()` - Startet Scan mit Timeout
3. `_clamav_parse_findings()` - Parst Output nach Pattern `<pfad>: <Signature> FOUND`
4. `_quarantine_file()` - Führt Quarantäne-Aktion aus (move/copy/chmod)
5. `record_av_event()` - Schreibt Finding in `av_events` (nach Whitelist-Check)

### 2. Quarantäne-Aktionen

| Action | Beschreibung | Use Case |
|--------|-------------|----------|
| **move** | Datei nach `AV_QUARANTINE_DIR` verschieben | Standard-Quarantäne (Datei isoliert) |
| **copy** | Kopie in Quarantäne, Original bleibt | Forensik (Original für Analyse behalten) |
| **chmod** | Berechtigungen auf 0000 setzen | Datei "einfrieren" ohne Verschieben |
| **none** | Nur loggen, keine Aktion | Dry-Run / Monitoring-Only |

**Quarantäne-Pfad-Struktur:**
```
/var/quarantine/clamav/
├── suspicious_file.exe            # Original-Dateiname beibehalten
├── malware_doc.pdf
└── ...
```

**Wichtig:** Quarantäne-Verzeichnis wird aus ClamAV-Findings ausgefiltert (verhindert Re-Detection).

### 3. Ergebnisse abfragen

#### a) Heutige Findings (alle Sources)

```sql
SELECT detected_at, source, path, signature, action
FROM av_events
WHERE DATE(detected_at) = UTC_DATE()
ORDER BY detected_at DESC;
```

#### b) Quarantinierte Dateien seit 7 Tagen

```sql
SELECT detected_at, source, path, signature, quarantine_path
FROM av_events
WHERE action = 'quarantine'
  AND detected_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
ORDER BY detected_at DESC;
```

#### c) Top 10 häufigste Signaturen (letzter Monat)

```sql
SELECT signature, COUNT(*) AS cnt
FROM av_events
WHERE detected_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY signature
ORDER BY cnt DESC
LIMIT 10;
```

#### d) Findings nach Source aggregiert (heute)

```sql
SELECT source, 
       COUNT(*) AS total_findings,
       SUM(CASE WHEN action='quarantine' THEN 1 ELSE 0 END) AS quarantined
FROM av_events
WHERE DATE(detected_at) = UTC_DATE()
GROUP BY source;
```

#### e) Scan-Übersicht mit AV-Statistiken

```sql
SELECT source, 
       finished_at,
       av_found_count,
       av_quarantined_count,
       note
FROM scan_summary
WHERE av_found_count > 0
ORDER BY finished_at DESC
LIMIT 20;
```

### Quick Reference: Einfachste Methoden zum Auflisten

#### **Heute infizierte Dateien anzeigen:**
```bash
mysql -u entropywatcher -p entropywatcher -t -e "
SELECT 
  DATE_FORMAT(detected_at, '%Y-%m-%d %H:%i') AS detected,
  source,
  signature,
  action,
  path
FROM av_events
WHERE DATE(detected_at) = UTC_DATE()
ORDER BY detected_at DESC;
"
```

#### **Nur Pfade (z.B. für Script-Verarbeitung):**
```bash
mysql -u entropywatcher -p entropywatcher -N -e \
  "SELECT path FROM av_events WHERE DATE(detected_at) = UTC_DATE();"
```

#### **Quarantinierte Dateien der letzten 7 Tage:**
```bash
mysql -u entropywatcher -p entropywatcher -t -e "
SELECT 
  DATE_FORMAT(detected_at, '%Y-%m-%d %H:%i') AS detected,
  signature,
  path AS original_path,
  quarantine_path
FROM av_events
WHERE action = 'quarantine'
  AND detected_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
ORDER BY detected_at DESC;
"
```

#### **Export als CSV:**
```bash
mysql -u entropywatcher -p entropywatcher -N -e "
SELECT detected_at, source, signature, action, path, quarantine_path
FROM av_events
WHERE DATE(detected_at) >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
" | sed 's/\t/,/g' > /tmp/av_findings_$(date +%F).csv
```

### 4. Quarantäne-Zugriff

**Quarantinierte Datei wiederherstellen:**

```bash
# 1. Quarantäne-Pfad aus DB ermitteln
mysql -u entropywatcher -p entropywatcher \
  -e "SELECT quarantine_path FROM av_events WHERE path='/original/path/file.exe';"

# 2. Datei zurückkopieren (VORSICHT!)
sudo cp /var/quarantine/clamav/file.exe /original/path/file.exe

# 3. Optional: AV-Event als "restored" markieren (manuell via extra-JSON)
mysql -u entropywatcher -p entropywatcher \
  -e "UPDATE av_events SET extra=JSON_OBJECT('restored', NOW()) WHERE path='/original/path/file.exe';"
```

**Warnung:** Nur wiederherstellen, wenn du sicher bist, dass es ein False-Positive war!

### 5. Whitelist-Management

**False-Positive zur Whitelist hinzufügen:**

```bash
mysql -u entropywatcher -p entropywatcher <<EOF
INSERT INTO av_whitelist (signature, reason)
VALUES ('Eicar-Test-Signature', 'Testfile für AV-Funktionstest')
ON DUPLICATE KEY UPDATE reason=VALUES(reason);
EOF
```

**Whitelist anzeigen:**

```sql
SELECT signature, reason FROM av_whitelist ORDER BY signature;
```

**Whitelist-Entry entfernen:**

```sql
DELETE FROM av_whitelist WHERE signature='Eicar-Test-Signature';
```

## Systemd-Service-Beispiele

### Hot-Scan (Downloads/Incoming täglich)

```ini
# /etc/systemd/system/entropywatcher-nas-av.service
[Unit]
Description=EntropyWatcher NAS AV Hot-Scan (Downloads/Incoming)
After=network.target mysql.service

[Service]
Type=oneshot
User=root
WorkingDirectory=/opt/apps/entropywatcher/main
ExecStart=/opt/apps/entropywatcher/venv/bin/python entropywatcher.py av-scan \
  --paths /mnt/nas/Downloads,/mnt/nas/Incoming \
  --env-file /opt/apps/entropywatcher/config/nas-av.env
```

```ini
# /etc/systemd/system/entropywatcher-nas-av.timer
[Unit]
Description=EntropyWatcher NAS AV Hot-Scan Timer (täglich 02:00)

[Timer]
OnCalendar=daily 02:00
Persistent=true

[Install]
WantedBy=timers.target
```

### Weekly Full-Scan (gesamtes NAS)

```ini
# /etc/systemd/system/entropywatcher-nas-av-weekly.service
[Unit]
Description=EntropyWatcher NAS AV Weekly Full-Scan
After=network.target mysql.service

[Service]
Type=oneshot
User=root
WorkingDirectory=/opt/apps/entropywatcher/main
ExecStart=/opt/apps/entropywatcher/venv/bin/python entropywatcher.py av-scan \
  --paths /mnt/nas \
  --env-file /opt/apps/entropywatcher/config/nas-av-weekly.env

# Längere Timeouts für Full-Scan
Environment="CLAMAV_TIMEOUT=7200"
```

```ini
# /etc/systemd/system/entropywatcher-nas-av-weekly.timer
[Unit]
Description=EntropyWatcher NAS AV Weekly Full-Scan Timer (Sonntags 04:00)

[Timer]
OnCalendar=Sun 04:00
Persistent=true

[Install]
WantedBy=timers.target
```

## Troubleshooting

### Problem: "ClamAV nicht gefunden"

**Fehler:**
```
FileNotFoundError: [Errno 2] No such file or directory: 'clamscan'
```

**Lösung:**
```bash
# clamscan installieren (Debian/Ubuntu)
sudo apt-get install clamav

# Datenbank aktualisieren
sudo freshclam

# Oder: clamdscan nutzen
sudo apt-get install clamav-daemon
sudo systemctl start clamav-daemon
# In .env: CLAMAV_USE_CLAMD=1
```

### Problem: "clamdscan: Can't connect to clamd"

**Fehler:**
```
ERROR: Can't connect to clamd through /var/run/clamav/clamd.ctl
```

**Lösung:**
```bash
# Daemon starten
sudo systemctl start clamav-daemon
sudo systemctl enable clamav-daemon

# Status prüfen
sudo systemctl status clamav-daemon

# Socket-Pfad in clamdscan.conf prüfen
grep LocalSocket /etc/clamav/clamd.conf
```

### Problem: Timeout bei großen Scans

**Fehler:**
```
ClamAV Timeout nach 1800s
```

**Lösung:**
```bash
# In .env:
CLAMAV_TIMEOUT=7200    # 2 Stunden

# Oder für Weekly-Scans:
CLAMAV_TIMEOUT=21600   # 6 Stunden
```

### Problem: Exclude-Pfade werden nicht beachtet (clamdscan)

**Symptom:** clamdscan scannt auch ausgeschlossene Verzeichnisse

**Lösung:** Bei `CLAMAV_USE_CLAMD=1` werden Excludes NICHT via `--exclude` übergeben (wird ignoriert). Stattdessen in `/etc/clamav/clamd.conf`:

```bash
# /etc/clamav/clamd.conf
ExcludePath ^/mnt/nas/Backup/
ExcludePath ^/proc/
ExcludePath ^/sys/
ExcludePath ^/var/quarantine/

# clamd neu starten
sudo systemctl restart clamav-daemon
```

### Problem: Quarantäne-Verzeichnis nicht beschreibbar

**Fehler:**
```
PermissionError: [Errno 13] Permission denied: '/var/quarantine/clamav/file.exe'
```

**Lösung:**
```bash
# Verzeichnis anlegen mit passenden Berechtigungen
sudo mkdir -p /var/quarantine/clamav
sudo chown root:root /var/quarantine/clamav
sudo chmod 700 /var/quarantine/clamav

# Oder: Service als anderer User laufen lassen
# In .service: User=clamav
```

### Problem: Duplikate in av_events trotz UNIQUE-Constraint

**Symptom:** Gleiche Datei mehrfach in av_events

**Erklärung:** UNIQUE-Constraint nutzt `detected_at + signature + engine + path(255)`. Bei exakt gleicher Sekunde + exakt gleichem Pfad (inkl. 255-Zeichen-Präfix) werden Duplikate verhindert.

**Gut so:** Bei unterschiedlichen Scan-Zeitpunkten (z.B. täglich) werden separate Events geschrieben = korrekt (Tracking über Zeit).

## Best Practices

1. **Hot-Scans täglich** - Downloads/Incoming/Temp-Ordner mit `clamdscan` scannen
2. **Weekly Full-Scans** - Gesamtes NAS mit `clamscan` (mehr Kontrolle via Excludes)
3. **Quarantäne-Action "move"** - Standard für produktive Systeme
4. **Whitelist pflegen** - False-Positives zentral dokumentieren
5. **Timeouts großzügig** - Min. 30 Min für Hot-Scans, 2+ Stunden für Full-Scans
6. **Logs überwachen** - `journalctl -u entropywatcher-nas-av -f`
7. **Mail-Alerts aktivieren** - Bei Findings sofort Benachrichtigung
8. **Quarantäne regelmäßig prüfen** - Alte Findings nach 90 Tagen archivieren/löschen

## Integration mit Safety-Gate

Die `safety_gate.sh` (Backup-Pipeline-Blocker) nutzt sowohl Entropy- als auch AV-Findings:

```bash
# Query kombiniert beide Tabellen:
# - files.flagged (Entropy-basiert)
# - av_events (ClamAV-basiert)

if [ -n "$(mysql -e "SELECT 1 FROM files WHERE flagged=1 LIMIT 1")" ]; then
  echo "BLOCKED: Entropy-Anomalie erkannt"
  exit 1
fi

if [ -n "$(mysql -e "SELECT 1 FROM av_events WHERE detected_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR)")" ]; then
  echo "BLOCKED: ClamAV-Fund in letzten 24h"
  exit 1
fi
```

**Ergebnis:** Cloud-Backup wird blockiert, bis manuelle Freigabe erfolgt (verhindert Upload infizierter Dateien).

## Weiterführende Dokumentation

- **E-Mail-Konfiguration:** [TESTING.md](TESTING.md#mail-configuration)
- **Datenbank-Queries:** [db-queries.md](db-queries.md)
- **systemd-Service-Setup:** [INSTALLATION.md](INSTALLATION.md#systemd-integration)
- **Safety-Gate-Logik:** [README.md](README.md#safety-gate)
