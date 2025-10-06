# EntropyWatcher & pCloud HTML-Doku

Dieses Verzeichnis enthält eine statische HTML-Dokumentation für EntropyWatcher
und die pCloud-Backup-Integration. Die zentrale Einstiegsseite ist `index.html`.

## Inhalte

- Übersicht zu EntropyWatcher, Safety-Gate und pCloud-Integration
- Timing-Diagramme (grün/gelb/rot, alle Szenarien)
- Prozess- und Architektur-Ansichten
- Helper-Skripte & venv-Nutzung (Abschnitt "EntropyWatcher Helper Scripts")
- Beispiele für direkte `entropywatcher.py`-Aufrufe

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
