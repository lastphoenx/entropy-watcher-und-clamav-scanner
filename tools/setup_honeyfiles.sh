#!/usr/bin/env bash
#
# setup_honeyfiles.sh
# Erstellt Honeyfiles (Köder-Dateien) und konfiguriert auditd-Überwachung
#
# Honeyfiles sind verlockende Dateien (z.B. mit Credentials), die niemals 
# angefasst werden sollten. Ein Zugriff = Alarm (Malware/Intrusion).
#
# Usage:
#   sudo bash setup_honeyfiles.sh                # Setup: Honeyfiles + auditd + systemd Units
#   sudo bash setup_honeyfiles.sh --dry-run      # Test-Modus ohne Änderungen
#   sudo bash setup_honeyfiles.sh --remove       # Cleanup: Alles entfernen (Logs bleiben)
#   sudo bash setup_honeyfiles.sh --purge-logs   # Nur Logs löschen
#   sudo bash setup_honeyfiles.sh --systemd-only # Nur systemd Units aktualisieren (Honeyfiles bleiben)
#
# Hinweis: Dieses Script sollte von tools/setup_honeyfiles.sh verwendet werden!
#

set -euo pipefail

# ============================================================================
# Konfiguration
# ============================================================================
DRY_RUN=0
REMOVE=0
PURGE_LOGS=0
SYSTEMD_ONLY=0
LOG_FILE="/var/log/honeyfiles.log"
AUDIT_KEY="honeyfile_access"
CONFIG_DIR="/opt/apps/entropywatcher/config"
HONEYFILE_PATHS_CONFIG="$CONFIG_DIR/honeyfile_paths"

# Parse Argumente
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --remove)
            REMOVE=1
            shift
            ;;
        --purge-logs)
            PURGE_LOGS=1
            shift
            ;;
        --systemd-only)
            SYSTEMD_ONLY=1
            shift
            ;;
        *)
            echo "Unbekannter Parameter: $1"
            exit 1
            ;;
    esac
done

# ============================================================================
# Helper Functions
# ============================================================================
log() {
    printf "%s [honeyfiles] %s\n" "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"
}

error() {
    printf "%s [honeyfiles] ✗ %s\n" "$(date '+%F %T')" "$*" >&2 | tee -a "$LOG_FILE"
}

# ============================================================================
# Honeyfile Definition (Templates - echte Pfade werden randomisiert)
# ============================================================================
declare -A HONEYFILE_TEMPLATES=(
    ["aws"]="/root/.aws/credentials"
    ["git"]="/root/.git-credentials"
    ["env_backup"]="/root/.env.backup"
    ["env_production"]="/root/.env.production"
    ["samba"]="/srv/nas/admin/passwords.txt"
    ["mysql"]="/var/lib/mysql/.db_root_credentials"
    ["pcloud"]="/opt/pcloud/.pcloud_token"
)

# Echte Pfade mit Randomisierung (werden bei create_honeyfiles() generiert)
declare -A HONEYFILES=()

