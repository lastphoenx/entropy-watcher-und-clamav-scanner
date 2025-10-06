# Honeyfile Intrusion Detection System

## Übersicht

Das **Honeyfile Intrusion Detection System** ist ein Sicherheitsmechanismus, der verlockende "Köder-Dateien" auf dem System verteilt. Diese Honeyfiles sollten niemals zugegriffen werden - ein Zugriff bedeutet sofortige System-Kompromittierung.

### Funktionsweise

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Honeyfiles erstellen (randomisiert)                      │
│    Stored in: /opt/apps/entropywatcher/config/honeyfile_paths
│    7 fake credential files with random names + timestamps   │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. Multi-Tier Audit Rules                                   │
│    Tier 1: Honeyfile Access (-k honeyfile_access)           │
│    Tier 2: Config Read Detection (-k honeyfile_config_access)│
│    Tier 3: Audit Tampering (-k audit_tampering)             │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. honeyfile_monitor.sh läuft alle 5 Minuten (systemd timer)│
│    Prüft: ausearch für alle 3 Tiers                         │
└─────────────────────────────────────────────────────────────┘
                            ↓
        ┌───────────────────┴───────────────────┐
        ↓                                       ↓
    ZUGRIFF ERKANNT                        KEIN ZUGRIFF
        ↓                                       ↓
   ✓ Alert-Flag                          ✓ Timestamp
     setzen                                 aktualisieren
   ✓ Email (Dynamic Subject):
     🚨🔥 CRITICAL: AUDIT TAMPERING (Tier 3)
     ⚠️ CONFIG SNIFFING (Tier 2)
     🚨 HONEYFILE ACCESS (Tier 1)
   ✓ Timestamp
     speichern
        ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. safety_gate.sh prüft vor Backups                         │
│    if [ -f /var/lib/honeyfile_alert ]; then                │
│      → EXIT 2 (RED) = Backup BLOCKIERT                     │
│    fi                                                       │
└─────────────────────────────────────────────────────────────┘
```

---

## Installation

### Voraussetzungen

- Linux (Debian/Ubuntu/Raspberry Pi OS)
- `sudo` Zugriff
- `auditd` (wird automatisch installiert)
- Python3 (für Email-Versand)

### Setup durchführen

```bash
sudo bash /opt/apps/entropywatcher/tools/setup_honeyfiles.sh
```

**Was wird konfiguriert:**

1. ✓ **Honeyfiles erstellen** (randomisierte Namen) mit restriktiven Rechten (600)
2. ✓ **Multi-Tier Audit Rules installieren:**
   - Tier 1: Honeyfile Access Detection
   - Tier 2: Config Read Detection (honeyfile_paths access)
   - Tier 3: Audit Tampering Detection (auditctl/auditd execution)
3. ✓ **logrotate konfigurieren** (tägliche Log-Rotation, 7 Tage)
4. ✓ **systemd Units installieren:**
   - `honeyfile-monitor.service` (das Monitoring-Script)
   - `honeyfile-monitor.timer` (alle 5 Min)

### Test-Modus (keine Änderungen)

```bash
sudo bash /opt/apps/entropywatcher/tools/setup_honeyfiles.sh --dry-run
```

---

## Dateien & Pfade

### Honeyfile Speicherorte

```
/root/.aws/credentials                  # AWS Credentials
/root/.git-credentials                  # GitHub Token
/root/.env.backup                       # Backup-Secrets
/root/.env.production                   # Prod-Secrets
/srv/nas/admin/passwords.txt            # Samba-Admin
/var/lib/mysql/.db_root_credentials     # MySQL Root
/opt/pcloud/.pcloud_token               # pCloud Token
```

### Konfiguration & Logs

```
/etc/audit/rules.d/honeyfiles.rules              # auditd Rules
/etc/logrotate.d/honeyfile-monitor               # Log-Rotation
/etc/systemd/system/honeyfile-monitor.service    # Monitoring Script
/etc/systemd/system/honeyfile-monitor.timer      # Timer (5 Min Interval)

