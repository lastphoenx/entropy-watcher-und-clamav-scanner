# EntropyWatcher Configuration

Quick-Start-Anleitung für die Konfiguration von EntropyWatcher. Für detaillierte Variablen-Referenz siehe [docs/CONFIG.md](../docs/CONFIG.md).

---

## 📁 Dateien in diesem Verzeichnis

```
config/
├── README.md                   ← Diese Datei
├── common.env.example          ← Globale Defaults (DB, Mail, Schwellwerte)
├── nas.env.example             ← NAS-Entropy-Scan (stündlich)
├── os.env.example              ← OS-Entropy-Scan (täglich)
├── nas-av.env.example          ← NAS-AV-Hot-Scan (täglich)
├── nas-av-weekly.env.example   ← NAS-AV-Full-Scan (wöchentlich)
├── nas-os-weekly.env.example   ← NAS+OS-Combined-Scan (wöchentlich)
├── os-av.env.example           ← OS-AV-Scan (täglich)
└── os-av-weekly.env.example    ← OS-AV-Full-Scan (wöchentlich)
```

**Hinweis:** Die `.env`-Dateien (ohne `.example`) werden von Git ignoriert und enthalten deine echten Credentials. Die `.example`-Dateien dienen als Template.

---

## 🚀 Quick Start

### 1. Basis-Konfiguration erstellen

```bash
cd /opt/entropywatcher/config

# Globale Konfiguration kopieren
cp common.env.example common.env

# Job-spezifische Konfigurationen erstellen
cp nas.env.example nas.env
cp os.env.example os.env
```

### 2. common.env anpassen

Öffne `common.env` und ersetze die Platzhalter:

```bash
# Datenbank-Credentials
DB_HOST=localhost
DB_USER=entropywatcher
DB_PASS=dein-sicheres-passwort

# SMTP-Server
MAIL_SMTP_HOST=mail.example.com
MAIL_SMTP_PORT=587
MAIL_USER=alerts@example.com
MAIL_PASS=dein-mail-passwort
MAIL_TO=admin@example.com
```

**Wichtig:** `common.env` wird von **allen** Jobs geladen. Setze hier nur globale Defaults!

### 3. Job-spezifische ENV anpassen

Öffne `nas.env` und passe an:

```bash
# NAS-Pfade
SCAN_PATHS="/srv/nas/user-a,/srv/nas/Shared"

# Mail-Branding
MAIL_FROM=nas-alerts@example.com
MAIL_SUBJECT_PREFIX="[NAS-EntropyWatcher]"
```

Öffne `os.env` und passe an:

```bash
# OS-Pfade (kritische System-Verzeichnisse)
SCAN_PATHS="/usr/local,/opt,/var/www"

# Mail-Branding
MAIL_FROM=os-alerts@example.com
MAIL_SUBJECT_PREFIX="[OS-EntropyWatcher]"
```

### 4. Test-Scan durchführen

```bash
# Aktiviere Virtual Environment
source /opt/entropywatcher/venv/bin/activate

# Lade common.env + nas.env und führe Baseline-Scan durch
export $(grep -v '^#' config/common.env | xargs)
export $(grep -v '^#' config/nas.env | xargs)

python entropywatcher.py init-scan --paths "$SCAN_PATHS"
```

**Erwartetes Ergebnis:** Baseline für alle Dateien in `/srv/nas` wird erstellt.

---

## 🎯 Konfigurations-Prinzip

EntropyWatcher nutzt ein **Layer-System**:

```
┌─────────────────────────────────────────┐
│  common.env (Basis-Layer)               │
│  - DB-Credentials                       │
│  - SMTP-Konfiguration                   │
│  - Globale Schwellwerte                 │
│  - Default-EXCLUDES                     │
└─────────────────────────────────────────┘
                  ↓ überschreibt
┌─────────────────────────────────────────┐
│  Job-spezifische ENV (nas.env, os.env)  │
│  - SCAN_PATHS                           │
│  - MAIL_SUBJECT_PREFIX                  │
│  - ALERT_STATE_FILE                     │
│  - HEALTH_WINDOW_MIN                    │
└─────────────────────────────────────────┘
```

