# EntropyWatcher Helper Scripts

Übersicht über zusätzliche Tools und Scripts für EntropyWatcher-Setup, Wartung und Integration.

---

## 📁 Verzeichnisstruktur

```
tools/
├── README.md                      ← Diese Datei
├── setup_honeyfiles.sh            ← Honeyfile-Intrusion-Detection einrichten
├── graceful_shutdown.sh           ← Safe-Shutdown mit Backup-Warte-Logik
├── anonymize-server-configs.sh    ← Server-Configs anonymisieren für GitHub
└── oauth/
    ├── README.md                  ← OAuth2-Flow-Dokumentation
    └── oauth2_flow.py             ← pCloud OAuth2-Token generieren
```

---

## 🛡️ setup_honeyfiles.sh

**Zweck:** Vollautomatisches Setup von Honeyfile-basierter Intrusion Detection mit auditd-Überwachung.

### Was macht das Script?

1. **Generiert 7 Köder-Dateien** mit randomisierten Namen:
   - `/root/.aws/credentials_<random>_<date>`
   - `/root/.git-credentials_<random>_<date>`
   - `/root/.ssh/id_rsa_backup_<random>_<date>`
   - `/var/lib/mysql/.db_root_credentials_<random>_<date>`
   - `/opt/pcloud/.pcloud_token_<random>_<date>`
   - `/etc/ssl/private/ssl_master_key_<random>_<date>`
   - `/root/.docker/config_<random>_<date>.json`

2. **Konfiguriert auditd Rules** (3-Tier-System):
   - **Tier 1:** Zugriff auf Honeyfile → sofortiger Alarm
   - **Tier 2:** Zugriff auf `/opt/apps/entropywatcher/config/honeyfile_paths` → verdächtig
   - **Tier 3:** Manipulation an auditd-Rules → kritischer Alarm

3. **Installiert systemd Units:**
   - `honeyfile-monitor.service` - Prüft Audit-Log auf verdächtige Zugriffe
   - `honeyfile-monitor.timer` - Triggert alle 5 Minuten

4. **Erstellt Monitor-Script:**
   - `/usr/local/bin/honeyfile_monitor.sh` - Nutzt SMTP aus `common.env` für Alerts

### Usage

```bash
# Vollständiges Setup (empfohlen)
sudo bash /opt/apps/entropy-watcher/tools/setup_honeyfiles.sh

# Test-Modus (keine Änderungen, nur Anzeige)
sudo bash /opt/apps/entropy-watcher/tools/setup_honeyfiles.sh --dry-run

# Cleanup (alle Honeyfiles, auditd-Rules, systemd Units entfernen)
sudo bash /opt/apps/entropy-watcher/tools/setup_honeyfiles.sh --remove

# Nur Logs löschen (z.B. nach Test-Alarm)
sudo bash /opt/apps/entropy-watcher/tools/setup_honeyfiles.sh --purge-logs
```

### Output

Das Script gibt am Ende **Copy-Paste-Strings** für Excludes aus:

```bash
# EntropyWatcher Excludes (in common.env oder Service-ENV):
SCAN_EXCLUDES="/root/.aws/credentials_a7f3e_20251214,/root/.git-credentials_b8g2h_20251214,..."

# ClamAV Excludes (in /etc/clamav/clamd.conf):
ExcludePath ^/root/.aws/credentials_a7f3e_20251214$
ExcludePath ^/root/.git-credentials_b8g2h_20251214$
```

### Best Practices

- **Nach Installation:** Excludes in `common.env` und `clamd.conf` eintragen
- **Regelmäßig testen:** Manuellen Zugriff simulieren: `cat /root/.aws/credentials_*`
- **Monitoring:** `journalctl -u honeyfile-monitor.service -n 50`

**Weitere Details:** Siehe [docs/HONEYFILE_SETUP.md](../docs/HONEYFILE_SETUP.md)

---

## 🛑 graceful_shutdown.sh

**Zweck:** Wartet auf laufende Backup-Prozesse und fährt den Server dann sauber herunter (verhindert korrupte Backups).

### Was macht das Script?

