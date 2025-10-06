# EntropyWatcher Configuration Reference

Vollständige Referenz aller Umgebungsvariablen für EntropyWatcher. Diese Variablen werden aus `.env`-Dateien geladen (siehe [config/](../config/)).

---

## 📁 Konfigurationsstruktur

```
config/
├── common.env              ← Globale Defaults (DB, Mail, Schwellwerte)
├── nas.env                 ← NAS-Entropy-Scan (stündlich)
├── os.env                  ← OS-Entropy-Scan (täglich)
├── nas-av.env              ← NAS-AV-Hot-Scan (täglich)
├── nas-av-weekly.env       ← NAS-AV-Full-Scan (wöchentlich)
├── os-av.env               ← OS-AV-Scan (täglich)
└── os-av-weekly.env        ← OS-AV-Full-Scan (wöchentlich)
```

**Prinzip:** `common.env` wird immer geladen, dann überschreiben job-spezifische `.env`-Dateien nur abweichende Werte.

---

## 🗄️ Datenbank (DB_*)

Verbindung zur MariaDB-Datenbank mit Entropie-Historie.

| Variable | Typ | Default | Beschreibung |
|----------|-----|---------|--------------|
| `DB_HOST` | string | - | MariaDB-Host (z.B. `localhost`, IP-Adresse) |
| `DB_PORT` | int | `3306` | MariaDB-Port |
| `DB_NAME` | string | `entropywatcher` | Datenbankname |
| `DB_USER` | string | - | Datenbankbenutzer |
| `DB_PASS` | string | - | Datenbankpasswort |

**Schema:** Die Tabelle `files` enthält:
- `path` - Dateipfad
- `last_entropy` - Aktueller Entropie-Wert
- `prev_entropy` - Vorheriger Wert (für Sprung-Detection)
- `start_entropy` - Baseline (erste Messung)
- `scanned_at` - Letzter Scan-Zeitstempel
- `score_exempt` - Flag (1 = nicht alarmieren, aber messen)
- `flagged_at` - Wann wurde alarmiert?

---

## 📧 E-Mail-Benachrichtigungen (MAIL_*)

Alert-System bei Entropie-Anomalien oder ClamAV-Funden.

| Variable | Typ | Default | Beschreibung |
|----------|-----|---------|--------------|
| `MAIL_ENABLE` | 0\|1 | `1` | E-Mail-Benachrichtigungen aktivieren |
| `MAIL_SMTP_HOST` | string | - | SMTP-Server (z.B. `mail.example.com`) |
| `MAIL_SMTP_PORT` | int | `587` | SMTP-Port (587=STARTTLS, 465=SSL, 25=unverschlüsselt) |
| `MAIL_STARTTLS` | 0\|1 | `1` | STARTTLS verwenden (empfohlen für Port 587) |
| `MAIL_SSL` | 0\|1 | `0` | SSL/TLS verwenden (für Port 465) |
| `MAIL_USER` | string | - | SMTP-Benutzername (oft identisch mit `MAIL_FROM`) |
| `MAIL_PASS` | string | - | SMTP-Passwort |
| `MAIL_FROM` | string | - | Absender-Adresse |
| `MAIL_TO` | string | - | Empfänger-Adresse (Comma-separated für mehrere) |
| `MAIL_SUBJECT_PREFIX` | string | `[EntropyWatcher]` | Betreff-Präfix (z.B. `[NAS-AV]`, `[OS-Entropy]`) |
| `MAIL_MIN_ALERT_INTERVAL_MIN` | int | `30` | Rate-Limit: Min. Minuten zwischen Alarm-E-Mails |
| `ALERT_STATE_FILE` | path | `/var/lib/entropywatcher/last_alert.txt` | State-File für Rate-Limiting (pro Service eigenes File!) |

**Best Practice:**
- `common.env` setzt globale SMTP-Credentials
- Job-spezifische `.env` überschreiben nur `MAIL_FROM`, `MAIL_SUBJECT_PREFIX`, `ALERT_STATE_FILE`
- Pro Service eigenes `ALERT_STATE_FILE` (z.B. `last_alert_nas.txt`, `last_alert_os-av.txt`)

