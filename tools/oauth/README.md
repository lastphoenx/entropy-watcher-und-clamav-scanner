# pCloud OAuth2 Flow

Python-Script zur Generierung von pCloud Access Tokens via OAuth2 Code Flow. Erforderlich für die Integration von [pCloud-Tools](https://github.com/lastphoenx/pcloud-tools) mit EntropyWatcher.

---

## 📋 Überblick

**Was macht das Script?**
- Führt OAuth2 Code Flow mit pCloud durch
- Startet lokalen HTTP-Server für Redirect (localhost:8000)
- Öffnet Browser für User-Autorisierung
- Tauscht Authorization Code gegen Access Token
- Speichert Token sicher in `token.env`

**Wann brauchst du das?**
- Initial-Setup von pCloud-Tools (einmalig)
- Nach Ablauf des Tokens (pCloud-Tokens haben kein Expiry, aber nach Revoke)
- Bei Wechsel des pCloud-Accounts

---

## 🚀 Installation

### Prerequisites

```bash
# Python 3.7+ erforderlich
python3 --version

# Dependencies installieren
pip install requests python-dotenv
```

### pCloud App registrieren (einmalig)

1. **pCloud Developer Console öffnen:**
   - https://docs.pcloud.com/

2. **OAuth2 App erstellen:**
   - Login mit deinem pCloud-Account
   - "My Apps" → "Create App"
   - **App Name:** z.B. "EntropyWatcher Backup"
   - **Redirect URI:** `http://127.0.0.1:8000` (exakt so!)
   - **Permissions:** `files.read`, `files.write`, `files.delete` (je nach Bedarf)

3. **Client ID & Secret notieren:**
   - Nach Erstellung werden `Client ID` und `Client Secret` angezeigt
   - **WICHTIG:** Client Secret nur einmal sichtbar → sofort sichern!

---

## 🔐 Konfiguration

### Option 1: .env-Datei (empfohlen)

Erstelle `.env` im gleichen Verzeichnis wie `oauth2_flow.py`:

```bash
# tools/oauth/.env
PCLOUD_CLIENT_ID=your_client_id_here
PCLOUD_CLIENT_SECRET=your_client_secret_here
```

**Sicherheit:**
```bash
chmod 600 .env  # Nur Owner kann lesen
```

### Option 2: Interaktive Eingabe

Ohne `.env` wird das Script nach Credentials fragen:

```bash
python3 oauth2_flow.py
# → Prompt: Client ID (verborgen):
# → Prompt: Client Secret (verborgen):
```

---

## 🎯 Usage

### Standard-Flow (automatischer Browser-Redirect)

```bash
cd /opt/apps/entropy-watcher/tools/oauth
python3 oauth2_flow.py
```

**Ablauf:**
1. Script startet lokalen Server auf Port 8000
2. Browser öffnet pCloud-Autorisierungs-Seite
3. User loggt sich bei pCloud ein und genehmigt App
4. pCloud redirected zu `http://127.0.0.1:8000?code=...`
5. Script empfängt Code, tauscht gegen Token
6. Token wird in `token.env` gespeichert

**Output:**
```
============================================================
pCloud OAuth2 - Code Flow
============================================================

[1] Starte lokalen HTTP-Server...
[Server] Läuft auf http://127.0.0.1:8000

[2] Öffne Browser...
AUTHORIZATION URL:
https://my.pcloud.com/oauth2/authorize?client_id=...&response_type=code&redirect_uri=http://127.0.0.1:8000

[3] Warte auf Redirect (60 Sekunden)...
✓ Code vom Server erhalten!
✓ Code: AbC123DeF456...
✓ Hostname: eapi.pcloud.com

[4] Hole Access Token...
  (EU-Region: nutze https://eapi.pcloud.com/oauth2_token)
✓ Token erfolgreich erhalten!
  Token Type: Bearer
  UID: 123456789

[5] Speichere Token in token.env...
✓ Token in token.env gespeichert

============================================================
✓ Erfolg!
============================================================
```

### Manueller Fallback (wenn Browser nicht automatisch funktioniert)

**Problem:** Browser öffnet sich nicht oder Redirect schlägt fehl.

**Lösung:**

1. Script startet trotzdem (wartet 60 Sekunden)
2. Kopiere die angezeigte URL manuell in Browser:
   ```
   https://my.pcloud.com/oauth2/authorize?client_id=...&response_type=code&redirect_uri=http://127.0.0.1:8000
   ```
3. Nach Autorisierung: pCloud redirected zu `http://127.0.0.1:8000?code=ABC123...`
4. **Wenn Redirect nicht empfangen wird:**
   - Kopiere die komplette URL aus der Browser-Adresszeile
   - Füge sie ins Script ein (Prompt: "URL oder Code:")

**Beispiel:**
```bash
[3] Warte auf Redirect (60 Sekunden)...
⚠ Kein automatischer Redirect empfangen
Gib die Redirect-URL ein (oder nur den Code):

URL oder Code: http://127.0.0.1:8000?code=ABC123DEF456&hostname=eapi.pcloud.com

✓ Code: ABC123DEF456...
✓ Hostname: eapi.pcloud.com
```

---

## 📂 Output: token.env

Nach erfolgreicher Autorisierung wird `token.env` erstellt:

```bash
# tools/oauth/token.env (automatisch generiert)
PCLOUD_ACCESS_TOKEN=AbC123DeF456GhI789JkL...
PCLOUD_TOKEN_TYPE=Bearer
PCLOUD_UID=123456789
PCLOUD_HOSTNAME=eapi.pcloud.com
PCLOUD_TOKEN_RESPONSE={"access_token":"...","token_type":"Bearer","uid":123456789}
```

**Dateiberechtigungen:**
- Automatisch auf `600` gesetzt (nur Owner lesbar)
- Niemals in Git committen!

### Integration mit pCloud-Tools

```bash
# Token in pCloud-Tools-Verzeichnis kopieren
cp token.env /opt/apps/pcloud-tools/.env

# Oder: Variablen in bestehende .env mergen
cat token.env >> /opt/apps/pcloud-tools/.env
```

---

## 🔧 Troubleshooting

### Problem: "python-dotenv nicht installiert"

**Lösung:**
```bash
pip install python-dotenv
# oder
pip3 install python-dotenv
```

### Problem: "Port 8000 bereits belegt"

**Lösung 1:** Anderen Port verwenden:
```bash
# oauth2_flow.py editieren (Zeile 27)
PORT = 8001  # statt 8000

# Redirect URI anpassen (Zeile 28)
REDIRECT_URI = f"http://127.0.0.1:{PORT}"
```

**WICHTIG:** Redirect URI in pCloud App auch auf `http://127.0.0.1:8001` ändern!

**Lösung 2:** Bestehenden Prozess beenden:
```bash
# Linux/macOS
lsof -ti:8000 | xargs kill -9

# Windows PowerShell
Get-NetTCPConnection -LocalPort 8000 | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }
```

### Problem: "Browser öffnet sich nicht"

**Ursache:** Headless-Server, SSH-Session ohne X11-Forwarding, Browser blockiert.

**Lösung:** Manueller Flow (siehe oben):
1. URL aus Script-Output kopieren
2. In lokalem Browser öffnen
3. Nach Autorisierung: Redirect-URL zurück ins Script kopieren

### Problem: "Kein Code in URL gefunden"

**Ursache:** pCloud nutzt manchmal Token Flow statt Code Flow (falscher `response_type`).

**Lösung:** Script prüft bereits `response_type=code` → Sollte nicht auftreten.

**Workaround:** Falls doch Token-Response:
```bash
# URL sieht aus wie:
http://127.0.0.1:8000#access_token=ABC123&token_type=Bearer

# → Script erkennt das und gibt Fehler:
# "✗ Token Flow nicht unterstützt - nutze Code Flow!"
```

**Fix:** pCloud App-Einstellungen prüfen → "Authorization Code Flow" aktivieren.

### Problem: "Request Fehler: SSL Certificate Verify Failed"

**Ursache:** Veraltete CA-Zertifikate oder Proxy-Probleme.

**Lösung:**
```bash
# CA-Zertifikate aktualisieren (Debian/Ubuntu)
sudo apt update && sudo apt install --reinstall ca-certificates

# Oder: SSL-Verifikation temporär deaktivieren (NICHT für Production!)
# oauth2_flow.py, Zeile 196:
response = requests.post(token_url, data=token_params, verify=False)
```

### Problem: "Fehler: invalid_grant"

**Ursache:** Authorization Code bereits verwendet oder abgelaufen (10 Minuten Lifetime).

**Lösung:** Flow neu starten:
```bash
python3 oauth2_flow.py
# → Neuen Code holen
```

---

## 🔒 Sicherheit

### Token-Sicherheit

**Best Practices:**
- ✅ `token.env` mit `chmod 600` schützen
- ✅ Niemals in Git committen (`.gitignore`)
- ✅ Nicht in Logs ausgeben
- ✅ Nach Revoke neu generieren

**Token Revoke (bei Kompromittierung):**
1. pCloud Developer Console öffnen
2. "My Apps" → deine App → "Revoke all tokens"
3. Neuen Token via `oauth2_flow.py` generieren

### Client Secret Sicherheit

**Niemals:**
- ❌ In öffentliche Repos committen
- ❌ In Klartext-Logs speichern
- ❌ Per E-Mail versenden

**Stattdessen:**
- ✅ In `.env` mit `chmod 600`
- ✅ Secrets-Manager (Ansible Vault, KeePass, 1Password)
- ✅ Umgebungsvariablen (systemd `EnvironmentFile`)

---

## 🌍 pCloud Regionen

pCloud nutzt unterschiedliche API-Endpunkte je nach Account-Region:

| Region | API Hostname | Token URL |
|--------|--------------|-----------|
| **US** | `api.pcloud.com` | `https://api.pcloud.com/oauth2_token` |
| **EU** | `eapi.pcloud.com` | `https://eapi.pcloud.com/oauth2_token` |

**Automatische Erkennung:**
- Script erkennt `hostname` aus Redirect-URL
- Nutzt korrekten Endpunkt automatisch
- `token.env` enthält `PCLOUD_HOSTNAME` für zukünftige Requests

**Manuelle Prüfung:**
```bash
# In token.env prüfen
grep PCLOUD_HOSTNAME token.env

# EU-Account:
PCLOUD_HOSTNAME=eapi.pcloud.com

# US-Account:
PCLOUD_HOSTNAME=api.pcloud.com
```

---

## 📚 Weiterführende Dokumentation

### pCloud API Docs

- **OAuth2 Guide:** https://docs.pcloud.com/methods/oauth_2.0/
- **API Reference:** https://docs.pcloud.com/methods/
- **Rate Limits:** 2000 Requests/Tag (Free), unbegrenzt (Premium)

### Integration mit pCloud-Tools

Nach Token-Generierung:

```bash
# 1. Token in pCloud-Tools kopieren
cp tools/oauth/token.env ../../../pcloud-tools/.env

# 2. pCloud-Tools testen
cd ../../../pcloud-tools
python3 pcloud_bin_lib.py --list-folders /

# 3. Backup-Pipeline integrieren
# → Siehe pcloud-tools/README.md
```

---

## 🎯 Entwickler-Notizen

### Script-Architektur

```python
# Komponenten:
1. HTTP-Server (Thread) - Empfängt Redirect mit Authorization Code
2. Browser-Launch - Öffnet pCloud-Autorisierungs-URL
3. Token-Exchange - Tauscht Code gegen Access Token (POST Request)
4. Datei-Output - Speichert Token in token.env
```

**Besonderheiten:**
- `OAuthCallbackHandler` - Custom HTTP-Handler für Redirect
- `threading.Event` - Synchronisation Server ↔ Main-Thread
- `getpass` - Sichere Eingabe von Secrets (nicht in History)
- `webbrowser.open()` - Cross-Platform Browser-Launch

### Anpassungen für andere APIs

Das Script kann für andere OAuth2-Providers angepasst werden:

```python
# Ändern:
AUTHORIZE_URL = "https://other-provider.com/oauth/authorize"
TOKEN_URL = "https://other-provider.com/oauth/token"

# Variablen umbenennen:
PCLOUD_CLIENT_ID → PROVIDER_CLIENT_ID
PCLOUD_CLIENT_SECRET → PROVIDER_CLIENT_SECRET

# token.env Format anpassen
```

---

## 📋 Checkliste

- [ ] pCloud App registriert (Client ID & Secret erhalten)
- [ ] `tools/oauth/.env` erstellt mit Credentials
- [ ] Dependencies installiert (`requests`, `python-dotenv`)
- [ ] `python3 oauth2_flow.py` ausgeführt
- [ ] Browser-Autorisierung durchgeführt
- [ ] `token.env` erfolgreich generiert
- [ ] Token nach `/opt/apps/pcloud-tools/.env` kopiert
- [ ] pCloud-Tools Test (`pcloud_bin_lib.py --list-folders /`)
- [ ] Dateiberechtigungen geprüft (`chmod 600 token.env`)

---

## 🛠️ Siehe auch

- **[tools/README.md](../README.md)** - Übersicht aller Helper-Scripts
- **[pCloud-Tools README](https://github.com/lastphoenx/pcloud-tools)** - Deduplizierte Cloud-Backups
- **[EntropyWatcher README](../../README.md)** - Hauptdokumentation
