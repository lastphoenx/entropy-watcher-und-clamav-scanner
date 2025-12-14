#!/usr/bin/env bash
#
# graceful_shutdown.sh
# Wartet auf laufende Services (EntropyWatcher, RTB, pCloud) und fährt dann sauber herunter
#
# Usage:
#   sudo ./graceful_shutdown.sh [--timeout SECONDS] [--dry-run] [--no-shutdown]
#
# Options:
#   --timeout SECONDS     Maximale Wartezeit pro Service (default: 1800 = 30 min)
#   --dry-run            Nur prüfen, nicht herunterfahren
#   --no-shutdown        Nach Warten nicht herunterfahren (nur prüfen & warten)
#
# Exit Codes:
#   0 = Erfolgreich heruntergefahren
#   1 = Fehler / Timeout
#   2 = Nur --dry-run ausgeführt

set -euo pipefail

# ============================================================================
# Konfiguration
# ============================================================================
TIMEOUT=1800          # 30 Minuten max Wartezeit
DRY_RUN=0
NO_SHUTDOWN=0
POLL_INTERVAL=10      # Sekunden zwischen Checks
LOCKFILE="/run/backup_pipeline.lock" # Globales Lockfile

# Parse Argumente
while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --no-shutdown)
            NO_SHUTDOWN=1
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
    printf "%s [graceful_shutdown] %s\n" "$(date '+%F %T')" "$*"
}

error() {
    printf "%s [graceful_shutdown] ✗ %s\n" "$(date '+%F %T')" "$*" >&2
}

is_service_running() {
    local service="$1"
    systemctl is-active --quiet "$service" 2>/dev/null && return 0 || return 1
}

get_service_status() {
    local service="$1"
    systemctl is-active "$service" 2>/dev/null || echo "unknown"
}

wait_for_service() {
    local service="$1"
    local timeout="$2"
    local elapsed=0
    
    log "⏳ Warte auf $service (Timeout: ${timeout}s)..."
    
    while (( elapsed < timeout )); do
        if ! is_service_running "$service"; then
            log "✓ $service ist beendet"
            return 0
        fi
        
        log "  $service läuft noch... (${elapsed}/${timeout}s)"
        sleep "$POLL_INTERVAL"
        elapsed=$((elapsed + POLL_INTERVAL))
    done
    
    error "$service hat nicht rechtzeitig beendet (Timeout nach ${timeout}s)"
    return 1
}

check_process() {
    local name="$1"
    local pattern="$2"
    local pids
    
    pids=$(pgrep -f "$pattern" 2>/dev/null || echo "")
    if [[ -n "$pids" ]]; then
        log "  Prozesse: $name (PIDs: $pids)"
        return 0
    else
        return 1
    fi
}

# ============================================================================
# SCHRITT 0: Timer stoppen (Neue Jobs verhindern)
# ============================================================================
log "════════════════════════════════════════════════════════════════════"
log "Stoppe Timer (Verhindere neue Jobs während Wartezeit)..."
log "════════════════════════════════════════════════════════════════════"

TIMERS_TO_STOP=(
    "entropywatcher.timer"
    "entropywatcher-nas.timer"
    "entropywatcher-os.timer"
)

for timer in "${TIMERS_TO_STOP[@]}"; do
    if systemctl is-active --quiet "$timer"; then
        if [[ $DRY_RUN -eq 0 ]]; then
            systemctl stop "$timer"
            log "✓ $timer gestoppt"
        else
            log "[DRY-RUN] Würde $timer stoppen"
        fi
    fi
done

# ============================================================================
# PRÜFUNG: Laufende Services
# ============================================================================
log "════════════════════════════════════════════════════════════════════"
log "Prüfe laufende Services..."
log "════════════════════════════════════════════════════════════════════"

SERVICES_TO_WAIT=(
    "entropywatcher-nas.service"
    "entropywatcher-nas-av.service"
    "entropywatcher-os.service"
    "entropywatcher-os-av.service"
    "backup-pipeline.service"
)

RUNNING_SERVICES=()
for service in "${SERVICES_TO_WAIT[@]}"; do
    if is_service_running "$service"; then
        RUNNING_SERVICES+=("$service")
        log "⚠ $service läuft aktuell"
    else
        log "✓ $service ist nicht aktiv"
    fi
done

# ============================================================================
# PRÜFUNG: Laufende Prozesse (zusätzlich)
# ============================================================================
log ""
log "Prüfe laufende Prozesse & Lockfile..."

RUNNING_PROCESSES=0