**Rate-Limiting:**
- Alarm-Mails werden nur versendet, wenn letzter Alert älter als `MAIL_MIN_ALERT_INTERVAL_MIN`
- Verhindert E-Mail-Spam bei anhaltenden Anomalien
- Honeyfile-Alerts umgehen das Rate-Limit (kritischer Vorfall!)

---

## 🔍 Scan-Konfiguration

### Grundlegende Scan-Parameter

| Variable | Typ | Default | Beschreibung |
|----------|-----|---------|--------------|
| `SOURCE_LABEL` | string | - | Job-Identifier (z.B. `nas`, `os`, `nas-av`) für Logs/Reports |
| `SCAN_PATHS` | string | - | Comma-separated Liste von Pfaden (z.B. `"/srv/nas,/opt"`) |
| `MIN_SIZE` | int | `1` | Min. Dateigröße in Bytes (0 = kein Limit) |
| `MAX_SIZE` | int | `0` | Max. Dateigröße in Bytes (0 = kein Limit) |

### Excludes & Score-Excludes

| Variable | Typ | Default | Beschreibung |
|----------|-----|---------|--------------|
| `EXCLUDES_MODE` | `glob`\|`regex` | `glob` | Pattern-Modus für `EXCLUDES` |
| `EXCLUDES` | string | - | Comma-separated Patterns (z.B. `"*.git/*,*.pyc,/boot/*"`) |
| `SCORE_EXCLUDES_MODE` | `glob`\|`regex` | `glob` | Pattern-Modus für `SCORE_EXCLUDES` |
| `SCORE_EXCLUDES` | string | - | Dateien messen, aber nicht alarmieren (z.B. `*.jpg,*.mp4`) |

**Unterschied EXCLUDES vs. SCORE_EXCLUDES:**
- **EXCLUDES:** Dateien werden komplett übersprungen (nicht gescannt, nicht in DB)
- **SCORE_EXCLUDES:** Dateien werden gescannt + in DB gespeichert, aber niemals als `flagged` markiert (keine Alarm-Mails)

**Typische EXCLUDES (False-Positives vermeiden):**
```bash
EXCLUDES="*/.git/objects/*,/boot/*,*/av-quarantine/*,*/.Spotlight-V100/*,*/node_modules/*,*/__pycache__/*,*.gz,*.xz,*.zip,*.tar"
```

**Typische SCORE_EXCLUDES (Medien, komprimierte Formate):**
```bash
SCORE_EXCLUDES="*.jpg,*.jpeg,*.png,*.gif,*.mp4,*.mkv,*.avi,*.mp3,*.ogg,*.flac,*.iso,*.sqlite,*.db"
```

---

## 🧮 Entropie-Engine

### Berechnungs-Engine

| Variable | Typ | Default | Beschreibung |
|----------|-----|---------|--------------|
| `USE_ENT` | 0\|1 | `1` | System-Tool `ent` verwenden (falls installiert) |
| `ENT_THRESHOLD` | int | `2097152` | Dateigröße (Bytes), ab der `ent` statt NumPy genutzt wird (2 MiB) |
| `ENT_TIMEOUT` | int | `30` | Timeout (Sekunden) für `ent`-Berechnung |
| `CHUNK_SIZE` | int | `4194304` | Lese-Chunk-Größe (Bytes) bei NumPy-Berechnung (4 MiB) |
| `WORKERS` | int | `3` | Anzahl Heavy-Worker-Prozesse für paralleles Scanning |

**Performance-Tuning:**
- **FUSE/NAS:** `ENT_THRESHOLD=2097152` (2 MiB) - NumPy schneller auf Netzwerk-Shares
- **Lokale SSD:** `ENT_THRESHOLD=0` (immer `ent`) - System-Tool optimal für lokalen I/O
- **Raspberry Pi:** `WORKERS=3` - mehr Prozesse = höhere CPU-Last