/var/log/honeyfile_monitor.log                   # Monitoring Logs
/var/log/honeyfiles.log                          # Setup Logs
/var/lib/honeyfile_alert                         # Alert-Flag (PERSISTENT!)
/var/lib/honeyfile_last_alert_ts                 # Timestamp (Duplikat-Vermeidung)

/opt/apps/entropywatcher/main/honeyfile_monitor.sh  # Monitoring Script
```

---

## Verwendung

### 1. Honeyfiles Test (manuell)

```bash
sudo /opt/apps/entropywatcher/main/honeyfile_monitor.sh
```

**Ausgabe:**
```
[2025-12-14 02:03:56] Erste Ausführung - prüfe letzte 10 min...
[2025-12-14 02:03:56] ✓ Keine verdächtigen Zugriffe
```

### 2. Status prüfen

```bash
sudo systemctl status honeyfile-monitor.timer
```

### 3. Logs anschauen

```bash
sudo tail -f /var/log/honeyfile_monitor.log
sudo tail -f /var/log/honeyfiles.log
```

### 4. Audit-Events prüfen

```bash
sudo ausearch -k honeyfile_access --start recent
```

---

## Intrusion-Simulation (TEST)

⚠️ **NUR ZU TESTZWECKEN!** 

Greife auf ein Honeyfile zu, um Alert auszulösen:

```bash
sudo cat /root/.aws/credentials
```

**Danach prüfen:**

```bash
sudo /opt/apps/entropywatcher/main/honeyfile_monitor.sh
```

**Erwartete Ausgabe:**
```
[2025-12-14 XX:XX:XX] ⚠️  HONEYFILE ZUGRIFF ERKANNT!
[2025-12-14 XX:XX:XX]
... audit events ...
[2025-12-14 XX:XX:XX] ✓ Alert-Flag gesetzt: /var/lib/honeyfile_alert
[2025-12-14 XX:XX:XX] ✓ Alert-Email versendet
```

**Alert-Flag prüfen:**

```bash
ls -la /var/lib/honeyfile_alert
```

---

## Alert Management

### Alarm-Status prüfen

```bash
# Flag existiert = System ist KOMPROMMITIERT
if [ -f /var/lib/honeyfile_alert ]; then
    echo "🚨 INTRUSION ERKANNT! System unsicher!"
else
    echo "✓ Kein aktiver Alert"
fi
```

### Integration mit safety_gate.sh

**safety_gate.sh** prüft ZUERST das Honeyfile-Flag vor Backups:

```bash
# Vor RTB/pCloud Backups
sudo bash safety_gate.sh

# Exit Code:
# 0 = GREEN (Backup erlaubt)
# 1 = YELLOW (Warnung, Backup mit Vorsicht)
# 2 = RED (BACKUP BLOCKIERT!)
```

**Beispiel - Alarm blockiert Backup:**

```bash
$ sudo bash safety_gate.sh
[...] ✗ CRITICAL: Honeyfile-Alarm-Flag gefunden: /var/lib/honeyfile_alert
[...] !!! SYSTEM KOMPROMITTIERT - BACKUP BLOCKIERT !!!
[...] ✗✗✗ SAFETY-GATE: RED - KRITISCHER HONEYFILE-ALARM!

$ echo $?
2   # ← RED = EXIT CODE 2
```

### Alert MANUELL ZURÜCKSETZEN

⚠️ **NUR NACH SICHERHEITSÜBERPRÜFUNG!**

**Schritt 1: Audit-Log prüfen**

```bash
sudo ausearch -k honeyfile_access --start recent
```

**Schritt 2: Bedrohung beurteilen & beheben**

- War es legitimer Zugriff? → Audit-Regel anpassen
- War es Malware? → System bereinigen!
- War es ein Test? → Fortfahren

**Schritt 3: Alert-Flag LÖSCHEN**

```bash
sudo rm /var/lib/honeyfile_alert
```

**Schritt 4: Timestamp ZURÜCKSETZEN**

```bash
sudo rm /var/lib/honeyfile_last_alert_ts
```

**Schritt 5: Monitoring neu starten**

```bash
sudo /opt/apps/entropywatcher/main/honeyfile_monitor.sh
echo $?  # Sollte 0 sein
```

**Schritt 6: safety_gate.sh Verlauf löschen (optional)**

```bash
sudo journalctl --vacuum=time=1h  # Alte Logs löschen
```

---

## Mail-Konfiguration

Honeyfile-Alerts werden per Email versendet. Setup in `common.env`:

```bash
# /opt/apps/entropywatcher/config/common.env

