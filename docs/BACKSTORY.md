# Die Entstehungsgeschichte: Vom QNAP-Frust zur vollautomatisierten Backup-Pipeline

**TL;DR:** Frustration mit proprietären NAS-Systemen → Wechsel zu Debian → Schrittweise Entwicklung einer vollautomatisierten Security-Pipeline mit EntropyWatcher, Honeyfiles und deduplizierten Cloud-Backups.

---

## Von proprietären NAS-Systemen zu Debian

Die Reise begann mit Frustration: **QNAP** (TS-453 Pro, TS-473A, TS-251+) und **LaCie 5big NAS Pro** waren zwar funktional, aber sobald man mehr als die Standard-Features wollte, wurde es zum Gefrickel. Autostart-Scripts, limitierte Shell-Umgebungen, fehlende Packages - man kam einfach nicht ans Ziel.

**Die Lösung:** Wechsel auf ein vollwertiges **Debian-System**. Hardware: **Raspberry Pi 5** mit **Radxa Penta SATA HAT** (5x 2.5" SATA-SSDs), Samba-Share mit Recycling-Bin. Volle Kontrolle, Standard-Tools, keine Vendor-Lock-ins.

---

## Der Weg zur vollautomatisierten Backup-Pipeline

### 1️⃣ **RTB Wrapper** - Delta-gesteuerte Backups

**Ziel:** Automatisierte lokale Backups mit Deduplizierung über Standard-Debian-Tools.

Ich entschied mich für [Rsync Time Backup](https://github.com/laurent22/rsync-time-backup) - ein cleveres Script, das `rsync --hard-links` nutzt, um platzsparende Snapshots zu erstellen. **Problem:** Das Script lief immer, auch wenn keine Änderungen vorlagen.

**Lösung:** Der [RTB Wrapper](https://github.com/lastphoenx/rtb) prüft vorher ob überhaupt ein Delta existiert (via `rsync --dry-run`). Nur bei echten Änderungen wird das Backup ausgeführt.

**Repository:** [github.com/lastphoenx/rtb](https://github.com/lastphoenx/rtb)

---

### 2️⃣ **EntropyWatcher + ClamAV** - Pre-Backup Security Gate

**Eine Erkenntnis:** **Backups von infizierten Dateien sind wertlos.** Schlimmer noch - sie verbreiten Malware in die Backup-Historie und Cloud.

**Lösung:** [EntropyWatcher & ClamAV Scanner](https://github.com/lastphoenx/entropy-watcher-und-clamav-scanner) analysiert `/srv/nas` (und optional das OS) auf:
- **Entropy-Anomalien** (verschlüsselte/komprimierte verdächtige Dateien)
- **Malware-Signaturen** (ClamAV)
- **Safety-Gate-Mechanismus:** Backups werden nur bei grünem Status ausgeführt

Später erweitert auf das gesamte Betriebssystem (`/`, `/boot`, `/home`).

**Repository:** [github.com/lastphoenx/entropy-watcher-und-clamav-scanner](https://github.com/lastphoenx/entropy-watcher-und-clamav-scanner) (dieses Repo)

---

### 3️⃣ **Honeyfiles** - Intrusion Detection mit Ködern

**Auslöser:** Der **Shai-Hulud 2.0 npm Worm** zeigte: Moderne Malware sucht aktiv nach Credentials (`~/.aws/credentials`, `.git-credentials`, `.env`-Dateien).

**Gegenmaßnahme:** **Honeyfiles** - 7 Köder-Dateien mit **randomisierten Namen und Pfaden** (gespeichert in `/opt/apps/entropywatcher/config/honeyfile_paths`), überwacht durch **auditd** auf Kernel-Ebene:

- **Tier 1:** Zugriff auf Honeyfile = sofortiger Alarm + Backup-Blockade
- **Tier 2:** Zugriff auf Honeyfile-Config = verdächtig
- **Tier 3:** Manipulation an auditd = kritischer Alarm

**Sicherheits-Feature:** Dateinamen und Speicherorte werden bei Installation randomisiert (z.B. `credentials_a7f3e_20251214` statt `credentials`) → Angreifer können die Pfade nicht aus öffentlicher Dokumentation erraten.

**Setup-Guide:** [HONEYFILE_SETUP.md](HONEYFILE_SETUP.md)

---

### 4️⃣ **pCloud-Tools** - Deduplizierte Cloud-Backups

Mit funktionierender lokaler Backup- und Security-Pipeline kam die Frage: **Wie bekomme ich das sicher in die Cloud?**

**Anforderung:** Deduplizierung wie bei `rsync --hard-links` (Inode-Prinzip), aber `rclone` konnte das nicht.

**Lösung:** [pCloud-Tools](https://github.com/lastphoenx/pcloud-tools) mit **JSON-Manifest-Architektur**:
- **JSON-Stub-System:** Jedes Backup speichert nur Metadaten + Verweise auf echte Files
- **Inhalts-basierte Deduplizierung:** Gleicher SHA256-Hash = gleiche Datei = kein Upload
- **Restore-Funktion:** Rekonstruiert komplette Backups aus Manifests + File-Pool

**Repository:** [github.com/lastphoenx/pcloud-tools](https://github.com/lastphoenx/pcloud-tools)

---

## Zusammenspiel der Komponenten

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

## Technologie-Stack

- **OS:** Debian Bookworm (Raspberry Pi 5)
- **Storage:** 5x 2.5" SATA SSD (Radxa Penta SATA HAT)
- **File Sharing:** Samba mit Recycling-Bin
- **Security:** auditd, ClamAV, Python-basierte Entropy-Analyse
- **Backup:** rsync, JSON-Manifests, pCloud API
- **Automation:** Bash, systemd-timer, Git-Workflow

---

## Timeline (Entwicklungs-Meilensteine)

| Phase | Was | Wann |
|-------|-----|------|
| 1 | QNAP/LaCie Frustration | 2023-2024 |
| 2 | Raspberry Pi 5 + Debian Setup | Q4 2024 |
| 3 | RTB Wrapper (Delta-Detection) | Q1 2025 |
| 4 | EntropyWatcher (Entropy + ClamAV) | Q2 2025 |
| 5 | Honeyfiles (Shai-Hulud Response) | Q3 2025 |
| 6 | pCloud-Tools (JSON-Manifest-Deduplizierung) | Q4 2025 |
| 7 | Dashboard + Monitoring Integration | Q1 2026 |

---

## Lessons Learned

### Was funktioniert hat ✅

1. **Standard-Linux statt proprietärer NAS:**  
   Volle Kontrolle über Packages, Scripts, Automation. Kein Vendor-Lock-in.

2. **Layered Security:**  
   EntropyWatcher (Anomaly Detection) + ClamAV (Signatures) + Honeyfiles (IDS) = mehrere Schutzebenen.

3. **Deduplizierung über Inhalte, nicht Pfade:**  
   JSON-Manifest-Architektur = Cloud-Speicher-Einsparung von 90%+ bei Snapshots.

4. **systemd-Timer statt Cron:**  
   OnCalendar + OnUnitActiveSec + Persistent = Robuster als Cronjobs.

### Was überraschend komplex war ⚠️

1. **systemd Environment Inheritance:**  
   Monitoring-Chains (service → script → script) erben Umgebungsvariablen. `env -u` als Lösung.  
   Details: [DEVELOPER_GUIDE.md#systemd-security-architecture](DEVELOPER_GUIDE.md#systemd-security-architecture)

2. **ClamAV On-Demand vs. Real-Time:**  
   `clamd` Memory-Footprint auf Raspberry Pi 5: ~800 MB. Lösung: On-Demand-Scans nur.

3. **MariaDB auf Raspberry Pi:**  
   InnoDB Buffer-Pool muss limitiert werden (`innodb_buffer_pool_size=128M`).

---

## Nächste Schritte (Roadmap)

- [ ] Web-UI für EntropyWatcher (Status, Reports, History)
- [ ] Automatische False-Positive-Erkennung (ML-basiert)
- [ ] Multi-Host-Deployment (Ansible Playbooks)
- [ ] S3-Backend-Support für pCloud-Tools (zusätzlich zu pCloud)

---

**Zurück zu:** [Hauptdokumentation](../README.md)