### Heuristiken & Alarm-Schwellwerte

| Variable | Typ | Default | Beschreibung |
|----------|-----|---------|--------------|
| `ALERT_ENTROPY_ABS` | float | `7.8` | Absoluter Schwellwert (bits/Byte) - Dateien mit `last_entropy >= 7.8` werden geflaggt |
| `ALERT_ENTROPY_JUMP` | float | `0.2` | Relativer Sprung-Schwellwert - Alarm bei Delta `>= 0.2` zur Baseline/prev |
| `QUICK_FINGERPRINT` | 0\|1 | `1` | Head/Tail-MD5 zur schnellen Änderungsdetektion (ohne Full-Read) |
| `QUICK_FP_SAMPLE` | int | `65536` | Anzahl Bytes für Fingerprint (je 64 KiB Kopf+Ende = 128 KiB total) |
| `PERIODIC_REVERIFY_DAYS` | int | `7` | Vollverifikation alle N Tage, auch wenn mtime unverändert |

**Beispiel-Logik:**
```python
# Alarm wird ausgelöst bei:
if last_entropy >= ALERT_ENTROPY_ABS:  # Absolut: >= 7.8
    flag_file()
elif (last_entropy - prev_entropy) >= ALERT_ENTROPY_JUMP:  # Sprung: Delta >= 0.2
    flag_file()
```

**Typische Entropie-Werte:**
- **Plaintext/Code:** 4.0 - 5.5 bits/Byte
- **Komprimierte Dateien (.gz, .zip):** 7.5 - 7.9 bits/Byte
- **Verschlüsselte Dateien (AES, Ransomware):** 7.95 - 8.0 bits/Byte
- **Binärdaten (.exe, .so):** 6.5 - 7.5 bits/Byte

**Tuning:**
- `ALERT_ENTROPY_ABS=7.8` - Konservativ (wenig False-Positives)
- `ALERT_ENTROPY_ABS=7.5` - Aggressiv (fängt mehr Compressed-Files)
- `ALERT_ENTROPY_JUMP=0.2` - Erkennt Ransomware-Verschlüsselung (Plaintext → Ciphertext)

---

## 🏥 Health Check (Safety Gate)

Für Backup-Gating via `entropywatcher.py status` (genutzt von `safety_gate.sh`).

| Variable | Typ | Default | Beschreibung |
|----------|-----|---------|--------------|
| `HEALTH_WINDOW_MIN` | int | `120` | Zeitfenster (Minuten), in dem aktuelle Scans erwartet werden |
| `HEALTH_AV_FINDINGS_MAX` | int | `0` | Max. tolerierte ClamAV-Funde im Fenster (0 = keine Toleranz) |
| `HEALTH_FLAGGED_MAX` | int | `0` | Max. tolerierte geflaggte Dateien im Fenster (0 = keine Toleranz) |
| `HEALTH_SAFEAGE_MIN` | int | `10` | Min. Minuten seit letztem grünen Scan (Cooldown) |

**Best Practice (per Service-ENV):**
```bash
# nas.env (stündlich um :20)
HEALTH_WINDOW_MIN=75  # 75 Minuten Puffer

# os.env (täglich um 03:40)
HEALTH_WINDOW_MIN=1560  # 26 Stunden Puffer

# nas-av.env (täglich Mo-Sa)
HEALTH_WINDOW_MIN=1560  # 26 Stunden Puffer
```

**Safety Gate Exitcodes:**
- **EXIT 0 (GREEN):** Alle Scans im Fenster, keine Funde, Safeage erfüllt → Backup erlaubt
- **EXIT 1 (YELLOW):** Warnung (veraltete Scans, Safeage nicht erfüllt) → Backup mit Vorsicht
- **EXIT 2 (RED):** Kritisch (AV-Funde, Honeyfile-Alarm, flagged files) → Backup blockiert

---

## 🦠 ClamAV-Integration

Signatur-basiertes Malware-Scanning.