# ============================================================================
# Honeyfile Contents (Fake aber verlockend)
# ============================================================================
declare -A HONEYFILE_CONTENTS=(
    ["fake_aws_creds"]="# ==========================================
# ⚠️  HONEYFILE - NICHT IN PRODUKTION NUTZEN
# This file is monitored by auditd intrusion detection
# Any read access triggers security alerts & alerts
# File ID: HF-AWS-001 | Created: 2025-12-13
# ==========================================
[default]
aws_access_key_id=AKIAIOSFODNN7EXAMPLE
aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
region=eu-central-1"
    
    ["fake_git_token"]="# ==========================================
# ⚠️  HONEYFILE - NICHT IN PRODUKTION NUTZEN
# This file is monitored by auditd intrusion detection
# Any read access triggers security alerts
# File ID: HF-GITHUB-001 | Created: 2025-12-13
# ==========================================
ghp_1234567890abcdefghijklmnopqrstuvwxyz0123456"
    
    ["fake_env_backup"]="# ==========================================
# ⚠️  HONEYFILE - NICHT IN PRODUKTION NUTZEN
# This file is monitored by auditd intrusion detection
# Any read access triggers security alerts
# File ID: HF-ENV-BACKUP-001 | Created: 2025-12-13
# ==========================================
# Backup Credentials (NEVER DELETE!)
DB_HOST=mariadb.internal
DB_USER=root
DB_PASSWORD=MySecurePass123!@#
PCLOUD_API_TOKEN=aQ5e8W2xZ9pL7kM4nJ6hG3tY1uV5bC8dF2eA9sQ0x
SMTP_PASSWORD=EmailPass456!@#
BACKUP_SECRET=super_secret_backup_key_do_not_share"
    
    ["fake_env_production"]="# ==========================================
# ⚠️  HONEYFILE - NICHT IN PRODUKTION NUTZEN
# This file is monitored by auditd intrusion detection
# Any read access triggers security alerts
# File ID: HF-ENV-PROD-001 | Created: 2025-12-13
# ==========================================
# Production Secrets (NUR FÜR ADMIN)
API_KEY=sk_live_51234567890abcdefghijklmnopqrstuvwxyz
DB_PASSWORD=ProductionDBPass!@#789
JWT_SECRET=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9
AWS_KEY=AKIAIOSFODNN7EXAMPLE
STRIPE_KEY=sk_live_stripe_key_example"
    
    ["fake_samba_pass"]="# ==========================================
# ⚠️  HONEYFILE - NICHT IN PRODUKTION NUTZEN
# This file is monitored by auditd intrusion detection
# Any read access triggers security alerts
# File ID: HF-SAMBA-001 | Created: 2025-12-13
# ==========================================
# Samba Admin Credentials
# Username: admin
# Password: Samba@Admin2025!
backup_share_pass = BackupSharePass123!
media_share_admin = MediaAdmin456!"
    
    ["fake_mysql_creds"]="# ==========================================
# ⚠️  HONEYFILE - NICHT IN PRODUKTION NUTZEN
# This file is monitored by auditd intrusion detection
# Any read access triggers security alerts
# File ID: HF-MYSQL-001 | Created: 2025-12-13
# ==========================================
[mysqldump]
user=root
password=MySQLRootPass789!@#
host=localhost
port=3306"
    
    ["fake_pcloud_token"]="# ==========================================
# ⚠️  HONEYFILE - NICHT IN PRODUKTION NUTZEN
# This file is monitored by auditd intrusion detection
# Any read access triggers security alerts
# File ID: HF-PCLOUD-001 | Created: 2025-12-13
# ==========================================
access_token=abc123def456ghi789jkl012mno345pqr678stu901vwx234yz
token_type=Bearer
refresh_token=refresh_abc123def456ghi789jkl012mno345pqr678
expiry=2025-12-31T23:59:59Z"
)

# ============================================================================
# FUNKTION: Generiere randomisierte Pfade
# ============================================================================
generate_random_paths() {
    local timestamp=$(date +%Y%m%d)
    
    log "Generiere randomisierte Honeyfile-Pfade..."
    
    for key in "${!HONEYFILE_TEMPLATES[@]}"; do
        local template="${HONEYFILE_TEMPLATES[$key]}"
        local dir=$(dirname "$template")
        local basename=$(basename "$template")
        local extension="${basename##*.}"
        local name="${basename%.*}"
        
        # Random-ID: 5-stellig alphanumerisch
        local random_id=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 5)
        
        # Neuer Pfad: name_randomid_date.extension
        local new_basename="${name}_${random_id}_${timestamp}"
        if [[ "$extension" != "$basename" ]]; then
            new_basename="${new_basename}.${extension}"
        fi
        
        local new_path="$dir/$new_basename"
        
        # Mapping speichern
        case "$key" in
            "aws") HONEYFILES["$new_path"]="fake_aws_creds" ;;
            "git") HONEYFILES["$new_path"]="fake_git_token" ;;
            "env_backup") HONEYFILES["$new_path"]="fake_env_backup" ;;
            "env_production") HONEYFILES["$new_path"]="fake_env_production" ;;
            "samba") HONEYFILES["$new_path"]="fake_samba_pass" ;;
            "mysql") HONEYFILES["$new_path"]="fake_mysql_creds" ;;
            "pcloud") HONEYFILES["$new_path"]="fake_pcloud_token" ;;
        esac
        
        log "  $key: $new_path"
    done
}

