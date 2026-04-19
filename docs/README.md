# EntropyWatcher Dokumentation

Zentrale Dokumentations-Übersicht für EntropyWatcher & ClamAV Scanner.

---

## 📚 Guides

### Core Documentation
- **[DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md)** ⭐ - Technische Deep-Dives  
  systemd Security Architecture, Environment Inheritance, Debugging-Tipps
- **[INSTALLATION.md](INSTALLATION.md)** - Server-Installation & Setup  
  Systemd-Services, Timer, MariaDB, ClamAV
- **[CONFIG.md](CONFIG.md)** - Konfiguration & .env-Dateien  
  Schwellwerte, SMTP, DB-Settings
- **[TESTING.md](TESTING.md)** - Testing & Validation  
  Unit-Tests, Integrationstests

### Feature-Specific Guides
- **[CLAMAV_INTEGRATION.md](CLAMAV_INTEGRATION.md)** - ClamAV-Setup  
  Daemon-Konfiguration, On-Demand-Scans
- **[HONEYFILE_SETUP.md](HONEYFILE_SETUP.md)** - Intrusion Detection  
  Honeyfiles, auditd, 3-Tier-Überwachung
- **[EW_FORECAST_USAGE.md](EW_FORECAST_USAGE.md)** - Forecast-Tool  
  Backup-Slot-Prediction

### Reference Documentation
- **[BACKSTORY.md](BACKSTORY.md)** 📖 - Entstehungsgeschichte  
  Vom QNAP-Frust zur vollautomatisierten Pipeline
- **[MONITORING.md](MONITORING.md)** 📊 - Monitoring & Logs  
  Journal, Status-Checks, Alerting, Dashboard-Integration
- **[UTILITIES.md](UTILITIES.md)** 🔧 - Helper-Scripts  
  Tools-Verzeichnis, Setup-Scripts, OAuth-Flow
- **[db-queries.md](db-queries.md)** 🗄️ - SQL-Referenz  
  Nützliche Queries, Schema-Info

---

## 🌐 HTML-Dokumentation (Interaktiv)

### Timing-Diagramme
- **[index.html](index.html)** - Haupt-Übersicht mit Navigation
- **[timing-diagram.html](timing-diagram.html)** - Interaktive Timing-Diagramme
- **[timing-diagram-green.html](timing-diagram-green.html)** - GREEN Scenario
- **[timing-diagram-yellow.html](timing-diagram-yellow.html)** - YELLOW Scenario
- **[timing-diagram-red.html](timing-diagram-red.html)** - RED Scenario
- **[timing-diagram-no_changes.html](timing-diagram-no_changes.html)** - No-Changes Scenario
- **[timing-diagram-all-scenarios.html](timing-diagram-all-scenarios.html)** - Alle Szenarien

### Architektur & Prozess-Flow
- **[architecture.html](architecture.html)** - System-Architektur
- **[process-flow.html](process-flow.html)** - Prozess-Ablauf
- **[accurate-flow.html](accurate-flow.html)** - Detaillierter Flow
- **[pcloud.html](pcloud.html)** - pCloud-Integration
- **[pcloud_legacy.html](pcloud_legacy.html)** - Legacy-Dokumentation

### Nutzung (Lokale HTML-Doku)

**Variante A: Datei direkt öffnen**
```bash
# Im Dateimanager doppelklicken:
docs/index.html
```

**Variante B: Lokaler Webserver**
```bash
cd docs/
python3 -m http.server 8080

# Im Browser öffnen:
# http://localhost:8080/index.html
```

**Variante C: Auf Server installieren**
```bash
sudo mkdir -p /opt/apps/entropywatcher/docs
sudo cp -r docs/* /opt/apps/entropywatcher/docs/

# Mit Python-Server:
cd /opt/apps/entropywatcher/docs
python3 -m http.server 8080

# Zugriff: http://SERVER-IP:8080/index.html
```

---

## 🚀 Quick Links