| Variable | Typ | Default | Beschreibung |
|----------|-----|---------|--------------|
| `CLAMAV_ENABLE` | 0\|1 | `0` | ClamAV-Scanning aktivieren (nur in `*-av.env` auf `1` setzen!) |
| `CLAMAV_USE_CLAMD` | 0\|1 | `1` | clamd-Daemon nutzen (schneller als clamscan) |
| `CLAMAV_EXCLUDES` | string | - | Comma-separated Patterns (analog zu `EXCLUDES`) |
| `CLAMAV_EXCLUDES_MODE` | `glob`\|`regex` | `glob` | Pattern-Modus für `CLAMAV_EXCLUDES` |
| `CLAMAV_MAX_FILESIZE_MB` | int | `1024` | Max. Dateigröße in MB für ClamAV-Scan |
| `CLAMAV_THREADS` | int | `1` | Anzahl paralleler ClamAV-Threads (>1 nur bei Multi-Core) |
| `CLAMAV_TIMEOUT` | int | `3600` | Timeout (Sekunden) für gesamten AV-Scan |

**Best Practice:**
- **common.env:** `CLAMAV_ENABLE=0` (global deaktiviert)
- **nas-av.env / os-av.env:** `CLAMAV_ENABLE=1` (nur AV-Jobs aktivieren)
- **ClamAV vs. EntropyWatcher EXCLUDES:** Separate Exclude-Listen!
  - `EXCLUDES` - EntropyWatcher-spezifisch (z.B. `.git/objects`, komprimierte False-Positives)
  - `CLAMAV_EXCLUDES` - AV-spezifisch (z.B. `*.iso`, VM-Images, bereits quarantänierte Dateien)

**Typische CLAMAV_EXCLUDES:**
```bash
CLAMAV_EXCLUDES="*/av-quarantine/*,*/.cache/*,*/node_modules/*,*.iso,*.img,*.vhd,*.vdi,*.qcow2"
```

**Performance:**
- `CLAMAV_USE_CLAMD=1` - Empfohlen (persistenter Daemon, Pre-Loaded-Signaturen)
- `CLAMAV_THREADS=1` - Raspberry Pi (Single-Thread ausreichend)
- `CLAMAV_THREADS=4` - Server mit 8+ Cores (paralleles Scanning)

---

## 📊 Logging

| Variable | Typ | Default | Beschreibung |
|----------|-----|---------|--------------|
| `LOG_LEVEL` | `DEBUG`\|`INFO`\|`WARNING`\|`ERROR` | `INFO` | Python Logging-Level |
| `LOG_FILE` | path | - | Log-Datei-Pfad (leer = stdout/journal) |

**Best Practice:**
- **Development:** `LOG_LEVEL=DEBUG`, `LOG_FILE=/tmp/entropywatcher.log`
- **Production (systemd):** `LOG_LEVEL=INFO`, `LOG_FILE=` (leer → Journal-Logging)
- **Troubleshooting:** `LOG_LEVEL=DEBUG` temporär aktivieren

**Journal-Logging (empfohlen):**
```bash
# Logs per Service anzeigen
journalctl -u entropywatcher-nas.service -n 100 --no-pager
journalctl -t ew-os-scan -n 100  # via SyslogIdentifier
```

---

## 🎯 Job-spezifische ENV-Files

### common.env (Basis für alle Jobs)

**Inhalt:**
- DB-Credentials
- SMTP-Konfiguration
- Globale Schwellwerte (ALERT_ENTROPY_ABS, etc.)
- Default-EXCLUDES (`.git/objects`, `/boot/*`, etc.)
- ClamAV-Defaults (mit `CLAMAV_ENABLE=0`)

### nas.env (NAS-Entropy-Scan, stündlich)

**Überschreibt:**
```bash
SOURCE_LABEL=nas
SCAN_PATHS="/srv/nas"
MAIL_SUBJECT_PREFIX="[NAS-EntropyWatcher]"
ALERT_STATE_FILE=/var/lib/entropywatcher/last_alert_nas.txt
HEALTH_WINDOW_MIN=75  # stündlicher Rhythmus
```

