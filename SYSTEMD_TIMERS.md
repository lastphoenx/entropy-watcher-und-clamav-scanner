# Systemd Timer & NAS-Schedule (pi-nas)

> **Beispiel-Units:** `systemd/*.example` in diesem Repo  
> **Auf pi-nas:** Dateien nach `/etc/systemd/system/` — **manuell patchen**, nicht blind `cp` (Pfade/User können abweichen).

---

## Tagesablauf (NAS — pi-nas Produktion)

| Zeit (CEST) | Timer | Service | Was passiert | Warum so |
|-------------|-------|---------|--------------|----------|
| **23:00** ±10m | `entropywatcher-nas-av.timer` | `entropywatcher-nas-av.service` | ClamAV Hot Paths | Abends, vor Nacht-Jobs; getrennt von Entropy 02:00 |
| **02:00** ±5m | `entropywatcher-nas.timer` | `entropywatcher-nas.service` | Entropy Delta-Scan | ~2h vor Backup 04:00 |
| **03:00** ±15m | `entropywatcher-nas-av-weekly.timer` (So) | `entropywatcher-nas-av-weekly.service` | ClamAV Full (wöchentlich) | Sonntag nachts; `ALLOW_HOURS=02-06` nur hier |
| **04:00** | `backup-pipeline.timer` | `backup-pipeline.service` | RTB + pCloud POOL | Backup 1/3 |
| **10:00** ±5m | `entropywatcher-nas.timer` | `entropywatcher-nas.service` | Entropy Delta | ~2h vor Backup 12:00 |
| **12:00** | `backup-pipeline.timer` | `backup-pipeline.service` | RTB + pCloud POOL | Backup 2/3 |
| **18:00** ±5m | `entropywatcher-nas.timer` | `entropywatcher-nas.service` | Entropy Delta | ~2h vor Backup 20:00 |
| **20:00** | `backup-pipeline.timer` | `backup-pipeline.service` | RTB + pCloud POOL | Backup 3/3 |

**Nicht stündlich:** Stündliche Entropy-Scans über mergerfs haben den Pi mehrfach überlastet.

**Kein `Conflicts=`:** Früher hat `entropywatcher-nas` um :20 den AV-Scan per SIGTERM abgebrochen. Jetzt nur noch **gemeinsamer Lock** (`/run/backup_pipeline.lock`).

---

## Koordination schwerer Jobs

| Mechanismus | Wo | Wirkung |
|-------------|-----|---------|
| `with_nas_heavy_ops_lock.sh` | Entropy/AV systemd | Start nur wenn Lock frei |
| `NAS_HEAVY_OPS_FAIL_FAST=1` | Entropy + backup-pipeline | Lock belegt → sofort skip (exit 0), kein 2h-Warten |
| `NAS_HEAVY_OPS_ALLOW_HOURS=02-06` | **nur** `nas-av-weekly.service` | Nachhol-Läufe (`Persistent`) tagsüber blockieren |
| **kein** `ALLOW_HOURS` | backup-pipeline, nas, nas-av | Alle Timer-Zeiten (04/12/20, 02/10/18, 23:00) müssen laufen |
| Signature-Trigger | `rtb` (`RTB_TRIGGER_MODE=signature`) | Backup-Entscheid ohne `rsync -ni` Vollbaum (OOM-Fix) |

---

## backup-pipeline.service (Kernpunkte)

- `ExecStart=/opt/apps/rtb/rtb_pool_wrapper.sh`
- `WorkingDirectory=/opt/apps/pcloud-tools/main`
- `MemoryMax=5G` — Schutz beim **echten** rsync-Backup, nicht beim Signature-Check
- `TimeoutStartSec=4h`
- **Kein** `RTB_CHECK_MEMORY_MAX_MB` in der Unit

---

## Deploy-Checkliste

```bash
# Nach git pull (rtb + entropywatcher):
sudo systemctl daemon-reload

# Test vor backup-timer:
sudo /opt/apps/rtb/rtb_pool_wrapper.sh --check-only
# Erwartung: [RTB Signature] scanned … files in …s — RAM stabil

sudo systemctl enable --now entropywatcher-nas.timer
sudo systemctl enable --now entropywatcher-nas-av.timer
# backup-pipeline.timer erst nach erfolgreichem check-only:
# sudo systemctl enable --now backup-pipeline.timer
```

---

## Legacy / optional

| Timer | Hinweis |
|-------|---------|
| `raspi5nas-backup.timer` | Separates RTB ohne pCloud — prüfen ob noch nötig neben `backup-pipeline` |
| `entropywatcher-os*.timer` | OS-Partition, unabhängig von NAS |

Siehe auch: `doku/Raspi/raspinas/pcloud-tools/OPERATIONS_2026-08.md`, `rtb/README.md` § Signature-Trigger.
