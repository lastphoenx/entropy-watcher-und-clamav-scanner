# EntropyWatcher Developer Guide

Technische Deep-Dives, Architektur-Entscheidungen und Debugging-Guides für Entwickler.

---

## Table of Contents

- [systemd Security Architecture](#systemd-security-architecture)
  - [Design-Prinzip: Strikte Trennung](#design-prinzip-strikte-trennung)
  - [Das Vererbungs-Problem](#das-vererbungs-problem)
  - [Die Lösung: env -u](#die-lösung-env--u)
  - [Warum die Sicherheit NICHT gefährdet ist](#warum-die-sicherheit-nicht-gefährdet-ist)
  - [Debugging-Tipps](#debugging-tipps)

---

## systemd Security Architecture

### Design-Prinzip: Strikte Trennung

`entropywatcher.py` hat eine eingebaute Sicherheits-Regel, die verhindert, dass systemd-Services mit unsicheren `--env` Parametern gestartet werden:

```python
def _launched_by_systemd() -> bool:
    """Erkennt ob das Skript in einem systemd-Kontext läuft."""
    return any(k in os.environ for k in ("INVOCATION_ID", "JOURNAL_STREAM", "NOTIFY_SOCKET"))

# In main():
if systemd and env_files:
    sys.stderr.write("Fehler: Unter systemd sind zusätzliche --env Dateien nicht erlaubt.\n")
    sys.exit(2)  # EXIT 2 = CRITICAL
```

**Warum diese Regel existiert:**

Systemd-Services sollten **alle** Konfiguration über die `.service`-Datei (via `EnvironmentFile=`) bekommen. Wenn jemand in der Service-Definition zusätzlich `--env /tmp/malicious.env` einbaut, könnte das:

1. **Unerwartete Konfiguration laden** (Security Bypass)
   - Beispiel: `--env /tmp/override.env` mit `ALERT_ENTROPY_ABS=10.0`
   - Konsequenz: Keine Alarme mehr, obwohl Ransomware aktiv

2. **Production-Settings überschreiben**
   - Beispiel: `CHECK_HONEYFILES=0` in malicious.env
   - Konsequenz: Intrusion Detection deaktiviert

3. **Credentials aus unsicheren Quellen laden**
   - Beispiel: `--env /tmp/leak.env` mit DB-Passwort von Angreifer
   - Konsequenz: DB-Kompromittierung

Die strikte Regel **erzwingt** best practices:
- **Systemd-Services:** Nur `EnvironmentFile=` in der `.service`-Datei
- **CLI-Nutzung:** Flexibel mit `--env` für Entwicklung, Testing, manuelle Status-Checks

**Beispiel - Sichere Service-Definition:**

```ini
# /etc/systemd/system/entropywatcher-nas.service
[Service]
Type=oneshot
User=nasuser
EnvironmentFile=/opt/apps/entropywatcher/config/common.env
EnvironmentFile=/opt/apps/entropywatcher/config/nas.env
ExecStart=/opt/apps/entropywatcher/venv/bin/python /opt/apps/entropywatcher/main/entropywatcher.py scan-all
# ✓ Korrekt: Keine --env Parameter in ExecStart
# ✗ FALSCH: ExecStart=... --env /tmp/override.env  → würde mit Exit 2 abbrechen
```

---

### Das Vererbungs-Problem

**Szenario:** Ein systemd-Service ruft andere Scripts auf, die wiederum `entropywatcher.py status` ausführen.

**Problem:** Alle Kind-Prozesse erben die systemd-Umgebungsvariablen des Eltern-Prozesses.

**Konkrete Auswirkung im Monitoring-Dashboard:**

```
monitoring-status-update.service (systemd Unit)
├─ INVOCATION_ID=abc123...
├─ JOURNAL_STREAM=...
├─ NOTIFY_SOCKET=...
│
└─ aggregate_status.sh (Bash Script)
   └─ (erbt alle systemd-Variablen)
      │
      └─ safety_gate.sh (Bash Script)
         └─ (erbt alle systemd-Variablen)
            │
            └─ entropywatcher.py status --env common.env --env nas.env
               └─ _launched_by_systemd() = True  ← Sieht INVOCATION_ID!
               └─ env_files = ["common.env", "nas.env"]
               └─ ❌ FEHLER: systemd=True + env_files → Exit 2 (CRITICAL)
```

**Symptom:**

- **CLI:** `./safety_gate.sh` → Exit 0 (GREEN) ✓
  - Kein systemd-Kontext → `_launched_by_systemd()` = False
  - `--env` Parameter werden akzeptiert
  
- **Dashboard:** Zeigt RED, obwohl System sicher ist ✗
  - systemd-Timer ruft Script auf → systemd-Kontext
  - `entropywatcher.py` lehnt `--env` ab → Exit 2
  - `aggregate_status.sh` interpretiert Exit 2 als RED

**Auswirkung auf Backups:**

Die Safety-Gate-Logik in `rtb_wrapper.sh` sieht:
```bash
if ! /opt/apps/entropywatcher/main/safety_gate.sh; then
    log "❌ SAFETY-GATE: RED - Backup blockiert!"
    exit 1
fi
```

→ Backups werden unnötig blockiert, obwohl das System sicher ist.

---

### RTB Wrapper: Backup Loop Prevention (seit Mai 2026)

**Problem:** Tools wie **pCloud Commander** laden Dateien in `/srv/nas/restore/` herunter —
ein Unterverzeichnis der RTB-Backup-Quelle. Das erzeugt beim nächsten RTB-Lauf ein Delta
und triggert ein unnötiges Backup (Backup-Loop-Risiko).

**Implementierung in `rtb_wrapper.sh`:**

```bash
# Konfiguration (oben im Skript)
RTB_AUTO_EXCLUDE_RESTORE=${RTB_AUTO_EXCLUDE_RESTORE:-1}
RTB_RESTORE_EXCLUDE_PATTERN=${RTB_RESTORE_EXCLUDE_PATTERN:-/restore/}

# Effektive Exclude-Datei bauen
if [[ "$RTB_AUTO_EXCLUDE_RESTORE" -eq 1 ]]; then
  TMP_RTB_EXCL="$(mktemp /tmp/rtb_excludes_effective.XXXXXX)"
  cp "$RTB_EXCL" "$TMP_RTB_EXCL"
  if ! grep -qF "$RTB_RESTORE_EXCLUDE_PATTERN" "$TMP_RTB_EXCL"; then
    printf '%s\n' "$RTB_RESTORE_EXCLUDE_PATTERN" >> "$TMP_RTB_EXCL"
  fi
  EFFECTIVE_RTB_EXCL="$TMP_RTB_EXCL"
  trap '[[ -n "$TMP_RTB_EXCL" ]] && rm -f "$TMP_RTB_EXCL" || true' EXIT
fi
```

**Zwei Schutzschichten:**
1. **`excludes.txt`** enthält statisch `/restore/` → gilt auch bei manuellem Aufruf ohne Wrapper
2. **`EFFECTIVE_RTB_EXCL`** Temp-Datei → Wrapper-Laufzeit, Sicherheitsnetz bei direkter Bearbeitung

**Alle drei rsync-Aufrufe** im Wrapper nutzen `EFFECTIVE_RTB_EXCL`:
- `--check-only` Dry-Run (Change Detection für Monitoring)
- Pre-Backup Delta-Check (vor dem eigentlichen RTB-Aufruf)
- `rsync_tmbackup.sh`-Übergabe

Kein Eingriff in `rsync_tmbackup.sh` nötig (upstream-Datei bleibt unberührt).

---

### Die Lösung: `env -u`

**Implementierung in `safety_gate.sh`:**

```bash
# Definition (Zeile ~34):
# Sauberer Aufruf ohne systemd-Kontext (für Status-Checks in systemd Units)
# Dies verhindert den Konflikt: entropywatcher.py denkt es ist ein Service und lehnt --env ab
CLEAN_CALL="env -u INVOCATION_ID -u JOURNAL_STREAM -u NOTIFY_SOCKET"

# Anwendung (Zeile ~108):
set +e
$CLEAN_CALL "$ENTROPYWATCHER_PY" "$ENTROPYWATCHER_SCRIPT" \
  --env "$ENTROPYWATCHER_COMMON_ENV" \
  --env "$SERVICE_ENV" \
  status --json-out /dev/null 2>/dev/null

STATUS=$?
set -e
```

**Was `env -u` macht:**

`env -u VARIABLE` entfernt eine Umgebungsvariable **nur für diesen einen Befehl**:

```bash
# Vorher:
echo $INVOCATION_ID  # abc123...

# Mit env -u:
env -u INVOCATION_ID bash -c 'echo $INVOCATION_ID'  # (leer)

# Nachher:
echo $INVOCATION_ID  # abc123... (unverändert!)
```

**Effekt:**

```
safety_gate.sh (systemd-Kontext)
├─ INVOCATION_ID=abc123...  ← Gesetzt im Parent
│
└─ env -u INVOCATION_ID ... entropywatcher.py status
   └─ INVOCATION_ID=  ← Leer im Child!
   └─ _launched_by_systemd() = False  ← Keine systemd-Variablen sichtbar
   └─ --env common.env wird akzeptiert ✓
   └─ Exit 0 (GREEN)
```

---

### Warum die Sicherheit NICHT gefährdet ist

**Kritische Frage:** Umgehen wir damit nicht die Sicherheitsprüfung?

**Antwort:** Nein, aus folgenden Gründen:

#### 1. Echte systemd-Services bleiben geschützt

Wenn jemand versucht, in einer **echten** Service-Definition unsichere Parameter einzubauen:

```ini
# /etc/systemd/system/entropywatcher-nas.service (FALSCH!)
[Service]
ExecStart=/opt/apps/entropywatcher/venv/bin/python \
  /opt/apps/entropywatcher/main/entropywatcher.py \
  --env /tmp/malicious.env \  # ← Versuch, unsichere Config zu laden
  scan-all
```

→ Systemd setzt die Variablen **direkt**, ohne `env -u` davor.  
→ `_launched_by_systemd()` = True  
→ Script bricht mit Exit 2 ab ✓ (Sicherheitsprüfung greift!)

#### 2. Nur in `safety_gate.sh` - explizite Ausnahme

Die Verwendung von `env -u` ist auf **einen einzigen Ort** beschränkt:
- **safety_gate.sh** - für read-only Status-Checks
- **Nicht** in Production-Service-Definitionen
- **Nicht** in Scan-Scripts
- **Dokumentiert** als bewusste Design-Entscheidung

#### 3. Read-Only Status-Check vs. Production Scan

Es gibt einen fundamentalen Unterschied:

| Aktion | Kontext | Risiko | Schutz erforderlich? |
|--------|---------|--------|----------------------|
| `scan-all` in systemd | Production-Scan mit DB-Write | Hoch | ✓ Ja - strikte Regel |
| `status` in safety_gate.sh | Read-Only Check aus Monitoring | Niedrig | ✗ Nein - bekannter Kontext |

**Begründung:**

`safety_gate.sh` ist ein **kontrolliertes Script** mit festgelegten `.env`-Dateien:
```bash
SERVICE_ENV="/opt/apps/entropywatcher/config/${SERVICE}.env"
# ↑ Hardcoded, nicht vom User beeinflussbar
```

Ein Angreifer kann **nicht** einfach einen beliebigen Path injizieren, weil:
- Das Script selbst definiert die Pfade (`/opt/apps/entropywatcher/config/nas.env`)
- Keine User-Input-Parameter für `--env`
- Script liegt in `/opt/apps/` → Root-Rechte zum Ändern erforderlich

Wenn ein Angreifer Root hat, kann er ohnehin:
- Die `.env`-Dateien direkt modifizieren
- Das Script selbst ändern
- Die systemd-Services manipulieren

→ Die `env -u`-Lösung fügt keine neue Angriffsfläche hinzu.

#### 4. Minimaler Scope

`env -u` wirkt **nur** für den einen `entropywatcher.py status` Aufruf:

```bash
# Vorher:
echo $INVOCATION_ID  # abc123...

# Während env -u:
env -u INVOCATION_ID entropywatcher.py status  # Keine systemd-Vars

# Nachher:
echo $INVOCATION_ID  # abc123... (unverändert!)
```

Der Rest der Monitoring-Chain (aggregate_status.sh, andere Scripts) behält den systemd-Kontext.

**Dashboard-Timer (pcloud-tools, seit Aug 2026):** `monitoring-status-quick.timer` (5 min, ohne RTB `--check-only`) + `monitoring-status-update.timer` (15 min full, nach Backup). Live Safety-Gate wird bei jedem Aggregate-Lauf neu abgefragt; Header-Datum im Dashboard springt typisch alle 5 min.

---

### Debugging-Tipps

#### Problem: `safety_gate.sh` liefert unerwartet RED (Exit 2)

**Schritt 1: Prüfe systemd-Kontext**

```bash
# In CLI (sollte leer sein):
env | grep -E 'INVOCATION_ID|JOURNAL_STREAM|NOTIFY_SOCKET'

# Im systemd-Service (sollte gesetzt sein):
sudo systemctl status monitoring-status-update.service
# → Zeigt Environment-Variablen
```

**Schritt 2: Teste manuell vs. systemd**

```bash
# Manueller Test (sollte funktionieren):
/opt/apps/entropywatcher/main/safety_gate.sh
echo $?  # 0 = GREEN, 1 = YELLOW, 2 = RED

# Aus systemd (kann fehlschlagen ohne env -u Fix):
sudo systemctl start monitoring-status-update.service
cat /opt/apps/monitoring/status.json | jq '.scripts.rtb_wrapper.live_safety_gate'
# Sollte "GREEN" oder "YELLOW" sein, nicht "RED"
```

**Schritt 3: Verbose Mode für entropywatcher.py**

```bash
# Mit systemd-Variablen gesetzt (simuliert Problem):
export INVOCATION_ID="test123"
export JOURNAL_STREAM="8:12345"

# Ohne env -u (sollte fehlschlagen):
/opt/apps/entropywatcher/venv/bin/python \
  /opt/apps/entropywatcher/main/entropywatcher.py \
  --env /opt/apps/entropywatcher/config/common.env \
  --env /opt/apps/entropywatcher/config/nas.env \
  status
# Fehler: Unter systemd sind zusätzliche --env Dateien nicht erlaubt.
# Exit: 2

# Mit env -u (sollte funktionieren):
env -u INVOCATION_ID -u JOURNAL_STREAM \
  /opt/apps/entropywatcher/venv/bin/python \
  /opt/apps/entropywatcher/main/entropywatcher.py \
  --env /opt/apps/entropywatcher/config/common.env \
  --env /opt/apps/entropywatcher/config/nas.env \
  status
# Exit: 0 (GREEN)

# Cleanup:
unset INVOCATION_ID JOURNAL_STREAM
```

**Schritt 4: Check safety_gate.sh Implementation**

```bash
# Prüfe ob CLEAN_CALL definiert ist:
grep -n "CLEAN_CALL=" /opt/apps/entropywatcher/main/safety_gate.sh
# Erwartung: Zeile ~34 mit env -u Definition

# Prüfe ob es verwendet wird:
grep -n "\$CLEAN_CALL" /opt/apps/entropywatcher/main/safety_gate.sh
# Erwartung: Zeile ~108 im entropywatcher.py Aufruf
```

**Schritt 5: Logs prüfen**

```bash
# Systemd-Service-Logs:
journalctl -u monitoring-status-update.service -n 50 --no-pager

# Safety-Gate-Output (wenn in aggregate_status.sh geloggt):
tail -f /var/log/syslog | grep -i "safety"

# Status-JSON (manuell aktualisieren und vergleichen):
sudo /opt/apps/pcloud-tools/main/scripts/aggregate_status.sh --verbose
cat /opt/apps/monitoring/status.json | jq '.'
```

---

## Best Practices

### DO: Systemd-Services mit EnvironmentFile=

```ini
[Service]
Type=oneshot
EnvironmentFile=/opt/apps/entropywatcher/config/common.env
EnvironmentFile=/opt/apps/entropywatcher/config/nas.env
ExecStart=/opt/apps/entropywatcher/venv/bin/python \
  /opt/apps/entropywatcher/main/entropywatcher.py scan-all
```

### DON'T: --env in systemd ExecStart

```ini
# ❌ FALSCH - wird mit Exit 2 abbrechen!
[Service]
ExecStart=/opt/apps/entropywatcher/venv/bin/python \
  /opt/apps/entropywatcher/main/entropywatcher.py \
  --env /opt/apps/entropywatcher/config/common.env \
  scan-all
```

### DO: CLI-Testing mit --env

```bash
# ✓ Korrekt für Entwicklung/Testing:
/opt/apps/entropywatcher/venv/bin/python \
  /opt/apps/entropywatcher/main/entropywatcher.py \
  --env /opt/apps/entropywatcher/config/common.env \
  --env /opt/apps/entropywatcher/config/nas.env \
  status
```

### DO: env -u für Status-Checks in systemd-Chains

```bash
# ✓ Korrekt in safety_gate.sh:
CLEAN_CALL="env -u INVOCATION_ID -u JOURNAL_STREAM -u NOTIFY_SOCKET"
$CLEAN_CALL "$ENTROPYWATCHER_PY" "$ENTROPYWATCHER_SCRIPT" \
  --env "$COMMON_ENV" \
  --env "$SERVICE_ENV" \
  status
```

---

## Weitere Themen

- [Config-Management](CONFIG.md) - `.env`-Dateien, Variablen-Hierarchie
- [Testing](TESTING.md) - Unit-Tests, Integrationstests
- [ClamAV Integration](CLAMAV_INTEGRATION.md) - Antivirus-Scanning
- [Installation](INSTALLATION.md) - Server-Setup, systemd-Konfiguration