1. **Prüft laufende Services:**
   - EntropyWatcher-Scans (`entropywatcher-*.service`)
   - RTB-Backups (`rtb-*.service`)
   - pCloud-Uploads (`pcloud-*.service`)

2. **Wartet auf Abschluss** (max. 30 Minuten default)

3. **Fährt herunter** wenn alle Services fertig sind

### Usage

```bash
# Standard-Shutdown (30 Min Timeout)
sudo ./graceful_shutdown.sh

# Längerer Timeout (60 Min)
sudo ./graceful_shutdown.sh --timeout 3600

# Nur prüfen & warten, nicht herunterfahren
sudo ./graceful_shutdown.sh --no-shutdown

# Test-Modus (keine Aktionen)
sudo ./graceful_shutdown.sh --dry-run
```

### Exitcodes

- **0** - Erfolgreich heruntergefahren (alle Services beendet)
- **1** - Fehler / Timeout (Services laufen noch)
- **2** - Nur `--dry-run` ausgeführt (keine echte Aktion)

### Integration mit systemd

Empfohlen für automatische Shutdowns via systemd:

```bash
# /etc/systemd/system/graceful-shutdown.service
[Unit]
Description=Graceful Shutdown (wait for backups)
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
ExecStart=/opt/apps/entropy-watcher/tools/graceful_shutdown.sh --timeout 1800
TimeoutStartSec=2100

[Install]
WantedBy=halt.target reboot.target
```

### Use Cases

- **Geplante Wartung:** Server herunterfahren ohne Backup-Unterbrechung
- **UPS-Integration:** Bei Stromausfall sauber herunterfahren
- **Cronjob-Shutdown:** Nächtlicher Shutdown nach Backup-Window

---

## 🔒 anonymize-server-configs.sh

**Zweck:** Server-Konfigurationen anonymisieren für GitHub-Dokumentation (entfernt Secrets, IPs, E-Mails).

### Was macht das Script?

1. **Kopiert `.env`-Dateien** von `/opt/apps/entropywatcher/config/`
2. **Ersetzt sensible Daten:**
   - Passwörter → `<DB_PASSWORD>`, `<MAIL_PASSWORD>`
   - E-Mail-Adressen → `<YOUR_EMAIL>`
   - IPs → `<SERVER_IP>`
   - Tokens → `<PCLOUD_TOKEN>`, `<API_TOKEN>`
3. **Speichert in:** `/tmp/server-config-examples/`

### Usage

```bash
# Auf dem SERVER ausführen
cd /opt/apps/entropy-watcher/tools
chmod +x anonymize-server-configs.sh
./anonymize-server-configs.sh

# Output prüfen
ls -la /tmp/server-config-examples/

# Lokal herunterladen (vom DEV-Rechner)
scp -r user@server:/tmp/server-config-examples/ ~/.
```

### Workflow (für Entwickler)

```bash
# 1. Auf Server: Configs anonymisieren
ssh user@server
cd /opt/apps/entropy-watcher/tools
./anonymize-server-configs.sh
exit

# 2. Lokal: Anonymisierte Configs holen
scp -r user@server:/tmp/server-config-examples/ ~/.

# 3. Lokal: In Repo kopieren (für Doku-Updates)
cp -r ~/server-config-examples/* .server-config/example/

# 4. Commit & Push
git add .server-config/example/
git commit -m "Update anonymized server configs"
git push origin main
```

### Sicherheit

**Was wird anonymisiert:**
- ✅ DB-Passwörter (`DB_PASS`, `DB_PASSWORD`, `MYSQL_PASSWORD`)
- ✅ Mail-Credentials (`MAIL_USER`, `MAIL_PASS`)
- ✅ API-Tokens (`PCLOUD_API_TOKEN`, `TOKEN`, `BEARER_TOKEN`)
- ✅ E-Mail-Adressen
- ✅ IP-Adressen
- ✅ Hostnames (Server-spezifisch)

**Was bleibt:**
- ✅ Struktur der Configs
- ✅ Variable-Namen
- ✅ Kommentare
- ✅ Pfade (z.B. `/srv/nas/User1` bleibt)

---

## 🔐 oauth/ (pCloud OAuth2)

