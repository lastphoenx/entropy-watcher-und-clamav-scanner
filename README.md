# Entropy-Watcher-und-ClamAV-Scanner
Entropie-Wächter (Standard): misst Dateientropie/Integrität über die Zeit. Speichert Baseline (start), vorherigen und letzten Wert (prev/last) und markiert Dateien, wenn die Entropie absolut hoch ist oder stark springt.  ClamAV-Wächter (optional): scannt angegebene Pfade mit ClamAV; bei Funden gibt’s Mail.

Was macht das Tool?

Entropie-Wächter (Standard): misst Dateientropie/Integrität über die Zeit. Speichert Baseline (start), vorherigen und letzten Wert (prev/last) und markiert Dateien, wenn die Entropie absolut hoch ist oder stark springt.

ClamAV-Wächter (optional): scannt angegebene Pfade mit ClamAV; bei Funden gibt’s Mail.

Architektur (kurz)

Programm: /opt/entropywatcher/entropywatcher.py (eine CLI für beides).

Datenbank: MariaDB-Tabelle files (ein Eintrag je Pfad; Entropie-Werte, Zeiten, Flags, u. a.).

Konfiguration (.env):

common.env → globale Defaults (DB, Mail-Transport, Schwellen).

Pro Job eigene ENV: nas.env, os.env, nas-av.env, nas-av-weekly.env, os-av.env, os-av-weekly.env. Darin nur Unterschiede (z. B. SCAN_PATHS, Mail-Branding, AV an/aus).

systemd:

.service führt einmalig aus (Type=oneshot), setzt ENV-Dateien, User, ExecStart.

.timer triggert den Service zeitgesteuert. Nur Timer aktivieren.

Logging: standardmäßig ins Journal; pro Service eigener SyslogIdentifier (z. B. ew-os-scan) → journalctl -t ew-os-scan. Optional Datei-Log via LOG_FILE=.

E-Mail-Benachrichtigungen

Entropie: Mail nur bei neuen Flags dieses Laufs (nicht bei Altlasten), respektiert Rate-Limit (ALERT_STATE_FILE + MAIL_MIN_ALERT_INTERVAL_MIN).

ClamAV: Mail nur bei echten Funden (Exitcode 1), ebenfalls mit Rate-Limit.

CLI-Befehle (das brauchst du praktisch)

init-scan --paths "/pfad1,/pfad2" → Baseline anlegen (mit --force neu inicialisieren).

scan --paths "/pfad1,/pfad2" → Delta-Scan: nur neue/geänderte Dateien schwer scannen; regelmäßige Vollprüfung nach N Tagen.

report [--source os|nas] [--only-flagged] [--since-missing] [--export out.csv|json --format csv|json]

tag-exempt <path> / tag-normal <path> → Datei vom Alarmieren aus-/wieder einschließen (Messung bleibt).

av-scan --paths "/pfad1,/pfad2" → ClamAV über angegebene Pfade.

WICHTIG: Pfade gibst du immer über --paths (oder ${SCAN_PATHS} aus dem Service) an. Das frühere WATCH_DIRS aus .env ist ersetzt.

Typische Rollen (so hast du’s eingerichtet)

NAS Entropie (stündlich): entropywatcher-nas.service + entropywatcher-nas.timer
ENV: common.env + nas.env (setzt SCAN_PATHS="/srv/nas/Thomas,...")

OS Entropie (täglich): entropywatcher-os.service + entropywatcher-os.timer
ENV: common.env + os.env

AV Hot (täglich): *-av.service + *-av.timer
ENV: *-av.env (setzt SCAN_PATHS auf Hot-Ordner, CLAMAV_ENABLE=1).

AV Weekly (breiter): *-av-weekly.service + *-av-weekly.timer
ENV: *-av-weekly.env (z. B. /srv/nas, CLAMAV_ENABLE=1).

Rechte/Benutzer

NAS-Scans: als thomas (passt zu Share-Rechten).

OS-Scans: für sensible Dateien (z. B. /etc/shadow) als root; sonst thomas + passende EXCLUDES.

ClamAV: mit clamdscan + --fdpass; auf Pfade achten, die der User lesen darf.

Wann wird „flagged“ (Entropie)?

Absolut: last_entropy >= ALERT_ENTROPY_ABS (z. B. 7.8).

Sprung: last_entropy - COALESCE(prev_entropy, start_entropy) >= ALERT_ENTROPY_JUMP (Δ zu prev; Fallback start).

Exempt: Dateien mit score_exempt=1 oder SCORE_EXCLUDES werden gemessen, aber nicht alarmiert.

Nützliche Journal-Kommandos

Letzte Läufe sehen:
journalctl -u entropywatcher-nas.service -n 100 --no-pager
oder mit Identifier: journalctl -t ew-os-scan -n 100

Ad-hoc Start:
sudo systemctl start entropywatcher-os.service

Kurzer Report:
/opt/entropywatcher/venv/bin/python /opt/entropywatcher/entropywatcher.py report --source os | head

Bewährte Einstellungen & Stolperfallen

Timer aktivieren, nicht Services. Missed runs holen Timer mit Persistent=true nach (so konfiguriert).

Pfade mit Leerzeichen: in ENVs immer in Anführungszeichen, z. B.
SCAN_PATHS="/srv/nas/Ablage mit Leerzeichen,/srv/nas/Thomas".

Überlappung vermeiden: Zeiten versetzt planen; deine Timer sind gestaffelt → gut.

CLAMAV_ENABLE im common.env auf 0 lassen; nur in *-av*.env auf 1 setzen.

Wenn du möchtest, formatiere ich dir das als README.md für /opt/entropywatcher/ oder als kurze „Cheat-Sheet“-Textdatei.