### os.env (OS-Entropy-Scan, täglich)

**Überschreibt:**
```bash
SOURCE_LABEL=os
SCAN_PATHS="/usr/local,/opt,/var/www"
MAIL_SUBJECT_PREFIX="[OS-EntropyWatcher]"
ALERT_STATE_FILE=/var/lib/entropywatcher/last_alert_os.txt
HEALTH_WINDOW_MIN=1560  # täglicher Rhythmus
```

### nas-av.env (NAS-AV-Hot-Scan, täglich)

**Überschreibt:**
```bash
SOURCE_LABEL=nas-av
SCAN_PATHS="/srv/nas/Downloads,/srv/nas/Incoming"
CLAMAV_ENABLE=1  # ← AV aktiviert!
MAIL_SUBJECT_PREFIX="[NAS-AV-Hot]"
ALERT_STATE_FILE=/var/lib/entropywatcher/last_alert_nas-av.txt
HEALTH_WINDOW_MIN=1560
```

### nas-av-weekly.env (NAS-AV-Full-Scan, wöchentlich)

**Überschreibt:**
```bash
SOURCE_LABEL=nas-av-weekly
SCAN_PATHS="/srv/nas"  # komplettes NAS
CLAMAV_ENABLE=1
MAIL_SUBJECT_PREFIX="[NAS-AV-Weekly]"
ALERT_STATE_FILE=/var/lib/entropywatcher/last_alert_nas-av-weekly.txt
HEALTH_WINDOW_MIN=10080  # 7 Tage
```

---

## 🔧 Troubleshooting

### "Zu viele False-Positives (Entropie)"

**Lösung 1:** Schwellwert erhöhen
```bash
# common.env
ALERT_ENTROPY_ABS=7.9  # statt 7.8
ALERT_ENTROPY_JUMP=0.3  # statt 0.2
```

**Lösung 2:** SCORE_EXCLUDES erweitern
```bash
# Medienformate ausschließen
SCORE_EXCLUDES="*.jpg,*.png,*.mp4,*.mkv,*.iso"
```

### "Zu viele False-Positives (ClamAV)"

**Lösung:** CLAMAV_EXCLUDES erweitern
```bash
# nas-av.env
CLAMAV_EXCLUDES="*.iso,*.img,*/av-quarantine/*,*/.recycle/*"
```

### "Mails werden nicht versendet"

**Debug-Schritte:**
1. `LOG_LEVEL=DEBUG` setzen
2. `MAIL_ENABLE=1` prüfen
3. SMTP-Credentials testen:
   ```bash
   python3 -c "import smtplib; s=smtplib.SMTP('mail.example.com', 587); s.starttls(); s.login('user', 'pass'); s.quit()"
   ```
4. Rate-Limit prüfen:
   ```bash
   cat /var/lib/entropywatcher/last_alert_nas.txt
   ```

### "Health Check schlägt fehl (YELLOW/RED)"

**Debug:**
```bash
# Status manuell prüfen
/opt/entropywatcher/venv/bin/python /opt/entropywatcher/entropywatcher.py status

# Logs analysieren
journalctl -u entropywatcher-nas.service -n 50
journalctl -t ew-os-scan --since "1 hour ago"
```

**Häufige Ursachen:**
- `HEALTH_WINDOW_MIN` zu eng (Timer lief nicht rechtzeitig)
- `HEALTH_SAFEAGE_MIN` nicht erfüllt (letzter Scan zu neu)
- Flagged files vorhanden (manuell `tag-exempt` setzen oder Malware entfernen)

---

## 📚 Siehe auch

- **[README.md](../README.md)** - Hauptdokumentation
- **[HONEYFILE_SETUP.md](HONEYFILE_SETUP.md)** - Intrusion Detection mit Ködern
- **[config/](../config/)** - ENV-Beispiel-Dateien
- **[.server-config/README.md](../.server-config/README.md)** - Deployment-Referenz