| Thema | Dokument |
|-------|----------|
| **Erste Installation** | [INSTALLATION.md](INSTALLATION.md) |
| **systemd Debugging** | [DEVELOPER_GUIDE.md#debugging-tipps](DEVELOPER_GUIDE.md#debugging-tipps) |
| **Safety-Gate erklärt** | [DEVELOPER_GUIDE.md#systemd-security-architecture](DEVELOPER_GUIDE.md#systemd-security-architecture) |
| **Honeyfiles einrichten** | [HONEYFILE_SETUP.md](HONEYFILE_SETUP.md) |
| **Logs anschauen** | [MONITORING.md#systemd-journal](MONITORING.md#systemd-journal-empfohlen) |
| **Projekt-Geschichte** | [BACKSTORY.md](BACKSTORY.md) |

---

## Inhalte (Legacy - HTML-fokussiert)

### HTML-Dokumentation
- Übersicht zu EntropyWatcher, Safety-Gate und pCloud-Integration
- Timing-Diagramme (grün/gelb/rot, alle Szenarien)
- Prozess- und Architektur-Ansichten  
- Helper-Skripte & venv-Nutzung (Abschnitt "EntropyWatcher Helper Scripts")
- Beispiele für direkte `entropywatcher.py`-Aufrufe

### Markdown-Dokumentation
- [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md) - Technische Deep-Dives (systemd Security, Debugging)
- [CONFIG.md](CONFIG.md) - Konfiguration und .env-Dateien
- [INSTALLATION.md](INSTALLATION.md) - Server-Installation
- [TESTING.md](TESTING.md) - Testing-Guides
- [CLAMAV_INTEGRATION.md](CLAMAV_INTEGRATION.md) - ClamAV-Setup
- [HONEYFILE_SETUP.md](HONEYFILE_SETUP.md) - Honeyfile-Konfiguration
- [UTILITIES.md](UTILITIES.md) - Helper-Scripts

---

## Lokale Nutzung

1. Repository klonen oder aktualisieren:

   ```bash
   git clone https://github.com/<DEIN-ORG>/<DEIN-REPO>.git
   cd <DEIN-REPO>/pcloud
   ```

2. HTML-Doku im Browser öffnen (Datei direkt öffnen):

   - `docs/index.html` im Dateimanager doppelklicken **oder**
   - Browser öffnen und `file:///Pfad/zum/Repo/pcloud/docs/index.html` aufrufen.

   Es ist kein zusätzlicher Webserver nötig; alles ist statisch.

## Installation auf dem Server (/opt)

Die Doku kann optional auch auf dem Backup-Server installiert werden, z. B. unter
`/opt/apps/entropywatcher/docs`.

1. Verzeichnis anlegen und Dateien kopieren:

   ```bash
   sudo mkdir -p /opt/apps/entropywatcher/docs
   sudo cp -r docs/* /opt/apps/entropywatcher/docs/
   ```

2. Doku auf dem Server anzeigen:

   - Variante A: Dateien per SFTP/SSHFS auf den lokalen Rechner holen und lokal öffnen.
   - Variante B: Einen einfachen, temporären HTTP-Server auf dem Server starten, z. B.:

     ```bash
     cd /opt/apps/entropywatcher/docs
     python3 -m http.server 8080
     ```

     Dann im Browser auf dem Client `http://SERVERNAME:8080/index.html` aufrufen.

> Hinweis: Die Doku selbst benötigt keine Python-venv; sie ist komplett statisch.
> Die venv kommt nur bei den beschriebenen Beispiel-Kommandos (EntropyWatcher-Skripte) zum Einsatz.

## Pflege / Updates

- Änderungen an Markdown-Dateien (`README.md`, `ENTROPYWATCHER_README.md`, etc.)
  sollten bei Bedarf in die HTML-Doku übernommen werden.
- Die zentrale Navigationsstruktur und neue Sektionen werden in `docs/index.html`
  gepflegt (Sidebar-Links, neue Abschnitte).
- Nach einem `git pull` auf dem Server ggf. die HTML-Dateien erneut nach
  `/opt/apps/entropywatcher/docs` kopieren.