# Email aktivieren
MAIL_ENABLE=1

# SMTP Server
MAIL_SMTP_HOST=mail.example.com
MAIL_SMTP_PORT=587

# Authentifizierung
MAIL_USER=admin@example.com
MAIL_PASS=password123

# Empfänger
MAIL_TO=security@example.com

# TLS/STARTTLS
MAIL_STARTTLS=1  # 1 = TLS, 0 = Plain
```

---

## Troubleshooting

### 1. Alert-Flag wird nicht gesetzt

```bash
# Prüfe ausearch
sudo ausearch -k honeyfile_access --start recent

# Prüfe auditd Status
sudo systemctl status auditd

# Neu starten
sudo systemctl restart auditd
```

### 2. Emails werden nicht versendet

```bash
# Prüfe common.env
cat /opt/apps/entropywatcher/config/common.env | grep MAIL

# Test Python SMTP
python3 -c "import smtplib; print('OK')"

# Logs prüfen
tail -f /var/log/honeyfile_monitor.log
```

### 3. Timer läuft nicht

```bash
# Status
sudo systemctl status honeyfile-monitor.timer

# Aktivieren
sudo systemctl enable honeyfile-monitor.timer
sudo systemctl start honeyfile-monitor.timer

# Nächste Ausführung
sudo systemctl list-timers honeyfile-monitor.timer
```

### 4. Safety-Gate blockiert ohne Alarm

```bash
# Flag manuell löschen
sudo rm /var/lib/honeyfile_alert

# Kurz davor prüfen
ls -la /var/lib/honeyfile_alert
```

---

## Entfernung

Um das gesamte Honeyfile-System zu entfernen:

```bash
# Entfernt alles außer Logs (empfohlen für Forensik)
sudo bash /opt/apps/entropywatcher/tools/setup_honeyfiles.sh --remove

# Nur Logs löschen (falls nötig)
sudo bash /opt/apps/entropywatcher/tools/setup_honeyfiles.sh --purge-logs
```

**Was wird mit `--remove` gelöscht:**

- ✗ Alle Honeyfiles (aus `/opt/apps/entropywatcher/config/honeyfile_paths`)
- ✗ Honeyfile Paths Config-Datei
- ✗ auditd Rules (`/etc/audit/rules.d/honeyfiles.rules`)
- ✗ systemd Units (honeyfile-monitor.service & .timer)
- ✗ Alert-Flag (`/var/lib/honeyfile_alert`)

**Was BLEIBT erhalten:**

- ✓ `/var/log/honeyfiles.log` (Setup-Log)
- ✓ `/var/log/honeyfile_monitor.log` (Monitor-Log)
- ✓ `/opt/apps/entropywatcher/main/honeyfile_monitor.sh` (Git-Repo Datei)

**Logs behalten für Forensik:**
Logs enthalten wichtige Informationen für Incident-Response. Nur mit `--purge-logs` löschen, wenn Sie sicher sind.

---

## Sicherheitshinweise

### ⚠️ WICHTIG

1. **Alert-Flag ist PERSISTENT** - wird nicht automatisch gelöscht!
   - Nur manuell löschen nach Überprüfung
   - Verhindert "Zeitbombe"-Szenarios

2. **Honeyfiles sind VERLOCKEND** - enthalten Fake-Credentials
   - Sie sind deutlich gekennzeichnet ("⚠️ HONEYFILE")
   - Echte Admin-Credentials sollten WOANDERS sein!

3. **Root-User ist EXEMPT** - UID 0 (root/System) werden nicht erfasst
   - Backup-Scripts können lesen ohne Alarm
   - Anpassbar in `/etc/audit/rules.d/honeyfiles.rules`

4. **Tägliche Log-Rotation** - verhindert Speicher-Überfluss
   - 7 Tage aufbewahrt
   - Automatisch komprimiert
   - Konfiguriert via logrotate

---

## Integration mit EntropyWatcher

### Honeyfiles von Scan ausschließen

In `common.env` oder Service-ENV:

```bash
SCAN_EXCLUDES="/root/.aws/credentials,/root/.git-credentials,/root/.env.backup,/root/.env.production,/srv/nas/admin/passwords.txt,/var/lib/mysql/.db_root_credentials,/opt/pcloud/.pcloud_token"
```

### ClamAV Integration

In `/etc/clamav/clamd.conf`:

```
ExcludePath ^/root/.aws/credentials$
ExcludePath ^/root/.git-credentials$
ExcludePath ^/root/.env.backup$
ExcludePath ^/root/.env.production$
ExcludePath ^/srv/nas/admin/passwords.txt$
ExcludePath ^/var/lib/mysql/.db_root_credentials$
ExcludePath ^/opt/pcloud/.pcloud_token$
```

---

## Architektur

### Komponenten

```
┌──────────────────────────────────────────┐
│         tools/setup_honeyfiles.sh         │ Setup
├──────────────────────────────────────────┤
│  - create_honeyfiles()                   │
│  - setup_auditd()                        │
│  - setup_logrotate()                     │
│  - setup_systemd_units()                 │
└──────────────────────────────────────────┘
           ↓