# ============================================================================
# FUNKTION: Speichere Pfade in Config
# ============================================================================
save_honeyfile_paths() {
    if [[ $DRY_RUN -eq 1 ]]; then
        log "[DRY-RUN] Würde speichern: $HONEYFILE_PATHS_CONFIG"
        return
    fi
    
    mkdir -p "$CONFIG_DIR"
    
    log "Speichere Honeyfile-Pfade nach $HONEYFILE_PATHS_CONFIG..."
    
    {
        echo "# Honeyfile Paths (Auto-Generated on $(date))"
        echo "# DO NOT EDIT MANUALLY - Managed by setup_honeyfiles.sh"
        echo "#"
        for filepath in "${!HONEYFILES[@]}"; do
            echo "$filepath"
        done
    } > "$HONEYFILE_PATHS_CONFIG"
    
    chmod 600 "$HONEYFILE_PATHS_CONFIG"
    log "✓ Config gespeichert: $HONEYFILE_PATHS_CONFIG"
}

# ============================================================================
# FUNKTION: Honeyfiles erstellen
# ============================================================================
create_honeyfiles() {
    log "════════════════════════════════════════════════════════════════════"
    log "Erstelle Honeyfiles..."
    log "════════════════════════════════════════════════════════════════════"
    
    # Zuerst randomisierte Pfade generieren
    generate_random_paths
    
    # Pfade speichern für honeyfile_monitor.sh
    save_honeyfile_paths
    
    for filepath in "${!HONEYFILES[@]}"; do
        content_key="${HONEYFILES[$filepath]}"
        content="${HONEYFILE_CONTENTS[$content_key]}"
        
        # Verzeichnis erstellen
        dir=$(dirname "$filepath")
        
        if [[ $DRY_RUN -eq 1 ]]; then
            log "[DRY-RUN] Würde erstellen: $filepath"
            log "[DRY-RUN] Verzeichnis: $dir"
            continue
        fi
        
        # Verzeichnis mit restriktiven Rechten
        if [[ ! -d "$dir" ]]; then
            log "Erstelle Verzeichnis: $dir"
            mkdir -p "$dir"
            chmod 700 "$dir"
        fi
        
        # Honeyfile mit restriktiven Rechten schreiben
        echo "$content" > "$filepath"
        chmod 600 "$filepath"
        
        log "✓ Erstellt: $filepath (600)"
    done
}

