# Server-Config Reference

Dieses Verzeichnis enthält **anonymisierte Beispiele** der Server-Konfiguration.

## 📁 Struktur

```
.server-config/
├── README.md                    ← Diese Datei
├── example/
│   ├── config/
│   │   ├── common.env.example
│   │   ├── nas.env.example
│   │   └── ...
│   └── systemd/
│       ├── entropywatcher-nas.service.example
│       ├── entropywatcher-nas.timer.example
│       └── ...
└── (aktuelle Konfiguration — nicht im Git)
```

## 🔒 Sicherheit

- **Keine echten `.env` Dateien auf GitHub** (ignoriert per `.gitignore`)
- **Keine Secrets in diesem Repo** (Tokens, Passwörter, E-Mails)
- **Nur `.example` Dateien sind versioniert** (als Template für neue Nutzer)

## 📖 Wie nutzt man die Beispiele?

1. **Lokal entwickeln / testen:**
   ```bash
   cp .server-config/example/examples/config/common.env.example config/common.env
   cp .server-config/example/examples/config/nas.env.example config/nas.env
   # → echte Werte eintragen
   ```

2. **Auf den Server deployen:**
   ```bash
   scp config/*.env user@server:/opt/apps/entropywatcher/config/
   scp .server-config/example/systemd/*.service.example user@server:/tmp/
   # → auf dem Server überprüfen und echte Dateien anlegen
   ```

## 🔄 Beispiele aktualisieren (für Entwickler)

Wenn sich die Konfiguration ändert:

1. **Auf dem Server ausführen:**
   ```bash
   bash anonymize-server-configs.sh
   ```

2. **Anonymisierte Beispiele lokal holen:**
   ```bash
   scp -r user@server:/tmp/server-config-examples/* .
   ```

3. **Überprüfen & ggf. Regex-Pattern im Skript tunen**

4. **Auf GitHub pushen:**
   ```bash
   git add .server-config/example/
   git commit -m "docs: update server config examples"
   git push
   ```

---

**Hinweis:** Die echten `.env` und Service-Dateien bleiben auf dem Server. Sie werden nicht versioniert.