# 1. Lockfile Check
if [[ -f "$LOCKFILE" ]]; then
    # Prüfen ob Lockfile wirklich gelockt ist (flock -n prüft non-blocking)
    exec 9<"$LOCKFILE"
    if ! flock -n 9; then
        log "⚠ Globales Lockfile $LOCKFILE ist aktiv (Backup läuft!)"
        RUNNING_PROCESSES=$((RUNNING_PROCESSES + 1))
    else
        log "✓ Lockfile existiert, ist aber nicht gesperrt (Stale?)"
    fi
    exec 9<&-
fi

if check_process "entropywatcher" "entropywatcher.py"; then
    RUNNING_PROCESSES=$((RUNNING_PROCESSES + 1))
fi

if check_process "rsync/rtb" "rsync.*backup"; then
    RUNNING_PROCESSES=$((RUNNING_PROCESSES + 1))
fi

if check_process "pcloud-tools" "pcloud.*sync"; then
    RUNNING_PROCESSES=$((RUNNING_PROCESSES + 1))
fi

# ============================================================================
# --DRY-RUN MODE
# ============================================================================
if [[ $DRY_RUN -eq 1 ]]; then
    log ""
    log "════════════════════════════════════════════════════════════════════"
    log "DRY-RUN MODUS (kein Shutdown)"
    log "════════════════════════════════════════════════════════════════════"
    
    if [[ ${#RUNNING_SERVICES[@]} -eq 0 ]] && [[ $RUNNING_PROCESSES -eq 0 ]]; then
        log "✓ Alle Services sind idle. Shutdown würde sofort ausgeführt"
        exit 0
    else
        log "⚠ Es laufen noch Services/Prozesse:"
        for svc in "${RUNNING_SERVICES[@]}"; do
            log "  - $svc ($(get_service_status "$svc"))"
        done
        log "  Bei normalem Aufruf würde auf diese gewartet"
        exit 2
    fi
fi

# ============================================================================
# WARTEN: Auf Services
# ============================================================================
if [[ ${#RUNNING_SERVICES[@]} -gt 0 ]]; then
    log ""
    log "════════════════════════════════════════════════════════════════════"
    log "Warte auf ${#RUNNING_SERVICES[@]} laufende Service(s)..."
    log "════════════════════════════════════════════════════════════════════"
    
    FAILED_SERVICES=()
    for service in "${RUNNING_SERVICES[@]}"; do
        if ! wait_for_service "$service" "$TIMEOUT"; then
            FAILED_SERVICES+=("$service")
        fi
    done
    
    if [[ ${#FAILED_SERVICES[@]} -gt 0 ]]; then
        error "Services konnten nicht rechtzeitig beendet werden:"
        for svc in "${FAILED_SERVICES[@]}"; do
            error "  - $svc"
        done
        error "Shutdown abgebrochen!"
        exit 1
    fi
else
    log "✓ Keine laufenden Services gefunden"
fi

# ============================================================================
# FINALE PRÜFUNG
# ============================================================================
log ""
log "════════════════════════════════════════════════════════════════════"
log "Finale Prüfung vor Shutdown..."
log "════════════════════════════════════════════════════════════════════"

FINAL_CHECK_FAILED=0

for service in "${SERVICES_TO_WAIT[@]}"; do
    if is_service_running "$service"; then
        error "$service läuft noch!"
        FINAL_CHECK_FAILED=1
    else
        log "✓ $service ist beendet"
    fi
done

if [[ $FINAL_CHECK_FAILED -eq 1 ]]; then
    error "Finale Prüfung fehlgeschlagen!"
    exit 1
fi

# Check auf manuelle Prozesse vor dem harten Shutdown
if check_process "ANY-MANUAL" "entropywatcher.py|rsync.*backup|pcloud.*sync"; then
    error "Es laufen noch manuelle Prozesse (nicht via systemd)! Shutdown abgebrochen."
    exit 1
fi

log "✓ Alle Services beendet"

# ============================================================================
# SHUTDOWN (sofern nicht --no-shutdown)
# ============================================================================
if [[ $NO_SHUTDOWN -eq 1 ]]; then
    log ""
    log "════════════════════════════════════════════════════════════════════"
    log "✓ Alle Services beendet. --no-shutdown aktiv, fahre nicht herunter"
    log "════════════════════════════════════════════════════════════════════"
    exit 0
fi

log ""
log "════════════════════════════════════════════════════════════════════"
log "✓✓✓ Fahre Server sauber herunter..."
log "════════════════════════════════════════════════════════════════════"

# Letzte Logs flushen
sync

# Herunterfahren (+1 Minute Frist)
sudo shutdown -h +1 "graceful_shutdown: Server wird heruntergefahren"

log "Shutdown initiiert. System fährt in 1 Minute herunter."
exit 0