# ============================================================================
# FUNKTION: auditd Rules konfigurieren
# ============================================================================
setup_auditd() {
    log ""
    log "════════════════════════════════════════════════════════════════════"
    log "Konfiguriere auditd Rules..."
    log "════════════════════════════════════════════════════════════════════"
    
    # auditd prüfen / installieren
    if ! command -v auditctl &> /dev/null; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log "[DRY-RUN] Würde installieren: auditd"
            return
        fi
        log "Installiere auditd..."
        apt-get update -qq
        apt-get install -y auditd audispd-plugins
    fi
    
    log "✓ auditd verfügbar"
    
    # Bestehende Rules aufräumen (für diesen Key)
    if [[ $DRY_RUN -eq 0 ]]; then
        auditctl -D -k "$AUDIT_KEY" 2>/dev/null || true
    fi
    
    # Neue Rules erstellen
    RULES_FILE="/etc/audit/rules.d/honeyfiles.rules"
    
    # EXCLUDE USER: Root (UID 0) darf lesen ohne Alarm (für EntropyWatcher/Backup)
    # Falls EntropyWatcher unter einem anderen User läuft, hier dessen UID eintragen!
    EXCLUDE_UID=0
    
    if [[ $DRY_RUN -eq 1 ]]; then
        log "[DRY-RUN] Würde erstellen: $RULES_FILE"
        log "[DRY-RUN] Exclude UID: $EXCLUDE_UID (root/System-Prozesse)"
        for filepath in "${!HONEYFILES[@]}"; do
            log "[DRY-RUN]   -a always,exit -F path=$filepath -F perm=ra -F auid!=$EXCLUDE_UID -k $AUDIT_KEY"
        done
        return
    fi
    
    log "Schreibe Audit-Rules zu $RULES_FILE..."
    log "Exclude UID: $EXCLUDE_UID (root/System-Prozesse dürfen ohne Alarm lesen)"
    
    cat > "$RULES_FILE" << AUDITEOF
# Honeyfile Audit Rules
# Überwache Zugriffe (read/attr) auf Honeyfiles
# EXCLUDE: UID $EXCLUDE_UID (System/Backup) wird ignoriert, um False-Positives zu vermeiden.
AUDITEOF
    
    for filepath in "${!HONEYFILES[@]}"; do
        # Syntax: -a always,exit (Filter)
        # -F path=...   : Die Datei
        # -F perm=ra    : Read / Attribute change
        # -F auid!=$EXCLUDE_UID : Ignoriere specified UID
        # -k ...        : Key für Suche
        echo "-a always,exit -F path=$filepath -F perm=ra -F auid!=$EXCLUDE_UID -k $AUDIT_KEY" >> "$RULES_FILE"
    done
    
    # ========================================================================
    # TIER 2: Config-Access Monitoring
    # Überwacht Zugriff auf die Honeyfile-Config selbst
    # Ein Wurm der die Config liest = hochverdächtig!
    # ========================================================================
    cat >> "$RULES_FILE" << 'TIER2EOF'

# Tier 2: Config-Access Detection
# Überwache Lese-Zugriffe auf Honeyfile-Config (außer root)
-a always,exit -F path=/opt/apps/entropywatcher/config/honeyfile_paths -F perm=r -F auid!=0 -k honeyfile_config_access

TIER2EOF

    # ========================================================================
    # TIER 3: Auditd-Tampering Detection
    # Überwacht Manipulationsversuche am Audit-System
    # ========================================================================
    cat >> "$RULES_FILE" << 'TIER3EOF'
# Tier 3: Auditd Tampering Detection
# Überwache Manipulationsversuche am Audit-System
-w /usr/sbin/auditctl -p x -k audit_tampering
-w /usr/sbin/auditd -p x -k audit_tampering
-w /etc/audit/ -p wa -k audit_config_change
-w /etc/audit/rules.d/ -p wa -k audit_config_change

TIER3EOF

    # Rules laden
    # augen (audit generator) lädt rules.d automatisch beim restart, 
    # aber wir laden sie hier explizit für sofortige Wirkung
    auditctl -R "$RULES_FILE" || log "⚠ Warnung: Konnte Rules nicht sofort laden (evtl. Reboot nötig)"
    log "✓ Audit-Rules geladen"
    
    # Persistent machen
    systemctl enable auditd
    systemctl restart auditd
    log "✓ auditd aktiviert & neugestartet"
}

# ============================================================================
# FUNKTION: logrotate konfigurieren
# ============================================================================
setup_logrotate() {
    log ""
    log "════════════════════════════════════════════════════════════════════"
    log "Konfiguriere logrotate..."
    log "════════════════════════════════════════════════════════════════════"
    
    LOGROTATE_FILE="/etc/logrotate.d/honeyfile-monitor"
    
    if [[ $DRY_RUN -eq 1 ]]; then
        log "[DRY-RUN] Würde erstellen: $LOGROTATE_FILE"
        return 0
    fi
    
    log "Schreibe logrotate-Konfiguration zu $LOGROTATE_FILE..."
    
    tee "$LOGROTATE_FILE" > /dev/null << 'ROTATEEOF'
/var/log/honeyfile_monitor.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 root root
    sharedscripts
}
ROTATEEOF
    
    log "✓ logrotate konfiguriert"
}