**Regel:** Setze in job-spezifischen ENVs nur Werte, die sich vom `common.env`-Default unterscheiden!

---

## 📋 Welche ENV-Dateien brauchst du?

### Minimal-Setup (nur Entropy-Scanning)

```bash
common.env  ← Globale Config
nas.env     ← NAS-Scans
os.env      ← OS-Scans
```

**Systemd-Timer:**
- `entropywatcher-nas.timer` (stündlich) → nutzt `common.env` + `nas.env`
- `entropywatcher-os.timer` (täglich) → nutzt `common.env` + `os.env`

### Erweitert (mit ClamAV)

```bash
common.env          ← Globale Config (CLAMAV_ENABLE=0!)
nas.env             ← NAS-Entropy
nas-av.env          ← NAS-AV-Hot (Downloads, Incoming)
nas-av-weekly.env   ← NAS-AV-Full (gesamtes NAS)
os.env              ← OS-Entropy
os-av.env           ← OS-AV (kritische Pfade)
```

**Best Practice:**
- `common.env` setzt `CLAMAV_ENABLE=0` (global deaktiviert)
- Nur `*-av.env`-Dateien setzen `CLAMAV_ENABLE=1`

---

## ⚙️ Wichtige Variablen erklärt

### SCAN_PATHS (Pflicht in job-spezifischen ENVs)

Comma-separated Liste von Pfaden:

```bash
# NAS-Scan
SCAN_PATHS="/srv/nas/user-a,/srv/nas/Shared"

# OS-Scan (ohne /boot - komprimierte Kernel → False-Positives)
SCAN_PATHS="/usr/local,/opt,/var/www"
```

**Tipp:** Pfade mit Leerzeichen in Anführungszeichen setzen:
```bash
SCAN_PATHS="/srv/nas/Ablage mit Leerzeichen,/srv/nas/User1"
```

### EXCLUDES vs. SCORE_EXCLUDES

**EXCLUDES** - Dateien komplett überspringen (nicht scannen):
```bash
EXCLUDES="*/.git/objects/*,/boot/*,*.pyc,*.gz,*.zip"
```

**SCORE_EXCLUDES** - Dateien scannen, aber nicht alarmieren:
```bash
SCORE_EXCLUDES="*.jpg,*.mp4,*.iso,*.sqlite"
```

**Unterschied:**
- **EXCLUDES:** Nicht in Datenbank, kein Scan, kein Alert
- **SCORE_EXCLUDES:** In Datenbank, gescannt, aber niemals geflaggt (kein Alert)

### ALERT_STATE_FILE (Rate-Limiting)

Pro Service eigenes State-File:

```bash
# nas.env
ALERT_STATE_FILE=/var/lib/entropywatcher/last_alert_nas.txt

# os.env
ALERT_STATE_FILE=/var/lib/entropywatcher/last_alert_os.txt

# nas-av.env
ALERT_STATE_FILE=/var/lib/entropywatcher/last_alert_nas-av.txt
```

**Zweck:** Verhindert E-Mail-Spam durch Rate-Limiting (`MAIL_MIN_ALERT_INTERVAL_MIN=30`).

### HEALTH_WINDOW_MIN (Safety Gate)

Zeitfenster, in dem Scans erwartet werden (für Backup-Gating):

```bash
# nas.env (stündlich um :20)
HEALTH_WINDOW_MIN=75  # 60 Min + 15 Min Puffer

# os.env (täglich um 03:40)
HEALTH_WINDOW_MIN=1560  # 24h + 2h Puffer

# nas-av-weekly.env (sonntags)
HEALTH_WINDOW_MIN=10080  # 7 Tage
```

---

## 🔍 ClamAV-Konfiguration (Optional)

### Aktivierung nur in AV-Jobs

**common.env** (Basis):
```bash
CLAMAV_ENABLE=0  # ← Global AUS!
```

**nas-av.env** (AV-Job):
```bash
CLAMAV_ENABLE=1  # ← Nur hier aktivieren!
CLAMAV_USE_CLAMD=1
CLAMAV_EXCLUDES="*.iso,*.img,*/av-quarantine/*"
```