┌──────────────────────────────────────────┐
│     honeyfile_monitor.sh                  │ Monitoring
├──────────────────────────────────────────┤
│  - Prüft ausearch auf neue Events        │
│  - Setzt Alert-Flag bei Zugriff          │
│  - Versendet Email-Alert                 │
│  - Speichert Timestamp (Duplikat-Schutz) │
└──────────────────────────────────────────┘
           ↓
┌──────────────────────────────────────────┐
│      safety_gate.sh                       │ Pre-Backup
├──────────────────────────────────────────┤
│  - Prüft /var/lib/honeyfile_alert        │
│  - Return 2 (RED) = BLOCKIERT            │
│  - Blockiert RTB/pCloud Backups          │
└──────────────────────────────────────────┘
```

### Fehler-Handling

- **Duplikat-Emails vermeiden**: Timestamp in `/var/lib/honeyfile_last_alert_ts`
- **Persistent Alerts**: Flag wird NUR manuell gelöscht
- **Automatische Log-Rotation**: Verhindert Disk-Full
- **auditd Restart**: Sichert Rule-Persistierung

---

## Befehls-Referenz

| Aufgabe | Befehl |
|---------|--------|
| **Setup** | `sudo bash tools/setup_honeyfiles.sh` |
| **Test-Modus** | `sudo bash tools/setup_honeyfiles.sh --dry-run` |
| **Entfernung** | `sudo bash tools/setup_honeyfiles.sh --remove` |
| **Logs löschen** | `sudo bash tools/setup_honeyfiles.sh --purge-logs` |
| **Audit Rules prüfen** | `sudo auditctl -l` |
| **Audit Rules filtern** | `sudo auditctl -l \| grep -E "honeyfile\|audit_tampering\|audit_config"` |
| **Rules-Datei anzeigen** | `sudo cat /etc/audit/rules.d/honeyfiles.rules` |
| **Monitoring testen** | `sudo /opt/apps/entropywatcher/main/honeyfile_monitor.sh` |
| **Timer-Status** | `sudo systemctl status honeyfile-monitor.timer` |
| **Logs folgen** | `sudo tail -f /var/log/honeyfile_monitor.log` |
| **Audit-Events** | `sudo ausearch -k honeyfile_access --start recent` |
| **Alert-Status** | `ls -la /var/lib/honeyfile_alert` |
| **Alert-Reset** | `sudo rm /var/lib/honeyfile_alert` |
| **Safety-Check** | `sudo bash safety_gate.sh` |
| **Strict Mode** | `sudo bash safety_gate.sh --strict` |

---

**Version**: 1.0  
**Last Updated**: 2025-12-14  
**Status**: ✓ Production Ready