# ============================================================================
# FUNKTION: systemd Units installieren (aus .example Dateien)
# ============================================================================
setup_systemd_units() {
    log ""
    log "════════════════════════════════════════════════════════════════════"
    log "Installiere systemd Units (honeyfile-monitor.service + .timer)..."
    log "════════════════════════════════════════════════════════════════════"
    
    SYSTEMD_DIR="/etc/systemd/system"
    
    if [[ $DRY_RUN -eq 1 ]]; then
        log "[DRY-RUN] Würde erstellen: $SYSTEMD_DIR/honeyfile-monitor.service"
        log "[DRY-RUN] Würde erstellen: $SYSTEMD_DIR/honeyfile-monitor.timer"
        log "[DRY-RUN] Würde ausführen: systemctl daemon-reload"
        log "[DRY-RUN] Würde ausführen: systemctl enable honeyfile-monitor.timer"
        log "[DRY-RUN] Würde ausführen: systemctl start honeyfile-monitor.timer"
        return 0
    fi
    
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_SYSTEMD_DIR="$SCRIPT_DIR/../systemd"
    
    if [[ ! -d "$REPO_SYSTEMD_DIR" ]]; then
        error "systemd Examples-Verzeichnis nicht gefunden: $REPO_SYSTEMD_DIR"
        return 1
    fi
    
    SERVICE_SRC="$REPO_SYSTEMD_DIR/honeyfile-monitor.service.example"
    SERVICE_DST="$SYSTEMD_DIR/honeyfile-monitor.service"
    TIMER_SRC="$REPO_SYSTEMD_DIR/honeyfile-monitor.timer.example"
    TIMER_DST="$SYSTEMD_DIR/honeyfile-monitor.timer"
    
    if [[ ! -f "$SERVICE_SRC" ]]; then
        error "Datei nicht gefunden: $SERVICE_SRC"
        return 1
    fi
    
    log "Kopiere: $SERVICE_SRC → $SERVICE_DST"
    cp "$SERVICE_SRC" "$SERVICE_DST"
    log "✓ Installiert: honeyfile-monitor.service"
    
    log "Kopiere: $TIMER_SRC → $TIMER_DST"
    cp "$TIMER_SRC" "$TIMER_DST"
    log "✓ Installiert: honeyfile-monitor.timer"
    
    systemctl daemon-reload
    log "✓ systemctl daemon-reload"
    
    systemctl enable honeyfile-monitor.timer
    log "✓ Timer aktiviert (enable)"
    
    systemctl start honeyfile-monitor.timer
    log "✓ Timer gestartet"
    
    log ""
    systemctl status honeyfile-monitor.timer --no-pager || true
}

# ============================================================================
# FUNKTION: Konfigurationier-Hinweise ausgeben
# ============================================================================
print_configuration_hints() {
    log ""
    log "════════════════════════════════════════════════════════════════════"
    log "📋 KONFIGURATION: Honeyfiles in EntropyWatcher & ClamAV eintragen"
    log "════════════════════════════════════════════════════════════════════"
    log ""
    
    # Lies tatsächliche Pfade aus Config
    if [[ ! -f "$HONEYFILE_PATHS_CONFIG" ]]; then
        log "⚠️  Config nicht gefunden: $HONEYFILE_PATHS_CONFIG"
        return 1
    fi
    
    # Extrahiere Pfade (ohne Kommentare)
    local paths=($(grep -v '^#' "$HONEYFILE_PATHS_CONFIG" | grep -v '^$'))
    
    # Baue komma-separierte Liste für SCAN_EXCLUDES
    local scan_excludes=$(IFS=,; echo "${paths[*]}")
    
    log "1️⃣  EntropyWatcher: In common.env oder spezifisches Service-ENV ergänzen:"
    log ""
    log "────────────────────────────────────────────────────────────────────"
    echo "# Exclude Honeyfiles von Scan (auditd-monitored intrusion detection)"
    echo "SCAN_EXCLUDES=\"${scan_excludes}\""
    log "────────────────────────────────────────────────────────────────────"
    log ""
    
    log "2️⃣  ClamAV: In /etc/clamav/clamd.conf eintragen:"
    log ""
    log "────────────────────────────────────────────────────────────────────"
    echo "# Exclude Honeyfiles from scanning (auditd-monitored)"
    for path in "${paths[@]}"; do
        # Escape special regex characters für ClamAV
        local escaped_path=$(echo "$path" | sed 's/\./\\./g')
        echo "ExcludePath ^${escaped_path}\$"
    done
    log "────────────────────────────────────────────────────────────────────"
    log ""
    
    log "3️⃣  Mail-Setup (automatisch aus common.env):"
    log "   honeyfile_monitor.sh liest Konfiguration automatisch aus:"
    log ""
    log "   /opt/apps/entropywatcher/config/common.env"
    log ""
    log "   Nutzte Variablen:"
    log "   - MAIL_ENABLE (muss 1 sein)"
    log "   - MAIL_SMTP_HOST, MAIL_SMTP_PORT"
    log "   - MAIL_USER, MAIL_PASS (falls Auth nötig)"
    log "   - MAIL_TO (Empfänger)"
    log "   - MAIL_STARTTLS (1 = TLS, 0 = Plain)"
    log ""
    log "   ℹ️  Python3 wird für SMTP-Versand benötigt (meist vorhanden)"
    log ""
}