### Getrennte Exclude-Listen

**EntropyWatcher-EXCLUDES** (für Entropy-Scans):
```bash
EXCLUDES="*/.git/objects/*,/boot/*,*.pyc"
```

**ClamAV-EXCLUDES** (für AV-Scans):
```bash
CLAMAV_EXCLUDES="*.iso,*.img,*.vhd,*/av-quarantine/*"
```

**Warum getrennt?**
- `.git/objects` hat hohe Entropie (Git-Compression) → Entropy-EXCLUDES
- `*.iso` ist zu groß für AV-Scan → CLAMAV_EXCLUDES
- `av-quarantine` ist bereits isoliert → beides ausschließen

---

## ✅ Checkliste für neue Umgebung

- [ ] `common.env` erstellt und DB-Credentials eingetragen
- [ ] `common.env` SMTP-Credentials eingetragen
- [ ] `nas.env` erstellt und `SCAN_PATHS` angepasst
- [ ] `os.env` erstellt und `SCAN_PATHS` angepasst
- [ ] Pro Service eigenes `ALERT_STATE_FILE` gesetzt
- [ ] Test-Scan durchgeführt (`init-scan`)
- [ ] Baseline in MariaDB verifiziert (`SELECT COUNT(*) FROM files;`)
- [ ] Test-Mail versendet (manuell `scan` mit neuem File)
- [ ] Systemd-Timer installiert und aktiviert
- [ ] Optional: `*-av.env` für ClamAV-Scans erstellt

---

## 🛠️ Troubleshooting

### "Variable wird nicht geladen"

**Problem:** ENV-Datei existiert, aber Variable bleibt Default.

**Lösung:** Systemd-Service prüfen:
```bash
# In /etc/systemd/system/entropywatcher-nas.service
EnvironmentFile=/opt/entropywatcher/config/common.env
EnvironmentFile=/opt/entropywatcher/config/nas.env
```

**Wichtig:** `EnvironmentFile` darf **keine** `.example`-Dateien laden!

### "Zu viele False-Positives"

**Lösung:** SCORE_EXCLUDES erweitern:
```bash
# common.env
SCORE_EXCLUDES="*.jpg,*.png,*.gif,*.mp4,*.mkv,*.avi,*.iso,*.sqlite"
```

### "Mail-Spam trotz Rate-Limiting"

**Problem:** Alle Services nutzen das gleiche `ALERT_STATE_FILE`.

**Lösung:** Pro Service eigenes State-File:
```bash
# nas.env
ALERT_STATE_FILE=/var/lib/entropywatcher/last_alert_nas.txt

# os.env
ALERT_STATE_FILE=/var/lib/entropywatcher/last_alert_os.txt
```

### "EXCLUDES funktionieren nicht"

**Problem:** Pattern-Syntax falsch.

**Lösung:** `EXCLUDES_MODE=glob` (Standard):
```bash
EXCLUDES="*/.git/objects/*"  # ← Wildcard '*' für beliebige Ordner
```

**Nicht:** `EXCLUDES="**/.git/objects/**"` (das ist rsync-Syntax, nicht glob!)

---

## 📚 Siehe auch

- **[docs/CONFIG.md](../docs/CONFIG.md)** - Vollständige Variablen-Referenz
- **[README.md](../README.md)** - Hauptdokumentation
- **[docs/HONEYFILE_SETUP.md](../docs/HONEYFILE_SETUP.md)** - Intrusion Detection Setup
- **[.server-config/README.md](../.server-config/README.md)** - Deployment-Referenz

---

## 💡 Best Practices

1. **Secrets nie committen:** `.env`-Dateien sind in `.gitignore`, nur `.example`-Dateien versionieren
2. **Pro Service eigenes State-File:** Verhindert Rate-Limiting-Konflikte
3. **HEALTH_WINDOW_MIN großzügig:** Puffer für Timer-Verzögerungen einplanen
4. **SCORE_EXCLUDES statt EXCLUDES:** Lieber messen und nicht alarmieren, als komplett überspringen
5. **CLAMAV_ENABLE=0 in common.env:** Nur in AV-Jobs aktivieren (reduziert CPU-Last)
