# EntropyWatcher & ClamAV Scanner

Pre-Backup Security Gate für Debian-Systeme. Kombiniert Entropie-Analyse, ClamAV-Scanning und Honeyfile-basierte Intrusion Detection, um Backups vor Malware und Ransomware zu schützen.

**Hauptvorteil:** Safety-Gate-Mechanismus blockiert Backups bei kritischen Funden → verhindert Malware-Verbreitung in Backup-Historie und Cloud-Storage.

**Optimiert für:** Linux/Debian, Raspberry Pi NAS-Systeme

---

## 📚 Table of Contents

- [🏗️ Projekt-Übersicht](#️-projekt-übersicht-secure-nas--backup-ecosystem)
  - [📦 Repositories](#-repositories)
  - [🎯 Die Entstehungsgeschichte](#-die-entstehungsgeschichte)
  - [🔗 Zusammenspiel der Komponenten](#-zusammenspiel-der-komponenten)
- [🛠️ Technologie-Stack](#️-technologie-stack)
- [Installation](#installation)
- [Usage](#usage)
- [Features](#features)
- [Examples](#examples)
- [Honeyfile Setup](#honeyfile-setup)
- [Architecture](#architecture)
- [Alert Logic](#alert-logic)
- [Monitoring & Logs](#monitoring--logs)
- [Typical Deployment](#typical-deployment)
- [Best Practices](#best-practices)
- [📚 Erweiterte Dokumentation](#-erweiterte-dokumentation)
- [Contributing](#contributing)
- [License](#license)

---

# 🏗️ Projekt-Übersicht: Secure NAS & Backup Ecosystem

## 📦 Repositories

Dieses Projekt besteht aus mehreren zusammenhängenden Komponenten:

- **[EntropyWatcher & ClamAV Scanner](https://github.com/lastphoenx/entropy-watcher-und-clamav-scanner)** - Pre-Backup Security Gate mit Intrusion Detection
- **[pCloud-Tools](https://github.com/lastphoenx/pcloud-tools)** - Deduplizierte Cloud-Backups mit JSON-Manifest
- **[RTB Wrapper](https://github.com/lastphoenx/rtb)** - Delta-Detection für Rsync Time Backup
- **[Rsync Time Backup](https://github.com/laurent22/rsync-time-backup)** (Original) - Hardlink-basierte lokale Backups

---

## 🎯 Die Entstehungsgeschichte

### Von proprietären NAS-Systemen zu Debian

Die Reise begann mit Frustration: **QNAP** (TS-453 Pro, TS-473A, TS-251+) und **LaCie 5big NAS Pro** waren zwar funktional, aber sobald man mehr als die Standard-Features wollte, wurde es zum Gefrickel. Autostart-Scripts, limitierte Shell-Umgebungen, fehlende Packages - man kam einfach nicht ans Ziel.

**Die Lösung:** Wechsel auf ein vollwertiges **Debian-System**. Hardware: **Raspberry Pi 5** mit **Radxa Penta SATA HAT** (5x 2.5" SATA-SSDs), Samba-Share mit Recycling-Bin. Volle Kontrolle, Standard-Tools, keine Vendor-Lock-ins.

### Der Weg zur vollautomatisierten Backup-Pipeline

#### 1️⃣ **RTB Wrapper** - Delta-gesteuerte Backups

Ziel: Automatisierte lokale Backups mit Deduplizierung über Standard-Debian-Tools.

Ich entschied mich für [Rsync Time Backup](https://github.com/laurent22/rsync-time-backup) - ein cleveres Script, das `rsync --hard-links` nutzt, um platzsparende Snapshots zu erstellen. **Problem:** Das Script lief immer, auch wenn keine Änderungen vorlagen.

**Lösung:** Der [RTB Wrapper](https://github.com/lastphoenx/rtb) prüft vorher ob überhaupt ein Delta existiert (via `rsync --dry-run`). Nur bei echten Änderungen wird das Backup ausgeführt.

#### 2️⃣ **EntropyWatcher + ClamAV** - Pre-Backup Security Gate

Eine Erkenntnis: **Backups von infizierten Dateien sind wertlos.** Schlimmer noch - sie verbreiten Malware in die Backup-Historie und Cloud.

**Lösung:** [EntropyWatcher & ClamAV Scanner](https://github.com/lastphoenx/entropy-watcher-und-clamav-scanner) analysiert `/srv/nas` (und optional das OS) auf:
- **Entropy-Anomalien** (verschlüsselte/komprimierte verdächtige Dateien)
- **Malware-Signaturen** (ClamAV)
- **Safety-Gate-Mechanismus:** Backups werden nur bei grünem Status ausgeführt

Später erweitert auf das gesamte Betriebssystem (`/`, `/boot`, `/home`).

#### 3️⃣ **Honeyfiles** - Intrusion Detection mit Ködern

Der **Shai-Hulud 2.0 npm Worm** zeigte: Moderne Malware sucht aktiv nach Credentials (`~/.aws/credentials`, `.git-credentials`, `.env`-Dateien).

**Gegenmaßnahme:** **Honeyfiles** - 7 Köder-Dateien mit **randomisierten Namen und Pfaden** (gespeichert in `/opt/apps/entropywatcher/config/honeyfile_paths`), überwacht durch **auditd** auf Kernel-Ebene:
- **Tier 1:** Zugriff auf Honeyfile = sofortiger Alarm + Backup-Blockade
- **Tier 2:** Zugriff auf Honeyfile-Config = verdächtig
- **Tier 3:** Manipulation an auditd = kritischer Alarm

**Sicherheits-Feature:** Dateinamen und Speicherorte werden bei Installation randomisiert (z.B. `credentials_a7f3e_20251214` statt `credentials`) → Angreifer können die Pfade nicht aus öffentlicher Dokumentation erraten.

#### 4️⃣ **pCloud-Tools** - Deduplizierte Cloud-Backups

Mit funktionierender lokaler Backup- und Security-Pipeline kam die Frage: **Wie bekomme ich das sicher in die Cloud?**

**Anforderung:** Deduplizierung wie bei `rsync --hard-links` (Inode-Prinzip), aber `rclone` konnte das nicht.

**Lösung:** [pCloud-Tools](https://github.com/lastphoenx/pcloud-tools) mit **JSON-Manifest-Architektur**:
- **JSON-Stub-System:** Jedes Backup speichert nur Metadaten + Verweise auf echte Files
- **Inhalts-basierte Deduplizierung:** Gleicher SHA256-Hash = gleiche Datei = kein Upload
- **Restore-Funktion:** Rekonstruiert komplette Backups aus Manifests + File-Pool

---

## 🔗 Zusammenspiel der Komponenten

```
┌─────────────────────────────────────────────────────────────┐
│  1. EntropyWatcher + ClamAV (Safety Gate)                   │
│     ↓ GREEN = Sicher | YELLOW = Warnung | RED = STOP        │
└─────────────────────────────────────────────────────────────┘
                            ↓ (nur bei GREEN)
┌─────────────────────────────────────────────────────────────┐
│  2. RTB Wrapper prüft: Hat sich was geändert?               │
│     ↓ JA = Delta erkannt | NEIN = Skip Backup               │
└─────────────────────────────────────────────────────────────┘
                            ↓ (nur bei Delta)
┌─────────────────────────────────────────────────────────────┐
│  3. Rsync Time Backup (lokale Snapshots mit Hard-Links)     │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  4. pCloud-Tools (deduplizierter Upload in Cloud)           │
└─────────────────────────────────────────────────────────────┘

       [Honeyfiles überwachen parallel das gesamte System]
```

---

## 🛠️ Technologie-Stack

- **OS:** Debian Bookworm (Raspberry Pi 5)
- **Storage:** 5x 2.5" SATA SSD (Radxa Penta SATA HAT)
- **File Sharing:** Samba mit Recycling-Bin
- **Security:** auditd, ClamAV, Python-basierte Entropy-Analyse
- **Backup:** rsync, JSON-Manifests, pCloud API
- **Automation:** Bash, systemd-timer, Git-Workflow

---

## Installation

### Quick Start – Local Development

For testing and development without systemd integration:

```bash
git clone https://github.com/lastphoenx/entropy-watcher-und-clamav-scanner
cd entropy-watcher-und-clamav-scanner

python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

cp config/common.env.example config/common.env
cp config/nas.env.example config/nas.env
# Edit .env files with database credentials and paths
```

### Production Installation (Automated)

**Interactive mode (recommended):**

```bash
sudo ./install.sh --interactive
```

**Non-interactive mode (CI/CD):**

```bash
sudo ./install.sh --non-interactive \
  --db-password "secure_password" \
  --smtp-host mail.example.com \
  --smtp-user alerts@example.com \
  --smtp-password "smtp_password" \
  --admin-email admin@example.com \
  --install-clamav
```

**What gets installed:**
- MariaDB with `entropywatcher` database
- Python venv with all dependencies
- systemd services + timers
- auditd rules for honeyfile monitoring
- ClamAV (optional)
- Complete configuration templates

See [docs/INSTALLATION.md](docs/INSTALLATION.md) for detailed setup instructions.

## Usage

```
Usage: entropywatcher.py [COMMAND] [OPTIONS]

Commands:
  init-scan     Initialize baseline entropy values for specified paths
  scan          Perform delta scan (only changed files) with periodic full scans
  av-scan       Run ClamAV scan on specified paths
  report        Generate reports (CSV/JSON export available)
  tag-exempt    Mark file as exempt from alerting (still measured)
  tag-normal    Remove exempt status from file

Options:
  --paths       Comma-separated list of paths to scan
  --force       Force re-initialization of baseline
  --source      Filter by source (os|nas)
  --only-flagged  Show only flagged files in report
  --export      Export report to file
  --format      Export format (csv|json)

Umgebungsvariablen werden aus .env-Dateien geladen:
  common.env    Globale Defaults (DB, Mail, Schwellwerte)
  nas.env       NAS-spezifische Konfiguration
  os.env        OS-Scan Konfiguration
  *-av.env      ClamAV-spezifische Einstellungen
```

## Features

* **Entropy-basierte Anomalie-Erkennung** - Misst Dateientropie über Zeit (Baseline + Delta-Tracking)

* **ClamAV Integration** - Signatur-basiertes Malware-Scanning mit automatischen Updates

* **Honeyfile Intrusion Detection** - Kernel-Level Überwachung via auditd mit 3-Tier-Alarm-System

* **Safety Gate Mechanismus** - Backup-Blockade bei kritischen Funden (EXIT 2 = RED)

* **Smart Scanning** - Delta-Scans mit periodischen Vollprüfungen, überspringt unveränderte Dateien

* **Rate-Limited Alerts** - Verhindert E-Mail-Spam durch konfigurierbare Mindestintervalle

* **Flexible Configuration** - ENV-basierte Multi-Job-Profile (NAS, OS, AV-Hot, AV-Weekly)

* **systemd Integration** - Timer-gesteuerte Ausführung mit Journal-Logging

* **Export & Reporting** - CSV/JSON-Export, gefilterte Reports (nur flagged, seit missing)

## Examples

* **Baseline für NAS-Share erstellen:**

```bash
/opt/entropywatcher/venv/bin/python /opt/entropywatcher/entropywatcher.py \
  init-scan --paths "/srv/nas/User1,/srv/nas/Shared"
```

* **Delta-Scan durchführen:**

```bash
/opt/entropywatcher/venv/bin/python /opt/entropywatcher/entropywatcher.py \
  scan --paths "/srv/nas/User1,/srv/nas/Shared"
```

* **ClamAV-Scan auf Hot-Ordner:**

```bash
/opt/entropywatcher/venv/bin/python /opt/entropywatcher/entropywatcher.py \
  av-scan --paths "/srv/nas/Downloads,/srv/nas/Incoming"
```

* **Report generieren (nur flagged):**

```bash
/opt/entropywatcher/venv/bin/python /opt/entropywatcher/entropywatcher.py \
  report --source nas --only-flagged
```

* **CSV-Export für Analyse:**

```bash
/opt/entropywatcher/venv/bin/python /opt/entropywatcher/entropywatcher.py \
  report --source os --export /tmp/entropy_report.csv --format csv
```

* **Datei als exempt markieren (zählt, alarmiert nicht):**

```bash
/opt/entropywatcher/venv/bin/python /opt/entropywatcher/entropywatcher.py \
  tag-exempt /srv/nas/User1/false_positive.zip
```

* **Exempt-Status entfernen:**

```bash
/opt/entropywatcher/venv/bin/python /opt/entropywatcher/entropywatcher.py \
  tag-normal /srv/nas/User1/false_positive.zip
```

* **Systemd-Timer Setup (empfohlen):**

```bash
# Service-Files nach /etc/systemd/system/ kopieren
sudo systemctl daemon-reload

# Timer aktivieren (nicht Services!)
sudo systemctl enable --now entropywatcher-nas.timer
sudo systemctl enable --now entropywatcher-os.timer
sudo systemctl enable --now entropywatcher-nas-av.timer

# Status prüfen
systemctl list-timers | grep entropywatcher
```

## Honeyfile Setup

**Zweck:** Erkennt Ransomware/Malware, die nach Credentials sucht (NPM-Worms, Cloud-Token-Diebe).

**Sicherheits-Prinzip:** Honeyfile-Pfade und -Namen werden bei Installation **randomisiert** (z.B. `/root/.aws/credentials_a7f3e_20251214` statt des dokumentierten `/root/.aws/credentials`). Dadurch können Angreifer die Köder nicht aus öffentlicher Dokumentation erraten. Die tatsächlichen Pfade werden in `/opt/apps/entropywatcher/config/honeyfile_paths` gespeichert und von auditd/monitor automatisch gelesen.

**Vollautomatisches Setup:**

```bash
sudo bash /opt/apps/entropy-watcher/setup_honeyfiles.sh
```

Das Script erledigt:
- ✅ Generiert 7 Köder-Dateien mit **randomisierten Namen** (z.B. `credentials_a7f3e_20251214`)
- ✅ Speichert tatsächliche Pfade in `/opt/apps/entropywatcher/config/honeyfile_paths`
- ✅ Konfiguriert auditd Rules (Tier 1/2/3: Zugriff, Config-Sniffing, Audit-Tampering)
- ✅ Installiert systemd Units (honeyfile-monitor.service + .timer, alle 5 Min)
- ✅ Aktiviert & startet Timer automatisch
- ✅ Gibt **Copy-Paste-Strings mit korrekten randomisierten Pfaden** in die CLI aus

**Nach Installation: Excludes konfigurieren**

**Wichtig:** Die folgenden Beispiele zeigen Platzhalter. Das Setup-Script gibt am Ende die **echten randomisierten Pfade** aus, die du kopieren musst:

```bash
# EntropyWatcher (common.env oder Service-ENV):
SCAN_EXCLUDES="/root/.aws/credentials_a7f3e_20251214,/root/.git-credentials_b8g2h_20251214,..."

# ClamAV (/etc/clamav/clamd.conf):
ExcludePath ^/root/.aws/credentials_a7f3e_20251214$
ExcludePath ^/root/.git-credentials_b8g2h_20251214$
# ...

sudo systemctl reload clamd@main
```

**💡 Tipp:** Nach Setup-Ausführung scrolle zum Ende der Ausgabe - dort findest du fertige Copy-Paste-Strings mit den korrekten randomisierten Pfaden für `common.env` und `clamd.conf`.

**Mail-Konfiguration (automatisch):**

`honeyfile_monitor.sh` liest Einstellungen aus `common.env`:

```bash
MAIL_ENABLE=1
MAIL_SMTP_HOST=mail.example.com
MAIL_SMTP_PORT=587
MAIL_STARTTLS=1
MAIL_USER=alerts@example.com
MAIL_PASS='geheim'
MAIL_TO=admin@example.com
```

**Monitoring:**

```bash
# Live-Prüfung
/usr/local/bin/honeyfile_monitor.sh

# Logs
journalctl -u honeyfile-monitor.service -n 50

# Audit-Events
sudo ausearch -k honeyfile_access --start recent

# Alert-Flag prüfen
ls -la /var/lib/honeyfile_alert
```

**Entfernen:**

```bash
sudo bash /opt/apps/entropy-watcher/setup_honeyfiles.sh --remove
```

## Architecture

**Programm:** `/opt/entropywatcher/entropywatcher.py` (eine CLI für alle Funktionen)

**Datenbank:** MariaDB-Tabelle `files`
- `path` - Dateipfad
- `last_entropy` - Aktueller Entropie-Wert
- `prev_entropy` - Vorheriger Wert (für Sprung-Detection)
- `start_entropy` - Baseline (erste Messung)
- `scanned_at` - Letzter Scan-Zeitstempel
- `score_exempt` - Flag (1 = nicht alarmieren, aber messen)
- `flagged_at` - Wann wurde alarmiert?

**Konfiguration (.env-Dateien):**
- `common.env` → Globale Defaults (DB, Mail-Transport, Schwellwerte)
- Pro Job eigene ENV: `nas.env`, `os.env`, `nas-av.env`, `os-av-weekly.env`

**systemd:**
- `.service` führt einmalig aus (Type=oneshot), setzt ENV-Dateien, User, ExecStart
- `.timer` triggert den Service zeitgesteuert (nur Timer aktivieren!)

**Logging:** Journal mit eigenem SyslogIdentifier (z.B. `ew-os-scan`) → `journalctl -t ew-os-scan`

**Safety Gate Integration:**

```
honeyfile-monitor.service (alle 5 Min)
├─ Prüft Audit-Log auf verdächtige Zugriffe
├─ Setzt /var/lib/honeyfile_alert Flag
└─ Sendet Email-Alert

safety_gate.sh (vor jedem Backup)
├─ Liest /var/lib/honeyfile_alert + live Audit-Log
├─ EXIT 2 (RED) → Backup blockiert
└─ EXIT 0 (GREEN) → weiter zu EntropyWatcher-Checks
```

## Alert Logic

**Entropie-Flags werden gesetzt bei:**
- **Absolut:** `last_entropy >= ALERT_ENTROPY_ABS` (z.B. 7.8)
- **Sprung:** `last_entropy - prev_entropy >= ALERT_ENTROPY_JUMP`

**Exempt-Status:** Dateien mit `score_exempt=1` werden gemessen, aber nicht alarmiert

**E-Mail-Benachrichtigungen:**
- Mail nur bei **neuen Flags** (nicht Altlasten)
- Rate-Limit via `MAIL_MIN_ALERT_INTERVAL_MIN`
- ClamAV: Mail nur bei echten Funden (Exitcode 1)

## Monitoring & Logs

```bash
# Letzte Läufe anzeigen
journalctl -u entropywatcher-nas.service -n 100 --no-pager
journalctl -t ew-os-scan -n 100

# Ad-hoc Start
sudo systemctl start entropywatcher-os.service

# Kurzer Report
/opt/entropywatcher/venv/bin/python /opt/entropywatcher/entropywatcher.py report --source os | head

# Timer-Status
systemctl list-timers | grep entropywatcher
```

## Typical Deployment

**NAS Entropy (stündlich):**
- Service: `entropywatcher-nas.service` + `.timer`
- ENV: `common.env` + `nas.env` (setzt `SCAN_PATHS="/srv/nas/User1,..."`)
- User: `nasuser`

**OS Entropy (täglich):**
- Service: `entropywatcher-os.service` + `.timer`
- ENV: `common.env` + `os.env`
- User: `root` (für `/etc/shadow`, etc.)

**AV Hot (täglich):**
- Service: `*-av.service` + `.timer`
- ENV: `*-av.env` (setzt `SCAN_PATHS` auf Downloads, `CLAMAV_ENABLE=1`)

**AV Weekly (breiter):**
- Service: `*-av-weekly.service` + `.timer`
- ENV: `*-av-weekly.env` (scannt `/srv/nas` vollständig)

## Best Practices

* **Timer aktivieren, nicht Services** - Missed runs werden durch `Persistent=true` nachgeholt

* **Pfade mit Leerzeichen** - Immer in Anführungszeichen: `SCAN_PATHS="/srv/nas/Ablage mit Leerzeichen"`

* **Überlappung vermeiden** - Timer zeitlich staffeln

* **CLAMAV_ENABLE** - Im `common.env` auf 0 lassen, nur in `*-av.env` auf 1

* **Honeyfiles** - Durch SCAN_EXCLUDES und ExcludePath werden False Positives verhindert

* **Rechte** - NAS-Scans als passender User (z.B. `nasuser`), OS-Scans als `root`

---

## 📚 Erweiterte Dokumentation

### 📖 Konfigurations-Referenzen

- **[docs/CONFIG.md](docs/CONFIG.md)** - Vollständige .env-Variablen-Referenz (DB, Mail, Entropy, Health Check, ClamAV)
- **[docs/HONEYFILE_SETUP.md](docs/HONEYFILE_SETUP.md)** - Intrusion Detection Setup & Monitoring
- **[config/README.md](config/README.md)** - Quick-Start für .env-Konfiguration mit Troubleshooting

### 🛠️ Helper Scripts & Tools

- **[tools/README.md](tools/README.md)** - Übersicht aller Helper-Scripts
  - `setup_honeyfiles.sh` - Automatisches Honeyfile-Setup
  - `graceful_shutdown.sh` - Safe-Shutdown mit Backup-Warte-Logik
  - `anonymize-server-configs.sh` - Server-Configs anonymisieren für GitHub
- **[tools/oauth/README.md](tools/oauth/README.md)** - pCloud OAuth2-Flow-Dokumentation

### 🎯 Utility Scripts (Monitoring & Safety-Gate)

- **[scripts/README.md](scripts/README.md)** - Übersicht aller Utility-Scripts
  - **[docs/UTILITIES.md](docs/UTILITIES.md)** - Detaillierte technische Dokumentation

**Wichtige Root-Scripts:**
- `safety_gate.sh` - Zentraler Pre-Backup-Check (Honeyfiles + EntropyWatcher-Status)
  - Prüft ob Backups sicher sind (GREEN=0, YELLOW=1, RED=2)
  - Genutzt von RTB-Wrapper und pCloud-Tools
- `honeyfile_monitor.sh` - Honeyfile-Access-Monitor (läuft als systemd-Service)
  - Überwacht auditd-Logs auf Honeyfile-Zugriffe
  - Setzt Alert-Flag + versendet Alarm-Mails

**Optional Scripts (scripts/):**
- `scripts/ew_status.sh` - Service-Health-Dashboard (terminal/mail)
- `scripts/ew_forecast_next_run.sh` - Timer-Status-Übersicht
- `scripts/forecast_safety_gate.sh` - Safety-Gate-Forecasting
- `scripts/ew_backup_slot_check.sh` - Backup-Slot-Verfügbarkeits-Check

**Quick-Start:**
```bash
# Safety-Gate manuell prüfen
./safety_gate.sh                    # Standard (blockiert nur bei RED)
./safety_gate.sh --strict           # Strict (blockiert auch bei YELLOW)

# Status-Dashboard anzeigen
./scripts/ew_status.sh /opt/apps/entropywatcher/config dashboard

# Status per Mail versenden
./scripts/ew_status.sh /opt/apps/entropywatcher/config mail

# Timer-Übersicht
./scripts/ew_forecast_next_run.sh           # ASCII-Stil
STYLE=box ./scripts/ew_forecast_next_run.sh # Box-Stil (schöner)

# Safety-Gate für morgen forecasten
./scripts/forecast_safety_gate.sh 1         # +1 Tag
./scripts/forecast_safety_gate.sh 7         # +7 Tage
```

---