# ============================================================================
# FUNKTION: systemd Units entfernen
# ============================================================================
remove_systemd_units() {
    log ""
    log "════════════════════════════════════════════════════════════════════"
    log "Entferne systemd Units..."
    log "════════════════════════════════════════════════════════════════════"
    
    SYSTEMD_DIR="/etc/systemd/system"
    
    if [[ $DRY_RUN -eq 1 ]]; then
        log "[DRY-RUN] Würde stoppen: systemctl stop honeyfile-monitor.timer"
        log "[DRY-RUN] Würde deaktivieren: systemctl disable honeyfile-monitor.timer"
        log "[DRY-RUN] Würde löschen: $SYSTEMD_DIR/honeyfile-monitor.service"
        log "[DRY-RUN] Würde löschen: $SYSTEMD_DIR/honeyfile-monitor.timer"
        log "[DRY-RUN] Würde ausführen: systemctl daemon-reload"
        return 0
    fi
    
    if systemctl is-active --quiet honeyfile-monitor.timer; then
        systemctl stop honeyfile-monitor.timer
        log "✓ Timer gestoppt"
    fi
    
    if systemctl is-enabled --quiet honeyfile-monitor.timer 2>/dev/null; then
        systemctl disable honeyfile-monitor.timer
        log "✓ Timer deaktiviert"
    fi
    
    rm -f "$SYSTEMD_DIR/honeyfile-monitor.service"
    log "✓ Gelöscht: honeyfile-monitor.service"
    
    rm -f "$SYSTEMD_DIR/honeyfile-monitor.timer"
    log "✓ Gelöscht: honeyfile-monitor.timer"
    
    systemctl daemon-reload
    log "✓ systemctl daemon-reload"
}