**Zweck:** OAuth2-Token für pCloud-API generieren (für pCloud-Tools Integration).

### oauth2_flow.py

Interaktives Python-Script für OAuth2-Flow mit pCloud.

#### Prerequisites

```bash
# Python-Dependencies installieren
pip install requests python-dotenv
```

#### Usage

```bash
cd /opt/apps/entropy-watcher/tools/oauth

# Option 1: Client ID/Secret in .env setzen
echo "PCLOUD_CLIENT_ID=your_client_id" > .env
echo "PCLOUD_CLIENT_SECRET=your_client_secret" >> .env
python3 oauth2_flow.py

# Option 2: Interaktiv eingeben
python3 oauth2_flow.py
# → Prompts für Client ID und Secret
```

#### Ablauf

1. **Browser öffnet sich** mit pCloud-Autorisierungs-URL
2. **User autorisiert** die App (Login bei pCloud)
3. **Redirect zu localhost:8000** mit Authorization Code
4. **Script tauscht Code** gegen Access Token
5. **Token wird gespeichert** in `.env` oder ausgegeben

#### Output

```bash
✓ Access Token erhalten!
✓ API Hostname: api.pcloud.com

# Speichern in .env (für pCloud-Tools):
PCLOUD_ACCESS_TOKEN=AbC123DeF456...
PCLOUD_API_HOST=api.pcloud.com
```

#### Troubleshooting

**Problem:** "Browser öffnet sich nicht"

**Lösung:** Manuelle URL kopieren:
```bash
python3 oauth2_flow.py
# → Script zeigt URL: https://my.pcloud.com/oauth2/authorize?client_id=...
# → Manuell im Browser öffnen
```

**Problem:** "Port 8000 bereits belegt"

**Lösung:** Port ändern:
```python
# oauth2_flow.py, Zeile 27:
PORT = 8001  # statt 8000
```

**Weitere Details:** Siehe [oauth/README.md](oauth/README.md)

---

## 🎯 Wann brauchst du welches Tool?

| Tool | Zweck | Häufigkeit | Nutzer |
|------|-------|------------|--------|
| `setup_honeyfiles.sh` | Honeyfile-Setup | **Einmalig** (bei Installation) | Admin |
| `graceful_shutdown.sh` | Safe-Shutdown | **Optional** (bei Wartung/UPS) | Admin |
| `anonymize-server-configs.sh` | Config-Doku | **Optional** (für GitHub-Updates) | Developer |
| `oauth2_flow.py` | pCloud-Token | **Einmalig** (wenn pCloud-Tools genutzt) | Admin/Developer |

---

## 🔧 Entwickler-Notizen

### Neue Tools hinzufügen

Wenn du ein neues Helper-Script erstellst:

1. **Shebang & Header:**
   ```bash
   #!/usr/bin/env bash
   #
   # script_name.sh
   # Kurzbeschreibung
   #
   # Usage: ...
   ```

2. **Error-Handling:**
   ```bash
   set -euo pipefail
   ```

3. **Help-Option:**
   ```bash
   if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
       show_usage
       exit 0
   fi
   ```

4. **Dokumentation:**
   - Dieses README aktualisieren
   - Ggf. eigene README im Unterordner

### Script-Qualität

Alle Scripts sollten:
- ✅ Root-Check (falls nötig): `[[ $EUID -eq 0 ]] || { echo "Muss als root laufen"; exit 1; }`
- ✅ Dry-Run-Modus unterstützen
- ✅ Sinnvolle Exitcodes (0=Erfolg, 1=Fehler, 2+=spezifisch)
- ✅ Logging (stdout für Info, stderr für Errors)
- ✅ Cleanup-Handler (falls Dateien/Prozesse erstellt)

---

## 📚 Siehe auch

- **[README.md](../README.md)** - Hauptdokumentation
- **[docs/HONEYFILE_SETUP.md](../docs/HONEYFILE_SETUP.md)** - Honeyfile-Details
- **[docs/CONFIG.md](../docs/CONFIG.md)** - ENV-Variablen-Referenz
- **[oauth/README.md](oauth/README.md)** - OAuth2-Flow-Details
