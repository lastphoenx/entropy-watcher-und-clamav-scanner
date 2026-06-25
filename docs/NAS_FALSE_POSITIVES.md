# NAS False-Positives (Backup-Daten, AppleDouble)

Häufiges Szenario auf einem NAS mit Proxmox-Backup-Server (PBS), PVE-Dumps, Paperless und Mac-Clients: EntropyWatcher flaggt **erwartbar hoch-entropische Dateien** — das Safety-Gate blockiert RTB/pCloud, obwohl ClamAV grün ist.

---

## Symptome

- `entropywatcher.py status` → **RED** wegen `flagged_files`
- `nas-av` grün (0 ClamAV-Funde)
- `report --only-flagged` zeigt u. a.:
  - PBS-Chunks unter `.../Backup/pbs2/.chunks/`
  - PVE-Backups (`*.gpg`, `.rnd`)
  - Paperless-Thumbnails (`*.webp`)
  - macOS AppleDouble (`._*`)

**Wichtig:** `HEALTH_FLAGGED_MAX=0` zählt nur Flags **im Zeitfenster** (`HEALTH_WINDOW_MIN`), nicht die Gesamtzahl historischer DB-Einträge. Alte `flagged=1` Zeilen können das Report trotzdem voll machen.

---

## Drei getrennte Pipelines

```
/srv/nas/...
    ├─► EntropyWatcher (EXCLUDES / SCORE_EXCLUDES)
    │      → Scan, Flag, Safety-Gate
    │      → blockiert Backup bei RED
    │
    ├─► RTB (excludes.txt)
    │      → rsync kopiert alles außer Exclude-Patterns
    │      → unabhängig von EntropyWatcher
    │
    └─► pCloud-Pool-Sync
           → spiegelt RTB-Pool-Inhalt
```

| Änderung | PBS/Backup weiter im RTB? | `._*` / `__pycache__` im RTB? |
|----------|---------------------------|-------------------------------|
| `EXCLUDES` / `SCORE_EXCLUDES` in `common.env` | Ja | Ja (nur EW ignoriert/alarmiert nicht) |
| `**/._*`, `__pycache__/`, … in `rtb/excludes.txt` | Ja | Nein (nicht gesichert) |
| `/pcloud-archive/`, `/pcloud-temp/` nur in Check-Exclude | Ja (wenn anderes Delta Backup startet) | Mit im Snapshot; triggern allein nicht |

---

## Dauerhafter Fix (EntropyWatcher)

### 1. `EXCLUDES` — komplett überspringen

Sinnvoll für Bereiche, in denen hohe Entropie **normal** ist und ein Scan wenig Sicherheitsgewinn bringt:

```bash
EXCLUDES=...,/srv/nas/Backup/**,**/Backup/pbs2/**,**/Backup/pve2/**
```

### 2. `SCORE_EXCLUDES` — messen, nicht alarmieren

Für Dateitypen/Pfade, die noch in der DB landen sollen, aber nie `flagged` werden:

```bash
SCORE_EXCLUDES=...,**/.chunks/**,**/*.blob,**/*.fidx,**/*.webp,**/*.gpg,**/.rnd,\
**/trusted.gpg.d/**,**/Paperless/media/documents/thumbnails/**,**/._*
```

`**/._*` matcht AppleDouble über **vollen Pfad oder Dateiname** (Glob in `entropywatcher.py`).

Beispiel-Config: [.server-config/example/config/common.env.example](../.server-config/example/config/common.env.example)

### 3. DB bereinigen (einmalig nach Config-Änderung)

Alte `flagged=1` Einträge bleiben in der DB, bis sie bereinigt werden — auch wenn neue Scans die Pfade überspringen (`EXCLUDES`).

Siehe private Ops-Doku unter `doku/Raspi/raspinas/entropywatcher/db-cleanup.md` (SQL + Validierung).

Reihenfolge empfohlen: **Config anpassen → DB bereinigen → manuellen Scan starten**

```bash
sudo systemctl start entropywatcher-nas.service
/opt/apps/entropywatcher/main/safety_gate.sh; echo exit=$?
```

---

## RTB: AppleDouble & Python-Cache nicht sichern

In `rtb/excludes.txt` (rsync `--exclude-from` beim **echten** Backup):

```text
**/._*
__pycache__/
*.py[cod]
.venv/
venv/
```

Reduziert Pool/pCloud-Größe und vermeidet Backup-Trigger durch `.pyc`-Churn. **Kein Ersatz** für serverseitige EW-Regeln — beide Schichten ergänzen sich.

Pipeline-Pfade (`pcloud-archive/`, `pcloud-temp/`) stehen **nicht** in `excludes.txt` — sie triggern nur im Delta-Check nicht (`rtb_check_excludes.sh`). Siehe `rtb/README.md` § Excludes.

---

## Optional (Client-seitig)

Mac: `defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true` — verhindert neue `._*` auf Netzwerk-Shares. Server-Filter (oben) decken auch Geräte ab, die das nicht setzen.

---

## Siehe auch

- [CONFIG.md](CONFIG.md) — alle ENV-Variablen
- [.server-config/README.md](../.server-config/README.md) — Beispiel-Configs ohne Secrets