# ============================================================================
# FUNKTION: Honeyfiles entfernen
# ============================================================================
remove_honeyfiles() {
    log "════════════════════════════════════════════════════════════════════"
    log "Entferne Honeyfiles..."
    log "════════════════════════════════════════════════════════════════════"
    
    # Lade Pfade aus Config (falls vorhanden)
    if [[ -f "$HONEYFILE_PATHS_CONFIG" ]]; then
        log "Lade Honeyfile-Pfade aus Config..."
        while IFS= read -r line; do
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            if [[ -f "$line" ]]; then
                if [[ $DRY_RUN -eq 1 ]]; then
                    log "[DRY-RUN] Würde löschen: $line"
                else
                    rm -f "$line"
                    log "✓ Gelöscht: $line"
                fi
            fi
        done < "$HONEYFILE_PATHS_CONFIG"
        
        # Config-Datei selbst löschen
        if [[ $DRY_RUN -eq 0 ]]; then
            rm -f "$HONEYFILE_PATHS_CONFIG"
            log "✓ Config gelöscht: $HONEYFILE_PATHS_CONFIG"
        fi
    else
        log "⚠️  Keine Config gefunden - Honeyfiles können nicht automatisch gelöscht werden"
        log "   Falls vorhanden, manuell löschen oder Pfade aus /var/log/honeyfiles.log entnehmen"
    fi
    
    # auditd Rules entfernen
    RULES_FILE="/etc/audit/rules.d/honeyfiles.rules"
    if [[ -f "$RULES_FILE" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log "[DRY-RUN] Würde löschen: $RULES_FILE"
        else
            rm -f "$RULES_FILE"
            auditctl -D -k "$AUDIT_KEY"
            systemctl restart auditd
            log "✓ Audit-Rules entfernt"
        fi
    fi
    
    # NICHT das Monitor-Script löschen - es ist Teil des Git-Repos!
    # Es liegt in /opt/apps/entropywatcher/main/honeyfile_monitor.sh
    
    # Alert-Flag löschen
    ALERT_FLAG="/var/lib/honeyfile_alert"
    if [[ -f "$ALERT_FLAG" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log "[DRY-RUN] Würde löschen: $ALERT_FLAG"
        else
            rm -f "$ALERT_FLAG"
            log "✓ Alert-Flag entfernt"
        fi
    fi
    
    log ""
    log "ℹ️  Log-Datei behalten: $LOG_FILE"
    log "   (Für Forensik/Incident-Response wichtig)"
    log "   Manuell löschen mit: sudo bash setup_honeyfiles.sh --purge-logs"
    log ""
    log "✓ Honeyfiles & systemd Units vollständig entfernt"
}

# ============================================================================
# FUNKTION: Logs löschen
# ============================================================================
purge_logs() {
    log "════════════════════════════════════════════════════════════════════"
    log "Lösche Log-Dateien..."
    log "════════════════════════════════════════════════════════════════════"
    
    if [[ -f "$LOG_FILE" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log "[DRY-RUN] Würde löschen: $LOG_FILE"
        else
            rm -f "$LOG_FILE"
            log "✓ Gelöscht: $LOG_FILE"
        fi
    else
        log "ℹ️  Log-Datei nicht gefunden: $LOG_FILE"
    fi
    
    MONITOR_LOG="/var/log/honeyfile_monitor.log"
    if [[ -f "$MONITOR_LOG" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log "[DRY-RUN] Würde löschen: $MONITOR_LOG"
        else
            rm -f "$MONITOR_LOG"
            log "✓ Gelöscht: $MONITOR_LOG"
        fi
    fi
    
    log ""
    log "✓ Log-Dateien gelöscht"
}

# ============================================================================
# MAIN
# ============================================================================
if [[ $PURGE_LOGS -eq 1 ]]; then
    log "PURGE LOGS MODE aktiv"
    log ""
    purge_logs
    exit 0
fi

if [[ $REMOVE -eq 1 ]]; then
    log "REMOVE MODE aktiv"
    log ""
    remove_systemd_units
    remove_honeyfiles
    exit 0
fi

if [[ $SYSTEMD_ONLY -eq 1 ]]; then
    log "SYSTEMD-ONLY MODE - Aktualisiere nur systemd Units"
    log ""
    setup_systemd_units
    log ""
    log "════════════════════════════════════════════════════════════════════"
    log "✓ Systemd Units AKTUALISIERT"
    log "════════════════════════════════════════════════════════════════════"
    log ""
    log "Status:"
    log "  ✓ honeyfile-monitor.service aktualisiert"
    log "  ✓ honeyfile-monitor.timer aktualisiert"
    log "  ✓ systemctl daemon-reload ausgeführt"
    log "  → Bestehende Honeyfiles wurden NICHT verändert"
    log ""
    log "Prüfen:"
    log "  systemctl status honeyfile-monitor.timer"
    log "  journalctl -u honeyfile-monitor.service -n 20"
    log ""
    exit 0
fi

# Create mode
if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY-RUN MODE - Keine Änderungen"
    log ""
fi

create_honeyfiles
setup_auditd
setup_logrotate
setup_systemd_units

log ""
log "════════════════════════════════════════════════════════════════════"
log "✓ Honeyfile-Setup ABGESCHLOSSEN"
log "════════════════════════════════════════════════════════════════════"
log ""
log "Status:"
log "  ✓ Honeyfiles erstellt in /root/.aws/, /root/.git-credentials, etc."
log "  ✓ auditd Rules konfiguriert (honeyfile_access)"
log "  ✓ logrotate konfiguriert (/var/log/honeyfile_monitor.log)"
log "  ✓ systemd Units (.service & .timer) installiert & aktiviert"
log "  ✓ honeyfile-monitor.timer läuft (alle 5 Min)"
log ""
log "Hinweis:"
log "  → honeyfile_monitor.sh muss separat nach /opt/apps/entropywatcher/main/ deployed werden"
log "  → Siehe: Repository-Datei entropywatcher/honeyfile_monitor.sh"
log ""
log "Integration mit safety_gate.sh:"
log "  → safety_gate.sh prüft ZUERST: /var/lib/honeyfile_alert Flag"
log "  → honeyfile-monitor.sh prüft Audit-Log & setzt Flag bei Alarm"
log "  → Honeyfile-Zugriff → sofort RED → Backup blockiert"
log ""

print_configuration_hints

log "Testen (optional):"
log "  1. Manuell: /opt/apps/entropywatcher/main/honeyfile_monitor.sh"
log "  2. Timer-Status: systemctl status honeyfile-monitor.timer"
log "  3. Logs: journalctl -u honeyfile-monitor.service -n 50"
log "  4. Audit-Events: sudo ausearch -k honeyfile_access --start recent"
log "  5. Safety-Gate Test: sudo bash safety_gate.sh"
log ""
log "Entfernen (falls nötig):"
log "  sudo bash setup_honeyfiles.sh --remove"
log ""
